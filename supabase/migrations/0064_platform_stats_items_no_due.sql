-- نفس عطل الإشعارات: itemsUpcoming (due_at >= now) وitemsOverdue (due_at < now) لا تحسبان
-- عنصرا بلا موعد استحقاق (due_at is null) لأن أي مقارنة بـ null تعطي null لا true، فيسقط من الفلترين معا.
-- 15 عنصرا إجمالا مقابل 12 + 1 + 0 = 13 في التفصيل يظهر هذا بوضوح: عنصران بلا موعد غير محسوبين.
create or replace function public.platform_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'organizations', (select count(*) from public.organizations),
    'trackers', (select count(*) from public.trackers),
    'items', (select count(*) from public.items),
    'itemsUpcoming', (select count(*) from public.items where status = 'open' and due_at >= now()),
    'itemsOverdue', (select count(*) from public.items where status = 'open' and due_at < now()),
    'itemsNoDue', (select count(*) from public.items where status = 'open' and due_at is null),
    'itemsDone', (select count(*) from public.items where status = 'done'),
    'notifications', (select count(*) from public.notifications where status = 'sent'),
    'notifInapp', (select count(*) from public.notifications where status = 'sent' and channel = 'inapp'),
    'notifEmail', (select count(*) from public.notifications where status = 'sent' and channel = 'email'),
    'notifTelegram', (select count(*) from public.notifications where status = 'sent' and channel = 'telegram'),
    'notifWhatsapp', (select count(*) from public.notifications where status = 'sent' and channel = 'whatsapp'),
    'notifSms', (select count(*) from public.notifications where status = 'sent' and channel = 'sms')
  )
$function$;
