-- المهندس رعد 2026-10-01: «نفذ» حماية بيانات الموارد البشرية قبل شاشة العروض.
--
-- قيس قبلها: سياسة items_rw تفتح كل عناصر الحساب لكل اعضائه، فرواتب الموظفين
-- وهوياتهم وحساباتهم البنكية وإجازاتهم تظهر لاي عضو في قائمة لوحة التحكم العامة،
-- ويصدرها الى Excel بكل حقولها، ويقراها بجلسته من القاعدة، ويسال عنها البوت. وسجل
-- التدقيق يحمل نسخة كاملة من كل عنصر يقراها كل عضو، والمرفقات وملفاتها كذلك.
--
-- العلاج في القاعدة نفسها فيتبعها كل طريق:
-- 1) عمود عام items.visibility: فارغ = لكل اعضاء الحساب كما كان، و'hr' = لقسم
--    الموارد البشرية وقسم الادارة والمالك والمشرف وحدهم. يضعه مشغل لا المتصفح:
--    كل عنصر يحمل مفتاحا من مفاتيح شاشات الموارد البشرية يصير 'hr' ايا كان مصدره.
-- 2) سياسات items و ledger و attachments و storage.objects (ملفات الموارد البشرية
--    في مجلد <org>/hr/ من التخزين).
-- 3) الدوال التي تتجاوز السياسة بصلاحية مالكها وتعرض العناصر لشخص: البوت وادوات
--    MCP ودردشة الاوامر والتقويم الخارجي وواجهة API لا تعرض سجلات الموارد البشرية
--    لاحد، وملخص الاسبوع وملف القضية ومرشحو الربط يتبعون صلاحية صاحب الجلسة،
--    والتذكيرات لا تولد الا لمن يرى العنصر. كل دالة كما هي حرفا الا قيد الرؤية.
-- حين كتب الترحيل كانت القاعدة بلا موظف ولا اجازة ولا دورة، فلا يختفي شيء عن احد.

begin;

alter table public.items add column if not exists visibility text;
alter table public.items drop constraint if exists items_visibility_check;
alter table public.items add constraint items_visibility_check check (visibility is null or visibility in ('hr'));

-- من يرى فئة رؤية في حساب: الفارغ للجميع، و'hr' للقسم والادارة والمالك والمشرف
create or replace function public.hr_visible(p_org uuid, p_visibility text, p_user uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select p_visibility is null
      or (p_visibility = 'hr' and p_user is not null and exists (
            select 1 from public.org_members m
             where m.org_id = p_org and m.user_id = p_user and m.status = 'active'
               and (m.role in ('owner', 'admin') or m.department in ('hr', 'management'))))
$$;
create or replace function public.hr_visible_me(p_org uuid, p_visibility text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select public.hr_visible(p_org, p_visibility, auth.uid())
$$;
create or replace function public.item_visible_me(p_item uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select public.hr_visible(i.org_id, i.visibility, auth.uid()) from public.items i where i.id = p_item), true)
$$;
create or replace function public.ledger_row_visible_me(p_org uuid, p_type text, p_entity uuid, p_before jsonb, p_after jsonb)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select p_type is distinct from 'item' or public.hr_visible(p_org,
           coalesce((select i.visibility from public.items i where i.id = p_entity), p_after ->> 'visibility', p_before ->> 'visibility'),
           auth.uid())
$$;
revoke all on function public.hr_visible(uuid, text, uuid) from public, anon, authenticated;
-- الدوال القديمة التي تناديها يملكها postgres، فلها وحدها حق النداء
grant execute on function public.hr_visible(uuid, text, uuid) to postgres;
revoke all on function public.hr_visible_me(uuid, text) from public;
revoke all on function public.item_visible_me(uuid) from public;
revoke all on function public.ledger_row_visible_me(uuid, text, uuid, jsonb, jsonb) from public;
grant execute on function public.hr_visible_me(uuid, text) to anon, authenticated;
grant execute on function public.item_visible_me(uuid) to anon, authenticated;
grant execute on function public.ledger_row_visible_me(uuid, text, uuid, jsonb, jsonb) to anon, authenticated;

-- المشغل يضع الفئة: مفاتيح شاشات الموارد البشرية وحدها، ولا ينزلها ما دامت المفاتيح قائمة.
-- ليس security definer (قاعدة 0135).
create or replace function public.items_set_visibility()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if coalesce(new.data, '{}'::jsonb) ?| array['staff_stage', 'leave_approval', 'train_kind', 'offer_stage', 'hr_task'] then
    new.visibility := 'hr';
  end if;
  return new;
end $$;
revoke all on function public.items_set_visibility() from public;
drop trigger if exists items_visibility on public.items;
create trigger items_visibility before insert or update of data, visibility on public.items
  for each row execute function public.items_set_visibility();
update public.items set visibility = 'hr'
 where visibility is null and data ?| array['staff_stage', 'leave_approval', 'train_kind', 'offer_stage', 'hr_task'];

-- السياسات: كما كانت حرفا وزيادة قيد الرؤية
drop policy if exists items_rw on public.items;
create policy items_rw on public.items for all
  using (org_id in (select public.current_org_ids()) and (visibility is null or public.hr_visible_me(org_id, visibility)))
  with check (org_id in (select public.current_org_ids()) and (visibility is null or public.hr_visible_me(org_id, visibility)));

drop policy if exists ledger_read on public.ledger;
create policy ledger_read on public.ledger for select
  using ((org_id in (select public.current_org_ids()) and public.ledger_row_visible_me(org_id, entity_type, entity_id, before, after))
         or public.is_platform_admin());

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select
  using ((org_id in (select public.current_org_ids()) and (item_id is null or public.item_visible_me(item_id)))
         or public.is_platform_admin());
drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments for insert
  with check (org_id in (select public.current_org_ids()) and uploaded_by = (select auth.uid())
              and (item_id is null or public.item_visible_me(item_id)));

drop policy if exists tracker_attachments_read on storage.objects;
create policy tracker_attachments_read on storage.objects for select
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids())
         and (split_part(name, '/', 2) <> 'hr' or public.hr_visible_me((split_part(name, '/', 1))::uuid, 'hr')));
