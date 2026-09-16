begin;

-- 0135 — تحصين الصلاحيات: البنود العالية في القاعدة من فحص 2026-09-16.
-- أمر المهندس رعد: «صلح المشاكل دي الان».
-- النمط المتكرر في كل ما يلي: القرار يؤخذ في مكان والحارس يوضع في مكان آخر.
-- سياسات RLS لا ترى الصف القديم فلا تميز الإبقاء على قيمة من تغييرها، فتضاف
-- مشغلات BEFORE UPDATE تعوضها. والتمييز بين كتابة العميل وكتابة دوال المنصة
-- يكون بـ current_user: المتصفح يكتب بدور authenticated عبر PostgREST، ودوال
-- SECURITY DEFINER تنفذ بدور postgres مالكها.

-- ---------- 1) المشرف لا يرقي نفسه مالكا، ولا يمس صف المالك ----------
-- سياسة members_update نسخت «or user_id = auth.uid()» من USING إلى WITH CHECK،
-- وفي WITH CHECK تعني الصف الجديد، فصار المعنى: يجوز أن تجعل دورك أنت owner.
-- وبعدها لا يخفضه المالك (USING تسقط على صف دوره owner لغيره) ولا يحذفه
-- (members_delete تشترط role <> 'owner')، فالتصعيد دائم.
drop policy if exists members_update on public.org_members;
create policy members_update on public.org_members for update
  using (public.is_org_admin(org_id) and (role <> 'owner' or user_id = (select auth.uid())))
  with check (public.is_org_admin(org_id));

-- ليست SECURITY DEFINER عمدا: داخل دالة definer يصير current_user هو مالكها
-- (postgres) فلا يميز الحارس كتابة المتصفح من كتابة دوال المنصة. وهي لا تحتاج
-- صلاحية زائدة لأنها ترفع استثناء ولا تقرأ جدولا محميا.
create or replace function public.guard_member_row()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if public.is_platform_admin() then return new; end if;
  if new.user_id is distinct from old.user_id or new.org_id is distinct from old.org_id then
    raise exception 'MEMBER_IDENTITY_LOCKED' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    if new.role = 'owner' then
      raise exception 'OWNER_ROLE_NOT_GRANTABLE' using errcode = '42501';
    end if;
    if old.role = 'owner' then
      raise exception 'OWNER_ROLE_LOCKED' using errcode = '42501';
    end if;
  end if;
  return new;
end $function$;
drop trigger if exists members_guard_row on public.org_members;
create trigger members_guard_row before update on public.org_members
  for each row execute function public.guard_member_row();

-- ---------- 2) المشرف لا ينقل الملكية إلى نفسه ولا يمنح منشأته باقة ----------
-- orgs_update تشترط is_org_admin وحدها ولا تحصر الأعمدة، وorgs_delete تثق بعمود
-- owner_id. فمن كتب العمود لنفسه صار مالكا أمام كل ما يعتمد عليه ثم حذف المنشأة
-- بكل ما يتبعها من 22 مفتاحا خارجيا. وplan_code وplan_expires_at يكتبهما الدفع
-- وحده (pay_complete) فلا شأن للعميل بهما.
-- ليست SECURITY DEFINER عمدا: داخل دالة definer يصير current_user هو مالكها
-- (postgres) فلا يميز الحارس كتابة المتصفح من كتابة دوال المنصة. وهي لا تحتاج
-- صلاحية زائدة لأنها ترفع استثناء ولا تقرأ جدولا محميا.
create or replace function public.guard_org_row()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if public.is_platform_admin() then return new; end if;
  if new.owner_id is distinct from old.owner_id then
    raise exception 'OWNER_TRANSFER_REQUIRES_FUNCTION' using errcode = '42501';
  end if;
  if new.plan_code is distinct from old.plan_code
     or new.plan_expires_at is distinct from old.plan_expires_at then
    raise exception 'PLAN_IS_SET_BY_PAYMENT' using errcode = '42501';
  end if;
  return new;
end $function$;
drop trigger if exists orgs_guard_row on public.organizations;
create trigger orgs_guard_row before update on public.organizations
  for each row execute function public.guard_org_row();

