-- 0140 — يكمل ما بدأه 0139. المهندس رعد 2026-09-16: «رجعلي اختيار الواجهة».
-- 0139 حرر set_org_pack و admin_set_org_pack ونسي set_my_pack و set_member_pack،
-- وهما اللتان تنادى بهما شريحة الواجهة في الشريط العلوي وقائمة الفريق. فبقي فيهما
-- منع 0137 حرفيا: «حساب شخصي يبقى على الواجهة الشخصية»، فكان الاختيار يظهر ثم
-- ترفضه القاعدة. الحارس هنا يصير مرجعه entity_choices كما في 0139، فلا يتناقض
-- موضعان، والمنع الباقي وحده: الواجهة الشخصية لا تعطى لكيان تجاري — محفوظ لان
-- حزمة individual لا تقبل سوى individual في entity_choices.
begin;

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
  if p_pack is not null and not exists (
       select 1 from public.ui_packs u
        where u.key = p_pack and u.active
          and coalesce(v_entity, 'company') = any (u.entity_choices)) then
    raise exception 'pack not allowed for this account type' using errcode = '22023';
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
  if p_pack is not null and not exists (
       select 1 from public.ui_packs u
        where u.key = p_pack and u.active
          and coalesce(v_entity, 'company') = any (u.entity_choices)) then
    raise exception 'pack not allowed for this account type' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = p_user and status = 'active';
  return public.pack_for_member(p_org, p_user);
end $function$;

commit;
