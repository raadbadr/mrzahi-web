-- الترحيل كما طبق على Supabase (version 20260903211957, name tracker_0017_delete_own_notifications); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- لكل مستخدم أن يحذف تنبيهاته
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications
  for delete using (user_id = auth.uid());

grant delete on public.notifications to authenticated;