drop policy if exists tracker_attachments_insert on storage.objects;
create policy tracker_attachments_insert on storage.objects for insert
  with check (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids())
              and (split_part(name, '/', 2) <> 'hr' or public.hr_visible_me((split_part(name, '/', 1))::uuid, 'hr')));
drop policy if exists tracker_attachments_delete on storage.objects;
create policy tracker_attachments_delete on storage.objects for delete
  using (bucket_id = 'attachments' and (split_part(name, '/', 1))::uuid in (select public.current_org_ids())
         and (split_part(name, '/', 2) <> 'hr' or public.hr_visible_me((split_part(name, '/', 1))::uuid, 'hr')));

-- الدوال: نصها الحي كما هو، وقيد الرؤية في استعلام العناصر وحده

-- telegram_search
CREATE OR REPLACE FUNCTION public.telegram_search(p_secret text, p_user_id uuid, p_query text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q text; result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  q := '%' || trim(coalesce(p_query, '')) || '%';
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'item_number', i.item_number, 'title', i.title, 'due_at', i.due_at, 'status', i.status,
    'client_name', i.client_name, 'case_number', i.case_number, 'amount', i.amount,
    'violation_number', i.data->>'violation_number', 'record_name', t.name,
    'attachments', (select count(*) from public.attachments a where a.item_id = i.id),
    'roles', public.item_roles_text(i.id)
  ) order by (i.status = 'open') desc, i.due_at asc nulls last), '[]'::jsonb) into result
  from (
    select i.* from public.items i
    where i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
      and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
    order by (i.status = 'open') desc, i.due_at asc nulls last
    limit greatest(1, least(coalesce(p_limit, 8), 20))
  ) i left join public.records t on t.id = i.record_id;
  return result;
end $function$;

-- telegram_items
CREATE OR REPLACE FUNCTION public.telegram_items(p_secret text, p_user_id uuid, p_mode text, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', x.title, 'due_at', x.due_at, 'record_name', x.record_name, 'org_name', x.org_name,
           'client_name', x.client_name, 'case_number', x.case_number,
           'kind', public.item_kind(x.category, x.case_number, x.data, x.parent_id),
           'document_kind', x.data->>'document_kind',
           'doc_number', coalesce(x.data->>'number', x.data->'details'->>'cr_number', x.data->'details'->>'vat_number'),
           'issue_date', coalesce(x.data->'details'->>'issue_date', x.data->'details'->>'certificate_date', x.data->>'issue_date'),
           'violation_number', x.data->>'violation_number') order by x.due_at asc), '[]'::jsonb)
  into result
  from (
    select i.title, i.due_at, i.client_name, i.case_number, i.category, i.data, i.parent_id,
           t.name as record_name, o.name as org_name
    from public.items i
    left join public.records t on t.id = i.record_id
    left join public.organizations o on o.id = i.org_id
    where i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
      and i.status = 'open' and i.due_at is not null
      and ((p_mode = 'overdue' and i.due_at < now()) or (p_mode <> 'overdue' and i.due_at >= now()))
      and (p_mode = 'overdue'
           or not (i.data ? 'document_kind')
           or i.due_at <= now() + interval '30 days')
    order by i.due_at asc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) x;
  return result;
end $function$;

