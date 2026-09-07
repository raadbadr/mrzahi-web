-- ============================================================
-- 0063 — إعادة رقن ما طبق على القاعدة الحية ولم يدخل أي ملف هجرة:
-- جدول api_keys ودوالها الخمس، وحاوية التخزين attachments وسياساتها.
-- نص وصفي بلا أي تغيير سلوك: ينسخ ما هو مطبق اليوم حرفيا حتى يصير
-- المخطط قابلا لإعادة البناء من المستودع وحده. (رصدتها مراجعة أمنية،
-- 2026-09-06). كل عبارة آمنة التكرار (idempotent) فتطبيقها على القاعدة
-- الحية لا يغير شيئا — تحقق منه هذا الالتزام قبل الدفع.
-- ============================================================

-- ---------- (1) جدول مفاتيح الربط الخارجي (/api/v1/*) ----------
create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  key_hash text not null unique,
  prefix text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

alter table public.api_keys enable row level security;

drop policy if exists api_keys_read on public.api_keys;
create policy api_keys_read on public.api_keys for select
  using (public.is_org_admin(org_id));

-- ---------- (2) إصدار مفتاح وإلغاؤه: لمدير الشركة عبر جلسته (auth.uid) ----------
create or replace function public.api_key_create(p_org uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_key text; v_id uuid;
begin
  if not public.is_org_admin(p_org) then raise exception 'forbidden' using errcode = '42501'; end if;
  v_key := 'tt_live_' || encode(gen_random_bytes(24), 'hex');
  insert into public.api_keys (org_id, name, key_hash, prefix, created_by)
  values (p_org, coalesce(nullif(trim(p_name), ''), 'API'), encode(digest(v_key, 'sha256'), 'hex'), left(v_key, 16), auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'key', v_key);
end $$;

create or replace function public.api_key_revoke(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.api_keys set revoked_at = now()
  where id = p_id and public.is_org_admin(org_id) and revoked_at is null;
end $$;

revoke all on function public.api_key_create(uuid, text) from public, anon;
grant execute on function public.api_key_create(uuid, text) to authenticated, service_role;
revoke all on function public.api_key_revoke(uuid) from public, anon;
grant execute on function public.api_key_revoke(uuid) to authenticated, service_role;

-- ---------- (3) الاستهلاك الخارجي: مفتاح مباشر لا جلسة مستخدم، الحماية ببصمته ----------
create or replace function public.api_key_resolve(p_secret text, p_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare k record;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select k1.id, k1.org_id, k1.created_by, o.name into k
  from public.api_keys k1 join public.organizations o on o.id = k1.org_id
  where k1.key_hash = p_hash and k1.revoked_at is null;
  if k.id is null then return null; end if;
  update public.api_keys set last_used_at = now() where id = k.id;
  return jsonb_build_object('org_id', k.org_id, 'user_id', k.created_by, 'org_name', k.name);
end $$;

create or replace function public.api_import(p_secret text, p_hash text, p_filename text, p_tracker_name text, p_columns jsonb, p_mapping jsonb, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid; v_user uuid; v_tracker uuid; v_new boolean := false; v_import uuid;
  v_inserted int := 0; r jsonb; v_assignee uuid; v_email text; k record;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select org_id, created_by into k from public.api_keys where key_hash = p_hash and revoked_at is null;
  if k.org_id is null then raise exception 'bad key' using errcode = '42501'; end if;
  v_org := k.org_id; v_user := k.created_by;

  select id into v_tracker from public.trackers where org_id = v_org and name = p_tracker_name order by created_at asc limit 1;
  if v_tracker is null then
    insert into public.trackers (org_id, name, columns, created_by)
    values (v_org, p_tracker_name, coalesce(p_columns, '[]'::jsonb), v_user) returning id into v_tracker;
    v_new := true;
  end if;

  insert into public.imports (org_id, tracker_id, filename, rows_count, mapping, created_by)
  values (v_org, v_tracker, coalesce(p_filename, 'api'), jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), coalesce(p_mapping, '{}'::jsonb), v_user)
  returning id into v_import;

  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_assignee := null;
    v_email := lower(nullif(r->>'assignee_email', ''));
    if v_email is not null then
      select p.id into v_assignee from public.profiles p
      join public.org_members m on m.user_id = p.id and m.org_id = v_org and m.status = 'active'
      where lower(p.email) = v_email limit 1;
    end if;
    insert into public.items (org_id, tracker_id, import_id, title, category, due_at, status, assignee_id, amount, client_name, case_number, data, created_by)
    values (v_org, v_tracker, v_import,
            coalesce(nullif(trim(r->>'title'), ''), '-'),
            nullif(r->>'category', ''),
            nullif(r->>'due_at', '')::timestamptz,
            case when r->>'status' = 'done' then 'done' else 'open' end,
            v_assignee,
            nullif(r->>'amount', '')::numeric,
            nullif(r->>'client_name', ''),
            nullif(r->>'case_number', ''),
            coalesce(r->'data', '{}'::jsonb),
            v_user);
    v_inserted := v_inserted + 1;
  end loop;
  return jsonb_build_object('tracker_id', v_tracker, 'tracker_name', p_tracker_name, 'new_tracker', v_new, 'inserted', v_inserted, 'import_id', v_import);
end $$;

create or replace function public.api_items_export(p_secret text, p_hash text, p_tracker text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select org_id into v_org from public.api_keys where key_hash = p_hash and revoked_at is null;
  if v_org is null then raise exception 'bad key' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', i.id, 'number', i.item_number, 'title', i.title, 'category', i.category, 'tracker', t.name,
      'status', i.status, 'due_at', i.due_at, 'assignee_email', p.email, 'amount', i.amount,
      'client_name', i.client_name, 'case_number', i.case_number, 'data', i.data,
      'created_at', i.created_at, 'updated_at', i.updated_at) order by i.created_at desc)
    from public.items i
    join public.trackers t on t.id = i.tracker_id
    left join public.profiles p on p.id = i.assignee_id
    where i.org_id = v_org and (p_tracker is null or p_tracker = '' or t.name = p_tracker)), '[]'::jsonb);
end $$;

-- الـ Worker يستدعي PostgREST بدور anon، فالدوال الثلاث تمنح له (الحماية بـ p_secret + بصمة المفتاح)
revoke all on function public.api_key_resolve(text, text) from public;
grant execute on function public.api_key_resolve(text, text) to anon, service_role;
revoke all on function public.api_import(text, text, text, text, jsonb, jsonb, jsonb) from public;
grant execute on function public.api_import(text, text, text, text, jsonb, jsonb, jsonb) to anon, service_role;
revoke all on function public.api_items_export(text, text, text) from public;
grant execute on function public.api_items_export(text, text, text) to anon, service_role;

-- ---------- (4) حاوية المرفقات ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 26214400, array[
  'application/pdf', 'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/csv', 'text/plain', 'image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif', 'image/gif'
])
on conflict (id) do update set
  public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- المسار org_id/... : أول مقطع في اسم الملف هو معرف الشركة، والعزل بعضوية current_org_ids()
drop policy if exists tracker_attachments_read on storage.objects;
create policy tracker_attachments_read on storage.objects for select
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids()));

drop policy if exists tracker_attachments_insert on storage.objects;
create policy tracker_attachments_insert on storage.objects for insert
  with check (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids()));

drop policy if exists tracker_attachments_delete on storage.objects;
create policy tracker_attachments_delete on storage.objects for delete
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids()));
