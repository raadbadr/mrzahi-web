-- ============================================================
-- 0067 - تفويض Google Drive من الخادم بدل المتصفح.
-- المشكلة: رمز الوصول من Google Identity Services قصير الاجل ولا
-- يحمل رمز تحديث، فيضيع مع كل اعادة تحميل صفحة وتفتح نافذة اذن
-- جديدة في كل مرة. الحل: رمز تحديث دائم يخزن هنا مرة واحدة،
-- والوركر وحده يستبدله برمز وصول قصير عند الحاجة.
--
-- رمز التحديث بيان حساس: لا يقرا من المتصفح اطلاقا. الجدول بلا اي
-- سياسة RLS (فلا وصول لاحد)، والوصول الوحيد عبر دوال SECURITY
-- DEFINER محمية بـ check_worker_secret، وكل دالة تتحقق ايضا ان
-- الطالب عضو نشط في الشركة قبل ان تعطيه شيئا.
-- ============================================================

create table if not exists public.drive_connections (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  refresh_token text not null,
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  last_used_at timestamptz
);

alter table public.drive_connections enable row level security;
-- بلا سياسات: لا احد يصل الى الجدول مباشرة، لا anon ولا authenticated
revoke all on public.drive_connections from anon, authenticated;

-- عضوية نشطة في الشركة: شرط كل عملية على اتصال درايف
create or replace function public.drive_conn_member(p_org uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org and m.user_id = p_user and m.status = 'active'
  )
$$;

revoke all on function public.drive_conn_member(uuid, uuid) from public, anon, authenticated;

-- حفظ رمز التحديث بعد موافقة صاحب الحساب مرة واحدة
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

-- رمز التحديث للوركر وحده: لا يعاد الا لعضو نشط في الشركة نفسها
create or replace function public.drive_conn_token(p_secret text, p_org uuid, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_token text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;

  select refresh_token into v_token from public.drive_connections where org_id = p_org;
  if v_token is null then return jsonb_build_object('status', 'not_connected'); end if;

  update public.drive_connections set last_used_at = now() where org_id = p_org;
  return jsonb_build_object('status', 'ok', 'refresh_token', v_token);
end $$;

-- فصل الاتصال: يحذف الرمز نهائيا من عندنا
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

-- الوركر ينادي PostgREST بدور anon، والحماية هي السر لا الدور
revoke all on function public.drive_conn_save(text, uuid, uuid, text) from public;
grant execute on function public.drive_conn_save(text, uuid, uuid, text) to anon, service_role;
revoke all on function public.drive_conn_token(text, uuid, uuid) from public;
grant execute on function public.drive_conn_token(text, uuid, uuid) to anon, service_role;
revoke all on function public.drive_conn_forget(text, uuid, uuid) from public;
grant execute on function public.drive_conn_forget(text, uuid, uuid) to anon, service_role;
