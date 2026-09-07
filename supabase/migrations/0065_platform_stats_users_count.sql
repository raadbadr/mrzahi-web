-- ============================================================
-- 0065 — أرقام المنصة العامة (الصفحة الرئيسية) تضيف عدد المستخدمين
-- المهندس رعد: «ضيف عدد المستخدمين قبل عدد الشركات في أرقام المنصة».
-- المستخدمون = كل صف في public.profiles، بنفس تعريف 'users' في
-- telegram_platform (0060_telegram_platform_admin_stats.sql). رقم
-- حقيقي من count(*) لا تقدير، اتساقا مع منع الاختراع.
-- ============================================================

-- دمج لاحق (0063/0064): لا تطبق هذه النسخة بلا itemsNoDue وnotifInapp، وإلا رجع عطلان
-- ثابتان بالأرقام الحقيقية إلى الظهور (12+1+0 لا يساوي 15، و17 مقابل صفر في كل قناة خارجية).
create or replace function public.platform_stats()
returns jsonb
language sql
stable security definer
set search_path = public
as $$
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
    'notifSms', (select count(*) from public.notifications where status = 'sent' and channel = 'sms'),
    'telegramMessages', (select count(*) from public.telegram_messages)
  )
$$;
