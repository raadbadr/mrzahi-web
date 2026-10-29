-- WhatsApp قناة ثانية للبوت بالعقل نفسه (امر المهندس رعد 2026-10-29: «نحتاج نسوي خدمة الواتس زي التليغرام
-- ونضيفها مع خدمات الشركة»، ثم «نبدا»). محادثة WhatsApp تحمل في القاعدة المعرف wa:<الرقم الدولي>، فلا تختلط
-- بمحادثات تيليغرام في السجل والمسودات، ورابطها في channel_links بالرقم وحده (channel = 'whatsapp').
-- ملفات WhatsApp تحذفها Meta بعد 7 ايام، فالمستند المحفوظ منها ينسخ الى خادم جدة لا يبقى رابطا اليها.

-- 1) سجل الرسائل يعرف صاحب محادثة WhatsApp كما يعرف صاحب محادثة تيليغرام
create or replace function public.log_telegram_message(p_secret text, p_chat_id text, p_username text, p_first_name text, p_body text, p_user_id uuid, p_action text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_user uuid := p_user_id;
begin
  if not public.check_worker_secret(p_secret) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if v_user is null then
    if p_chat_id like 'wa:%' then
      select user_id into v_user from public.channel_links
      where channel = 'whatsapp' and external_id = substr(p_chat_id, 4) and verified_at is not null
      limit 1;
    else
      select user_id into v_user from public.channel_links
      where channel = 'telegram' and external_id = p_chat_id and verified_at is not null
      limit 1;
    end if;
  end if;
  insert into public.telegram_messages (chat_id, username, first_name, body, user_id, action)
  values (p_chat_id, p_username, p_first_name, left(p_body, 4000), v_user, coalesce(p_action, 'none'));
  return v_user;
end $$;

-- 2) الشركة النشطة هي التي تكتب فيها المحادثة فعلا (telegram_user_orgs: اختيار الوكيل ثم رابط تيليغرام)،
--    فمن يكتب من WhatsApp وحده لا يسال عن الشركة مع كل رسالة
create or replace function public.telegram_org_choices(p_secret text, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare result jsonb; v_active uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(
    (select p.agent_org_id from public.profiles p
       join public.org_members m on m.org_id = p.agent_org_id and m.user_id = p_user_id and m.status = 'active'
      where p.id = p_user_id and p.agent_org_id is not null),
    (select l.active_org_id from public.channel_links l
      where l.user_id = p_user_id and l.channel = 'telegram' and l.verified_at is not null
      order by l.verified_at desc limit 1)) into v_active;
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'role', m.role,
           'personal', coalesce(pr.entity_type = 'individual', false),
           'active', (o.id = v_active))
         order by coalesce(pr.entity_type = 'individual', false) desc,   -- حساب بلا بطاقة يعطي NULL، وNULL في DESC يتصدر القائمة
                  case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
                  o.created_at), '[]'::jsonb)
  into result
  from public.org_members m
  join public.organizations o on o.id = m.org_id
  left join public.org_profiles pr on pr.org_id = o.id
  where m.user_id = p_user_id and m.status = 'active';
  return result;
end $$;

