-- ============================================================
-- 0085 - تراجع عن 0068 و0084: ربط درايف وفصله يعود لكل عضو نشط.
--
-- سبب التراجع: قصر الربط على المالك والمدير كان قرارا مني انا لا
-- امرا من المهندس رعد. هو طلب نقل التفويض الى الخادم حتى لا يعيد
-- العميل تسجيل الدخول، ولم يطلب تغيير من يملك الربط في شركته.
-- تحديد الصلاحيات قرار منتج يخصه وحده.
--
-- تعاد الحالة الى ما كانت عليه في 0067 بالضبط: كل عضو نشط يربط
-- ويفصل ويستعمل. تبقى دالة drive_conn_admin موجودة بلا استعمال حتى
-- يقرر هو، فحذفها تغيير اخر لم يطلبه.
-- ============================================================

create or replace function public.drive_conn_save(p_secret text, p_org uuid, p_user uuid, p_refresh text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if coalesce(btrim(p_refresh), '') = '' then return jsonb_build_object('status', 'no_token'); end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;

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
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;
  delete from public.drive_connections where org_id = p_org;
  return jsonb_build_object('status', 'forgotten');
end $$;

-- الفحص قبل شاشة موافقة جوجل يبقى موجودا لكن بشرط العضوية لا الادارة
create or replace function public.drive_conn_can_connect(p_secret text, p_org uuid, p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;
  return jsonb_build_object('status', 'ok');
end $$;

revoke all on function public.drive_conn_save(text, uuid, uuid, text) from public;
grant execute on function public.drive_conn_save(text, uuid, uuid, text) to anon, service_role;
revoke all on function public.drive_conn_forget(text, uuid, uuid) from public;
grant execute on function public.drive_conn_forget(text, uuid, uuid) to anon, service_role;
revoke all on function public.drive_conn_can_connect(text, uuid, uuid) from public;
grant execute on function public.drive_conn_can_connect(text, uuid, uuid) to anon, service_role;
