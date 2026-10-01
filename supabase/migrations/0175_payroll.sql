-- 0175: مسيّرات الرواتب (أمر المهندس رعد 2026-10-01: «نحتاج نشتغل على الموارد البشرية ونحط
-- مسيرات الرواتب ونسوي نظام يخدم القسم بشكل صحيح»، واختار: المرحلتان معا، والتأمينات
-- تحسب تلقائيا بنسب قابلة للتعديل).
--
-- المسيّر الشهري يولّد من عناصر الموظفين (data.staff_stage) بضغطة، ويمر بثلاث حالات:
-- مسودة ← معتمد ← مدفوع. بعد الاعتماد لا يعدّل سطر، والمالك وحده يعيد فتح ما لم يدفع.
-- الأرقام المشتقة (المستحق، الخصومات، التأمينات، الصافي) يحسبها مشغل في القاعدة من
-- مدخلات السطر والإعداد، فلا يكتبها عميل ولا تختلف بين شاشة وأخرى.
--
-- الرؤية بالشرط الموحد للموارد البشرية: hr_visible_me(org_id, 'hr') (المالك والمشرف
-- وقسما hr و management)، والاعتماد والدفع للمالك والمشرف وحدهما (is_org_admin).
-- لا كتابة مباشرة على الجداول: القراءة بسياسة، والكتابة بدوال security definer.
--
-- مصادر السطر:
--   الموظف: items.data — salary_basic، و allowances [{name, kind?, method, value, period}]
--     (الشهرية وحدها، والنسبة من الأساسي)، والمفاتيح القديمة salary_housing/_transport/_other
--     للتوافق، و nationality و id_number و iban و hire_date و last_working_day.
--   الإجازة بلا راتب: عناصر data.leave_kind='unpaid' و leave_approval='approved' و employee_id.
--   الحضور (0178، وكيل «حل الموضوع»): عنصر شهري بالفئة «سجل حضور» و data.employee_id
--     و data.att_month='YYYY-MM' و data.att_summary {absent, late_minutes} عند قفل الشهر.

-- ═══ الإعداد ═══
create table if not exists public.payroll_settings (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  gosi_saudi_employee_pct    numeric(5,2) not null default 9.75,   -- معاش 9 + ساند 0.75
  gosi_saudi_employer_pct    numeric(5,2) not null default 11.75,  -- معاش 9 + ساند 0.75 + أخطار 2
  gosi_nonsaudi_employee_pct numeric(5,2) not null default 0,
  gosi_nonsaudi_employer_pct numeric(5,2) not null default 2,      -- أخطار مهنية
  gosi_cap                   numeric(12,2) not null default 45000,  -- سقف الوعاء
  gosi_include_housing       boolean not null default true,         -- الوعاء: الأساسي + السكن
  work_hours_per_day         numeric(4,2) not null default 8,
  deduct_late                boolean not null default true,
  employer_mol_id            text,   -- رقم المنشأة في مدد / الموارد البشرية (ملف حماية الأجور)
  employer_iban              text,   -- حساب المنشأة المحوّل منه
  accounts                   jsonb not null default '{}'::jsonb,   -- حسابات قيد الرواتب (0176)
  updated_at                 timestamptz not null default now(),
  updated_by                 uuid
);

-- ═══ المسيّر ═══
create table if not exists public.payroll_runs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  period      date not null check (period = date_trunc('month', period)::date),
  status      text not null default 'draft' check (status in ('draft', 'approved', 'paid')),
  totals      jsonb not null default '{}'::jsonb,
  note        text,
  created_by  uuid, created_at  timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  paid_by     uuid, paid_at     timestamptz,
  unique (org_id, period)
);

