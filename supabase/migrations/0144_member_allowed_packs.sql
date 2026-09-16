-- 0144 — المهندس رعد 2026-09-16: «في تست، لاني عضو، في لستة الواجهات ما تظهر
-- غير المسموح لي بها». المدير يحدد الواجهات المسموحة لكل عضو، والعضو يختار
-- منها وحدها. null أو مصفوفة فارغة = بلا تضييق (كل الواجهات)، فلا يتغير شيء
-- لمن لم يحدد له مديره شيئا، ويبقى قادرا على تغيير واجهته كما في 0143.
begin;

alter table public.org_members add column if not exists allowed_packs text[];

comment on column public.org_members.allowed_packs is
  'الواجهات المسموحة لهذا العضو. null = كل الواجهات. المالك والمدير وحدهما يضبطانها.';

create or replace function public.packs_allowed_for(p_org uuid, p_user uuid)
returns text[] language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    (select m.allowed_packs from public.org_members m
      where m.org_id = p_org and m.user_id = p_user and m.status = 'active'
        and m.allowed_packs is not null and array_length(m.allowed_packs, 1) > 0),
    (select array_agg(key order by sort_order, key) from public.ui_packs where active)
  )
$function$;

create or replace function public.set_member_allowed_packs(p_org uuid, p_user uuid, p_packs text[])
returns text[] language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_clean text[];
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_packs is null or array_length(p_packs, 1) is null then
    v_clean := null;
  else
    select array_agg(u.key order by u.sort_order, u.key) into v_clean
      from public.ui_packs u where u.active and u.key = any (p_packs);
    if v_clean is null then
      raise exception 'unknown pack' using errcode = '22023';
    end if;
  end if;
  update public.org_members set allowed_packs = v_clean
   where org_id = p_org and user_id = p_user and status = 'active';
  update public.org_members set ui_pack = null
   where org_id = p_org and user_id = p_user and status = 'active'
     and ui_pack is not null and v_clean is not null and not (ui_pack = any (v_clean));
  return public.packs_allowed_for(p_org, p_user);
end $function$;

create or replace function public.set_my_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  if p_pack is not null and not (p_pack = any (public.packs_allowed_for(p_org, auth.uid()))) then
    raise exception 'this interface is not allowed for you' using errcode = '42501';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  return public.pack_for_member(p_org, auth.uid());
end $function$;

create or replace function public.my_pack_config(p_org uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with k as (select public.pack_for_member(p_org, (select auth.uid())) as key)
  select case when (select key from k) is null then null else jsonb_build_object(
    'pack',       (select key from k),
    'names',      (select names  from public.ui_packs where key = (select key from k)),
    'labels',     (select labels from public.ui_packs where key = (select key from k)),
    'is_default', (select is_default from public.ui_packs where key = (select key from k)),
    'allowed',    to_jsonb(public.packs_allowed_for(p_org, (select auth.uid()))),
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
$function$;

grant execute on function public.packs_allowed_for(uuid, uuid) to authenticated;
grant execute on function public.set_member_allowed_packs(uuid, uuid, text[]) to authenticated;

commit;
