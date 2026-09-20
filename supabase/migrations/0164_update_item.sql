-- فعل «عدّل موعد» لدردشة الاوامر وبوت تيليغرام (المهندس رعد 2026-09-20: «نحتاج
-- نضيف دردشة بحيث اقدر اعطيها اوامر بدل من الشغل اليدوي، يعني اكتب فيها مثلا عدل
-- موعد»). الافعال الموجودة: اضافة، انجاز، اسناد، تذكير — ولا دالة تغير موعد عنصر.
--
-- على نسق telegram_complete حرفا: نفس البحث (العنوان، رقم القضية، العميل، الرقم
-- القياسي، رقم المخالفة)، نفس not_found و ambiguous مع المرشحين، ونفس النطاق
-- telegram_user_orgs. الحقول المقبولة في p_patch: due_at و title و client_name
-- و amount (اعمدة) و notes (داخل data كما تخزنها telegram_add_item). ما عداها يهمل.

begin;

create or replace function public.telegram_update_item(p_secret text, p_user_id uuid, p_query text, p_item_id uuid default null, p_patch jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q text; c int;
  v_id uuid; v_title text; v_num text; v_due timestamptz;
  n_due timestamptz; n_title text; n_client text; n_amount numeric; n_notes text;
  has_any boolean := false;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;

  -- ما يتغير: حقول معروفة وحدها، وكل قيمة تفحص قبل اللمس
  if p_patch ? 'due_at' and nullif(trim(p_patch->>'due_at'), '') is not null then
    begin n_due := (p_patch->>'due_at')::timestamptz;
    exception when others then return jsonb_build_object('status', 'bad_date'); end;
    has_any := true;
  end if;
  if p_patch ? 'title' then
    n_title := left(trim(p_patch->>'title'), 300);
    if n_title <> '' then has_any := true; else n_title := null; end if;
  end if;
  if p_patch ? 'client_name' then
    n_client := left(trim(p_patch->>'client_name'), 200);
    if n_client <> '' then has_any := true; else n_client := null; end if;
  end if;
  if p_patch ? 'amount' and nullif(trim(p_patch->>'amount'), '') is not null then
    begin n_amount := (p_patch->>'amount')::numeric;
    exception when others then return jsonb_build_object('status', 'bad_amount'); end;
    has_any := true;
  end if;
  if p_patch ? 'notes' and nullif(trim(p_patch->>'notes'), '') is not null then
    n_notes := left(p_patch->>'notes', 2000);
    has_any := true;
  end if;
  if not has_any then return jsonb_build_object('status', 'nothing'); end if;

  -- تحديد العنصر: بالمعرف، والا بالبحث كما في telegram_complete
  if p_item_id is not null then
    select i.id, i.title, i.item_number into v_id, v_title, v_num
      from public.items i
     where i.id = p_item_id and i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id));
    if v_id is null then return jsonb_build_object('status', 'not_found'); end if;
  else
    if trim(coalesce(p_query, '')) = '' then return jsonb_build_object('status', 'not_found'); end if;
    q := '%' || trim(p_query) || '%';
    select count(*) into c from public.items i
     where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id))
       and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q);
    if c = 0 then return jsonb_build_object('status', 'not_found'); end if;
    if c > 1 then
      return jsonb_build_object('status', 'ambiguous', 'candidates', (
        select jsonb_agg(jsonb_build_object('id', i.id, 'item_number', i.item_number, 'title', i.title, 'due_at', i.due_at, 'client_name', i.client_name) order by i.due_at asc nulls last)
          from (select * from public.items i where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id))
                  and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
                 order by i.due_at asc nulls last limit 6) i));
    end if;
    select i.id, i.title, i.item_number into v_id, v_title, v_num from public.items i
     where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id))
       and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
     limit 1;
  end if;

  update public.items i
     set due_at      = coalesce(n_due, i.due_at),
         title       = coalesce(n_title, i.title),
         client_name = coalesce(n_client, i.client_name),
         amount      = coalesce(n_amount, i.amount),
         data        = case when n_notes is null then i.data else coalesce(i.data, '{}'::jsonb) || jsonb_build_object('notes', n_notes) end,
         updated_at  = now()
   where i.id = v_id
  returning i.id, i.title, i.item_number, i.due_at into v_id, v_title, v_num, v_due;

  return jsonb_build_object('status', 'updated', 'id', v_id, 'title', v_title, 'item_number', v_num, 'due_at', v_due);
end $$;

-- السر داخل الدالة هو الحارس، والنداء ياتي بمفتاح anon من الـ Worker كبقية telegram_*
revoke all on function public.telegram_update_item(text, uuid, text, uuid, jsonb) from public;
grant execute on function public.telegram_update_item(text, uuid, text, uuid, jsonb) to service_role, authenticated, anon;

commit;

-- تحقق: دالة واحدة وصلاحياتها كاخواتها
select p.oid::regprocedure as tawqi3, coalesce(array_to_string(p.proacl, ' | '), '(bila acl)') as salahiyat
  from pg_proc p where p.proname = 'telegram_update_item';
