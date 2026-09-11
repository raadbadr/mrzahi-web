-- الترحيل كما طبق على Supabase (version 20260903200949, name tracker_0011_inapp_notifications); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- التنبيهات داخل الموقع أولاً: كل موعد يولّد تنبيهاً في جرس المنصة بصرف النظر عن
-- القنوات الخارجية، ويقرأه صاحبه ويعلّمه مقروءاً.
alter table public.notifications add column if not exists read_at timestamptz;
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, created_at desc) where read_at is null;

-- تحديث المولّد: قنوات القاعدة كما هي + قناة inapp دائماً، ولو لم توجد قاعدة تذكير
-- يُنبَّه المسؤول (أو كل الفريق) قبل الاستحقاق بيوم.
create or replace function public.generate_due_notifications()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare n int := 0; m int := 0;
begin
  -- (1) قنوات قواعد التذكير كما كانت + نسخة داخل الموقع
  insert into public.notifications (org_id, item_id, user_id, channel, scheduled_at, payload, status, sent_at)
  select i.org_id, i.id, mem.user_id, ch, i.due_at - make_interval(mins => r.offset_minutes),
         jsonb_build_object('title', i.title, 'due_at', i.due_at, 'tracker_id', i.tracker_id, 'item_number', i.item_number),
         case when ch = 'inapp' then 'sent' else 'pending' end,
         case when ch = 'inapp' then now() else null end
  from public.items i
  join public.reminder_rules r on r.org_id = i.org_id and (r.item_id = i.id or (r.item_id is null and r.tracker_id = i.tracker_id))
  cross join lateral unnest(r.channels || array['inapp']) as ch
  join public.org_members mem on mem.org_id = i.org_id and mem.status = 'active'
       and (r.target = 'all' or mem.user_id = i.assignee_id)
  where i.status = 'open' and i.due_at is not null
    and i.due_at - make_interval(mins => r.offset_minutes) <= now() + interval '5 minutes'
    and i.due_at > now() - interval '1 day'
  on conflict do nothing;
  get diagnostics n = row_count;

  -- (2) عناصر بلا قاعدة تذكير: تنبيه داخل الموقع قبل الاستحقاق بيوم
  insert into public.notifications (org_id, item_id, user_id, channel, scheduled_at, payload, status, sent_at)
  select i.org_id, i.id, mem.user_id, 'inapp', i.due_at - interval '1 day',
         jsonb_build_object('title', i.title, 'due_at', i.due_at, 'tracker_id', i.tracker_id, 'item_number', i.item_number),
         'sent', now()
  from public.items i
  join public.org_members mem on mem.org_id = i.org_id and mem.status = 'active'
       and (i.assignee_id is null or mem.user_id = i.assignee_id)
  where i.status = 'open' and i.due_at is not null
    and i.due_at - interval '1 day' <= now() + interval '5 minutes'
    and i.due_at > now() - interval '1 day'
    and not exists (
      select 1 from public.reminder_rules r
      where r.org_id = i.org_id and (r.item_id = i.id or (r.item_id is null and r.tracker_id = i.tracker_id))
    )
    and not exists (
      select 1 from public.notifications x
      where x.item_id = i.id and x.user_id = mem.user_id and x.channel = 'inapp'
    );
  get diagnostics m = row_count;

  return n + m;
end $function$;

-- المستخدم يعلّم تنبيهاته مقروءة
create or replace function public.mark_notifications_read()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare n int := 0;
begin
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.mark_notifications_read() from public, anon;
grant execute on function public.mark_notifications_read() to authenticated;