-- telegram_items_by_kind
CREATE OR REPLACE FUNCTION public.telegram_items_by_kind(p_secret text, p_user_id uuid, p_kind text DEFAULT 'all'::text, p_status text DEFAULT 'open'::text, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; k text := lower(coalesce(p_kind,'all')); st text := lower(coalesce(p_status,'open'));
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', x.id, 'item_number', x.item_number, 'title', x.title, 'status', x.status, 'due_at', x.due_at,
      'client_name', x.client_name, 'case_number', x.case_number, 'amount', x.amount, 'category', x.category, 'record_name', x.record_name,
      'document_kind', x.data->>'document_kind', 'doc_number', coalesce(x.data->>'number', x.data->'details'->>'cr_number', x.data->'details'->>'vat_number'),
      'issue_date', coalesce(x.data->'details'->>'issue_date', x.data->'details'->>'certificate_date', x.data->>'issue_date'),
      'violation_number', x.data->>'violation_number')
      order by (x.status = 'open') desc, x.due_at asc nulls last, x.created_at desc), '[]'::jsonb)
  into result
  from (
    select i.id, i.item_number, i.title, i.status, i.due_at, i.client_name, i.case_number, i.amount, i.category, i.created_at, i.data, t.name as record_name
    from public.items i left join public.records t on t.id = i.record_id
    where i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
      and (st = 'all' or (st = 'open' and i.status = 'open') or (st = 'done' and i.status <> 'open'))
      and (k = 'all'
        or (k = 'case' and (coalesce(t.name,'') ilike '%قض%' or coalesce(t.name,'') ilike '%case%' or coalesce(i.category,'') ilike '%قض%' or i.case_number is not null))
        or (k = 'violation' and (coalesce(t.name,'') ilike '%مخالف%' or coalesce(t.name,'') ilike '%violation%' or coalesce(i.category,'') ilike '%مخالف%'))
        or (k = 'task' and (coalesce(t.name,'') ilike '%مهام%' or coalesce(t.name,'') ilike '%task%' or coalesce(i.category,'') ilike '%مهم%'))
        or (k = 'document' and (coalesce(t.name,'') ilike '%مستند%' or coalesce(t.name,'') ilike '%document%' or i.data ? 'document_kind')))
    order by (i.status = 'open') desc, i.due_at asc nulls last, i.created_at desc
    limit greatest(1, least(coalesce(p_limit, 10), 30))
  ) x;
  return result;
end $function$;

-- telegram_digest
CREATE OR REPLACE FUNCTION public.telegram_digest(p_secret text, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tz text; d0 timestamptz; d1 timestamptz; d2 timestamptz; result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(p.tz, 'Asia/Riyadh') into tz from public.profiles p where p.id = p_user_id;
  tz := coalesce(tz, 'Asia/Riyadh');
  d0 := ((now() at time zone tz)::date)::timestamp at time zone tz;
  d1 := d0 + interval '1 day'; d2 := d0 + interval '2 days';
  with mine as (
    select i.*, t.name as record_name, (select count(*) from public.attachments a where a.item_id = i.id) as attachments
    from public.items i left join public.records t on t.id = i.record_id
    where i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null and i.status = 'open'
  )
  select jsonb_build_object(
    'today', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'due_at', due_at, 'client_name', client_name, 'case_number', case_number, 'attachments', attachments, 'record_name', record_name) order by due_at), '[]'::jsonb) from mine where due_at >= d0 and due_at < d1),
    'tomorrow', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'due_at', due_at, 'client_name', client_name, 'case_number', case_number, 'attachments', attachments, 'record_name', record_name) order by due_at), '[]'::jsonb) from mine where due_at >= d1 and due_at < d2),
    'violations_soon', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'due_at', due_at, 'amount', amount, 'client_name', client_name) order by due_at), '[]'::jsonb) from mine where category = 'مخالفة' and due_at >= d0 and due_at < d0 + interval '3 days'),
    'violations_soon_total', (select coalesce(sum(amount), 0) from mine where category = 'مخالفة' and due_at >= d0 and due_at < d0 + interval '3 days'),
    'overdue_count', (select count(*) from mine where due_at < d0),
    'overdue_amount', (select coalesce(sum(amount), 0) from mine where due_at < d0 and category = 'مخالفة'),
    'neglected', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'client_name', client_name, 'case_number', case_number, 'days', extract(day from now() - updated_at)::int) order by updated_at asc), '[]'::jsonb)
                  from (select * from mine where updated_at < now() - interval '30 days' order by updated_at asc limit 3) n),
    'open_total', (select count(*) from mine)
  ) into result;
  return result;
end $function$;

