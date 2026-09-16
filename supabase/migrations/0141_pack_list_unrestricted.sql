-- 0141 — المهندس رعد 2026-09-16: «رجع اللسته حقت تغيير الواجهة زي ماكانت».
-- القائمة كاملة بلا تقييد بنوع الحساب: كل واجهة نشطة يختارها صاحب الحساب.
-- الحارس الباقي وحده: الدور (مالك أو مدير)، وأن تكون الواجهة موجودة ونشطة.
-- يلغي تقييد entity_choices الذي أدخله 0140 وما سبقه (0136، 0137، 0139).
begin;

create or replace function public.set_my_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  return public.pack_for_member(p_org, auth.uid());
end $function$;

create or replace function public.set_member_pack(p_org uuid, p_user uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = p_user and status = 'active';
  return public.pack_for_member(p_org, p_user);
end $function$;

create or replace function public.set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_old text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select ui_pack into v_old from public.org_profiles where org_id = p_org;
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
declare v_old text;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select ui_pack into v_old from public.org_profiles where org_id = p_org;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null where org_id = p_org and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

commit;