-- نقل الملكية بابه الوحيد: المالك الحالي وحده، والمستقبل عضو نشط، والمالك
-- السابق يصير مشرفا فلا يخرج من حسابه فجأة.
create or replace function public.transfer_org_ownership(p_org uuid, p_new_owner uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_old uuid;
begin
  select owner_id into v_old from public.organizations where id = p_org;
  if v_old is null then raise exception 'NO_ORG' using errcode = '22023'; end if;
  if v_old <> auth.uid() and not public.is_platform_admin() then
    raise exception 'OWNER_ONLY' using errcode = '42501';
  end if;
  if p_new_owner = v_old then return jsonb_build_object('org', p_org, 'owner', v_old, 'changed', false); end if;
  if not exists (select 1 from public.org_members
                  where org_id = p_org and user_id = p_new_owner and status = 'active') then
    raise exception 'NEW_OWNER_NOT_MEMBER' using errcode = '22023';
  end if;
  update public.organizations set owner_id = p_new_owner where id = p_org;
  update public.org_members set role = 'admin' where org_id = p_org and user_id = v_old;
  update public.org_members set role = 'owner' where org_id = p_org and user_id = p_new_owner;
  return jsonb_build_object('org', p_org, 'owner', p_new_owner, 'previous', v_old, 'changed', true);
end $function$;
revoke all on function public.transfer_org_ownership(uuid, uuid) from public;
grant execute on function public.transfer_org_ownership(uuid, uuid) to authenticated;

-- ---------- 3) البريد هوية لا يكتبها صاحبها ----------
-- platform_admin_set تختار هدفها بـ lower(email)، وprofiles_update تتيح للمستخدم
-- كتابة صفه بلا حصر أعمدة، ولا فهرس فريد على البريد. فمن كتب بريد غيره في صفه
-- حول اختيار مدير المنصة إلى صف آخر.
-- ليست SECURITY DEFINER عمدا: داخل دالة definer يصير current_user هو مالكها
-- (postgres) فلا يميز الحارس كتابة المتصفح من كتابة دوال المنصة. وهي لا تحتاج
-- صلاحية زائدة لأنها ترفع استثناء ولا تقرأ جدولا محميا.
create or replace function public.guard_profile_row()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  -- الملء الأول مسموح (صف بلا بريد يكمله تسجيل الدخول)، والتغيير بعده ممنوع.
  if old.email is not null and new.email is distinct from old.email then
    raise exception 'EMAIL_IS_SET_BY_AUTH' using errcode = '42501';
  end if;
  if new.profile_number is distinct from old.profile_number then
    raise exception 'PROFILE_NUMBER_LOCKED' using errcode = '42501';
  end if;
  return new;
end $function$;
drop trigger if exists profiles_guard_row on public.profiles;
create trigger profiles_guard_row before update on public.profiles
  for each row execute function public.guard_profile_row();

create unique index if not exists profiles_email_unique on public.profiles (lower(email)) where email is not null;

-- الهوية القاطعة معرف لا بريد. النسخة بالبريد تبقى للواجهة حتى تنتقل، لكنها
-- ترفض إذا طابق البريد أكثر من صف بدل أن تختار واحدا بلا ترتيب.
create or replace function public.platform_admin_set(p_user uuid, p_admin boolean)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_count int;
begin
  if not public.is_platform_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_user is null or not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'NO_USER: لا يوجد مستخدم بهذا المعرف' using errcode = 'P0001';
  end if;
  if not p_admin then
    if p_user = auth.uid() then
      raise exception 'CANNOT_SELF_REMOVE: لا يمكنك إزالة صلاحيتك عن نفسك' using errcode = 'P0001';
    end if;
    select count(*) into v_count from public.profiles where is_platform_admin = true;
    if v_count <= 1 then
      raise exception 'LAST_ADMIN: لا يمكن ترك المنصة بلا مدير' using errcode = 'P0001';
    end if;
  end if;
  update public.profiles set is_platform_admin = p_admin where id = p_user;
end $function$;
revoke all on function public.platform_admin_set(uuid, boolean) from public;
grant execute on function public.platform_admin_set(uuid, boolean) to authenticated;

create or replace function public.platform_admin_set(p_email text, p_admin boolean)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_n int;
begin
  if not public.is_platform_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select count(*), min(id) into v_n, v_id from public.profiles where lower(email) = lower(trim(p_email));
  if v_n = 0 then raise exception 'NO_USER: لا يوجد مستخدم مسجّل بهذا البريد' using errcode = 'P0001'; end if;
  if v_n > 1 then raise exception 'AMBIGUOUS_EMAIL: البريد يطابق أكثر من حساب، استعمل المعرف' using errcode = 'P0001'; end if;
  perform public.platform_admin_set(v_id, p_admin);
