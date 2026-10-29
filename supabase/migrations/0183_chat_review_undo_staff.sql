-- اكمال مرونة الادخال من المحادثة (امر المهندس رعد 2026-10-29: «نفذ»):
-- 1) قبل العرض: ورقة تشبه ورقة مسجلة (الرقم نفسه، او للفاتورة المورد والمبلغ والتاريخ نفسها) تنبه، وهل يرى صاحب
--    الرسالة بيانات الموارد البشرية (لزر «ملف موظف»)
-- 2) ملف موظف من عقد العمل او الهوية او الجواز، وملفه في مجلد <org>/hr/ المحجوب
-- 3) التراجع: ما انشاته المحادثة يلغى (cancelled) خلال 15 دقيقة بيد من انشاه، ويبقى في السجل للاسترجاع
-- 4) المراجعة: ما ادخله غير المالك والمدير وفيه تنبيه او تصحيح يعلم «يحتاج مراجعة»، ويصل المالك والمدير في
--    محادثتهما بزر اعتماد، و«المراجعة» تسرد ما ينتظر

-- 1) الفحص قبل العرض
create or replace function public.chat_document_precheck(p_secret text, p_user_id uuid, p_doc jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_org uuid; v_kind text := nullif(btrim(coalesce(p_doc->>'kind', '')), ''); v_number text := nullif(btrim(coalesce(p_doc->>'number', '')), '');
        v_seller text := nullif(btrim(coalesce(p_doc->'details'->>'seller', '')), ''); v_amount numeric; v_issue date; v_similar jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select m.org_id into v_org from public.org_members m
  where m.user_id = p_user_id and m.status = 'active' and m.org_id in (select public.telegram_user_orgs(p_user_id))
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, m.created_at asc limit 1;
  if v_org is null or v_kind is null then return jsonb_build_object('can_hr', false); end if;
  v_amount := case when jsonb_typeof(p_doc->'amount') = 'number' then (p_doc->>'amount')::numeric
                   when (p_doc->'details'->>'total') ~ '^\d+(\.\d+)?$' then (p_doc->'details'->>'total')::numeric end;
  v_issue := case when (p_doc->>'issue_date') ~ '^\d{4}-\d{2}-\d{2}$' then (p_doc->>'issue_date')::date end;
  -- الاوراق الفريدة (السجل، الشهادات…) تحدث القائم اصلا، فلا تنبيه لها
  if v_kind <> all (array['commercial_register','vat_certificate','zakat_certificate','gosi_certificate','chamber_certificate','saudization_certificate','articles_of_association','bylaws']) then
    select jsonb_build_object('title', i.title, 'date', to_char(i.created_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD')) into v_similar
    from public.items i
    where i.org_id = v_org and i.status <> 'cancelled' and public.hr_visible(i.org_id, i.visibility, p_user_id)
      and i.data->>'document_kind' = v_kind
      and ((v_number is not null and i.data->>'number' = v_number)
           or (v_kind = 'invoice' and v_seller is not null and v_amount is not null and v_issue is not null
               and i.client_name = v_seller and i.amount = v_amount and (i.due_at at time zone 'Asia/Riyadh')::date = v_issue))
    order by i.created_at desc limit 1;
  end if;
  return jsonb_build_object('similar', v_similar, 'can_hr', public.hr_visible(v_org, 'hr', p_user_id));
end $$;
revoke all on function public.chat_document_precheck(text, uuid, jsonb) from public, authenticated;
grant execute on function public.chat_document_precheck(text, uuid, jsonb) to anon, service_role;

-- 2) خانة الرفع تقبل مجلد الموارد البشرية لمن يراه
drop function if exists public.chat_upload_slot(text, uuid, text, bigint);
create or replace function public.chat_upload_slot(p_secret text, p_user_id uuid, p_ext text, p_size bigint, p_hr boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_ext text; v_path text; v_cap bigint; v_used bigint; v_exp timestamptz;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  -- الشركة نفسها التي يختارها telegram_save_document
  select m.org_id into v_org from public.org_members m
  where m.user_id = p_user_id and m.status = 'active' and m.org_id in (select public.telegram_user_orgs(p_user_id))
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, m.created_at asc limit 1;
  if v_org is null then return jsonb_build_object('status', 'no_org'); end if;
  if coalesce(p_hr, false) and not public.hr_visible(v_org, 'hr', p_user_id) then return jsonb_build_object('status', 'forbidden_hr'); end if;
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
  v_path := v_org::text || '/' || case when coalesce(p_hr, false) then 'hr/' else '' end
            || extract(year from now())::int::text || '/chat/' || gen_random_uuid()::text || '.' || v_ext;
  v_exp := now() + interval '5 minutes';
  insert into public.chat_upload_slots (path, user_id, org_id, size_bytes, expires_at)
  values (v_path, p_user_id, v_org, greatest(coalesce(p_size, 0), 0), v_exp);
  return jsonb_build_object('status', 'ok', 'path', v_path, 'expires_at', v_exp);
end $$;
revoke all on function public.chat_upload_slot(text, uuid, text, bigint, boolean) from public, authenticated;
grant execute on function public.chat_upload_slot(text, uuid, text, bigint, boolean) to anon, service_role;

-- 3) التراجع
create or replace function public.chat_undo_save(p_secret text, p_user_id uuid, p_item_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_row public.items;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select * into v_row from public.items where id = p_item_id for update;
  if not found or v_row.created_by is distinct from p_user_id or coalesce(v_row.data->>'source', '') not in ('telegram', 'whatsapp') then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  if v_row.status = 'cancelled' then return jsonb_build_object('status', 'already', 'title', v_row.title); end if;
  if v_row.created_at < now() - interval '15 minutes' then return jsonb_build_object('status', 'expired', 'title', v_row.title); end if;
  update public.items set status = 'cancelled', data = data || jsonb_build_object('undone_at', now(), 'needs_review', false) where id = p_item_id;
  return jsonb_build_object('status', 'ok', 'title', v_row.title);
end $$;
revoke all on function public.chat_undo_save(text, uuid, uuid) from public, authenticated;
grant execute on function public.chat_undo_save(text, uuid, uuid) to anon, service_role;

-- 4) المراجعة: من يصله التنبيه، والاعتماد، والقائمة
create or replace function public.chat_review_targets(p_secret text, p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'chat_id', case when l.channel = 'whatsapp' then 'wa:' || l.external_id else l.external_id end,
           'lang', coalesce(p.lang, 'ar'))), '[]'::jsonb) into result
  from public.items i
  join public.org_members m on m.org_id = i.org_id and m.status = 'active' and m.role in ('owner', 'admin')
  join public.channel_links l on l.user_id = m.user_id and l.channel in ('telegram', 'whatsapp') and l.verified_at is not null and l.external_id is not null
  join public.profiles p on p.id = m.user_id
  where i.id = p_item_id and m.user_id is distinct from i.created_by;
  return result;
