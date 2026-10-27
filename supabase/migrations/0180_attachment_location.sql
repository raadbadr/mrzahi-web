-- مكان حفظ المستند ونقله (امر المهندس رعد 2026-10-27: «ضيف في كل مستند وين محفوظ وامكانية نقله،
-- وامكانية حفظ المستند في السيرفر حقنا او جوجل درايف او الاثنين معا»، و«نسخة درايف تروح سلة المهملات»).
-- المرفق يحمل مكانين مستقلين: storage_path (خادم جدة) و drive_file_id + external_url (Google Drive)،
-- وقد يحملهما معا. النسخ والحذف من التخزين ومن درايف يجريان في المتصفح، والقاعدة تثبت المكان الجديد
-- بعد ان تتحقق ان النسخة على الخادم موجودة فعلا، ولا تسمح بمستند بلا مكان.

-- 1) «الاثنان» خيار ثالث لمكان الحفظ الافتراضي
alter table public.profiles drop constraint if exists profiles_storage_mode_check;
alter table public.profiles add constraint profiles_storage_mode_check
  check (storage_mode in ('platform', 'drive', 'both'));

-- 2) حصة الباقة تحسب نسخة الخادم وحدها، وتطبق ايضا حين ينتقل مستند قائم الى الخادم
create or replace function public.enforce_storage_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare used bigint; cap bigint;
begin
  if new.storage_path is null then return new; end if;
  if tg_op = 'UPDATE' and old.storage_path is not null then return new; end if;
  select coalesce((p.limits->>'storage_mb')::bigint, 0) * 1024 * 1024 into cap
  from public.plans p where p.code = public.effective_plan(new.org_id);
  if cap is null or cap = 0 then
    raise exception 'PLAN_LIMIT_STORAGE' using errcode = 'check_violation';
  end if;
  select coalesce(sum(a.size_bytes), 0) into used
  from public.attachments a where a.org_id = new.org_id and a.storage_path is not null and a.id <> new.id;
  if used + coalesce(new.size_bytes, 0) > cap then
    raise exception 'PLAN_LIMIT_STORAGE' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function public.enforce_storage_limit() from public, anon, authenticated;

drop trigger if exists attachments_enforce_storage on public.attachments;
create trigger attachments_enforce_storage before insert or update of storage_path on public.attachments
  for each row execute function public.enforce_storage_limit();

-- 3) تثبيت مكان المستند بعد النسخ: صاحب الرفع او مدير الجهة، بالصلاحية نفسها التي يحذف بها.
--    p_storage_path: المسار على الخادم او null لازالته. p_drive_file_id و p_external_url: نسخة درايف او null.
--    لا يغير مسار قائم ولا ملف درايف قائم الى غيره: المكان يضاف او يزال فقط.
create or replace function public.attachment_set_location(p_id uuid, p_storage_path text, p_drive_file_id text, p_external_url text)
returns public.attachments language plpgsql security definer set search_path = public as $$
declare
  current_row public.attachments;
  caller uuid := auth.uid();
  clean_path text := nullif(btrim(coalesce(p_storage_path, '')), '');
  clean_drive text := nullif(btrim(coalesce(p_drive_file_id, '')), '');
  clean_url text := nullif(btrim(coalesce(p_external_url, '')), '');
begin
  if caller is null then raise exception 'unauthorized' using errcode = '42501'; end if;
  select * into current_row from public.attachments where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if current_row.org_id not in (select public.current_org_ids()) then raise exception 'not_member' using errcode = '42501'; end if;
  if current_row.item_id is not null and not public.item_visible_me(current_row.item_id) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  if not (current_row.uploaded_by = caller or public.is_org_admin(current_row.org_id)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  -- رابط خارجي بلا ملف درايف معروف لا ينقل: لا نملك نسخته
  if current_row.storage_path is null and current_row.drive_file_id is null then
    raise exception 'not_movable' using errcode = 'check_violation';
  end if;
  if clean_path is null and clean_drive is null then
    raise exception 'no_location' using errcode = 'check_violation';
  end if;

  if clean_path is not null and clean_path is distinct from current_row.storage_path then
    if current_row.storage_path is not null then raise exception 'path_change' using errcode = 'check_violation'; end if;
    if split_part(clean_path, '/', 1) <> current_row.org_id::text then raise exception 'bad_path' using errcode = 'check_violation'; end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'attachments' and o.name = clean_path) then
      raise exception 'missing_object' using errcode = 'check_violation';
    end if;
  end if;

  if clean_drive is not null and clean_drive is distinct from current_row.drive_file_id then
    if current_row.drive_file_id is not null then raise exception 'drive_change' using errcode = 'check_violation'; end if;
    if clean_drive !~ '^[A-Za-z0-9_-]{10,200}$' then raise exception 'bad_drive_id' using errcode = 'check_violation'; end if;
    if clean_url is null or clean_url !~ '^https://(drive|docs)\.google\.com/' then
      raise exception 'bad_drive_url' using errcode = 'check_violation';
    end if;
  end if;

  update public.attachments
     set storage_path = clean_path,
         drive_file_id = clean_drive,
         external_url = case when clean_drive is null then null
                             when clean_drive = current_row.drive_file_id then current_row.external_url
                             else clean_url end
   where id = p_id
  returning * into current_row;
  return current_row;
end $$;
revoke all on function public.attachment_set_location(uuid, text, text, text) from public, anon;
grant execute on function public.attachment_set_location(uuid, text, text, text) to authenticated;
