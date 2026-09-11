-- الترحيل كما طبق على Supabase (version 20260903104524, name tracker_0003_harden_function_grants); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- تقوية: دوال التريغر والدوال الداخلية لا تُستدعى عبر RPC من anon/authenticated
alter function public.touch_updated_at() set search_path = public;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_new_org() from public, anon, authenticated;
revoke execute on function public.enforce_item_limit() from public, anon, authenticated;
revoke execute on function public.enforce_member_limit() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;
revoke execute on function public.generate_due_notifications() from public, anon, authenticated;
-- دوال السياسات: تبقى للمسجلين فقط (تُستخدم داخل RLS ومن common.js)
revoke execute on function public.current_org_ids() from public, anon;
revoke execute on function public.is_org_admin(uuid) from public, anon;
revoke execute on function public.is_platform_admin() from public, anon;
revoke execute on function public.effective_plan(uuid) from public, anon;
grant execute on function public.current_org_ids() to authenticated;
grant execute on function public.is_org_admin(uuid) to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.effective_plan(uuid) to authenticated;
-- دوال الـ Worker: تبقى لـ anon (محمية بالسر/الرمز) ولا تُعطى للمسجلين
revoke execute on function public.check_worker_secret(text) from authenticated;
revoke execute on function public.cron_pending_notifications(text) from authenticated;
revoke execute on function public.cron_mark_notification(text, uuid, text, text) from authenticated;
revoke execute on function public.calendar_feed(text) from authenticated;
revoke execute on function public.link_channel(text, text, text, text) from authenticated;
revoke execute on function public.notify_target(text, uuid, text) from authenticated;
-- الافتراضي للدوال الجديدة: لا تنفيذ تلقائي لـ anon/authenticated
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
