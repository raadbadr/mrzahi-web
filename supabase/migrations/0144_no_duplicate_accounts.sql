-- المهندس رعد 2026-09-16: بطاقتان متطابقتان لحساب واحد في لوحة ادارة المنصة
-- (الاسم Non، السجل التجاري 7000000000، المالك نفسه، بفارق ثلاث دقائق).
--
-- السبب: create_org_registered تنشئ منشاة جديدة في كل نداء بلا اي فحص، فمن ضغط
-- «انشاء» مرتين او اعاد المحاولة بعد تاخر الشبكة صار له حسابان متطابقان. ولا
-- قيد في القاعدة يمنع تكرار الرقم الرسمي، ولا يمنع حسابا شخصيا ثانيا لنفس الشخص.
--
-- الحل ثلاث طبقات لا واحدة:
-- 1) تنظيف المكرر القائم الذي لا عمل فيه (ورقة التسجيل التلقائية وحدها).
-- 2) قيود في القاعدة: الرقم الرسمي لا يتكرر، والحساب الشخصي واحد لكل شخص.
-- 3) الدالة نفسها تعيد الحساب القائم بدل انشاء ثان، وترفض رقما مسجلا لغير صاحبه.

begin;

-- 1) تنظيف المكرر القائم -----------------------------------------------------
-- من كل مجموعة تحمل الرقم الرسمي نفسه للمالك نفسه يبقى الاقدم، ويحذف ما بعده
-- بشرط ان يكون فارغا تماما: لا ورقة غير ورقة التسجيل التلقائية، ولا مرفق، ولا
-- دفعة، ولا عضو غير المالك. اي حساب فيه عمل انسان لا يمس.
with ranked as (
  select p.org_id,
         row_number() over (
           partition by o.owner_id, coalesce(p.cr_number, p.license_number, p.unified_number)
           order by o.created_at asc, o.id asc) as rn
  from public.org_profiles p
  join public.organizations o on o.id = p.org_id
  where coalesce(p.cr_number, p.license_number, p.unified_number) is not null
),
empty_dupes as (
  select r.org_id from ranked r
  where r.rn > 1
    and not exists (select 1 from public.items i
                     where i.org_id = r.org_id and coalesce(i.data->>'source', '') <> 'org_registration')
    and not exists (select 1 from public.attachments a where a.org_id = r.org_id)
    and not exists (select 1 from public.payments y where y.org_id = r.org_id)
    and (select count(*) from public.org_members m where m.org_id = r.org_id) <= 1
)
delete from public.organizations o using empty_dupes e where o.id = e.org_id;

-- 2) قيود القاعدة ------------------------------------------------------------
-- الرقم الرسمي يعرف الجهة: سجل تجاري او رخصة او رقم موحد واحد لجهة واحدة.
create unique index if not exists org_profiles_cr_number_key
  on public.org_profiles (cr_number) where cr_number is not null and cr_number <> '';
create unique index if not exists org_profiles_license_number_key
  on public.org_profiles (license_number) where license_number is not null and license_number <> '';
create unique index if not exists org_profiles_unified_number_key
  on public.org_profiles (unified_number) where unified_number is not null and unified_number <> '';

-- الحساب الشخصي واحد لكل شخص: مساحته الخاصة لا تتعدد مهما تكررت النداءات.
-- الدالة SECURITY DEFINER لانها تقرا صفوف غيره المحجوبة بـ RLS، ولا تعتمد على
-- current_user فلا ينطبق عليها تحفظ حراس الاعمدة في ترحيل 0135.
create or replace function public.one_personal_org_per_owner()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  if new.entity_type is distinct from 'individual' then return new; end if;
  select owner_id into v_owner from public.organizations where id = new.org_id;
  if v_owner is null then return new; end if;
  if exists (
    select 1 from public.org_profiles p
    join public.organizations o on o.id = p.org_id
    where o.owner_id = v_owner and p.org_id <> new.org_id and p.entity_type = 'individual'
  ) then
    raise exception 'PERSONAL_ORG_EXISTS' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists org_profiles_one_personal on public.org_profiles;
create trigger org_profiles_one_personal
before insert or update of entity_type on public.org_profiles
for each row execute function public.one_personal_org_per_owner();

