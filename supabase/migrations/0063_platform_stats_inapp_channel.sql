-- المستحق الآن يحسب فقط القنوات الخارجية (بريد، تيليغرام، واتساب، SMS)
-- فيغيب عنه تنبيهات الجرس داخل المنصة (channel = 'inapp')، وهي القناة الأولى فعليا.
-- أظهر ذلك: 17 تنبيها مرسلا في المجموع مقابل صفر في كل قناة من التفصيل الأربع.
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
    'itemsDone', (select count(*) from public.items where status = 'done'),
    'notifications', (select count(*) from public.notifications where status = 'sent'),
    'notifInapp', (select count(*) from public.notifications where status = 'sent' and channel = 'inapp'),
    'notifEmail', (select count(*) from public.notifications where status = 'sent' and channel = 'email'),
    'notifTelegram', (select count(*) from public.notifications where status = 'sent' and channel = 'telegram'),
    'notifWhatsapp', (select count(*) from public.notifications where status = 'sent' and channel = 'whatsapp'),
    'notifSms', (select count(*) from public.notifications where status = 'sent' and channel = 'sms')
  )
$function$;
