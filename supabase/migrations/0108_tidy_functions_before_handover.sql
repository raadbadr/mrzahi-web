-- الترحيل كما طبق على Supabase (version 20260905110212, name tidy_functions_before_handover); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- تنظيف قبل التسليم: مسار بحث ثابت لكل دالة، ولا دوال اختبار في الإنتاج،
-- ودالة المشغّل لا تُمنح لأحد (تُستدعى من المشغّل وحده).
drop function if exists public.test_parse_before_cases();

alter function public.telegram_parse_before(text) set search_path = public;
alter function public.item_kind(text, text, jsonb, uuid) set search_path = public;
alter function public.guard_platform_admin_column() set search_path = public;

revoke all on function public.tracker_default_rule() from public, anon, authenticated;
