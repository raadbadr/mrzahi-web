-- 0142 — المهندس رعد 2026-09-16: «شخصي واجهة منفصلة تماما اشتراك منفصل تماما»،
-- «ولو حساب مشترك شركة ما تتأثر واجهة شخصي».
-- حارس واحد في موضع واحد (pack_guard) تنادى به كل دوال ضبط الواجهة، فلا تتفرق
-- القاعدة على اربعة مواضع كما حصل في 0136–0141:
--   • الحساب الشخصي لا يأخذ الا الواجهة الشخصية.
--   • والواجهة الشخصية لا تعطى لغير الحساب الشخصي.
-- الاشتراك منفصل اصلا: لكل حساب plan_code و plan_expires_at خاصان به.
begin;

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

create or replace function public.set_my_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  return public.pack_for_member(p_org, auth.uid());
end $function$;

create or replace function public.set_member_pack(p_org uuid, p_user uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = p_user and status = 'active';
  return public.pack_for_member(p_org, p_user);
end $function$;

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

-- تصحيح ما كتب قبل الحارس: كيان تجاري عليه الواجهة الشخصية، أو حساب شخصي
-- عليه واجهة تخصص — يعود كل منهما الى واجهة نوعه.
update public.org_profiles set ui_pack = null
 where (entity_type <> 'individual' and ui_pack = 'individual')
    or (entity_type = 'individual' and ui_pack is not null and ui_pack <> 'individual');

update public.org_members m set ui_pack = null
  from public.org_profiles p
 where p.org_id = m.org_id and m.ui_pack is not null
   and ((p.entity_type <> 'individual' and m.ui_pack = 'individual')
        or (p.entity_type = 'individual' and m.ui_pack <> 'individual'));

commit;
