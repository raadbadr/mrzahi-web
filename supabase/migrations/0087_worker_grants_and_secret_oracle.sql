-- 0087 — منح دوال الوركر الاربع التي كانت ممنوعة عن anon، وسحب المصدق المجاني
--
-- 1) الوركر ينادي القاعدة بمفتاح anon. اربع دوال محروسة بسر الوركر كانت مسحوبة
--    منه، فكانت تفشل كل يوم بصمت: تنبيه الغياب والعد التنازلي للتجربة لم يعملا
--    يوما واحدا (5 ارتباطات تليغرام: 5 ملخصات، صفر تنبيه، صفر رسالة تجربة).
grant execute on function public.telegram_absent_targets(text, integer, integer) to anon;
grant execute on function public.telegram_mark_nudge(text, uuid)                 to anon;
grant execute on function public.telegram_trial_targets(text)                    to anon;
grant execute on function public.telegram_mark_trial(text, uuid)                 to anon;

-- 2) check_worker_secret كانت ممنوحة لـ anon، فصارت مصدقا مجانيا: اي زائر
--    بالمفتاح العام ينادها بسر مرشح فتجيبه true او false نظيفة بلا حد محاولات.
--    لا حاجة لهذا المنح: الوركر لا ينادها مباشرة، وانما تنادى من داخل دوال
--    SECURITY DEFINER اخرى، والنداء الداخلي ينفذ بصلاحية مالك الدالة لا بصلاحية المنادي.
revoke execute on function public.check_worker_secret(text) from anon, authenticated;