-- telegram_complete
CREATE OR REPLACE FUNCTION public.telegram_complete(p_secret text, p_user_id uuid, p_query text, p_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q text; c int; v_id uuid; v_title text; v_num text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if p_item_id is not null then
    update public.items set status = 'done' where id = p_item_id and status = 'open' and org_id in (select public.telegram_user_orgs(p_user_id)) and visibility is null
    returning id, title, item_number into v_id, v_title, v_num;
    if v_id is null then return jsonb_build_object('status', 'not_found'); end if;
    return jsonb_build_object('status', 'done', 'id', v_id, 'title', v_title, 'item_number', v_num);
  end if;
  q := '%' || trim(coalesce(p_query, '')) || '%';
  select count(*) into c from public.items i
  where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q);
  if c = 0 then return jsonb_build_object('status', 'not_found'); end if;
  if c > 1 then
    return jsonb_build_object('status', 'ambiguous', 'candidates', (
      select jsonb_agg(jsonb_build_object('id', i.id, 'item_number', i.item_number, 'title', i.title, 'due_at', i.due_at, 'client_name', i.client_name) order by i.due_at asc nulls last)
      from (select * from public.items i where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
            and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
            order by i.due_at asc nulls last limit 6) i));
  end if;
  update public.items i set status = 'done'
  where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
  returning i.id, i.title, i.item_number into v_id, v_title, v_num;
  return jsonb_build_object('status', 'done', 'id', v_id, 'title', v_title, 'item_number', v_num);
end $function$;

-- telegram_assign
CREATE OR REPLACE FUNCTION public.telegram_assign(p_secret text, p_user_id uuid, p_query text, p_member text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q text; mq text; v_item uuid; v_org uuid; v_title text; v_num text; c int; v_member uuid; v_member_name text; v_chat text; v_lang text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  q := '%' || trim(coalesce(p_query, '')) || '%'; mq := '%' || trim(coalesce(p_member, '')) || '%';
  select count(*) into c from public.items i where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q);
  if c = 0 then return jsonb_build_object('status', 'not_found'); end if;
  if c > 1 then return jsonb_build_object('status', 'ambiguous'); end if;
  select i.id, i.org_id, i.title, i.item_number into v_item, v_org, v_title, v_num from public.items i where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q) limit 1;
  select p.id, p.full_name, p.lang into v_member, v_member_name, v_lang from public.profiles p
  join public.org_members m on m.user_id = p.id and m.status = 'active'
  where m.org_id = v_org and (p.full_name ilike mq or p.email ilike mq)
  order by (p.email ilike mq) desc limit 1;
  if v_member is null then return jsonb_build_object('status', 'no_member'); end if;
  update public.items set assignee_id = v_member where id = v_item;
  delete from public.item_roles where item_id = v_item and role = 'R' and user_id <> v_member;
  insert into public.item_roles (org_id, item_id, user_id, role, set_by) values (v_org, v_item, v_member, 'R', p_user_id)
  on conflict (item_id, user_id) do update set role = 'R', set_by = p_user_id, updated_at = now();
  if not exists (select 1 from public.item_roles where item_id = v_item and role = 'A') and p_user_id <> v_member then
    insert into public.item_roles (org_id, item_id, user_id, role, set_by) values (v_org, v_item, p_user_id, 'A', p_user_id)
    on conflict (item_id, user_id) do update set role = 'A', set_by = p_user_id, updated_at = now();
  end if;
  select external_id into v_chat from public.channel_links where user_id = v_member and channel = 'telegram' and verified_at is not null;
  return jsonb_build_object('status', 'assigned', 'id', v_item, 'title', v_title, 'item_number', v_num,
                            'member_name', v_member_name, 'member_chat', v_chat, 'member_lang', coalesce(v_lang, 'ar'));
end $function$;

-- telegram_set_reminder
CREATE OR REPLACE FUNCTION public.telegram_set_reminder(p_secret text, p_user_id uuid, p_query text, p_before text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q text; c int; v_int interval; v_row public.items%rowtype;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  v_int := public.telegram_parse_before(p_before);
  if v_int is null or v_int <= interval '0' then
    return jsonb_build_object('status', 'bad_interval', 'given', p_before);
  end if;

  q := '%' || btrim(coalesce(p_query, '')) || '%';
  select count(*) into c from public.items i
  where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q);

  if c = 0 then return jsonb_build_object('status', 'not_found'); end if;
  if c > 1 then
    return jsonb_build_object('status', 'ambiguous', 'candidates', (
      select jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title, 'case_number', i.case_number,
                                          'client_name', i.client_name, 'due_at', i.due_at) order by i.due_at asc nulls last)
      from (select * from public.items i
            where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
              and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
            order by i.due_at asc nulls last limit 6) i));
  end if;

  update public.items i set remind_before = v_int
  where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
    and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
  returning i.* into v_row;

  if v_row.id is null then return jsonb_build_object('status', 'not_found'); end if;

  return jsonb_build_object('status', 'set',
    'title', v_row.title, 'case_number', v_row.case_number,
    'violation_number', v_row.data->>'violation_number',
    'client_name', v_row.client_name, 'due_at', v_row.due_at, 'status', v_row.status,
    'remind_before', v_int::text,
    'remind_at', case when v_row.due_at is null then null else v_row.due_at - v_int end);