-- 3) رقم WhatsApp المرسل (تتحقق منه Meta) يطابق رقم الجوال في ملف واحد بالضبط: 05xxxxxxxx و5xxxxxxxx
--    و+9665xxxxxxxx و009665xxxxxxxx كلها رقم واحد. لا يربط هنا: يعيد الاسم والشركة ليؤكد صاحب الرقم بزر
--    انه حسابه، لان رقم الملف يكتبه صاحبه بلا تحقق
create or replace function public.whatsapp_phone_match(p_secret text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_want text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'); v_user uuid; v_count int; v_org uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if length(v_want) < 10 or length(v_want) > 15 then return null; end if;
  with normalized as (
    select p.id, case
             when d ~ '^00' then substr(d, 3)
             when d ~ '^05\d{8}$' then '966' || substr(d, 2)
             when d ~ '^5\d{8}$' then '966' || d
             else d end as phone
    from public.profiles p, lateral (select regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') as d) digits
    where coalesce(p.phone, '') <> '')
  select count(*), min(id::text)::uuid into v_count, v_user from normalized where phone = v_want;
  if v_count <> 1 then return null; end if;
  v_org := public.telegram_user_org(v_user);
  return jsonb_build_object('user_id', v_user,
    'name', (select coalesce(nullif(full_name, ''), full_name_en, '') from public.profiles where id = v_user),
    'org_name', (select o.name from public.organizations o where o.id = v_org),
    'org_personal', coalesce((select pr.entity_type = 'individual' from public.org_profiles pr where pr.org_id = v_org), false));
end $$;
revoke all on function public.whatsapp_phone_match(text, text) from public, authenticated;
grant execute on function public.whatsapp_phone_match(text, text) to anon, service_role;

-- 4) خانات رفع لمرة واحدة: الـ Worker لا يحمل مفتاح خدمة، فيطلب خانة بسره ثم يرفع الملف بمفتاح anon الى
--    مسارها وحده خلال خمس دقائق. المسار عشوائي (uuid) تحت مجلد الشركة، فسياسات القراءة القائمة تحكمه كسائر مرفقاتها
create table if not exists public.chat_upload_slots (
  path text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete cascade,
  size_bytes bigint not null default 0,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.chat_upload_slots enable row level security;
revoke all on public.chat_upload_slots from public, anon, authenticated;

create or replace function public.chat_upload_slot(p_secret text, p_user_id uuid, p_ext text, p_size bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_ext text; v_path text; v_cap bigint; v_used bigint; v_exp timestamptz;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  -- الشركة نفسها التي يختارها telegram_save_document
  select m.org_id into v_org from public.org_members m
  where m.user_id = p_user_id and m.status = 'active' and m.org_id in (select public.telegram_user_orgs(p_user_id))
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, m.created_at asc limit 1;
  if v_org is null then return jsonb_build_object('status', 'no_org'); end if;
  -- السعة قبل الرفع، فلا يرفع ملف ترفضه الباقة ثم يبقى بلا مستند
  select coalesce((p.limits->>'storage_mb')::bigint, 0) * 1024 * 1024 into v_cap
  from public.plans p where p.code = public.effective_plan(v_org);
  select coalesce(sum(a.size_bytes), 0) into v_used from public.attachments a where a.org_id = v_org and a.storage_path is not null;
  if coalesce(v_cap, 0) = 0 or v_used + greatest(coalesce(p_size, 0), 0) > v_cap then
    raise exception 'PLAN_LIMIT_STORAGE' using errcode = 'check_violation';
  end if;
  v_ext := lower(coalesce(p_ext, ''));
  if v_ext !~ '^[a-z0-9]{1,8}$' then v_ext := 'bin'; end if;
  delete from public.chat_upload_slots where expires_at < now() - interval '1 day';
  v_path := v_org::text || '/' || extract(year from now())::int::text || '/chat/' || gen_random_uuid()::text || '.' || v_ext;
  v_exp := now() + interval '5 minutes';
  insert into public.chat_upload_slots (path, user_id, org_id, size_bytes, expires_at)
  values (v_path, p_user_id, v_org, greatest(coalesce(p_size, 0), 0), v_exp);
  return jsonb_build_object('status', 'ok', 'path', v_path, 'expires_at', v_exp);
end $$;
revoke all on function public.chat_upload_slot(text, uuid, text, bigint) from public, authenticated;
grant execute on function public.chat_upload_slot(text, uuid, text, bigint) to anon, service_role;

create or replace function public.chat_upload_allowed(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_upload_slots s where s.path = p_name and s.expires_at > now())
$$;
revoke all on function public.chat_upload_allowed(text) from public;
grant execute on function public.chat_upload_allowed(text) to anon, authenticated, service_role;

drop policy if exists mrzahi_chat_upload_insert on storage.objects;
create policy mrzahi_chat_upload_insert on storage.objects for insert to anon
  with check (bucket_id = 'attachments' and public.chat_upload_allowed(name));

-- 5) حفظ المستند من المحادثة يقبل ملفا على خادم جدة (storage_path) الى جانب الرابط، ويسجل قناته
create or replace function public.telegram_save_document(p_secret text, p_user_id uuid, p_doc jsonb, p_file jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org uuid; v_role text; v_record uuid; v_kind text; v_label text; v_title text; v_party text; v_number text; v_issuer text;
  v_issue date; v_expiry date; v_due timestamptz; v_amount numeric; v_case text; v_item uuid; v_status text := 'created';
  v_details jsonb; v_labels jsonb; v_new jsonb; v_updates jsonb := '{}'::jsonb; v_current jsonb := '{}'::jsonb; v_want text; v_have text; k text; col text;
  v_channel text := case when p_file->>'channel' = 'whatsapp' then 'whatsapp' else 'telegram' end; v_path text; v_slot text; v_size bigint;
  v_unique text[] := array['commercial_register','vat_certificate','zakat_certificate','gosi_certificate','chamber_certificate','saudization_certificate','articles_of_association','bylaws'];
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  -- الشركة النشطة في المحادثة (telegram_user_orgs تحترم اختيار المستخدم)، والمالك ثم المدير أولا عند التعدد
  select m.org_id, m.role into v_org, v_role from public.org_members m
  where m.user_id = p_user_id and m.status = 'active' and m.org_id in (select public.telegram_user_orgs(p_user_id))
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, m.created_at asc limit 1;
  if v_org is null then return jsonb_build_object('status', 'no_org'); end if;

  v_kind := nullif(btrim(coalesce(p_doc->>'kind', '')), '');
  if v_kind is null or v_kind = 'other' then return jsonb_build_object('status', 'unknown_kind'); end if;
  v_label := case v_kind
    when 'commercial_register' then 'السجل التجاري' when 'vat_certificate' then 'الشهادة الضريبية' when 'license' then 'الرخصة'
    when 'articles_of_association' then 'عقد التأسيس' when 'bylaws' then 'النظام الأساسي' when 'chamber_certificate' then 'شهادة الغرفة التجارية'
    when 'gosi_certificate' then 'شهادة التأمينات الاجتماعية' when 'zakat_certificate' then 'شهادة الزكاة' when 'saudization_certificate' then 'شهادة السعودة'
    when 'lease_contract' then 'عقد الإيجار' when 'power_of_attorney' then 'الوكالة' when 'court_ruling' then 'الحكم' when 'case_filing' then 'صحيفة الدعوى'
    when 'hearing_notice' then 'إشعار الجلسة' when 'violation' then 'المخالفة' when 'invoice' then 'الفاتورة' when 'id_document' then 'الهوية'
    when 'passport' then 'جواز السفر' when 'driving_license' then 'رخصة القيادة' when 'vehicle_registration' then 'استمارة المركبة'
    when 'insurance_policy' then 'وثيقة التأمين' when 'employment_contract' then 'عقد العمل' when 'contract' then 'العقد'
    else coalesce(nullif(btrim(p_doc->>'title'), ''), 'مستند') end;
  v_party  := nullif(btrim(coalesce(p_doc->>'party', '')), '');
  v_number := nullif(btrim(coalesce(p_doc->>'number', '')), '');
  v_issuer := nullif(btrim(coalesce(p_doc->>'issuer', '')), '');
  v_case   := nullif(btrim(coalesce(p_doc->>'case_number', '')), '');
  v_issue  := case when (p_doc->>'issue_date')  ~ '^\d{4}-\d{2}-\d{2}$' then (p_doc->>'issue_date')::date end;
  v_expiry := case when (p_doc->>'expiry_date') ~ '^\d{4}-\d{2}-\d{2}$' then (p_doc->>'expiry_date')::date end;
  v_amount := case when jsonb_typeof(p_doc->'amount') = 'number' then (p_doc->>'amount')::numeric end;
  v_details := case when jsonb_typeof(p_doc->'details') = 'object' then p_doc->'details' else '{}'::jsonb end;
  v_labels  := case when jsonb_typeof(p_doc->'detail_labels') = 'object' then p_doc->'detail_labels' else '{}'::jsonb end;
  v_title := v_label || case when v_party is not null then ' — ' || v_party when v_number is not null then ' ' || v_number else '' end;
  v_due := case when v_expiry is not null then (v_expiry::timestamp + interval '9 hours') at time zone 'Asia/Riyadh' end;
  v_new := jsonb_strip_nulls(jsonb_build_object('number', v_number, 'issuer', v_issuer, 'issue_date', v_issue::text, 'source', v_channel,
             'summary', nullif(btrim(coalesce(p_doc->>'summary', '')), ''), 'court', nullif(btrim(coalesce(p_doc->>'court', '')), '')));

  -- سجل «المستندات» كما تنشئه صفحة المستندات و create_org_registered
  select id into v_record from public.records where org_id = v_org and name in ('المستندات','Documents','دستاویزات') order by created_at asc limit 1;
  if v_record is null then
    insert into public.records (org_id, name, columns, created_by) values (v_org, 'المستندات', '[]'::jsonb, p_user_id) returning id into v_record;
  end if;

  if v_kind = any (v_unique) then
    select id into v_item from public.items where org_id = v_org and data->>'document_kind' = v_kind
    order by (status = 'open') desc, created_at desc limit 1;
  end if;
  if v_item is not null then
    update public.items set
      title = v_title, category = v_label, due_at = coalesce(v_due, due_at), status = 'open',
      client_name = coalesce(v_party, client_name), amount = coalesce(v_amount, amount), case_number = coalesce(v_case, case_number),
      data = (data || v_new) || jsonb_build_object(
        'document_kind', v_kind,
        'details', coalesce(case when jsonb_typeof(data->'details') = 'object' then data->'details' end, '{}'::jsonb) || v_details,
        'detail_labels', coalesce(case when jsonb_typeof(data->'detail_labels') = 'object' then data->'detail_labels' end, '{}'::jsonb) || v_labels)
    where id = v_item;
    v_status := 'updated';
  else
    insert into public.items (org_id, record_id, title, category, due_at, status, client_name, amount, case_number, data, created_by)
    values (v_org, v_record, v_title, v_label, v_due, 'open', v_party, v_amount, v_case,
            v_new || jsonb_build_object('document_kind', v_kind, 'details', v_details, 'detail_labels', v_labels), p_user_id)
    returning id into v_item;
  end if;

  -- الملف على خادم جدة (WhatsApp): رفعه الـ Worker الى خانة اصدرها chat_upload_slot لهذا المستخدم وهذه الشركة،
  -- فتستهلك الخانة هنا مرة واحدة، والحجم من التخزين نفسه لا من الطلب، ويحسب على سعة الباقة
  v_path := nullif(btrim(coalesce(p_file->>'storage_path', '')), '');
  if v_path is not null then
    delete from public.chat_upload_slots s where s.path = v_path and s.user_id = p_user_id and s.org_id = v_org
    returning s.path into v_slot;
    if v_slot is null then raise exception 'bad_path' using errcode = 'check_violation'; end if;
    select coalesce((o.metadata->>'size')::bigint, 0) into v_size from storage.objects o where o.bucket_id = 'attachments' and o.name = v_path;
    if not found then raise exception 'missing_object' using errcode = 'check_violation'; end if;
    insert into public.attachments (org_id, item_id, name, mime, size_bytes, storage_path, uploaded_by, channel)
    values (v_org, v_item, left(coalesce(nullif(btrim(p_file->>'name'), ''), v_label), 200), nullif(p_file->>'mime', ''),
            v_size, v_path, p_user_id, v_channel);
  -- الملف: رابط موقع يبقى صالحا (لا يحسب على سعة التخزين لأنه ليس في الحاوية)
  elsif nullif(btrim(coalesce(p_file->>'external_url', '')), '') is not null then
    insert into public.attachments (org_id, item_id, name, mime, size_bytes, external_url, uploaded_by, channel)
    values (v_org, v_item, left(coalesce(nullif(btrim(p_file->>'name'), ''), v_label), 200), nullif(p_file->>'mime', ''),
            coalesce(nullif(p_file->>'size_bytes', '')::bigint, 0), btrim(p_file->>'external_url'), p_user_id, v_channel);
  end if;

  -- ما يصلح لتحديث بطاقة الشركة ويختلف عما فيها: يعاد فقط، ولا يكتب هنا
  if jsonb_typeof(p_doc->'profile_updates') = 'object' then
    foreach k in array array['vat_number','cr_number','unified_number','legal_name'] loop
      v_want := nullif(btrim(coalesce(p_doc->'profile_updates'->>k, '')), '');
      if v_want is null then continue; end if;
      if k = 'cr_number' and v_want !~ '^7\d{9}$' then continue; end if;
      -- اسم لاتيني يقارن بالاسم الإنجليزي لا العربي
      col := case when k = 'legal_name' and v_want !~ '[؀-ۿ]' then 'legal_name_en' else k end;
      execute format('select p.%I from public.org_profiles p where p.org_id = $1', col) into v_have using v_org;
      if coalesce(v_have, '') <> v_want then
        v_updates := v_updates || jsonb_build_object(col, v_want);
        v_current := v_current || jsonb_build_object(col, v_have);
      end if;
    end loop;
  end if;

  return jsonb_build_object('status', v_status, 'item_id', v_item, 'title', v_title, 'kind', v_kind, 'label', v_label, 'number', v_number,
                            'party', v_party, 'issue_date', v_issue, 'expiry_date', v_expiry, 'role', v_role,
                            'profile_updates', v_updates, 'profile_current', v_current);
end $function$;
revoke all on function public.telegram_save_document(text, uuid, jsonb, jsonb) from public;
grant execute on function public.telegram_save_document(text, uuid, jsonb, jsonb) to anon, service_role;

-- 6) سياسة الرفع القائمة للمسجلين وحدهم: كانت لكل الادوار، فتنادي current_org_ids لطلب anon فيرفض قبل ان
--    تصل سياسة الخانة. لا يتغير شيء للمسجلين، وanon لم يكن يرفع بها اصلا
alter policy tracker_attachments_insert on storage.objects to authenticated;
