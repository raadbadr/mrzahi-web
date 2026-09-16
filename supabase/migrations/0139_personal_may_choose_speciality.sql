-- 0139 — يلغي تضييق 0137. المهندس رعد 2026-09-16: «عندي محاماة».
-- نوع الحساب يحدد الواجهة الافتراضية لا أكثر: شخصي ← الشخصية، وكيان تجاري ←
-- الأعمال. وبعدها يغير صاحب الحساب واجهته إلى أي تخصص، والشخصي منها: محام يعمل
-- وحده أو مدرب أو مصمم حسابه شخصي وواجهته تخصصه. الممنوع وحده أن يأخذ كيان
-- تجاري الواجهة الشخصية.
begin;

-- إعادة الحساب الشخصي إلى خيارات التخصص التي أزالها 0137.
update public.ui_packs set entity_choices = entity_choices || '{individual}'::text[]
 where key in ('legal', 'trainer', 'design') and not ('individual' = any (entity_choices));

-- الحارس يصير مرجعه entity_choices لا قاعدة مكتوبة في الدالة، فلا يتناقض
-- موضعان. والمنع الوحيد الباقي: الواجهة الشخصية لا تعطى لكيان تجاري.
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
  if p_pack is not null and not exists (
       select 1 from public.ui_packs u
        where u.key = p_pack and u.active
          and coalesce(v_entity, 'company') = any (u.entity_choices)) then
    raise exception 'pack not allowed for this account type' using errcode = '22023';
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
  if p_pack is not null and not exists (
       select 1 from public.ui_packs u
        where u.key = p_pack and u.active
          and coalesce(v_entity, 'company') = any (u.entity_choices)) then
    raise exception 'pack not allowed for this account type' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null where org_id = p_org and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

-- ما محاه 0137 من اختيارات قائمة يعاد: حساب وزارة الحج والعمرة كان على التدريب.
update public.org_profiles set ui_pack = 'trainer'
 where org_id = 'f35ae6a6-e99f-4a29-8139-46a43a1d2621' and ui_pack is null;

commit;