create table if not exists public.payroll_lines (
  id             uuid primary key default gen_random_uuid(),
  run_id         uuid not null references public.payroll_runs(id) on delete cascade,
  org_id         uuid not null references public.organizations(id) on delete cascade,
  staff_item_id  uuid references public.items(id) on delete set null,
  employee_name  text not null default '',
  employee_number text, id_number text, nationality text, iban text,
  is_saudi       boolean not null default false,
  -- العقد الشهري
  basic            numeric(12,2) not null default 0,
  housing          numeric(12,2) not null default 0,
  transport        numeric(12,2) not null default 0,
  other_allowances numeric(12,2) not null default 0,
  allowances       jsonb not null default '[]'::jsonb,   -- [{name, amount}] للقسيمة
  -- مدخلات آلية (تعاد عند التحديث)
  days_paid          numeric(5,2) not null default 30,
  unpaid_leave_days  numeric(5,2) not null default 0,
  att_absent_days    numeric(5,2) not null default 0,
  att_late_minutes   numeric(8,2) not null default 0,
  -- مدخلات يدوية (لا يمسها التحديث)
  days_override      numeric(5,2),
  extra_absence_days numeric(5,2) not null default 0,
  overtime           numeric(12,2) not null default 0,
  bonus              numeric(12,2) not null default 0,
  advance_deduction  numeric(12,2) not null default 0,
  other_deduction    numeric(12,2) not null default 0,
  note               text,
  -- مشتقة (المشغل وحده يكتبها)
  earned                 numeric(12,2) not null default 0,
  absence_deduction      numeric(12,2) not null default 0,
  unpaid_leave_deduction numeric(12,2) not null default 0,
  late_deduction         numeric(12,2) not null default 0,
  gosi_base              numeric(12,2) not null default 0,
  gosi_employee          numeric(12,2) not null default 0,
  gosi_employer          numeric(12,2) not null default 0,
  gross                  numeric(12,2) not null default 0,
  total_deductions       numeric(12,2) not null default 0,
  net                    numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (run_id, staff_item_id)
);
create index if not exists payroll_lines_run on public.payroll_lines (run_id);
create index if not exists payroll_lines_staff on public.payroll_lines (staff_item_id);

alter table public.payroll_settings enable row level security;
alter table public.payroll_runs     enable row level security;
alter table public.payroll_lines    enable row level security;

drop policy if exists payroll_settings_read on public.payroll_settings;
create policy payroll_settings_read on public.payroll_settings for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
drop policy if exists payroll_lines_read on public.payroll_lines;
create policy payroll_lines_read on public.payroll_lines for select to authenticated using (public.hr_visible_me(org_id, 'hr'));

revoke all on public.payroll_settings, public.payroll_runs, public.payroll_lines from anon, authenticated;
grant select on public.payroll_settings, public.payroll_runs, public.payroll_lines to authenticated;

-- ═══ الحساب ═══
create or replace function public.payroll_is_saudi(p_nat text)
returns boolean language sql immutable as $$
  select coalesce(p_nat, '') ~* '(سعود|saudi|^\s*ksa\s*$|^\s*sa\s*$)'
$$;

-- الإعداد بقيمه الافتراضية لحساب لم يحفظ إعدادا بعد
create or replace function public.payroll_settings_of(p_org uuid)
returns public.payroll_settings language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s from public.payroll_settings s where s.org_id = p_org),
    row(p_org, 9.75, 11.75, 0, 2, 45000, true, 8, true, null, null, '{}'::jsonb, now(), null)::public.payroll_settings)
$$;

