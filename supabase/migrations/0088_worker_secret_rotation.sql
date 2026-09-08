-- 0088 — تدوير سر الوركر بلا انقطاع
--
-- المشكلة: 97 دالة SECURITY DEFINER حارسها الوحيد سر واحد، ولا يوجد طريق لتغييره
-- بلا ان تتوقف المنصة بين لحظة تغييره في القاعدة ولحظة نشر الوركر بالسر الجديد.
--
-- الحل: يقبل سران معا فترة قصيرة. اجراء التدوير:
--   1) ادخل السر الجديد:  insert into app_settings values ('worker_secret_next', '<الجديد>');
--   2) انشر الوركر بالسر الجديد في WORKER_SECRET.
--   3) تحقق ان البوت والتقويم والاستيراد تعمل.
--   4) اعتمد الجديد:  update app_settings set value = '<الجديد>' where key = 'worker_secret';
--                      delete from app_settings where key = 'worker_secret_next';
-- وبين الخطوتين 1 و4 يقبل السران، فلا لحظة انقطاع واحدة.
create or replace function public.check_worker_secret(p_secret text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(p_secret, '') <> '' and length(p_secret) >= 32
     and exists (
       select 1 from public.app_settings
       where key in ('worker_secret', 'worker_secret_next') and value = p_secret
     )
$$;

-- تبقى مسحوبة من anon وauthenticated كما في 0087: لا مصدق مجانيا لاحد.
revoke execute on function public.check_worker_secret(text) from anon, authenticated;
