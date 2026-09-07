-- ============================================================
-- 0067 — قناة inapp توثق في المستودع كما هي في القاعدة الحية.
-- كل تنبيهات المنصة اليوم من نوع inapp (الجرس)، والقيد الحي يقبلها منذ
-- زمن، لكن 0001_init.sql ما زال يذكر أربع قنوات فقط. من يقرأ المستودع
-- كان يرى نظاما غير الذي يعمل، وأي إعادة بناء كانت ستسقط الجرس كله.
-- التنفيذ لا يغير سلوكا: القيد يعاد كتابته بنفس قيمه الحالية.
-- ============================================================

alter table public.notifications drop constraint if exists notifications_channel_check;
alter table public.notifications add constraint notifications_channel_check
  check (channel = any (array['inapp','email','telegram','whatsapp','sms']));
