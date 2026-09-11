-- الترحيل كما طبق على Supabase (version 20260907231916, name daily_trial_countdown_over_telegram); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- رسالة يومية في الفترة التجريبية: كم بقي على انتهائها (أمر المهندس رعد 2026-09-08).
-- لصاحب الحساب ومشرفيه وحدهم لا لكل الموظفين، مرة واحدة في اليوم، التاسعة بتوقيت المستخدم.
alter table public.channel_links add column if not exists last_trial_at timestamptz;

create or replace function public.telegram_trial_targets(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
      and not exists (select 1 from public.account_deletions d where d.user_id = p.id and d.cancelled_at is null)
    order by p.id, o.plan_expires_at asc
  ) t;
  return result;
end $function$;
revoke all on function public.telegram_trial_targets(text) from public, anon, authenticated;

create or replace function public.telegram_mark_trial(p_secret text, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  update public.channel_links set last_trial_at = now() where user_id = p_user_id and channel = 'telegram';
end $function$;
revoke all on function public.telegram_mark_trial(text, uuid) from public, anon, authenticated;
