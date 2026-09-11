-- الترحيل كما طبق على Supabase (version 20260903201213, name tracker_0013_attachments); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- مرفقات العناصر (مخالفات، قضايا، عقود): ملفات داخل تخزين سوبابيس أو روابط خارجية
-- (جوجل درايف مثلاً). المسار داخل الحاوية: <org_id>/<item_id>/<uuid>-<name>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 26214400,
        array['application/pdf','application/msword',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'application/vnd.ms-excel',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'image/png','image/jpeg','image/webp','text/plain'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  item_id uuid references public.items(id) on delete cascade,
  name text not null,
  mime text,
  size_bytes bigint not null default 0,
  storage_path text,
  external_url text,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint attachments_target_check check (storage_path is not null or external_url is not null)
);

create index if not exists attachments_item_idx on public.attachments (item_id, created_at desc);
create index if not exists attachments_org_idx on public.attachments (org_id, created_at desc);

alter table public.attachments enable row level security;

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments
  for select using (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert with check (org_id in (select current_org_ids()) and uploaded_by = auth.uid());

drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete using (uploaded_by = auth.uid() or is_org_admin(org_id));

grant select, insert, delete on public.attachments to authenticated;

-- حدود التخزين حسب الباقة (ميغابايت)
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '200'::jsonb) where code = 'trial';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '1000'::jsonb) where code = 'monthly';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '5000'::jsonb) where code = 'yearly';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '0'::jsonb) where code = 'expired';

create or replace function public.enforce_storage_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare used bigint; cap bigint;
begin
  select coalesce((p.limits->>'storage_mb')::bigint, 0) * 1024 * 1024 into cap
  from public.plans p where p.code = public.effective_plan(new.org_id);

  if cap is null or cap = 0 then
    raise exception 'PLAN_LIMIT_STORAGE' using errcode = 'check_violation';
  end if;

  select coalesce(sum(a.size_bytes), 0) into used from public.attachments a where a.org_id = new.org_id;
  if used + coalesce(new.size_bytes, 0) > cap then
    raise exception 'PLAN_LIMIT_STORAGE' using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists attachments_enforce_storage on public.attachments;
create trigger attachments_enforce_storage before insert on public.attachments
  for each row execute function public.enforce_storage_limit();

revoke all on function public.enforce_storage_limit() from public, anon, authenticated;

-- سياسات التخزين: العضو يقرأ ويرفع ويحذف داخل مجلد شركته فقط
drop policy if exists tracker_attachments_read on storage.objects;
create policy tracker_attachments_read on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select current_org_ids()));

drop policy if exists tracker_attachments_insert on storage.objects;
create policy tracker_attachments_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select current_org_ids()));

drop policy if exists tracker_attachments_delete on storage.objects;
create policy tracker_attachments_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select current_org_ids()));
