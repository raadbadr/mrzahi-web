-- إصلاح تبديل الواجهة على قاعدة جدة — المهندس رعد 2026-09-17
-- السبب: set_my_pack المطبقة تنادي pack_guard وهي غير موجودة، فكل تبديل واجهة
-- يرفع خطأ وترتد الشريحة. هذا الملف يعرف الناقص ويعيد الدوال بنسختها النهائية.
-- ذري: كله في معاملة واحدة، ولا يمس صفا واحدا من بيانات المستخدمين.
begin;

-- 1) الحارس الناقص (من 0142): الواجهة الشخصية للحساب الشخصي وحده، والعكس.
create or replace function public.pack_guard(p_entity text, p_pack text)
returns void language plpgsql immutable as $function$
begin
  if p_entity = 'individual' and coalesce(p_pack, 'individual') <> 'individual' then
    raise exception 'the personal account keeps its own interface' using errcode = '22023';
  end if;
  if p_pack = 'individual' and coalesce(p_entity, 'company') <> 'individual' then
    raise exception 'the personal interface belongs to the personal account' using errcode = '22023';
  end if;
end $function$;

-- 2) واجهة الحساب كله: للمالك والمدير (من 0141 + 0142).
create or replace function public.set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text; v_old text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type, ui_pack into v_entity, v_old from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null
     where org_id = p_org and user_id = auth.uid() and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

create or replace function public.admin_set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_entity text; v_old text;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type, ui_pack into v_entity, v_old from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null where org_id = p_org and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

-- 3) تحويل الحساب الشخصي الى كيان عند رفع ورقة تجارية (من 0148).
create or replace function public.convert_org_to_company(p_org uuid, p_entity text, p_number text, p_name text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_old text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  v_entity := case when p_entity in ('company','establishment','freelance','nonprofit','government')
                   then p_entity else 'company' end;
  select entity_type into v_old from public.org_profiles where org_id = p_org;
  if coalesce(v_old, '') not in ('individual', '') then
    return jsonb_build_object('status', 'unchanged', 'entity_type', v_old);
  end if;
  insert into public.org_profiles (org_id, entity_type, cr_number, license_number, updated_by)
  values (p_org, v_entity,
          case when v_entity in ('company','establishment') then nullif(btrim(coalesce(p_number,'')), '') end,
          case when v_entity = 'freelance' then nullif(btrim(coalesce(p_number,'')), '') end,
          auth.uid())
  on conflict (org_id) do update set
    entity_type = excluded.entity_type,
    cr_number = coalesce(excluded.cr_number, public.org_profiles.cr_number),
    license_number = coalesce(excluded.license_number, public.org_profiles.license_number),
    ui_pack = case when public.org_profiles.ui_pack = 'individual' then null else public.org_profiles.ui_pack end,
    updated_by = auth.uid(), updated_at = now();
  update public.org_members set ui_pack = null where org_id = p_org and ui_pack = 'individual';
  if nullif(btrim(coalesce(p_name,'')), '') is not null then
    update public.organizations set name = btrim(p_name) where id = p_org and coalesce(btrim(name),'') = '';
  end if;
  return jsonb_build_object('status', 'converted', 'from', v_old, 'entity_type', v_entity,
                            'pack', public.pack_for(p_org));
end $function$;

grant execute on function public.convert_org_to_company(uuid, text, text, text) to authenticated;

-- 4) الحزمة الافتراضية للحساب بلا نوع «اعمال» لا «شخصي» (من 0143).
update public.ui_packs set is_default = false where is_default and key <> 'business';
update public.ui_packs set is_default = true where key = 'business';

-- 5) اوراق الحساب الشخصي شخصية صرفة، بلا شيء تجاري (من 0148).
delete from public.required_docs where entity_type = 'individual';
insert into public.required_docs (entity_type, kind, required, renews, sort_order) values
  ('individual', 'id_document',            true,  true,  1),
  ('individual', 'passport',               false, true,  2),
  ('individual', 'driving_license',        false, true,  3),
  ('individual', 'vehicle_registration',   false, true,  4),
  ('individual', 'insurance_policy',       false, true,  5),
  ('individual', 'gosi_certificate',       false, false, 6),
  ('individual', 'employment_contract',    false, false, 7),
  ('individual', 'experience_certificate', false, false, 8),
  ('individual', 'cv',                     false, false, 9),
  ('individual', 'lease_contract',         false, true, 10),
  ('individual', 'installment_plan',       false, false, 11);

commit;

-- تحقق فوري بعد التطبيق
select 'pack_guard' as fn, count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='pack_guard'
union all select 'convert_org_to_company', count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='convert_org_to_company'
union all select 'default_pack_is_business', count(*) from public.ui_packs where is_default and key='business'
union all select 'personal_docs', count(*) from public.required_docs where entity_type='individual';
