-- صاحب الحساب يوزع الواجهات على فريقه، وله هو كل الواجهات:
-- لكل عضو واجهته، ومن لم تُسند له واجهة يأخذ واجهة الحساب الافتراضية.
-- وباقي الفريق لا يغيّر واجهته: المالك ومن أعطاه صفة إداري وحدهما.
alter table public.org_members add column if not exists ui_pack text;

create or replace function public.pack_for_member(p_org uuid, p_user uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select m.ui_pack from public.org_members m
       join public.ui_packs u on u.key = m.ui_pack and u.active
      where m.org_id = p_org and m.user_id = p_user and m.status = 'active'),
    public.pack_for(p_org)
  )
$$;

create or replace function public.my_pack_config(p_org uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  with k as (select public.pack_for_member(p_org, (select auth.uid())) as key)
  select case when (select key from k) is null then null else jsonb_build_object(
    'pack',       (select key from k),
    'names',      (select names  from public.ui_packs where key = (select key from k)),
    'labels',     (select labels from public.ui_packs where key = (select key from k)),
    'is_default', (select is_default from public.ui_packs where key = (select key from k)),
    'services',   coalesce((select jsonb_agg(jsonb_build_object('service', s.service, 'sort', s.sort_order, 'label', s.label)
                                             order by s.sort_order, s.service)
                            from public.pack_services s where s.pack_key = (select key from k)), '[]'::jsonb),
    'views',        (select views        from public.ui_packs where key = (select key from k)),
    'tiles',        (select tiles        from public.ui_packs where key = (select key from k)),
    'list_columns', (select list_columns from public.ui_packs where key = (select key from k)),
    'form',         (select form         from public.ui_packs where key = (select key from k)),
    'papers',       (select papers       from public.ui_packs where key = (select key from k)),
    'bot',          (select bot          from public.ui_packs where key = (select key from k))
  ) end
  where exists (select 1 from public.org_members m
                 where m.org_id = p_org and m.user_id = (select auth.uid()) and m.status = 'active')
$$;

create or replace function public.set_my_pack(p_org uuid, p_pack text)
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
  if v_entity in ('individual', 'freelance') and coalesce(p_pack, 'individual') <> 'individual' then
    raise exception 'a personal account keeps the personal interface' using errcode = '22023';
  end if;
  if p_pack = 'individual' and coalesce(v_entity, 'company') not in ('individual', 'freelance') then
    raise exception 'personal interface is for a personal account' using errcode = '22023';
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
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  if v_entity in ('individual', 'freelance') and coalesce(p_pack, 'individual') <> 'individual' then
    raise exception 'a personal account keeps the personal interface' using errcode = '22023';
  end if;
  if p_pack = 'individual' and coalesce(v_entity, 'company') not in ('individual', 'freelance') then
    raise exception 'personal interface is for a personal account' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = p_user and status = 'active';
  return public.pack_for_member(p_org, p_user);
end $function$;

revoke all on function public.set_my_pack(uuid, text) from public;
revoke all on function public.set_member_pack(uuid, uuid, text) from public;
revoke all on function public.pack_for_member(uuid, uuid) from public;
grant execute on function public.set_my_pack(uuid, text) to authenticated;
grant execute on function public.set_member_pack(uuid, uuid, text) to authenticated;
grant execute on function public.pack_for_member(uuid, uuid) to authenticated;