-- 3) الدالة لا تنشئ ثانيا ----------------------------------------------------
create or replace function public.create_org_registered(p_name text, p_entity_type text, p_reg_number text, p_reg_expiry date, p_name_en text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid(); v_type text; v_kind text; v_num text; v_org uuid; v_record uuid; v_item uuid; v_item_num text;
  v_label text; v_plan text; v_exp timestamptz; v_ar text; v_en text; v_show text; v_same uuid; v_other uuid;
begin
  if v_actor is null then raise exception 'forbidden' using errcode = '42501'; end if;
  v_ar := nullif(btrim(coalesce(p_name, '')), '');
  v_en := nullif(btrim(coalesce(p_name_en, '')), '');
  if v_ar is null and v_en is null then raise exception 'NAME_REQUIRED' using errcode = 'P0001'; end if;
  v_show := coalesce(v_ar, v_en);
  v_type := case when p_entity_type in ('company','establishment','freelance','individual','nonprofit','government') then p_entity_type else 'company' end;
  v_num := regexp_replace(coalesce(p_reg_number, ''), '\s', '', 'g');
  if v_type in ('company','establishment') then
    if v_num !~ '^7[0-9]{9}$' then raise exception 'REG_NUMBER_INVALID' using errcode = 'P0001'; end if;
    v_kind := 'commercial_register'; v_label := 'السجل التجاري';
  elsif v_type = 'individual' then
    -- الشخص يدخل بلا هوية؛ وان كتب رقما فهو رقم هوية سعودية او اقامة
    if v_num <> '' and v_num !~ '^[12][0-9]{9}$' then raise exception 'REG_NUMBER_INVALID' using errcode = 'P0001'; end if;
    v_kind := 'id_document'; v_label := 'الهوية';
  else
    if length(v_num) < 4 then raise exception 'REG_NUMBER_INVALID' using errcode = 'P0001'; end if;
    v_kind := 'license'; v_label := 'الرخصة';
  end if;

  -- قفل لصاحب الطلب وحده: نقرتان متتاليتان، او تبويبان، لا ينشئان حسابين
  perform pg_advisory_xact_lock(hashtext('create_org:' || v_actor::text));

  -- رقم رسمي مسجل لغيره: لا ينشا حساب ثان له، وصاحبه يدعى الى الحساب القائم
  if v_num <> '' then
    select o.owner_id into v_other
    from public.org_profiles p join public.organizations o on o.id = p.org_id
    where v_num in (p.cr_number, p.license_number, p.unified_number) and o.owner_id <> v_actor
    limit 1;
    if v_other is not null then raise exception 'REG_NUMBER_TAKEN' using errcode = 'P0001'; end if;
  end if;

  -- الحساب نفسه عنده اصلا: يعاد كما هو بدل بطاقة ثانية فارغة.
  -- ثلاث صور للتكرار: الرقم الرسمي نفسه، او حساب شخصي ثان، او نفس النوع والاسم.
  select o.id into v_same
  from public.organizations o join public.org_profiles p on p.org_id = o.id
  where o.owner_id = v_actor
    and ( (v_num <> '' and v_num in (p.cr_number, p.license_number, p.unified_number))
       or (v_type = 'individual' and p.entity_type = 'individual')
       or (p.entity_type = v_type
           and lower(btrim(regexp_replace(coalesce(o.name, ''), '\s+', ' ', 'g'))) = lower(btrim(regexp_replace(v_show, '\s+', ' ', 'g')))) )
  order by o.created_at asc limit 1;

  if v_same is not null then
    select o.plan_code, o.name, o.name_en, p.entity_type into v_plan, v_show, v_en, v_type
    from public.organizations o join public.org_profiles p on p.org_id = o.id where o.id = v_same;
    select i.id, i.item_number into v_item, v_item_num from public.items i
    where i.org_id = v_same and i.data->>'source' = 'org_registration' order by i.created_at asc limit 1;
    return jsonb_build_object('id', v_same, 'name', v_show, 'name_en', v_en, 'plan_code', v_plan,
                              'entity_type', v_type, 'item_id', v_item, 'item_number', v_item_num, 'existing', true);
  end if;

  insert into public.organizations (name, name_en, owner_id) values (v_show, v_en, v_actor) returning id, plan_code into v_org, v_plan;
  insert into public.org_profiles (org_id, entity_type, legal_name, legal_name_en, cr_number, license_number, unified_number, updated_by)
  values (v_org, v_type, v_show, v_en,
          case when v_kind = 'commercial_register' then v_num end,
          case when v_kind = 'license' then v_num end,
          case when v_kind = 'id_document' and v_num <> '' then v_num end, v_actor)
  on conflict (org_id) do update set entity_type = excluded.entity_type, legal_name = excluded.legal_name,
    legal_name_en = coalesce(excluded.legal_name_en, org_profiles.legal_name_en),
    cr_number = coalesce(excluded.cr_number, org_profiles.cr_number),
    license_number = coalesce(excluded.license_number, org_profiles.license_number),
    unified_number = coalesce(excluded.unified_number, org_profiles.unified_number),
    updated_by = v_actor, updated_at = now();
  select id into v_record from public.records where org_id = v_org and name in ('المستندات','Documents','دستاویزات') order by created_at asc limit 1;
  if v_record is null then
    insert into public.records (org_id, name, columns, created_by) values (v_org, 'المستندات', '[]'::jsonb, v_actor) returning id into v_record;
  end if;
  v_exp := case when p_reg_expiry is null then null else (p_reg_expiry::timestamp + interval '9 hours') at time zone 'Asia/Riyadh' end;
  -- لا ورقة رسمية بلا رقم: الشخص الذي دخل بلا هوية لا يجد صفا فارغا في اوراقه
  if v_num <> '' then
    insert into public.items (org_id, record_id, title, category, due_at, status, client_name, data, created_by)
    values (v_org, v_record, v_label || ' — ' || v_show, v_label, v_exp, 'open', v_show,
            jsonb_build_object('document_kind', v_kind, 'number', v_num, 'issuer',
              case v_kind when 'commercial_register' then 'وزارة التجارة' when 'id_document' then 'وزارة الداخلية' else null end,
              'party_en', v_en, 'source', 'org_registration'), v_actor)
    returning id, item_number into v_item, v_item_num;
  end if;
  update public.org_members set department = 'management' where org_id = v_org and user_id = v_actor;
  return jsonb_build_object('id', v_org, 'name', v_show, 'name_en', v_en, 'plan_code', v_plan, 'entity_type', v_type, 'item_id', v_item, 'item_number', v_item_num);
end $$;

revoke all on function public.create_org_registered(text, text, text, date, text) from public;
grant execute on function public.create_org_registered(text, text, text, date, text) to authenticated;

commit;