end $function$;

-- ---------- 4) دليل المشتركين ليس مفتوحا لكل من سجل ----------
-- find_profile_for_invite تتجاوز سياسة profiles_read وهي ممنوحة لكل authenticated
-- بلا شرط عضوية، فيستعيد أي مسجل اسم وبريد وجوال أي مشترك لا يشاركه منشأة.
-- الدعوة عمل مالك أو مشرف، والمطابقة تصير قاطعة لا جزئية، والجوال لا يعاد.
create or replace function public.find_profile_for_invite(p_query text)
returns table(id uuid, full_name text, email text, phone text, profile_number text)
language plpgsql security definer set search_path to 'public' as $function$
declare q text;
begin
  q := lower(btrim(coalesce(p_query, '')));

  if public.is_platform_admin() then
    return query
      select p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      where p.id <> auth.uid()
        and (q = ''
             or lower(coalesce(p.email, '')) like '%' || q || '%'
             or coalesce(p.phone, '') like '%' || q || '%'
             or lower(coalesce(p.full_name, '')) like '%' || q || '%'
             or lower(coalesce(p.profile_number, '')) like '%' || q || '%')
      order by p.created_at desc
      limit 50;
  elsif q = '' then
    -- زملاء المنادي في منشآته: ما تتيحه سياسة profiles_read أصلا.
    return query
      select distinct p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      join public.org_members m on m.user_id = p.id
      where m.org_id in (select public.current_org_ids())
        and p.id <> auth.uid()
      limit 50;
  else
    if not exists (select 1 from public.org_members
                    where user_id = auth.uid() and status = 'active' and role in ('owner','admin')) then
      raise exception 'INVITE_REQUIRES_ADMIN' using errcode = '42501';
    end if;
    return query
      select p.id, p.full_name, p.email, null::text, p.profile_number
      from public.profiles p
      where p.id <> auth.uid()
        and (lower(coalesce(p.email, '')) = q or lower(coalesce(p.profile_number, '')) = q)
      limit 1;
  end if;
end $function$;

-- ---------- 5) قناة تيليغرام لا يدعيها أحد ----------
-- channel_links_rw تتيح للعميل كتابة external_id وverified_at بشرط user_id وحده،
-- والقاعدة والوركر يبنيان هوية المتحدث عليهما. فمن ادعى معرف محادثة ضحيته بتاريخ
-- تحقق أحدث حول مستنداتها إلى منشأته وردوده إلى محادثتها. الكتابة تصير في دوال
-- الربط وحدها، والقراءة والحذف يبقيان لصاحب الصف.
drop policy if exists channel_links_rw on public.channel_links;
drop policy if exists channel_links_read on public.channel_links;
drop policy if exists channel_links_delete on public.channel_links;
create policy channel_links_read on public.channel_links for select
  using (user_id = (select auth.uid()));
create policy channel_links_delete on public.channel_links for delete
  using (user_id = (select auth.uid()));

-- محادثة واحدة لا تخص شخصين: القيد يمنع الادعاء ولو تسربت الكتابة يوما.
create unique index if not exists channel_links_external_unique
  on public.channel_links (channel, external_id) where external_id is not null;

-- والربط يزيح أي صف قديم يحمل المحادثة نفسها: تيليغرام أثبت أنها للمرسل.
create or replace function public.link_channel_direct(p_secret text, p_user_id uuid, p_channel text, p_external_id text)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.check_worker_secret(p_secret) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  delete from public.channel_links
   where channel = p_channel and external_id = p_external_id and user_id <> p_user_id;
  insert into public.channel_links (user_id, channel, external_id, verify_code, verified_at)
  values (p_user_id, p_channel, p_external_id, null, now())
  on conflict (user_id, channel) do update
    set external_id = excluded.external_id, verify_code = null, verified_at = now();
end $function$;

-- الربط بالرقم لا يخمن: رقم الجوال يكتبه صاحبه بلا تحقق، فإن طابق أكثر من ملف
-- لا يختار النظام أحدا.
create or replace function public.link_channel_by_phone(p_secret text, p_channel text, p_phone text, p_external_id text)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_user uuid; v_digits text; v_n int;
begin
  if not public.check_worker_secret(p_secret) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_digits := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
  if length(v_digits) < 9 then return null; end if;
  select count(*), min(id) into v_n, v_user from public.profiles
  where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 9) = v_digits;
  if v_n <> 1 then return null; end if;
  perform public.link_channel_direct(p_secret, v_user, p_channel, p_external_id);
  return v_user;
