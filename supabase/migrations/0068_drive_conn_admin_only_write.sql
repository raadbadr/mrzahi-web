-- ============================================================
-- 0068 - ربط درايف وفصله لمالك الشركة ومديرها وحدهما.
-- الثغرة: 0067 كان يقبل اي عضو نشط، فكان بامكان موظف عادي ان يحول
-- تخزين ملفات الشركة كلها الى درايفه الشخصي، او ان يفصل الاتصال عن
-- الشركة. القراءة تبقى لكل عضو نشط لان كل عضو يرفع ويقرا ملفات.
-- ============================================================

create or replace function public.drive_conn_admin(p_org uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org and m.user_id = p_user
      and m.status = 'active' and m.role in ('owner', 'admin')
  )
$$;

revoke all on function public.drive_conn_admin(uuid, uuid) from public, anon, authenticated;

create or replace function public.drive_conn_save(p_secret text, p_org uuid, p_user uuid, p_refresh text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if coalesce(btrim(p_refresh), '') = '' then return jsonb_build_object('status', 'no_token'); end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;

  insert into public.drive_connections (org_id, refresh_token, connected_by, connected_at)
  values (p_org, p_refresh, p_user, now())
  on conflict (org_id) do update
    set refresh_token = excluded.refresh_token,
        connected_by = excluded.connected_by,
        connected_at = now();

  return jsonb_build_object('status', 'saved');
end $$;

create or replace function public.drive_conn_forget(p_secret text, p_org uuid, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;
  delete from public.drive_connections where org_id = p_org;
  return jsonb_build_object('status', 'forgotten');
end $$;

revoke all on function public.drive_conn_save(text, uuid, uuid, text) from public;
grant execute on function public.drive_conn_save(text, uuid, uuid, text) to anon, service_role;
revoke all on function public.drive_conn_forget(text, uuid, uuid) from public;
grant execute on function public.drive_conn_forget(text, uuid, uuid) to anon, service_role;
