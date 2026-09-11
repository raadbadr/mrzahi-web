-- الترحيل كما طبق على Supabase (version 20260907225855, name absence_nudge_over_telegram); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- من يغيب عن المنصة تصله رسالة تيليغرام ودية بأرقام حسابه الحقيقية.
-- آخر ظهور يسجله المتصفح مرة في اليوم؛ والتنبيه يخرج مرة كل ثلاثة أيام على الأكثر، الساعة العاشرة بتوقيت المستخدم.

alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.channel_links add column if not exists last_nudge_at timestamptz;

-- يستدعيها المتصفح بجلسة المستخدم نفسه: لا سر ولا صلاحية زائدة
create or replace function public.mark_seen()
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.profiles set last_seen_at = now() where id = auth.uid();
$$;
revoke all on function public.mark_seen() from public, anon;
grant execute on function public.mark_seen() to authenticated;

-- من يستحق الرسالة الآن، ومعه أرقامه كي لا يخترع البوت شيئا
create or replace function public.telegram_absent_targets(p_secret text, p_days integer default 2, p_cooldown_days integer default 3)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
      and not exists (select 1 from public.account_deletions d where d.user_id = p.id and d.cancelled_at is null)
  ) t;
  return result;
end $function$;
revoke all on function public.telegram_absent_targets(text, integer, integer) from public, anon, authenticated;

create or replace function public.telegram_mark_nudge(p_secret text, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  update public.channel_links set last_nudge_at = now() where user_id = p_user_id and channel = 'telegram';
end $function$;
revoke all on function public.telegram_mark_nudge(text, uuid) from public, anon, authenticated;
