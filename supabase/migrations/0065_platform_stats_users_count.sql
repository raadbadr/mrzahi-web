-- ============================================================
-- 0065 — أرقام المنصة العامة (الصفحة الرئيسية) تضيف عدد المستخدمين
-- المهندس رعد: «ضيف عدد المستخدمين قبل عدد الشركات في أرقام المنصة».
-- المستخدمون = كل صف في public.profiles، بنفس تعريف 'users' في
-- telegram_platform (0060_telegram_platform_admin_stats.sql). رقم
-- حقيقي من count(*) لا تقدير، اتساقاً مع منع الاختراع.
-- ============================================================

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
    'itemsDone', (select count(*) from public.items where status = 'done'),
    'notifications', (select count(*) from public.notifications where status = 'sent'),
    'notifEmail', (select count(*) from public.notifications where status = 'sent' and channel = 'email'),
    'notifTelegram', (select count(*) from public.notifications where status = 'sent' and channel = 'telegram'),
    'notifWhatsapp', (select count(*) from public.notifications where status = 'sent' and channel = 'whatsapp'),
    'notifSms', (select count(*) from public.notifications where status = 'sent' and channel = 'sms')
  )
$$;
