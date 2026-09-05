-- حذف الحساب بنفس معيار باركينزي: طلب ذاتي، فترة سماح 30 يوما قابلة للإلغاء بالدخول، حذف نهائي بعدها.
-- تعمل عبر client.rpc() بجلسة المستخدم نفسها (كما rename_org)، فتصلح لأي عميل Supabase لاحقا (iOS/Android) بلا كود إضافي.
alter table public.profiles add column if not exists delete_requested_at timestamptz;

-- مالك شركة فيها أعضاء نشطون آخرون لا يحذف حسابه فورا: بياناتهم ليست ملكه وحده،
-- فيوقَف الطلب حتى ينقل الملكية أو يزيل الأعضاء (نفس ما تفرضه org_members_delete على المالك أصلا).
create or replace function public.request_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare v_uid uuid; v_blocking jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception 'unauthorized' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(o.name), '[]'::jsonb) into v_blocking
  from public.organizations o
  where o.owner_id = v_uid
    and exists (
      select 1 from public.org_members m
      where m.org_id = o.id and m.status = 'active' and m.user_id <> v_uid
    );

  if jsonb_array_length(v_blocking) > 0 then
    raise exception 'owner_has_team' using errcode = 'P0001', detail = v_blocking::text;
  end if;

  update public.profiles set delete_requested_at = now() where id = v_uid;
  return jsonb_build_object('scheduled_for', (now() + interval '30 days'));
end;
$function$;

revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;

-- الدخول خلال فترة السماح يلغي طلب الحذف تلقائيا، بلا زر إلغاء منفصل (كما في باركينزي بالضبط).
create or replace function public.cancel_own_account_deletion()
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare v_uid uuid; v_had boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception 'unauthorized' using errcode = '42501'; end if;
  select delete_requested_at is not null into v_had from public.profiles where id = v_uid;
  update public.profiles set delete_requested_at = null where id = v_uid;
  return coalesce(v_had, false);
end;
$function$;

revoke all on function public.cancel_own_account_deletion() from public, anon;
grant execute on function public.cancel_own_account_deletion() to authenticated;

-- التنفيذ النهائي بعد 30 يوما: يستدعيه الـ Worker دوريا بالسر المشترك، بلا مفتاح service role.
create or replace function public.purge_expired_account_deletions(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare v_user record; v_count int := 0;
begin
  if not public.check_worker_secret(p_secret) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  for v_user in
    select id from public.profiles
    where delete_requested_at is not null and delete_requested_at <= now() - interval '30 days'
  loop
    -- شركات يملكها وحيدا (بلا عضو نشط آخر): تحذف بكل عناصرها عبر cascade org_id الموجود أصلا
    delete from public.organizations o
      where o.owner_id = v_user.id
        and not exists (select 1 from public.org_members m where m.org_id = o.id and m.status = 'active' and m.user_id <> v_user.id);

    -- إن صار مالكا لفريق خلال فترة السماح: أوقف حذفه هذه الدورة حتى يحل وضعه يدويا
    if exists (
      select 1 from public.organizations o
      where o.owner_id = v_user.id
        and exists (select 1 from public.org_members m where m.org_id = o.id and m.status = 'active' and m.user_id <> v_user.id)
    ) then
      continue;
    end if;

    delete from public.org_members where user_id = v_user.id;
    delete from public.channel_links where user_id = v_user.id;
    delete from public.calendar_tokens where user_id = v_user.id;
    delete from public.notifications where user_id = v_user.id;
    update public.invitations set invited_by = null where invited_by = v_user.id;
    delete from public.profiles where id = v_user.id;
    delete from auth.users where id = v_user.id;
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('purged', v_count);
end;
$function$;

revoke all on function public.purge_expired_account_deletions(text) from public, anon, authenticated;
