-- الورقة من المحادثة تصحح قبل حفظها، والفاتورة تسجل مصروفا (امر المهندس رعد 2026-10-29: «النظام يعالج الاخطاء
-- ويكون مرن جدا لو فيه ادخالات غير صحيحة»، و«خلينا نبني»). telegram_save_document يقبل as_expense للفاتورة:
-- بند «مصروف» في سجل المصاريف بدل مستند في المستندات، وملفه معه، ويحفظ قائمة الحقول التي صححها صاحبها.

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
  if v_expense then
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

  if v_expense then v_status := 'expense'; end if;
  return jsonb_build_object('status', v_status, 'item_id', v_item, 'amount', v_amount, 'title', v_title, 'kind', v_kind, 'label', v_label, 'number', v_number,
                            'party', v_party, 'issue_date', v_issue, 'expiry_date', v_expiry, 'role', v_role,
                            'profile_updates', v_updates, 'profile_current', v_current);
end $function$;
revoke all on function public.telegram_save_document(text, uuid, jsonb, jsonb) from public;
grant execute on function public.telegram_save_document(text, uuid, jsonb, jsonb) to anon, service_role;