end $function$;

-- telegram_update_item
CREATE OR REPLACE FUNCTION public.telegram_update_item(p_secret text, p_user_id uuid, p_query text, p_item_id uuid DEFAULT NULL::uuid, p_patch jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
     where i.id = p_item_id and i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null;
    if v_id is null then return jsonb_build_object('status', 'not_found'); end if;
  else
    if trim(coalesce(p_query, '')) = '' then return jsonb_build_object('status', 'not_found'); end if;
    q := '%' || trim(p_query) || '%';
    select count(*) into c from public.items i
     where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
       and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q);
    if c = 0 then return jsonb_build_object('status', 'not_found'); end if;
    if c > 1 then
      return jsonb_build_object('status', 'ambiguous', 'candidates', (
        select jsonb_agg(jsonb_build_object('id', i.id, 'item_number', i.item_number, 'title', i.title, 'due_at', i.due_at, 'client_name', i.client_name) order by i.due_at asc nulls last)
          from (select * from public.items i where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
                  and (i.title ilike q or i.case_number ilike q or i.client_name ilike q or i.item_number ilike q or (i.data->>'violation_number') ilike q)
                 order by i.due_at asc nulls last limit 6) i));
    end if;
    select i.id, i.title, i.item_number into v_id, v_title, v_num from public.items i
     where i.status = 'open' and i.org_id in (select public.telegram_user_orgs(p_user_id)) and i.visibility is null
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
end $function$;

-- telegram_absent_targets
CREATE OR REPLACE FUNCTION public.telegram_absent_targets(p_secret text, p_days integer DEFAULT 2, p_cooldown_days integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; v_days integer := greatest(1, coalesce(p_days, 2)); v_cool integer := greatest(1, coalesce(p_cooldown_days, 3));
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into result from (
    select jsonb_build_object(
      'user_id', p.id,
      'chat_id', cl.external_id,
      'lang', coalesce(p.lang, 'ar'),
      'tz', coalesce(p.tz, 'Asia/Riyadh'),
      'time_format', coalesce(p.time_format, '24'),
      'name', p.full_name,
      'days_absent', floor(extract(epoch from (now() - coalesce(p.last_seen_at, p.created_at))) / 86400)::int,
      'open_total', (select count(*) from public.items i
                     where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active') and i.visibility is null
                       and i.status = 'open'),
      'overdue_count', (select count(*) from public.items i
                        where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active') and i.visibility is null
                          and i.status = 'open' and i.due_at is not null and i.due_at < now()),
      'due_soon_count', (select count(*) from public.items i
                         where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active') and i.visibility is null
                           and i.status = 'open' and i.due_at is not null and i.due_at >= now() and i.due_at < now() + interval '7 days'),
      'next_title', (select i.title from public.items i
                     where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active') and i.visibility is null
                       and i.status = 'open' and i.due_at is not null and i.due_at >= now()
                     order by i.due_at limit 1),
      'next_due', (select i.due_at from public.items i
                   where i.org_id in (select m.org_id from public.org_members m where m.user_id = p.id and m.status = 'active') and i.visibility is null
                     and i.status = 'open' and i.due_at is not null and i.due_at >= now()
                   order by i.due_at limit 1)
    ) as x
    from public.channel_links cl
    join public.profiles p on p.id = cl.user_id
    where cl.channel = 'telegram'
      and cl.verified_at is not null
      and cl.external_id is not null
      and extract(hour from (now() at time zone coalesce(p.tz, 'Asia/Riyadh'))) = 10
      and coalesce(p.last_seen_at, p.created_at) < now() - make_interval(days => v_days)
      and (cl.last_nudge_at is null or cl.last_nudge_at < now() - make_interval(days => v_cool))
      and p.delete_requested_at is null
  ) t;
  return result;
end $function$;

-- telegram_team
CREATE OR REPLACE FUNCTION public.telegram_team(p_secret text, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid; v_name text; v_result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  v_org := public.telegram_user_org(p_user_id);
  if v_org is null then return jsonb_build_object('status', 'no_org'); end if;
  select name into v_name from public.organizations where id = v_org;

  select jsonb_build_object(
    'status', 'ok',
    'org', jsonb_build_object('id', v_org, 'name', v_name),
    'members', coalesce(jsonb_agg(m order by m->>'full_name'), '[]'::jsonb)
  )
  into v_result
  from (
    select jsonb_build_object(
      'user_id', mem.user_id,
      'full_name', coalesce(pr.full_name, pr.email, ''),
      'email', pr.email,
      'role', mem.role,
      'department', mem.department,
      'job_title', mem.job_title,
      'open', coalesce(w.open_count, 0),
      'overdue', coalesce(w.overdue_count, 0),
      'next_due', w.next_due,
      'items', coalesce(w.items, '[]'::jsonb)
    ) as m
    from public.org_members mem
    left join public.profiles pr on pr.id = mem.user_id
    left join lateral (
      select count(*) filter (where i.status = 'open') as open_count,
             count(*) filter (where i.status = 'open' and i.due_at < now()) as overdue_count,
             min(i.due_at) filter (where i.status = 'open' and i.due_at >= now()) as next_due,
             (select jsonb_agg(x) from (
                 select jsonb_build_object(
                   'title', j.title, 'case_number', j.case_number,
                   'violation_number', j.data->>'violation_number',
                   'client_name', j.client_name, 'due_at', j.due_at, 'status', j.status) as x
                 from public.items j
                 where j.org_id = v_org and j.assignee_id = mem.user_id and j.status = 'open' and j.visibility is null
                 order by j.due_at asc nulls last limit 5) top5) as items
      from public.items i
      where i.org_id = v_org and i.assignee_id = mem.user_id and i.visibility is null
    ) w on true
    where mem.org_id = v_org and mem.status = 'active'
  ) rows;

  return v_result;
end $function$;

-- calendar_feed
CREATE OR REPLACE FUNCTION public.calendar_feed(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid; v_user uuid; result jsonb;
begin
  select org_id, user_id into v_org, v_user from public.calendar_tokens where token = p_token;
  if v_org is null then return null; end if;
  if not exists (select 1 from public.org_members m
                  where m.org_id = v_org and m.user_id = v_user and m.status = 'active') then
    return null;
  end if;
  select jsonb_build_object(
    'org_name', (select name from public.organizations where id = v_org),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'title', i.title, 'category', i.category, 'due_at', i.due_at, 'status', i.status, 'record_name', t.name
      ) order by i.due_at)
      from public.items i left join public.records t on t.id = i.record_id
      where i.org_id = v_org and i.visibility is null and i.due_at is not null and i.status <> 'cancelled'), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

-- api_items_export
CREATE OR REPLACE FUNCTION public.api_items_export(p_secret text, p_hash text, p_record text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select org_id into v_org from public.api_keys where key_hash = p_hash and revoked_at is null;
  if v_org is null then raise exception 'bad key' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', i.id, 'number', i.item_number, 'title', i.title, 'category', i.category, 'record', t.name,
      'status', i.status, 'due_at', i.due_at, 'assignee_email', p.email, 'amount', i.amount,
      'client_name', i.client_name, 'case_number', i.case_number, 'data', i.data,
      'created_at', i.created_at, 'updated_at', i.updated_at) order by i.created_at desc)
    from public.items i
    join public.records t on t.id = i.record_id
    left join public.profiles p on p.id = i.assignee_id
    where i.org_id = v_org and i.visibility is null and (p_record is null or p_record = '' or t.name = p_record)), '[]'::jsonb);
