-- المهندس رعد 2026-10-01: «نحتاج واجهة كاملة للعروض المقدمة للموظفين الجدد خلال
-- الاستقطاب، يضاف فيها البدلات كالسكن والتنقل وباقي البدلات ويكون ديناميكي»، ثم «نفذ».
--
-- 1) خدمة «العروض الوظيفية» (offers) في حزمة hr وحدها بعد «الموظفون»، والصلاحية لقسم
--    الموارد البشرية. العرض عنصر كالموظف والاجازة: حقوله في items.data، وتاريخ انتهاء
--    صلاحيته due_at فيدخل التقويم والتذكير. ومفتاحه offer_stage يجعله visibility = 'hr'
--    بمشغل 0173، فلا يراه الا القسم والادارة والمالك والمشرف.
-- 2) سياسات المنشاة الخاصة (org_policies): مفتاح وقيمة لكل حساب، واولها «البدلات
--    المعتادة» التي تملا كل عرض جديد. لا تقرا الا لمن يرى فئتها، ولا تكتب الا بدالة.
-- 3) حارس الاعتماد: لا يصير العرض «معتمدا» الا بيد المالك او المشرف، ويختم المعتمد
--    ووقته من القاعدة لا من المتصفح، ولا يسجل قبول او اعتذار لعرض لم يعتمد.
-- لا تمس حزمة اخرى، ولا يتبدل ترتيب تحت يد مستخدم: لا حساب على حزمة hr حين كتب.

begin;

-- 1) الخدمة والصلاحية والترتيب
insert into public.department_services (department, service) values ('hr', 'offers') on conflict do nothing;
insert into public.pack_services (pack_key, service, sort_order, label) values
  ('hr', 'offers', 3, jsonb_build_object('ar', 'العروض الوظيفية', 'en', 'Job offers', 'fr', 'Offres d''emploi', 'ur', 'ملازمت کی پیشکشیں'))
on conflict (pack_key, service) do update set sort_order = excluded.sort_order, label = excluded.label;
update public.pack_services set sort_order = 4  where pack_key = 'hr' and service = 'leaves';
update public.pack_services set sort_order = 5  where pack_key = 'hr' and service = 'training';
update public.pack_services set sort_order = 6  where pack_key = 'hr' and service = 'team';
update public.pack_services set sort_order = 7  where pack_key = 'hr' and service = 'expenses';
update public.pack_services set sort_order = 8  where pack_key = 'hr' and service = 'documents';
update public.pack_services set sort_order = 9  where pack_key = 'hr' and service = 'processes';
update public.pack_services set sort_order = 10 where pack_key = 'hr' and service = 'meetings';
update public.pack_services set sort_order = 11 where pack_key = 'hr' and service = 'settings';

-- 2) سياسات المنشاة الخاصة
create table if not exists public.org_policies (
  org_id uuid not null references public.organizations(id) on delete cascade,
  key text not null check (key in ('allowances')),
  value jsonb not null default '[]'::jsonb,
  visibility text check (visibility is null or visibility in ('hr')),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (org_id, key)
);
alter table public.org_policies enable row level security;
revoke all on public.org_policies from public, anon, authenticated;
grant select on public.org_policies to authenticated;
drop policy if exists org_policies_read on public.org_policies;
create policy org_policies_read on public.org_policies for select
  using (org_id in (select public.current_org_ids()) and (visibility is null or public.hr_visible_me(org_id, visibility)));

-- كتابة السياسة: لمن يرى فئتها، وبقيم منظمة لا نص حر بلا حد. ولكل بدل نوع ثابت
-- (housing, transport, ...) يقراه المسير، فالسكن يدخل وعاء التامينات ايا كان اسمه المكتوب.
create or replace function public.set_org_policy(p_org uuid, p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_vis text; v_clean jsonb := '[]'::jsonb; r jsonb;
begin
  if p_key is distinct from 'allowances' then return jsonb_build_object('status', 'bad_key'); end if;
  v_vis := 'hr';
  if not public.hr_visible(p_org, v_vis, auth.uid()) then return jsonb_build_object('status', 'not_allowed'); end if;
  if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value) > 30 then
    return jsonb_build_object('status', 'bad_value');
  end if;
  for r in select * from jsonb_array_elements(p_value) loop
    if jsonb_typeof(r) <> 'object' or btrim(coalesce(r ->> 'name', '')) = '' then continue; end if;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object(
      'kind', case when r ->> 'kind' in ('housing', 'transport', 'phone', 'food', 'nature', 'tickets', 'relocation', 'signing')
                   then r ->> 'kind' else 'other' end,
      'name', left(btrim(r ->> 'name'), 60),
      'method', case when r ->> 'method' = 'percent' then 'percent' else 'amount' end,
      'value', greatest(0, least(coalesce(nullif(r ->> 'value', '')::numeric, 0), 10000000)),
      'period', case when r ->> 'period' in ('annual', 'once') then r ->> 'period' else 'monthly' end));
  end loop;
  insert into public.org_policies (org_id, key, value, visibility, updated_by, updated_at)
  values (p_org, p_key, v_clean, v_vis, auth.uid(), now())
  on conflict (org_id, key) do update set value = excluded.value, visibility = excluded.visibility,
                                          updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('status', 'saved', 'count', jsonb_array_length(v_clean));
exception when invalid_text_representation then
  return jsonb_build_object('status', 'bad_value');
end $$;
revoke all on function public.set_org_policy(uuid, text, jsonb) from public, anon;
grant execute on function public.set_org_policy(uuid, text, jsonb) to authenticated;

-- 3) حارس اعتماد العرض. ليس security definer (قاعدة 0135): يميز كتابة المتصفح بدوره هو.
create or replace function public.offer_stage_guard()
returns trigger language plpgsql set search_path to 'public' as $$
declare v_new text := new.data ->> 'offer_stage';
        v_old text := case when tg_op = 'UPDATE' then old.data ->> 'offer_stage' end;
        v_role text; v_name text;
begin
  if v_new is null or v_new is not distinct from v_old then return new; end if;
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if v_new = 'approved' then
    select m.role into v_role from public.org_members m
     where m.org_id = new.org_id and m.user_id = auth.uid() and m.status = 'active';
    if coalesce(v_role, '') not in ('owner', 'admin') then
      raise exception 'OFFER_APPROVAL_OWNER_ADMIN' using errcode = '42501';
    end if;
    select p.full_name into v_name from public.profiles p where p.id = auth.uid();
    new.data := new.data || jsonb_build_object('approved_by', auth.uid(), 'approved_by_name', v_name, 'approved_at', now());
  elsif v_new in ('sent', 'accepted', 'declined') and coalesce(v_old, '') not in ('approved', 'sent', 'accepted', 'declined') then
    raise exception 'OFFER_NOT_APPROVED' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.offer_stage_guard() from public;
drop trigger if exists items_offer_stage_guard on public.items;
create trigger items_offer_stage_guard before insert or update of data on public.items
  for each row execute function public.offer_stage_guard();

commit;

-- تحقق: الخدمة في hr وحدها وترتيبها، والجدول بلا قراءة لغير العضو، والحارس قائم
select (select string_agg(service || ':' || sort_order, ' > ' order by sort_order) from public.pack_services where pack_key = 'hr') as khadamat_hr,
       (select count(*) from public.pack_services where service = 'offers' and pack_key <> 'hr') as huzam_ukhra,
       (select count(*) from pg_trigger where tgname = 'items_offer_stage_guard') as haris;