end $$;
revoke all on function public.chat_review_targets(text, uuid) from public, authenticated;
grant execute on function public.chat_review_targets(text, uuid) to anon, service_role;

create or replace function public.chat_review_approve(p_secret text, p_user_id uuid, p_item_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_row public.items;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select * into v_row from public.items where id = p_item_id for update;
  if not found or not exists (select 1 from public.org_members m where m.org_id = v_row.org_id and m.user_id = p_user_id
                                and m.status = 'active' and m.role in ('owner', 'admin')) then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if coalesce(v_row.data->>'needs_review', '') <> 'true' then return jsonb_build_object('status', 'already', 'title', v_row.title); end if;
  update public.items set data = (data - 'needs_review') || jsonb_build_object('reviewed_by', p_user_id, 'reviewed_at', now()) where id = p_item_id;
  return jsonb_build_object('status', 'ok', 'title', v_row.title);
end $$;
revoke all on function public.chat_review_approve(text, uuid, uuid) from public, authenticated;
grant execute on function public.chat_review_approve(text, uuid, uuid) to anon, service_role;

create or replace function public.chat_review_list(p_secret text, p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(row_data order by created desc), '[]'::jsonb) into result from (
    select jsonb_build_object('id', i.id, 'title', i.title, 'reasons', i.data->'review_reasons',
             'by', (select coalesce(nullif(pr.full_name, ''), pr.full_name_en, '') from public.profiles pr where pr.id = i.created_by),
             'date', to_char(i.created_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD')) as row_data, i.created_at as created
    from public.items i
    where i.data->>'needs_review' = 'true' and i.status <> 'cancelled'
      and i.org_id in (select m.org_id from public.org_members m where m.user_id = p_user_id and m.status = 'active' and m.role in ('owner', 'admin'))
    order by i.created_at desc limit 10) pending;
  return result;
end $$;
revoke all on function public.chat_review_list(text, uuid) from public, authenticated;
grant execute on function public.chat_review_list(text, uuid) to anon, service_role;

-- 5) الحفظ: ملف موظف، وعلامة المراجعة، وقابلية التراجع
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
  v_expense boolean := coalesce(p_doc->>'as_expense', '') = 'true' and p_doc->>'kind' = 'invoice'; v_seller text; v_category text;
  v_staff boolean := coalesce(p_doc->>'as_staff', '') = 'true' and p_doc->>'kind' in ('employment_contract', 'id_document', 'passport');
  v_name text; v_id_number text; v_staff_data jsonb; v_merged jsonb; v_review jsonb; v_undoable boolean := false;
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
  v_category := v_label;
  -- فاتورة تسجل مصروفا: بند «مصروف» كما تنشئه صفحة المصاريف، باسم المورد ومبلغ الاجمالي وتاريخ الفاتورة
  if v_expense then
    v_seller := nullif(btrim(coalesce(v_details->>'seller', '')), '');
    v_amount := coalesce(v_amount, case when (v_details->>'total') ~ '^\d+(\.\d+)?$' then (v_details->>'total')::numeric end);
    v_title := 'فاتورة' || case when v_seller is not null then ' — ' || v_seller else '' end || case when v_number is not null then ' ' || v_number else '' end;
    v_category := 'مصروف';
    v_party := coalesce(v_seller, v_party);
    v_due := case when v_issue is not null then (v_issue::timestamp + interval '9 hours') at time zone 'Asia/Riyadh' else now() end;
  end if;
  v_new := jsonb_strip_nulls(jsonb_build_object('number', v_number, 'issuer', v_issuer, 'issue_date', v_issue::text, 'source', v_channel,
             'summary', nullif(btrim(coalesce(p_doc->>'summary', '')), ''), 'court', nullif(btrim(coalesce(p_doc->>'court', '')), ''),
             'kind', case when v_expense then 'expense' end,
             'corrected', case when jsonb_typeof(p_doc->'corrected') = 'array' and jsonb_array_length(p_doc->'corrected') > 0 then p_doc->'corrected' end));

  -- سجل «المستندات» كما تنشئه صفحة المستندات و create_org_registered
  -- ملف موظف من عقد العمل او الهوية او الجواز: بطاقة «موظف» كما تنشئها شاشة الموظفين، وبيانات الموارد البشرية
  -- لا يكتبها الا من يراها (المالك والمدير وقسما الموارد البشرية والادارة). موظف قائم برقم هويته يحدث ولا يكرر
  if v_staff then
    if not public.hr_visible(v_org, 'hr', p_user_id) then return jsonb_build_object('status', 'forbidden_hr'); end if;
    v_name := coalesce(nullif(btrim(coalesce(v_details->>'employee', '')), ''), nullif(btrim(coalesce(v_details->>'full_name', '')), ''), v_party);
    if v_name is null then return jsonb_build_object('status', 'needs_name'); end if;
    v_id_number := case when v_kind in ('id_document', 'passport') then v_number else nullif(btrim(coalesce(v_details->>'id_number', '')), '') end;
    v_staff_data := jsonb_strip_nulls(jsonb_build_object(
      'id_number', v_id_number,
      'id_expiry', case when v_kind in ('id_document', 'passport') then v_expiry::text end,
      'nationality', nullif(btrim(coalesce(v_details->>'nationality', '')), ''),
      'job_title', nullif(btrim(coalesce(v_details->>'job_title', '')), ''),
      'salary_basic', case when (v_details->>'salary') ~ '^\d+(\.\d+)?$' then (v_details->>'salary')::numeric end,
      'hire_date', case when v_kind = 'employment_contract' then v_issue::text end,
      'contract_end', case when v_kind = 'employment_contract' then v_expiry::text end,
      'contract_type', case when v_kind = 'employment_contract' and v_expiry is not null then 'fixed' end));
    select id into v_item from public.items
    where org_id = v_org and category = 'موظف' and status <> 'cancelled'
      and ((v_id_number is not null and data->>'id_number' = v_id_number) or (v_id_number is null and title = v_name))
    order by created_at asc limit 1;
    if v_item is not null then
      update public.items set data = data || v_staff_data where id = v_item returning data into v_merged;
      v_status := 'staff_updated';
    else
      select id into v_record from public.records where org_id = v_org and name ~* 'موظف|employee' order by created_at asc limit 1;
      if v_record is null then
        insert into public.records (org_id, name, columns, created_by) values (v_org, 'الموظفون', '[]'::jsonb, p_user_id) returning id into v_record;
      end if;
      insert into public.items (org_id, record_id, title, category, status, amount, data, created_by)
      values (v_org, v_record, v_name, 'موظف', 'open', (v_staff_data->>'salary_basic')::numeric,
              v_staff_data || jsonb_build_object('staff_stage', 'active', 'source', v_channel, 'source_doc', v_kind), p_user_id)
      returning id, data into v_item, v_merged;
      v_status := 'staff';
      v_undoable := true;
    end if;
    -- موعد البطاقة اقرب انتهاء: الهوية او العقد، فيظهر في التقويم وينبه كسائر العناصر
    update public.items set due_at = (select (min(day)::timestamp + interval '9 hours') at time zone 'Asia/Riyadh'
                                        from (values (nullif(v_merged->>'id_expiry', '')::date), (nullif(v_merged->>'contract_end', '')::date)) dates(day))
    where id = v_item;
    v_title := v_name; v_label := 'ملف موظف';
  elsif v_expense then
    select id into v_record from public.records where org_id = v_org and name ~* 'مصاري|مصروف|expense' order by created_at asc limit 1;
    if v_record is null then
      insert into public.records (org_id, name, columns, created_by) values (v_org, 'المصاريف', '[]'::jsonb, p_user_id) returning id into v_record;
    end if;
  else
    select id into v_record from public.records where org_id = v_org and name in ('المستندات','Documents','دستاویزات') order by created_at asc limit 1;
    if v_record is null then
      insert into public.records (org_id, name, columns, created_by) values (v_org, 'المستندات', '[]'::jsonb, p_user_id) returning id into v_record;
    end if;
  end if;

  if not v_staff then

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
    values (v_org, v_record, v_title, v_category, v_due, 'open', v_party, v_amount, v_case,
            v_new || jsonb_build_object('document_kind', v_kind, 'details', v_details, 'detail_labels', v_labels), p_user_id)
    returning id into v_item;
    v_undoable := true;
  end if;
  end if;

  -- الملف على خادم جدة (WhatsApp): رفعه الـ Worker الى خانة اصدرها chat_upload_slot لهذا المستخدم وهذه الشركة،
  -- فتستهلك الخانة هنا مرة واحدة، والحجم من التخزين نفسه لا من الطلب، ويحسب على سعة الباقة
  v_path := nullif(btrim(coalesce(p_file->>'storage_path', '')), '');
  if v_path is not null then
    delete from public.chat_upload_slots s where s.path = v_path and s.user_id = p_user_id and s.org_id = v_org
    returning s.path into v_slot;
    if v_slot is null then raise exception 'bad_path' using errcode = 'check_violation'; end if;
    -- ملف الموظف في مجلد <org>/hr/ وحده، فسياسة التخزين تحجبه عن غير الموارد البشرية والادارة
    if v_staff and split_part(v_path, '/', 2) <> 'hr' then raise exception 'bad_path' using errcode = 'check_violation'; end if;
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
  if not v_staff and jsonb_typeof(p_doc->'profile_updates') = 'object' then
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

  -- ما ادخله غير المالك والمدير وفيه تنبيه او تصحيح: «يحتاج مراجعة» حتى يعتمده المالك او المدير
  v_review := case when jsonb_typeof(p_doc->'review') = 'array' and jsonb_array_length(p_doc->'review') > 0 then p_doc->'review' end;
  if v_review is not null and coalesce(v_role, '') not in ('owner', 'admin') then
    update public.items set data = data || jsonb_build_object('needs_review', true, 'review_reasons', v_review, 'review_by', p_user_id)
    where id = v_item;
  else
    v_review := null;
  end if;

  if v_expense then v_status := 'expense'; end if;
  return jsonb_build_object('status', v_status, 'item_id', v_item, 'amount', v_amount, 'undoable', v_undoable, 'needs_review', v_review is not null, 'title', v_title, 'kind', v_kind, 'label', v_label, 'number', v_number,
                            'party', v_party, 'issue_date', v_issue, 'expiry_date', v_expiry, 'role', v_role,
                            'profile_updates', v_updates, 'profile_current', v_current);
end $function$;
revoke all on function public.telegram_save_document(text, uuid, jsonb, jsonb) from public;
grant execute on function public.telegram_save_document(text, uuid, jsonb, jsonb) to anon, service_role;