create or replace function public.payroll_line_compute()
returns trigger language plpgsql security definer set search_path = public as $$
declare s public.payroll_settings; v_fixed numeric; v_daily numeric; v_dp numeric; v_emp numeric; v_er numeric;
begin
  -- سطر في مسيّر مقفل لا يعاد حسابه (يصله التحديث حين يحذف عنصر الموظف فيصير staff_item_id فارغا)
  if exists (select 1 from public.payroll_runs r where r.id = new.run_id and r.status <> 'draft') then return new; end if;
  s := public.payroll_settings_of(new.org_id);
  v_fixed := coalesce(new.basic,0) + coalesce(new.housing,0) + coalesce(new.transport,0) + coalesce(new.other_allowances,0);
  v_daily := v_fixed / 30.0;                               -- الشهر ثلاثون يوما في الأجر
  v_dp := least(greatest(coalesce(new.days_override, new.days_paid, 30), 0), 30);
  new.earned := round(v_fixed * v_dp / 30.0, 2);
  new.absence_deduction := round(v_daily * (coalesce(new.att_absent_days,0) + coalesce(new.extra_absence_days,0)), 2);
  new.unpaid_leave_deduction := round(v_daily * coalesce(new.unpaid_leave_days,0), 2);
  new.late_deduction := case when s.deduct_late and s.work_hours_per_day > 0
                             then round(v_daily / (s.work_hours_per_day * 60) * coalesce(new.att_late_minutes,0), 2) else 0 end;
  new.gosi_base := least(coalesce(new.basic,0) + case when s.gosi_include_housing then coalesce(new.housing,0) else 0 end, s.gosi_cap);
  v_emp := case when new.is_saudi then s.gosi_saudi_employee_pct else s.gosi_nonsaudi_employee_pct end;
  v_er  := case when new.is_saudi then s.gosi_saudi_employer_pct else s.gosi_nonsaudi_employer_pct end;
  new.gosi_employee := round(new.gosi_base * v_emp / 100.0, 2);
  new.gosi_employer := round(new.gosi_base * v_er  / 100.0, 2);
  new.gross := new.earned + coalesce(new.overtime,0) + coalesce(new.bonus,0);
  new.total_deductions := new.gosi_employee + new.absence_deduction + new.unpaid_leave_deduction + new.late_deduction
                        + coalesce(new.advance_deduction,0) + coalesce(new.other_deduction,0);
  new.net := new.gross - new.total_deductions;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists payroll_line_compute on public.payroll_lines;
create trigger payroll_line_compute before insert or update on public.payroll_lines
for each row execute function public.payroll_line_compute();

-- المسيّر المعتمد أو المدفوع مقفل: لا يضاف إليه سطر ولا يعدّل ولا يحذف
create or replace function public.payroll_line_lock()
returns trigger language plpgsql set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.payroll_runs where id = coalesce(new.run_id, old.run_id);
  -- حذف عنصر الموظف يفرغ staff_item_id وحده، فيمر ولا يغير رقما
  if tg_op = 'UPDATE' and old.staff_item_id is not null and new.staff_item_id is null
     and (to_jsonb(new) - 'staff_item_id' - 'updated_at') = (to_jsonb(old) - 'staff_item_id' - 'updated_at') then
    return new;
  end if;
  if v_status is not null and v_status <> 'draft' then
    raise exception 'PAYROLL_LOCKED' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists payroll_line_lock on public.payroll_lines;
create trigger payroll_line_lock before insert or update or delete on public.payroll_lines
for each row execute function public.payroll_line_lock();

create or replace function public.payroll_run_totals(p_run uuid)
returns void language sql security definer set search_path = public as $$
  update public.payroll_runs r set totals = (
    select jsonb_build_object(
      'employees', count(*),
      'gross', coalesce(sum(l.gross),0), 'deductions', coalesce(sum(l.total_deductions),0),
      'net', coalesce(sum(l.net),0),
      'gosi_employee', coalesce(sum(l.gosi_employee),0), 'gosi_employer', coalesce(sum(l.gosi_employer),0),
      'negative', count(*) filter (where l.net < 0),
      'no_iban', count(*) filter (where coalesce(btrim(l.iban),'') = ''))
    from public.payroll_lines l where l.run_id = p_run)
  where r.id = p_run
$$;

