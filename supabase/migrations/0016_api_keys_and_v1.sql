-- مفاتيح API لربط المنصات الأخرى: استيراد وتصدير عبر /api/v1/*. المفتاح يعرض مرة
-- واحدة ويخزن ببصمته، والـ Worker يحله إلى شركة. النص الكامل مطبق على المشروع
-- (api_keys, api_key_create, api_key_revoke, api_key_resolve, api_import, api_items_export).
-- الـ Worker يستدعي PostgREST بدور anon، فالدوال الثلاث تمنح له (الحماية بـ p_secret + بصمة المفتاح):
grant execute on function public.api_key_resolve(text, text) to anon;
grant execute on function public.api_import(text, text, text, text, jsonb, jsonb, jsonb) to anon;
grant execute on function public.api_items_export(text, text, text) to anon;
