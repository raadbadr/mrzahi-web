-- الترحيل كما طبق على Supabase (version 20260904060537, name tracker_0020_audit_policies_initplan); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- مراجعة الأداء (2/2): auth.uid() داخل (select …) لتُقيَّم مرة واحدة لا لكل صف،
-- والمعنى كما هو تماماً. وسياسة قراءة واحدة للاشتراكات بدل سياستين متداخلتين.

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (
  id = (select auth.uid()) or is_platform_admin()
  or exists (select 1 from public.org_members a join public.org_members b on a.org_id = b.org_id
             where a.user_id = (select auth.uid()) and b.user_id = profiles.id)
);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists orgs_read on public.organizations;
create policy orgs_read on public.organizations for select using (
  owner_id = (select auth.uid()) or id in (select current_org_ids()) or is_platform_admin()
);
drop policy if exists orgs_insert on public.organizations;
create policy orgs_insert on public.organizations for insert with check (owner_id = (select auth.uid()));
drop policy if exists orgs_delete on public.organizations;
create policy orgs_delete on public.organizations for delete using (owner_id = (select auth.uid()));

drop policy if exists members_delete on public.org_members;
create policy members_delete on public.org_members for delete
  using (is_org_admin(org_id) or user_id = (select auth.uid()));

drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select
  using (user_id = (select auth.uid()) or org_id in (select current_org_ids()));
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications for delete
  using (user_id = (select auth.uid()));

drop policy if exists channel_links_rw on public.channel_links;
create policy channel_links_rw on public.channel_links for all
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists calendar_tokens_rw on public.calendar_tokens;
create policy calendar_tokens_rw on public.calendar_tokens for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and org_id in (select current_org_ids()));

drop policy if exists plan_requests_insert on public.plan_requests;
create policy plan_requests_insert on public.plan_requests for insert
  with check (is_org_admin(org_id) and created_by = (select auth.uid()));

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments for insert
  with check (org_id in (select current_org_ids()) and uploaded_by = (select auth.uid()));
drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments for delete
  using (uploaded_by = (select auth.uid()) or is_org_admin(org_id));

drop policy if exists team_messages_read on public.team_messages;
create policy team_messages_read on public.team_messages for select using (
  org_id in (select current_org_ids())
  and (to_user_id is null or to_user_id = (select auth.uid()) or author_id = (select auth.uid()))
);
drop policy if exists team_messages_insert on public.team_messages;
create policy team_messages_insert on public.team_messages for insert
  with check (org_id in (select current_org_ids()) and author_id = (select auth.uid()));
drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_delete on public.team_messages for delete
  using (author_id = (select auth.uid()) or is_org_admin(org_id));

-- الاشتراكات: القراءة في سياسة واحدة، وصلاحيات المدير للكتابة فقط
drop policy if exists subscriptions_admin on public.subscriptions;
create policy subscriptions_admin_insert on public.subscriptions for insert with check (is_platform_admin());
create policy subscriptions_admin_update on public.subscriptions for update using (is_platform_admin()) with check (is_platform_admin());
create policy subscriptions_admin_delete on public.subscriptions for delete using (is_platform_admin());