end $function$;

-- بديل كتابة العميل لقناة الرسائل القصيرة: يسجل الرقم بلا تحقق ذاتي، فالتحقق
-- لا يكون بكلمة من المتصفح.
create or replace function public.set_sms_channel(p_phone text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_clean text;
begin
  if auth.uid() is null then raise exception 'forbidden' using errcode = '42501'; end if;
  v_clean := regexp_replace(coalesce(p_phone, ''), '[\s\-().]', '', 'g');
  if v_clean !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'INVALID_PHONE' using errcode = '22023'; end if;
  delete from public.channel_links where channel = 'sms' and external_id = v_clean and user_id <> auth.uid();
  insert into public.channel_links (user_id, channel, external_id, verify_code, verified_at)
  values (auth.uid(), 'sms', v_clean, null, null)
  on conflict (user_id, channel) do update set external_id = excluded.external_id, verify_code = null, verified_at = null;
  return jsonb_build_object('channel', 'sms', 'external_id', v_clean, 'verified', false);
end $function$;
revoke all on function public.set_sms_channel(text) from public;
grant execute on function public.set_sms_channel(text) to authenticated;

-- ---------- 6) رمز التقويم يموت بخروج صاحبه ----------
-- calendar_feed تتجاوز RLS ولا تفحص إلا وجود الرمز، ولا مسار يحذف الرموز عند
-- إزالة العضو. فمن ترك المنشأة بقي تقويمه يسحب مواعيدها إلى الأبد. والحالة قائمة
-- الآن: رمزان لشخصين لا عضوية لهما.
create or replace function public.calendar_feed(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_org uuid; v_user uuid; result jsonb;
begin
  select org_id, user_id into v_org, v_user from public.calendar_tokens where token = p_token;
  if v_org is null then return null; end if;
  if not exists (select 1 from public.org_members m
                  where m.org_id = v_org and m.user_id = v_user and m.status = 'active') then
    return null;
  end if;
  select jsonb_build_object(
    'org_name', (select name from public.organizations where id = v_org),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'title', i.title, 'category', i.category, 'due_at', i.due_at, 'status', i.status, 'record_name', t.name
      ) order by i.due_at)
      from public.items i left join public.records t on t.id = i.record_id
      where i.org_id = v_org and i.due_at is not null and i.status <> 'cancelled'), '[]'::jsonb)
  ) into result;
  return result;
end $function$;
revoke execute on function public.calendar_feed(text) from public;
grant execute on function public.calendar_feed(text) to anon, authenticated, service_role;

create or replace function public.drop_calendar_tokens_on_member_change()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if tg_op = 'DELETE' then
    delete from public.calendar_tokens where org_id = old.org_id and user_id = old.user_id;
    return old;
  end if;
  if new.status is distinct from 'active' then
    delete from public.calendar_tokens where org_id = new.org_id and user_id = new.user_id;
  end if;
  return new;
end $function$;
drop trigger if exists members_drop_calendar_tokens on public.org_members;
create trigger members_drop_calendar_tokens after update or delete on public.org_members
  for each row execute function public.drop_calendar_tokens_on_member_change();

-- الرموز القائمة لمن لا عضوية له تحذف الآن لا لاحقا.
delete from public.calendar_tokens t
 where not exists (select 1 from public.org_members m
                    where m.org_id = t.org_id and m.user_id = t.user_id and m.status = 'active');

-- ---------- 7) ثلاثة أعطال صغيرة تمنع أو تفتح بلا هوية ----------
-- الدالة التي تكتب الإشعارات فعلا كانت ممنوحة لـ PUBLIC: أي زائر بمفتاح anon
-- المنشور ينفذها بصلاحية postgres متجاوزة RLS. المستودع يقرر منعها منذ 0001.
revoke execute on function public.generate_due_notifications() from public, anon, authenticated;