end $function$;

-- acct_pending
CREATE OR REPLACE FUNCTION public.acct_pending(p_secret text, p_org uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x.row order by x.created_at), '[]'::jsonb) into v
  from (
    select i.created_at,
           jsonb_build_object('id', i.id, 'org_id', i.org_id, 'provider', l.provider, 'title', i.title,
             'category', i.category, 'amount', i.amount, 'client_name', i.client_name,
             'case_number', i.case_number, 'due_at', i.due_at, 'created_at', i.created_at,
             'status', i.status, 'data', i.data, 'push_status', p.status) as row
      from public.items i
      join public.accounting_links l on l.org_id = i.org_id
      left join public.accounting_pushes p on p.item_id = i.id and p.provider = l.provider
     where (p_org is null or i.org_id = p_org)
       and i.created_at >= l.connected_at
       and i.visibility is null
       and coalesce(i.status, '') <> 'cancelled'
       and not (coalesce(i.data, '{}'::jsonb) ? 'document_kind')
       and (   coalesce(i.data, '{}'::jsonb) ? 'fin_dir'
            or coalesce(i.category, '') ~* '(مصروف|مصاريف|expense|d.pense|اخراجات)'
            or (coalesce(i.category, '') = '' and coalesce(i.title, '') ~* '(مصروف|مصاريف|expense|d.pense|اخراجات)'))
       and (   p.item_id is null
            or (p.status = 'failed' and p.attempts < 5 and p.updated_at < now() - interval '15 minutes')
            or (p.status in ('waiting', 'skipped') and (i.updated_at > p.updated_at or l.updated_at > p.updated_at))
            or (p.status = 'pending' and p.updated_at < now() - interval '30 minutes'))
     order by i.created_at
     limit greatest(1, least(coalesce(p_limit, 20), 50))
  ) x;
  return v;
end $function$;