-- ═══ التوليد ═══
-- ينشئ مسيّر الشهر إن لم يوجد، ويضيف كل موظف مؤهل، ويحدّث المدخلات الآلية للأسطر القائمة
-- (العقد والأيام والإجازة والحضور) دون أن يمس ما أدخله المحاسب يدويا.
create or replace function public.payroll_generate(p_org uuid, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_run uuid; v_status text; v_from date; v_to date; r record;
        v_basic numeric; v_housing numeric; v_transport numeric; v_other numeric; v_allow jsonb;
        v_start date; v_end date; v_days numeric; v_unpaid numeric; v_abs numeric; v_late numeric; a jsonb; v_amt numeric; v_name text; v_kind text;
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  v_from := date_trunc('month', p_period)::date;
  v_to := (v_from + interval '1 month - 1 day')::date;

  select id, status into v_run, v_status from public.payroll_runs where org_id = p_org and period = v_from;
  if v_run is null then
    insert into public.payroll_runs (org_id, period, created_by) values (p_org, v_from, auth.uid()) returning id, status into v_run, v_status;
  end if;
  if v_status <> 'draft' then return v_run; end if;

  for r in
    select i.id, i.title, i.case_number, i.data
      from public.items i
     where i.org_id = p_org and i.data ? 'staff_stage'
       and (i.data->>'staff_stage' in ('probation', 'active', 'notice')
            or (i.data->>'staff_stage' = 'ended' and nullif(i.data->>'last_working_day','') is not null
                and (i.data->>'last_working_day')::date >= v_from))
       and (nullif(i.data->>'hire_date','') is null or (i.data->>'hire_date')::date <= v_to)
  loop
    -- العقد: الأساسي والبدلات الشهرية (المصفوفة، وإلا المفاتيح القديمة)
    v_basic := coalesce(nullif(r.data->>'salary_basic','')::numeric, 0);
    v_housing := 0; v_transport := 0; v_other := 0; v_allow := '[]'::jsonb;
    if jsonb_typeof(r.data->'allowances') = 'array' then
      for a in select * from jsonb_array_elements(r.data->'allowances') loop
        if coalesce(nullif(a->>'period',''), 'monthly') <> 'monthly' then continue; end if;
        v_amt := case when a->>'method' = 'percent'
                      then round(v_basic * coalesce(nullif(a->>'value','')::numeric,0) / 100.0, 2)
                      else coalesce(nullif(a->>'value','')::numeric, 0) end;
        if v_amt = 0 then continue; end if;
        v_name := coalesce(a->>'name', '');
        v_kind := coalesce(nullif(a->>'kind',''),
                    case when v_name ~* '(سكن|إسكان|اسكان|housing|accommodation|logement)' then 'housing'
                         when v_name ~* '(نقل|تنقل|مواصلات|transport)' then 'transport' else 'other' end);
        if v_kind = 'housing' then v_housing := v_housing + v_amt;
        elsif v_kind = 'transport' then v_transport := v_transport + v_amt;
        else v_other := v_other + v_amt; end if;
        v_allow := v_allow || jsonb_build_array(jsonb_build_object('name', v_name, 'kind', v_kind, 'amount', v_amt));
      end loop;
    else
      v_housing := coalesce(nullif(r.data->>'salary_housing','')::numeric, 0);
      v_transport := coalesce(nullif(r.data->>'salary_transport','')::numeric, 0);
      v_other := coalesce(nullif(r.data->>'salary_other','')::numeric, 0);
    end if;

    -- أيام الاستحقاق: من التعيين أو آخر يوم عمل إن وقعا داخل الشهر
    v_start := greatest(v_from, coalesce(nullif(r.data->>'hire_date','')::date, v_from));
    v_end := least(v_to, coalesce(nullif(r.data->>'last_working_day','')::date, v_to));
    v_days := case when v_start = v_from and v_end = v_to then 30 else greatest(0, least(30, v_end - v_start + 1)) end;

    -- الإجازة بلا راتب المعتمدة: ما يقع منها داخل الشهر
    select coalesce(sum(greatest(0, least(coalesce(nullif(l.data->>'leave_to','')::date, nullif(l.data->>'leave_from','')::date), v_to)
                                    - greatest(nullif(l.data->>'leave_from','')::date, v_from) + 1)), 0)
      into v_unpaid
      from public.items l
     where l.org_id = p_org and l.data->>'employee_id' = r.id::text
       and l.data->>'leave_kind' = 'unpaid' and l.data->>'leave_approval' = 'approved'
       and nullif(l.data->>'leave_from','')::date <= v_to
       and coalesce(nullif(l.data->>'leave_to','')::date, nullif(l.data->>'leave_from','')::date) >= v_from;

    -- الحضور المقفل للشهر (0178)
    select coalesce(nullif(t.data->'att_summary'->>'absent','')::numeric, 0),
           coalesce(nullif(t.data->'att_summary'->>'late_minutes','')::numeric, 0)
      into v_abs, v_late
      from public.items t
     where t.org_id = p_org and t.data->>'employee_id' = r.id::text
       and t.data->>'att_month' = to_char(v_from, 'YYYY-MM') and t.data ? 'att_summary'
     limit 1;

    insert into public.payroll_lines as pl (run_id, org_id, staff_item_id, employee_name, employee_number, id_number,
           nationality, iban, is_saudi, basic, housing, transport, other_allowances, allowances,
           days_paid, unpaid_leave_days, att_absent_days, att_late_minutes)
    values (v_run, p_org, r.id, coalesce(r.title, ''),
            coalesce(nullif(r.case_number,''), r.data->>'employee_number'), r.data->>'id_number',
            r.data->>'nationality', nullif(btrim(coalesce(r.data->>'iban','')), ''), public.payroll_is_saudi(r.data->>'nationality'),
            v_basic, v_housing, v_transport, v_other, v_allow,
            v_days, coalesce(v_unpaid, 0), coalesce(v_abs, 0), coalesce(v_late, 0))
    on conflict (run_id, staff_item_id) do update set
      employee_name = excluded.employee_name, employee_number = excluded.employee_number,
      id_number = excluded.id_number, nationality = excluded.nationality, iban = excluded.iban,
      basic = excluded.basic, housing = excluded.housing, transport = excluded.transport,
      other_allowances = excluded.other_allowances, allowances = excluded.allowances,
      days_paid = excluded.days_paid, unpaid_leave_days = excluded.unpaid_leave_days,
      att_absent_days = excluded.att_absent_days, att_late_minutes = excluded.att_late_minutes;
    -- is_saudi لا يعاد بعد الإدخال الأول: قد يكون المحاسب صححه يدويا
  end loop;

  perform public.payroll_run_totals(v_run);
  return v_run;
end $$;

-- ═══ التعديل اليدوي ═══
create or replace function public.payroll_line_update(p_line uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_run uuid; n numeric;
  num_keys text[] := array['overtime','bonus','advance_deduction','other_deduction','extra_absence_days','days_override'];
  k text;
begin
  select org_id, run_id into v_org, v_run from public.payroll_lines where id = p_line;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.hr_visible_me(v_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  foreach k in array num_keys loop
    if p_patch ? k then
      if p_patch->>k is null or p_patch->>k = '' then
        if k = 'days_override' then update public.payroll_lines set days_override = null where id = p_line;
        else execute format('update public.payroll_lines set %I = 0 where id = $1', k) using p_line; end if;
      else
        n := (p_patch->>k)::numeric;
        if n < 0 or (k in ('extra_absence_days','days_override') and n > 31) then
          return jsonb_build_object('status', 'bad_value', 'field', k);
        end if;
        execute format('update public.payroll_lines set %I = $2 where id = $1', k) using p_line, n;
      end if;
    end if;
  end loop;
  if p_patch ? 'is_saudi' then update public.payroll_lines set is_saudi = coalesce((p_patch->>'is_saudi')::boolean, false) where id = p_line; end if;
  if p_patch ? 'note' then update public.payroll_lines set note = left(nullif(btrim(p_patch->>'note'), ''), 500) where id = p_line; end if;
  perform public.payroll_run_totals(v_run);
  return jsonb_build_object('status', 'ok');
exception when invalid_text_representation then
  return jsonb_build_object('status', 'bad_value');
end $$;

create or replace function public.payroll_line_remove(p_line uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_run uuid;
begin
  select org_id, run_id into v_org, v_run from public.payroll_lines where id = p_line;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.hr_visible_me(v_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  delete from public.payroll_lines where id = p_line;
  perform public.payroll_run_totals(v_run);
  return jsonb_build_object('status', 'ok');
end $$;

-- ═══ الحالات ═══
create or replace function public.payroll_run_set_status(p_run uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_cur text; v_owner boolean;
begin
  select org_id, status into v_org, v_cur from public.payroll_runs where id = p_run;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.is_org_admin(v_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  select exists (select 1 from public.org_members m where m.org_id = v_org and m.user_id = auth.uid()
                  and m.status = 'active' and m.role = 'owner') into v_owner;
  if p_status = 'approved' and v_cur = 'draft' then
    if not exists (select 1 from public.payroll_lines where run_id = p_run) then
      return jsonb_build_object('status', 'empty');
    end if;
    perform public.payroll_run_totals(p_run);
    update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run;
  elsif p_status = 'paid' and v_cur = 'approved' then
    update public.payroll_runs set status = 'paid', paid_by = auth.uid(), paid_at = now() where id = p_run;
  elsif p_status = 'draft' and v_cur = 'approved' then
    -- إعادة الفتح للمالك وحده، وما دفع لا يفتح
    if not v_owner then raise exception 'OWNER_ONLY' using errcode = '42501'; end if;
    update public.payroll_runs set status = 'draft', approved_by = null, approved_at = null where id = p_run;
  else
    return jsonb_build_object('status', 'bad_transition', 'from', v_cur, 'to', p_status);
  end if;
  return jsonb_build_object('status', 'ok');
end $$;

create or replace function public.payroll_run_delete(p_run uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_cur text;
begin
  select org_id, status into v_org, v_cur from public.payroll_runs where id = p_run;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.hr_visible_me(v_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if v_cur <> 'draft' then return jsonb_build_object('status', 'locked'); end if;
  delete from public.payroll_lines where run_id = p_run;
  delete from public.payroll_runs where id = p_run;
  return jsonb_build_object('status', 'ok');
end $$;

-- ═══ الإعداد: قراءة وحفظ ═══
create or replace function public.payroll_settings_get(p_org uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  return to_jsonb(public.payroll_settings_of(p_org)) - 'org_id' - 'updated_by'
         || jsonb_build_object('can_approve', public.is_org_admin(p_org));
end $$;

create or replace function public.payroll_settings_save(p_org uuid, p_settings jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.payroll_settings;
begin
  if not public.is_org_admin(p_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  s := public.payroll_settings_of(p_org);
  if p_settings ? 'gosi_saudi_employee_pct'    then s.gosi_saudi_employee_pct    := (p_settings->>'gosi_saudi_employee_pct')::numeric; end if;
  if p_settings ? 'gosi_saudi_employer_pct'    then s.gosi_saudi_employer_pct    := (p_settings->>'gosi_saudi_employer_pct')::numeric; end if;
  if p_settings ? 'gosi_nonsaudi_employee_pct' then s.gosi_nonsaudi_employee_pct := (p_settings->>'gosi_nonsaudi_employee_pct')::numeric; end if;
  if p_settings ? 'gosi_nonsaudi_employer_pct' then s.gosi_nonsaudi_employer_pct := (p_settings->>'gosi_nonsaudi_employer_pct')::numeric; end if;
  if p_settings ? 'gosi_cap'                   then s.gosi_cap                   := (p_settings->>'gosi_cap')::numeric; end if;
  if p_settings ? 'gosi_include_housing'       then s.gosi_include_housing       := (p_settings->>'gosi_include_housing')::boolean; end if;
  if p_settings ? 'work_hours_per_day'         then s.work_hours_per_day         := (p_settings->>'work_hours_per_day')::numeric; end if;
  if p_settings ? 'deduct_late'                then s.deduct_late                := (p_settings->>'deduct_late')::boolean; end if;
  if p_settings ? 'employer_mol_id'            then s.employer_mol_id            := nullif(btrim(p_settings->>'employer_mol_id'), ''); end if;
  if p_settings ? 'employer_iban'              then s.employer_iban              := nullif(upper(replace(p_settings->>'employer_iban', ' ', '')), ''); end if;
  if p_settings ? 'accounts' and jsonb_typeof(p_settings->'accounts') = 'object' then s.accounts := p_settings->'accounts'; end if;
  if s.gosi_saudi_employee_pct not between 0 and 30 or s.gosi_saudi_employer_pct not between 0 and 30
     or s.gosi_nonsaudi_employee_pct not between 0 and 30 or s.gosi_nonsaudi_employer_pct not between 0 and 30
     or s.gosi_cap <= 0 or s.work_hours_per_day not between 1 and 24 then
    return jsonb_build_object('status', 'bad_value');
  end if;
  insert into public.payroll_settings values (p_org, s.gosi_saudi_employee_pct, s.gosi_saudi_employer_pct,
    s.gosi_nonsaudi_employee_pct, s.gosi_nonsaudi_employer_pct, s.gosi_cap, s.gosi_include_housing,
    s.work_hours_per_day, s.deduct_late, s.employer_mol_id, s.employer_iban, s.accounts, now(), auth.uid())
  on conflict (org_id) do update set
    gosi_saudi_employee_pct = excluded.gosi_saudi_employee_pct, gosi_saudi_employer_pct = excluded.gosi_saudi_employer_pct,
    gosi_nonsaudi_employee_pct = excluded.gosi_nonsaudi_employee_pct, gosi_nonsaudi_employer_pct = excluded.gosi_nonsaudi_employer_pct,
    gosi_cap = excluded.gosi_cap, gosi_include_housing = excluded.gosi_include_housing,
    work_hours_per_day = excluded.work_hours_per_day, deduct_late = excluded.deduct_late,
    employer_mol_id = excluded.employer_mol_id, employer_iban = excluded.employer_iban, accounts = excluded.accounts,
    updated_at = now(), updated_by = auth.uid();
  -- المسودات القائمة تعاد بالنسب الجديدة؛ المعتمد والمدفوع لا يمس
  update public.payroll_lines l set updated_at = now()
    from public.payroll_runs r where r.id = l.run_id and r.org_id = p_org and r.status = 'draft';
  perform public.payroll_run_totals(r.id) from public.payroll_runs r where r.org_id = p_org and r.status = 'draft';
  return jsonb_build_object('status', 'ok');
exception when invalid_text_representation then
  return jsonb_build_object('status', 'bad_value');
end $$;

-- ═══ للمخالصة (0177، وكيل «حل الموضوع»): صافي آخر مسير معتمد أو مدفوع للموظف ═══
create or replace function public.payroll_last_net(p_org uuid, p_staff uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  select jsonb_build_object('period', r.period, 'net', l.net, 'status', r.status) into v
    from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
   where r.org_id = p_org and l.staff_item_id = p_staff and r.status in ('approved', 'paid')
   order by r.period desc limit 1;
  return v;
end $$;

-- ═══ الصلاحيات ═══
revoke all on function public.payroll_settings_of(uuid), public.payroll_line_compute(), public.payroll_line_lock(),
  public.payroll_run_totals(uuid) from public, anon, authenticated;
revoke all on function public.payroll_generate(uuid, date), public.payroll_line_update(uuid, jsonb),
  public.payroll_line_remove(uuid), public.payroll_run_set_status(uuid, text), public.payroll_run_delete(uuid),
  public.payroll_settings_get(uuid), public.payroll_settings_save(uuid, jsonb), public.payroll_last_net(uuid, uuid) from public, anon;
grant execute on function public.payroll_generate(uuid, date), public.payroll_line_update(uuid, jsonb),
  public.payroll_line_remove(uuid), public.payroll_run_set_status(uuid, text), public.payroll_run_delete(uuid),
  public.payroll_settings_get(uuid), public.payroll_settings_save(uuid, jsonb), public.payroll_last_net(uuid, uuid) to authenticated;

-- ═══ الخدمة في حزمة الموارد البشرية ═══
do $$
begin
  if not exists (select 1 from public.pack_services where pack_key = 'hr' and service = 'payroll') then
    update public.pack_services set sort_order = sort_order + 1 where pack_key = 'hr' and sort_order >= 3;
    insert into public.pack_services (pack_key, service, sort_order, label)
    values ('hr', 'payroll', 3, jsonb_build_object('ar', 'مسيرات الرواتب', 'en', 'Payroll', 'fr', 'Paie', 'ur', 'پے رول'));
  end if;
end $$;
insert into public.department_services (department, service)
select d, 'payroll' from unnest(array['hr', 'management']) d
where not exists (select 1 from public.department_services x where x.department = d and x.service = 'payroll');
