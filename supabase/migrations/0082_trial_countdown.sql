-- رسالة يومية في الفترة التجريبية: كم بقي على انتهائها (أمر المهندس رعد 2026-09-08).
-- لصاحب الحساب ومشرفيه وحدهم، مرة واحدة في اليوم، التاسعة بتوقيت المستخدم.
-- مطبقة على القاعدة الحية باسم daily_trial_countdown_over_telegram.
alter table public.channel_links add column if not exists last_trial_at timestamptz;
