-- الواجهة تتبع نوع الحساب (قرار المهندس رعد 08-09-2026):
-- حساب نوعه «فرد» واجهته شخصية، وحساب الكيان لا يقبل الواجهة الشخصية.
-- وتكتب على الحساب وحده: كتابتها على ملف المستخدم كانت تسرب اختياره
-- إلى حساباته الأخرى التي لا واجهة لها.
create or replace function public.pack_for(p_org uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select p.ui_pack from public.org_profiles p
       join public.ui_packs u on u.key = p.ui_pack and u.active
      where p.org_id = p_org),
    (select 'individual' from public.org_profiles op
      where op.org_id = p_org and op.entity_type = 'individual'
        and exists (select 1 from public.ui_packs where key = 'individual' and active)),
    (select key from public.ui_packs where active and is_default order by sort_order limit 1)
  )
$$;

create or replace function public.set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  if p_pack = 'individual' and coalesce(v_entity, 'company') <> 'individual' then
    raise exception 'personal interface is for a personal account' using errcode = '22023';
  end if;
  if p_pack is not null and p_pack <> 'individual' and v_entity = 'individual' then
    raise exception 'a personal account keeps the personal interface' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  return public.pack_for(p_org);
end $function$;
