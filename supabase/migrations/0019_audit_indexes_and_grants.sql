-- الترحيل كما طبق على Supabase (version 20260904060459, name tracker_0019_audit_indexes_and_grants); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- مراجعة الأمان والأداء (1/2): دوال المشغّلات لا تُستدعى من الواجهة، وفهارس المفاتيح الأجنبية

-- دوال المشغّلات لا تحتاج تنفيذاً من anon/authenticated
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and pg_get_function_result(p.oid) = 'trigger'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- فهارس تغطية للمفاتيح الأجنبية التي أشار إليها الفاحص
create index if not exists attachments_uploaded_by_idx      on public.attachments (uploaded_by);
create index if not exists calendar_tokens_org_idx          on public.calendar_tokens (org_id);
create index if not exists imports_created_by_idx           on public.imports (created_by);
create index if not exists imports_tracker_idx              on public.imports (tracker_id);
create index if not exists invitations_invited_by_idx       on public.invitations (invited_by);
create index if not exists invitations_org_idx              on public.invitations (org_id);
create index if not exists items_created_by_idx             on public.items (created_by);
create index if not exists items_import_idx                 on public.items (import_id);
create index if not exists notifications_org_idx            on public.notifications (org_id);
create index if not exists org_members_invited_by_idx       on public.org_members (invited_by);
create index if not exists org_members_user_idx             on public.org_members (user_id);
create index if not exists organizations_owner_idx          on public.organizations (owner_id);
create index if not exists organizations_plan_code_idx      on public.organizations (plan_code);
create index if not exists plan_requests_created_by_idx     on public.plan_requests (created_by);
create index if not exists plan_requests_decided_by_idx     on public.plan_requests (decided_by);
create index if not exists plan_requests_plan_code_idx      on public.plan_requests (plan_code);
create index if not exists reminder_rules_item_idx          on public.reminder_rules (item_id);
create index if not exists reminder_rules_tracker_idx       on public.reminder_rules (tracker_id);
create index if not exists subscriptions_activated_by_idx   on public.subscriptions (activated_by);
create index if not exists subscriptions_plan_code_idx      on public.subscriptions (plan_code);
create index if not exists team_messages_author_idx         on public.team_messages (author_id);
create index if not exists team_messages_item_idx           on public.team_messages (item_id);
create index if not exists team_messages_to_user_idx        on public.team_messages (to_user_id);
create index if not exists trackers_created_by_idx          on public.trackers (created_by);