-- week_summary
CREATE OR REPLACE FUNCTION public.week_summary(p_org uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_this_start timestamptz; v_last_start timestamptz; v_next_start timestamptz; result jsonb;
begin
  if not exists (
    select 1 from public.org_members m
    where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active'
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_this_start := (date_trunc('day', now() at time zone 'Asia/Riyadh')
                   - make_interval(days => extract(dow from now() at time zone 'Asia/Riyadh')::int))
                  at time zone 'Asia/Riyadh';
  v_last_start := v_this_start - interval '7 days';
  v_next_start := v_this_start + interval '7 days';

  select jsonb_build_object(
    'week_start', v_this_start,
    'last_week_start', v_last_start,
    'done_this_week',  count(*) filter (where i.status = 'done' and coalesce(i.completed_at, i.updated_at) >= v_this_start and coalesce(i.completed_at, i.updated_at) < v_next_start),
    'added_this_week', count(*) filter (where i.created_at >= v_this_start and i.created_at < v_next_start),
    'late_this_week',  count(*) filter (where i.status <> 'done' and i.due_at >= v_this_start and i.due_at < v_next_start and i.due_at < now()),
    'done_last_week',  count(*) filter (where i.status = 'done' and coalesce(i.completed_at, i.updated_at) >= v_last_start and coalesce(i.completed_at, i.updated_at) < v_this_start),
    'added_last_week', count(*) filter (where i.created_at >= v_last_start and i.created_at < v_this_start),
    'late_last_week',  count(*) filter (where i.status <> 'done' and i.due_at >= v_last_start and i.due_at < v_this_start)
  )
  into result
  from public.items i
  where i.org_id = p_org and public.hr_visible(i.org_id, i.visibility, auth.uid());

  return result;
end $function$;

-- case_file
CREATE OR REPLACE FUNCTION public.case_file(p_org uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_head jsonb; v_kids jsonb;
begin
  if p_org not in (select public.current_org_ids()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select to_jsonb(h) - 'org_id' into v_head
  from (
    select i.id, i.item_number, i.title, i.category, i.status, i.due_at, i.amount,
           i.client_name, i.client_name_en, i.case_number, i.stage, i.assignee_id, i.data, i.org_id,
           public.item_kind(i.category, i.case_number, i.data, i.parent_id) as kind,
           (select count(*) from public.attachments a where a.item_id = i.id) as attachments
    from public.items i where i.id = p_case and i.org_id = p_org and public.hr_visible(i.org_id, i.visibility, auth.uid())
  ) h;
  if v_head is null then return jsonb_build_object('error', 'not_found'); end if;

  select coalesce(jsonb_agg(to_jsonb(k) order by k.due_at nulls last, k.created_at), '[]'::jsonb) into v_kids
  from (
    select i.id, i.item_number, i.title, i.category, i.status, i.due_at, i.amount,
           i.client_name, i.case_number, i.stage, i.assignee_id, i.created_at, i.data,
           public.item_kind(i.category, i.case_number, i.data, i.parent_id) as kind,
           (select count(*) from public.attachments a where a.item_id = i.id) as attachments
    from public.items i
    where i.org_id = p_org and public.hr_visible(i.org_id, i.visibility, auth.uid())
      and i.id <> p_case
      and (i.parent_id = p_case
           or (v_head->>'case_number' is not null and i.case_number = v_head->>'case_number'))
  ) k;

  return jsonb_build_object('head', v_head, 'children', v_kids);
end $function$;

-- parent_candidates
CREATE OR REPLACE FUNCTION public.parent_candidates(p_org uuid, p_hint text DEFAULT NULL::text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select i.id, i.item_number, i.title, i.client_name, i.case_number, i.data->>'violation_number' as violation_number, i.due_at, i.category
    from public.items i
    where i.org_id = p_org and public.hr_visible(i.org_id, i.visibility, auth.uid())
      and ((select auth.uid()) is null or p_org in (select public.current_org_ids()))
      and i.status = 'open' and i.parent_id is null
      and (i.category in ('جلسة', 'مخالفة') or i.case_number is not null or (i.data->>'violation_number') is not null or i.category is null)
  ), hinted as (
    select * from base
    where p_hint is null or btrim(p_hint) = ''
       or case_number ilike '%' || btrim(p_hint) || '%' or violation_number ilike '%' || btrim(p_hint) || '%'
       or client_name ilike '%' || btrim(p_hint) || '%' or title ilike '%' || btrim(p_hint) || '%' or item_number ilike '%' || btrim(p_hint) || '%'
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'item_number', item_number, 'title', title, 'client_name', client_name,
           'case_number', case_number, 'violation_number', violation_number, 'due_at', due_at) order by due_at asc nulls last), '[]'::jsonb)
  from (select * from hinted order by due_at asc nulls last limit greatest(1, least(coalesce(p_limit, 8), 30))) x
$function$;

-- generate_due_notifications
CREATE OR REPLACE FUNCTION public.generate_due_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k int := 0; n int := 0; m int := 0;
begin
  insert into public.notifications (org_id, item_id, user_id, channel, scheduled_at, payload, status, sent_at)
  select i.org_id, i.id, mem.user_id, ch, i.due_at - i.remind_before,
         jsonb_build_object('title', i.title, 'due_at', i.due_at, 'record_id', i.record_id, 'item_number', i.item_number,
           'number', coalesce(i.data->>'number', i.data->'details'->>'cr_number', i.data->'details'->>'vat_number', i.case_number, i.data->>'violation_number')),
         case when ch = 'inapp' then 'sent' else 'pending' end,
         case when ch = 'inapp' then now() else null end
  from public.items i
  cross join lateral unnest(
    coalesce((select r.channels from public.reminder_rules r
              where r.org_id = i.org_id and (r.item_id = i.id or (r.item_id is null and r.record_id = i.record_id))
              order by (r.item_id is not null) desc limit 1), '{}'::text[]) || array['inapp']) as ch
  join public.org_members mem on mem.org_id = i.org_id and mem.status = 'active' and public.hr_visible(i.org_id, i.visibility, mem.user_id)
       and (i.assignee_id is null or mem.user_id = i.assignee_id)
  where i.status = 'open' and i.due_at is not null and i.remind_before is not null
    and i.due_at - i.remind_before <= now() + interval '5 minutes'
    and i.due_at > now() - interval '1 day'
    and not exists (select 1 from public.notifications x
                    where x.item_id = i.id and x.user_id = mem.user_id and x.channel = ch)
  on conflict do nothing;
  get diagnostics k = row_count;

  insert into public.notifications (org_id, item_id, user_id, channel, scheduled_at, payload, status, sent_at)
  select i.org_id, i.id, mem.user_id, ch, i.due_at - make_interval(mins => r.offset_minutes),
         jsonb_build_object('title', i.title, 'due_at', i.due_at, 'record_id', i.record_id, 'item_number', i.item_number,
           'number', coalesce(i.data->>'number', i.data->'details'->>'cr_number', i.data->'details'->>'vat_number', i.case_number, i.data->>'violation_number')),
         case when ch = 'inapp' then 'sent' else 'pending' end,
         case when ch = 'inapp' then now() else null end
  from public.items i
  join public.reminder_rules r on r.org_id = i.org_id and (r.item_id = i.id or (r.item_id is null and r.record_id = i.record_id))
  cross join lateral unnest(r.channels || array['inapp']) as ch
  join public.org_members mem on mem.org_id = i.org_id and mem.status = 'active' and public.hr_visible(i.org_id, i.visibility, mem.user_id)
       and (r.target = 'all' or mem.user_id = i.assignee_id)
  where i.status = 'open' and i.due_at is not null and i.remind_before is null
    and i.due_at - make_interval(mins => r.offset_minutes) <= now() + interval '5 minutes'
    and i.due_at > now() - interval '1 day'
  on conflict do nothing;
  get diagnostics n = row_count;

  insert into public.notifications (org_id, item_id, user_id, channel, scheduled_at, payload, status, sent_at)
  select i.org_id, i.id, mem.user_id, 'inapp', i.due_at - interval '1 day',
         jsonb_build_object('title', i.title, 'due_at', i.due_at, 'record_id', i.record_id, 'item_number', i.item_number,
           'number', coalesce(i.data->>'number', i.data->'details'->>'cr_number', i.data->'details'->>'vat_number', i.case_number, i.data->>'violation_number')),
         'sent', now()
  from public.items i
  join public.org_members mem on mem.org_id = i.org_id and mem.status = 'active' and public.hr_visible(i.org_id, i.visibility, mem.user_id)
       and (i.assignee_id is null or mem.user_id = i.assignee_id)
  where i.status = 'open' and i.due_at is not null and i.remind_before is null
    and i.due_at - interval '1 day' <= now() + interval '5 minutes'
    and i.due_at > now() - interval '1 day'
    and not exists (
      select 1 from public.reminder_rules r
      where r.org_id = i.org_id and (r.item_id = i.id or (r.item_id is null and r.record_id = i.record_id))
    )
    and not exists (
      select 1 from public.notifications x
      where x.item_id = i.id and x.user_id = mem.user_id and x.channel = 'inapp'
    );
  get diagnostics m = row_count;

  return k + n + m;
end $function$;

commit;

-- تحقق: العمود والمشغل، وكل دالة معدلة تحمل القيد
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'visibility') as amud,
       (select count(*) from pg_trigger where tgname = 'items_visibility') as mushaghghil,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prosecdef and p.prosrc ~* '(from|join)\s+(public\.)?items\y' and p.prosrc ~ 'visibility') as dawal_muqayyada;