-- api_key_create تنادي pgcrypto بلا تأهيل وsearch_path مثبت على public، فترفض
-- دائما بالخطأ 42883: عدد المفاتيح الصالحة على المنصة صفر ومساراr /api/v1 و/mcp
-- معطلان. pgcrypto في مخطط extensions كما في ledger_seal.
create or replace function public.api_key_create(p_org uuid, p_name text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_key text; v_id uuid;
begin
  if not public.is_org_admin(p_org) then raise exception 'forbidden' using errcode = '42501'; end if;
  v_key := 'mz_live_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.api_keys (org_id, name, key_hash, prefix, created_by)
  values (p_org, coalesce(nullif(trim(p_name), ''), 'API'), encode(extensions.digest(v_key, 'sha256'), 'hex'), left(v_key, 16), auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'key', v_key);
end $function$;

-- تنبيها الغياب وانتهاء التجربة يفحصان جدولا لم ينشأ قط (account_deletions)،
-- فيسقط الاستعلام ويبتلعه الكرون: لم يصل أحدا تنبيه منذ الإنشاء. مصدر الحقيقة
-- لحالة «قيد الحذف» هو profiles.delete_requested_at.
create or replace function public.telegram_absent_targets(p_secret text, p_days integer default 2, p_cooldown_days integer default 3)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare result jsonb; v_days integer := greatest(1, coalesce(p_days, 2)); v_cool integer := greatest(1, coalesce(p_cooldown_days, 3));
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into result from (
    select jsonb_build_object(
      'user_id', p.id,
      'chat_id', cl.external_id,
      'lang', coalesce(p.lang, 'ar'),
      'tz', coalesce(p.tz, 'Asia/Riyadh'),
      'time_format', coalesce(p.time_format, '24'),
      'name', p.full_name,
      'days_absent', floor(extract(epoch from (now() - coalesce(p.last_seen_at, p.created_at))) / 86400)::int,
      'open_total', (select count(*) from public.items i
                     where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active')
                       and i.status = 'open'),
      'overdue_count', (select count(*) from public.items i
                        where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active')
                          and i.status = 'open' and i.due_at is not null and i.due_at < now()),
      'due_soon_count', (select count(*) from public.items i
                         where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active')
                           and i.status = 'open' and i.due_at is not null and i.due_at >= now() and i.due_at < now() + interval '7 days'),
      'next_title', (select i.title from public.items i
                     where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active')
                       and i.status = 'open' and i.due_at is not null and i.due_at >= now()
                     order by i.due_at limit 1),
      'next_due', (select i.due_at from public.items i
                   where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active')
                     and i.status = 'open' and i.due_at is not null and i.due_at >= now()
                   order by i.due_at limit 1)
    ) as x
    from public.channel_links cl
    join public.profiles p on p.id = cl.user_id
    where cl.channel = 'telegram'
      and cl.verified_at is not null
      and cl.external_id is not null
      and extract(hour from (now() at time zone coalesce(p.tz, 'Asia/Riyadh'))) = 10
      and coalesce(p.last_seen_at, p.created_at) < now() - make_interval(days => v_days)
      and (cl.last_nudge_at is null or cl.last_nudge_at < now() - make_interval(days => v_cool))
      and p.delete_requested_at is null
  ) t;
  return result;
end $function$;

create or replace function public.telegram_trial_targets(p_secret text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into result from (
    select distinct on (p.id) jsonb_build_object(
      'user_id', p.id,
      'chat_id', cl.external_id,
      'lang', coalesce(p.lang, 'ar'),
      'tz', coalesce(p.tz, 'Asia/Riyadh'),
      'name', p.full_name,
      'org_name', o.name,
      'ends_at', o.plan_expires_at,
      'days_left', greatest(0, ceil(extract(epoch from (o.plan_expires_at - now())) / 86400)::int)
    ) as x
    from public.channel_links cl
    join public.profiles p on p.id = cl.user_id
    join public.org_members m on m.user_id = p.id and m.status = 'active' and m.role in ('owner', 'admin')
    join public.organizations o on o.id = m.org_id
    where cl.channel = 'telegram'
      and cl.verified_at is not null
      and cl.external_id is not null
      and o.plan_code = 'trial'
      and o.plan_expires_at is not null
      and o.plan_expires_at > now()
      and extract(hour from (now() at time zone coalesce(p.tz, 'Asia/Riyadh'))) = 9
      and (cl.last_trial_at is null
           or (cl.last_trial_at at time zone coalesce(p.tz, 'Asia/Riyadh'))::date
               < (now() at time zone coalesce(p.tz, 'Asia/Riyadh'))::date)
      and p.delete_requested_at is null
    order by p.id, o.plan_expires_at asc
  ) t;
  return result;
end $function$;

commit;
