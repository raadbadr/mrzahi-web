-- الترحيل كما طبق على Supabase (version 20260903201127, name tracker_0012_allow_inapp_channel); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- قناة التنبيه داخل الموقع تحتاج إذناً في قيد القنوات
alter table public.notifications drop constraint if exists notifications_channel_check;
alter table public.notifications add constraint notifications_channel_check
  check (channel in ('inapp', 'email', 'telegram', 'whatsapp', 'sms'));

alter table public.channel_links drop constraint if exists channel_links_channel_check;
alter table public.channel_links add constraint channel_links_channel_check
  check (channel in ('email', 'telegram', 'whatsapp', 'sms'));
