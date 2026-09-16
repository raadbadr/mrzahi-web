-- 0138 — تخزين المنشأة قرار إدارة، ورمز ربط تيليغرام يستهلك مرة واحدة.
-- من فحص الصلاحيات 2026-09-16، أمر المهندس رعد «صلح المشاكل دي الان».
begin;

-- ---------- 1) تخزين درايف: مالك أو مشرف لا أي عضو ----------
-- الوركر يفحص الدور قبل جوجل ويعالج حالة not_admin، والقاعدة لا تعيدها أبدا لأن
-- الدوال الثلاث تنادي drive_conn_member. فكان الموظف العادي يستبدل رمز تحديث
-- المنشأة برمزه هو، فترفع مرفقات الشركة بعدها إلى درايفه ويبقى مالكا لها بعد
-- خروجه، أو يقطع ربط الشركة كله. دالة drive_conn_admin موجودة بلا مستدع منذ 0085.
create or replace function public.drive_conn_can_connect(p_secret text, p_org uuid, p_user uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;
  return jsonb_build_object('status', 'ok');
end $function$;

create or replace function public.drive_conn_save(p_secret text, p_org uuid, p_user uuid, p_refresh text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if coalesce(btrim(p_refresh), '') = '' then return jsonb_build_object('status', 'no_token'); end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;
  insert into public.drive_connections (org_id, refresh_token, connected_by, connected_at)
  values (p_org, p_refresh, p_user, now())
  on conflict (org_id) do update
    set refresh_token = excluded.refresh_token,
        connected_by = excluded.connected_by,
        connected_at = now();
  return jsonb_build_object('status', 'saved');
end $function$;

create or replace function public.drive_conn_forget(p_secret text, p_org uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_member(p_org, p_user) then return jsonb_build_object('status', 'not_member'); end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;
  delete from public.drive_connections where org_id = p_org;
  return jsonb_build_object('status', 'forgotten');
end $function$;

-- ---------- 2) رمز ربط تيليغرام يستهلك مرة واحدة ----------
-- الرمز كان يوقع معرف المحادثة ووقت الانتهاء وحدهما، ويبقى صالحا يوما كاملا،
-- ويقبل من أي جلسة. فمن كتب للبوت أخذ رابطا موقعا لمحادثته هو وأرسله للضحية،
-- فنقرة واحدة منها وهي مسجلة الدخول تحول صفها إلى محادثة المهاجم. الرمز الآن
-- سطر في القاعدة: يصدر لمحادثة، ويستهلك مرة، ويموت بعد عشر دقائق.
create table if not exists public.telegram_link_tokens (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid
);
create index if not exists telegram_link_tokens_expiry on public.telegram_link_tokens (expires_at);
alter table public.telegram_link_tokens enable row level security;
-- لا سياسة للعميل: الوركر وحده يمر بالدوال أدناه.

create or replace function public.tglink_issue(p_secret text, p_chat_id text, p_minutes integer default 10)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_exp timestamptz;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if coalesce(btrim(p_chat_id), '') = '' then raise exception 'NO_CHAT' using errcode = '22023'; end if;
  delete from public.telegram_link_tokens where expires_at < now() - interval '1 day';
  v_exp := now() + make_interval(mins => greatest(1, least(60, coalesce(p_minutes, 10))));
  insert into public.telegram_link_tokens (chat_id, expires_at) values (btrim(p_chat_id), v_exp)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'expires_at', v_exp);
end $function$;

create or replace function public.tglink_consume(p_secret text, p_id uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_chat text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  update public.telegram_link_tokens
     set used_at = now(), used_by = p_user
   where id = p_id and used_at is null and expires_at > now()
  returning chat_id into v_chat;
  if v_chat is null then return jsonb_build_object('status', 'invalid'); end if;
  return jsonb_build_object('status', 'ok', 'chat_id', v_chat);
end $function$;

create or replace function public.tglink_peek(p_secret text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_chat text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select chat_id into v_chat from public.telegram_link_tokens
   where id = p_id and used_at is null and expires_at > now();
  if v_chat is null then return jsonb_build_object('status', 'invalid'); end if;
  return jsonb_build_object('status', 'ok', 'chat_id', v_chat);
end $function$;

revoke all on function public.tglink_issue(text, text, integer) from public;
revoke all on function public.tglink_consume(text, uuid, uuid) from public;
revoke all on function public.tglink_peek(text, uuid) from public;
grant execute on function public.tglink_issue(text, text, integer) to anon, authenticated, service_role;
grant execute on function public.tglink_consume(text, uuid, uuid) to anon, authenticated, service_role;
grant execute on function public.tglink_peek(text, uuid) to anon, authenticated, service_role;

commit;
