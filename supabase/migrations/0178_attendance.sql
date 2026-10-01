-- 0178: الحضور والانصراف (أمر المهندس رعد 2026-10-01: «ابدأ بالحضور والانصراف»، وقبله:
-- «حضور وانصراف ويكون مربوط مع الاجهزة او التطبيق، كلو على قسم الموارد البشرية»).
--
-- ثلاثة مصادر للبصمة، كلها في جدول واحد attendance_punches:
--   الجهاز: أجهزة البصمة ZKTeco ببروتوكول ADMS (PUSH) ترسل الى mrzahi.com/iclock، والخادم
--     يمرر سطور ATTLOG الى attendance_device_ingest بسره. الجهاز يعرف برقمه التسلسلي (SN)
--     ولا يقبل منه شيء قبل ان يسجله مالك الحساب او مشرفه. والموظف في الجهاز برقمه (PIN):
--     data.device_pin على عنصر الموظف، والا الرقم الوظيفي.
--   التطبيق: الموظف المسجل في المنصة يضغط «حضور/انصراف» من صفحته، ومعه موقعه ان طلب
--     الحساب نطاقا جغرافيا. يعرف عنصر الموظف ببريده (data.email = بريد حسابه).
--   يدوي: الموارد البشرية تضيف او تصحح بصمة بسبب يسجل.
--
-- اليوم يحسب من البصمات بإعدادات الحساب (بداية الدوام، السماح، العطلة الاسبوعية،
-- المنطقة الزمنية)، والاجازة المعتمدة يوم «اجازة» لا غياب. وقفل الشهر يكتب ملخص كل موظف
-- في attendance_months، ومنه وحده يقرأ مسيّر الرواتب الغياب والتأخر (يعاد تعريف
-- payroll_generate هنا بهذا المصدر بدل عنصر «سجل حضور» الذي لم يبن).
--
-- الرؤية بالشرط الموحد للموارد البشرية hr_visible_me(org_id,'hr')؛ والموظف يرى بصماته هو
-- وحده عبر attendance_my_status. والاجهزة والاعداد للمالك والمشرف (is_org_admin).

create table if not exists public.attendance_settings (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  work_start time not null default '08:00',
  work_end   time not null default '17:00',
  grace_minutes integer not null default 15,
  weekend_days  integer[] not null default '{5,6}',      -- الجمعة والسبت (dow: الاحد 0)
  timezone text not null default 'Asia/Riyadh',
  app_enabled boolean not null default true,
  geofence_lat numeric(9,6), geofence_lng numeric(9,6),
  geofence_radius_m integer,                               -- فارغ = بلا نطاق
  updated_at timestamptz not null default now(), updated_by uuid,
  -- بداية التتبع: ما قبلها لا يعد غيابا. فارغ = يوم اول بصمة في الحساب، فمن بدأ الحضور
  -- منتصف الشهر لا يخصم عليه ما قبل ذلك
  tracking_since date
);
alter table public.attendance_settings add column if not exists tracking_since date;

create table if not exists public.attendance_devices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  serial text not null unique,
  name text not null default '',
  status text not null default 'active' check (status in ('active', 'disabled')),
  last_seen_at timestamptz, last_ip text, punches_total integer not null default 0,
  created_by uuid, created_at timestamptz not null default now()
);

-- رقم تسلسلي اتصل ولم يسجله احد: يرى صاحب الحساب «اتصل قبل دقائق» حين يكتب الرقم نفسه
create table if not exists public.attendance_unknown_devices (
  serial text primary key, first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(), last_ip text, hits integer not null default 1
);

create table if not exists public.attendance_punches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  staff_item_id uuid references public.items(id) on delete cascade,
  pin text,
  at timestamptz not null,
  direction text not null default 'auto' check (direction in ('in', 'out', 'auto')),
  source text not null check (source in ('device', 'app', 'manual')),
  device_id uuid references public.attendance_devices(id) on delete set null,
  lat numeric(9,6), lng numeric(9,6), accuracy_m integer, distance_m integer,
  note text, created_by uuid, created_at timestamptz not null default now()
);
create index if not exists attendance_punches_day on public.attendance_punches (org_id, at);
create index if not exists attendance_punches_staff on public.attendance_punches (staff_item_id, at);
-- الجهاز يعيد ارسال ما لم يصله رده: لا تكرار للبصمة نفسها من الجهاز نفسه
create unique index if not exists attendance_punches_device_once on public.attendance_punches (device_id, pin, at) where source = 'device';

create table if not exists public.attendance_months (
  org_id uuid not null references public.organizations(id) on delete cascade,
  staff_item_id uuid not null references public.items(id) on delete cascade,
  month date not null check (month = date_trunc('month', month)::date),
  present integer not null default 0, absent integer not null default 0, leave_days integer not null default 0,
  late_minutes integer not null default 0,
  closed_at timestamptz not null default now(), closed_by uuid,
  primary key (org_id, staff_item_id, month)
);

alter table public.attendance_settings enable row level security;
alter table public.attendance_devices enable row level security;
alter table public.attendance_unknown_devices enable row level security;
alter table public.attendance_punches enable row level security;
alter table public.attendance_months enable row level security;
drop policy if exists att_settings_read on public.attendance_settings;
create policy att_settings_read on public.attendance_settings for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
drop policy if exists att_devices_read on public.attendance_devices;
create policy att_devices_read on public.attendance_devices for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
drop policy if exists att_punches_read on public.attendance_punches;
create policy att_punches_read on public.attendance_punches for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
drop policy if exists att_months_read on public.attendance_months;
create policy att_months_read on public.attendance_months for select to authenticated using (public.hr_visible_me(org_id, 'hr'));
revoke all on public.attendance_settings, public.attendance_devices, public.attendance_unknown_devices,
  public.attendance_punches, public.attendance_months from anon, authenticated;
grant select on public.attendance_settings, public.attendance_devices, public.attendance_punches, public.attendance_months to authenticated;

-- ═══ مساعدات ═══
create or replace function public.attendance_settings_of(p_org uuid)
returns public.attendance_settings language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s from public.attendance_settings s where s.org_id = p_org),
    row(p_org, '08:00'::time, '17:00'::time, 15, '{5,6}'::integer[], 'Asia/Riyadh', true, null, null, null, now(), null, null)::public.attendance_settings)
$$;

-- الموظفون العاملون: مرحلة قائمة، او منته وآخر يوم عمله داخل المدى
create or replace function public.attendance_staff(p_org uuid, p_from date, p_to date)
returns table (id uuid, name text, number text, pin text, email text, hire date, last_day date)
language sql stable security definer set search_path = public as $$
  select i.id, coalesce(i.title, ''), coalesce(nullif(i.case_number, ''), i.data->>'employee_number'),
         coalesce(nullif(btrim(i.data->>'device_pin'), ''), nullif(i.case_number, ''), i.data->>'employee_number'),
         lower(nullif(btrim(i.data->>'email'), '')),
         nullif(i.data->>'hire_date', '')::date, nullif(i.data->>'last_working_day', '')::date
    from public.items i
   where i.org_id = p_org and i.data ? 'staff_stage'
     and (i.data->>'staff_stage' in ('probation', 'active', 'notice')
          or (i.data->>'staff_stage' = 'ended' and nullif(i.data->>'last_working_day', '')::date >= p_from))
     and (nullif(i.data->>'hire_date', '') is null or (i.data->>'hire_date')::date <= p_to)
$$;

-- المسافة بالامتار بين نقطتين (هافرساين)
create or replace function public.attendance_distance_m(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns integer language sql immutable as $$
  select round(2 * 6371000 * asin(sqrt(
    power(sin(radians((lat2 - lat1) / 2)), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians((lng2 - lng1) / 2)), 2))))::integer
$$;

-- ═══ اليوم: سطر لكل موظف ولكل يوم ═══
create or replace function public.attendance_days(p_org uuid, p_from date, p_to date)
returns table (staff_item_id uuid, name text, number text, day date, status text,
               first_in timestamptz, last_out timestamptz, punches integer, late_minutes integer, worked_minutes integer)
language plpgsql stable security definer set search_path = public as $$
declare s public.attendance_settings; v_today date; v_since date;
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if p_to < p_from or p_to - p_from > 62 then raise exception 'BAD_RANGE' using errcode = 'P0001'; end if;
  s := public.attendance_settings_of(p_org);
  v_today := (now() at time zone s.timezone)::date;
  v_since := coalesce(s.tracking_since,
    (select min((p.at at time zone s.timezone)::date) from public.attendance_punches p where p.org_id = p_org),
    v_today + 1);
  return query
  with st as (select * from public.attendance_staff(p_org, p_from, p_to)),
  days as (select g::date as d from generate_series(p_from, least(p_to, v_today), interval '1 day') g),
  grid as (
    select st.id, st.name, st.number, days.d from st cross join days
     where (st.hire is null or days.d >= st.hire) and (st.last_day is null or days.d <= st.last_day)),
  pun as (
    select p.staff_item_id sid, (p.at at time zone s.timezone)::date d, min(p.at) fi, max(p.at) la, count(*)::int n
      from public.attendance_punches p
     where p.org_id = p_org and p.staff_item_id is not null
       and p.at >= (p_from::timestamp at time zone s.timezone) and p.at < ((p_to + 1)::timestamp at time zone s.timezone)
     group by 1, 2),
  lv as (
    select g.id sid, g.d from grid g
     where exists (select 1 from public.items l
                    where l.org_id = p_org and l.data->>'employee_id' = g.id::text
                      and l.data->>'leave_approval' = 'approved'
                      and nullif(l.data->>'leave_from', '')::date <= g.d
                      and coalesce(nullif(l.data->>'leave_to', '')::date, nullif(l.data->>'leave_from', '')::date) >= g.d))
  select g.id, g.name, g.number, g.d,
         case when pun.n is not null then 'present'
              when lv.sid is not null then 'leave'
              when extract(dow from g.d)::int = any (s.weekend_days) then 'weekend'
              when g.d < v_since then 'untracked'
              when g.d = v_today then 'pending'
              else 'absent' end,
         pun.fi, case when pun.n > 1 then pun.la end, coalesce(pun.n, 0),
         case when pun.n is null then 0 else
           greatest(0, (extract(epoch from ((pun.fi at time zone s.timezone)::time - s.work_start)) / 60)::int) end,
         case when pun.n > 1 then (extract(epoch from (pun.la - pun.fi)) / 60)::int else 0 end
    from grid g
    left join pun on pun.sid = g.id and pun.d = g.d
    left join lv on lv.sid = g.id and lv.d = g.d
   order by g.name, g.d;
end $$;

-- التأخر المحتسب: ما زاد على السماح يحسب كله من بداية الدوام، وما دونه صفر
create or replace function public.attendance_late_counted(p_late integer, p_grace integer)
returns integer language sql immutable as $$ select case when p_late > p_grace then p_late else 0 end $$;

-- ═══ قفل الشهر ═══
create or replace function public.attendance_close_month(p_org uuid, p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_from date; v_to date; s public.attendance_settings; n integer;
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  v_from := date_trunc('month', p_month)::date;
  v_to := (v_from + interval '1 month - 1 day')::date;
  s := public.attendance_settings_of(p_org);
  if v_to >= (now() at time zone s.timezone)::date then return jsonb_build_object('status', 'not_ended'); end if;
  if exists (select 1 from public.payroll_runs r where r.org_id = p_org and r.period = v_from and r.status <> 'draft') then
    return jsonb_build_object('status', 'payroll_locked');
  end if;
  delete from public.attendance_months where org_id = p_org and month = v_from;
  insert into public.attendance_months (org_id, staff_item_id, month, present, absent, leave_days, late_minutes, closed_by)
  select p_org, d.staff_item_id, v_from,
         count(*) filter (where d.status = 'present'), count(*) filter (where d.status = 'absent'),
         count(*) filter (where d.status = 'leave'),
         coalesce(sum(public.attendance_late_counted(d.late_minutes, s.grace_minutes)) filter (where d.status = 'present'), 0),
         auth.uid()
    from public.attendance_days(p_org, v_from, v_to) d
   group by d.staff_item_id;
  get diagnostics n = row_count;
  return jsonb_build_object('status', 'ok', 'employees', n);
end $$;

create or replace function public.attendance_reopen_month(p_org uuid, p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if exists (select 1 from public.payroll_runs r where r.org_id = p_org and r.period = date_trunc('month', p_month)::date and r.status <> 'draft') then
    return jsonb_build_object('status', 'payroll_locked');
  end if;
  delete from public.attendance_months where org_id = p_org and month = date_trunc('month', p_month)::date;
  return jsonb_build_object('status', 'ok');
end $$;

-- ═══ التطبيق: الموظف يسجل حضوره ═══
create or replace function public.attendance_my_staff(p_org uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select i.id from public.items i
   where i.org_id = p_org and i.data ? 'staff_stage' and i.data->>'staff_stage' <> 'ended'
     and lower(btrim(i.data->>'email')) = lower((select email from auth.users where id = auth.uid()))
     and exists (select 1 from public.org_members m where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active')
   order by i.created_at limit 1
$$;

create or replace function public.attendance_punch_me(p_org uuid, p_lat numeric default null, p_lng numeric default null, p_accuracy integer default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_staff uuid; s public.attendance_settings; v_dist integer; v_last timestamptz; v_dir text; v_today_n integer; v_at timestamptz := now();
begin
  v_staff := public.attendance_my_staff(p_org);
  if v_staff is null then return jsonb_build_object('status', 'not_staff'); end if;
  s := public.attendance_settings_of(p_org);
  if not s.app_enabled then return jsonb_build_object('status', 'app_disabled'); end if;
  if s.geofence_radius_m is not null and s.geofence_lat is not null then
    if p_lat is null or p_lng is null then return jsonb_build_object('status', 'need_location'); end if;
    v_dist := public.attendance_distance_m(p_lat, p_lng, s.geofence_lat, s.geofence_lng);
    if v_dist > s.geofence_radius_m + least(coalesce(p_accuracy, 0), 100) then
      return jsonb_build_object('status', 'outside', 'distance_m', v_dist, 'radius_m', s.geofence_radius_m);
    end if;
  end if;
  select max(at) into v_last from public.attendance_punches where staff_item_id = v_staff;
  if v_last is not null and v_last > v_at - interval '1 minute' then return jsonb_build_object('status', 'too_soon'); end if;
  select count(*) into v_today_n from public.attendance_punches
   where staff_item_id = v_staff and (at at time zone s.timezone)::date = (v_at at time zone s.timezone)::date;
  v_dir := case when v_today_n % 2 = 0 then 'in' else 'out' end;
  insert into public.attendance_punches (org_id, staff_item_id, at, direction, source, lat, lng, accuracy_m, distance_m, created_by)
  values (p_org, v_staff, v_at, v_dir, 'app', p_lat, p_lng, p_accuracy, v_dist, auth.uid());
  return jsonb_build_object('status', 'ok', 'direction', v_dir, 'at', v_at, 'distance_m', v_dist);
end $$;

create or replace function public.attendance_my_status(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_staff uuid; s public.attendance_settings; v jsonb;
begin
  v_staff := public.attendance_my_staff(p_org);
  s := public.attendance_settings_of(p_org);
  if v_staff is null then return jsonb_build_object('staff', false, 'hr', public.hr_visible_me(p_org, 'hr')); end if;
  select jsonb_build_object('staff', true, 'hr', public.hr_visible_me(p_org, 'hr'),
           'name', (select title from public.items where id = v_staff),
           'app_enabled', s.app_enabled, 'geofence', s.geofence_radius_m is not null and s.geofence_lat is not null,
           'work_start', s.work_start, 'work_end', s.work_end,
           'today', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'direction', direction, 'source', source) order by at)
                                from public.attendance_punches
                               where staff_item_id = v_staff and (at at time zone s.timezone)::date = (now() at time zone s.timezone)::date), '[]'::jsonb))
    into v;
  return v;
end $$;

-- ═══ يدوي: الموارد البشرية ═══
create or replace function public.attendance_manual_punch(p_org uuid, p_staff uuid, p_at timestamptz, p_direction text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if not exists (select 1 from public.items where id = p_staff and org_id = p_org and data ? 'staff_stage') then
    return jsonb_build_object('status', 'not_found');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('status', 'need_note'); end if;
  if p_at > now() + interval '5 minutes' then return jsonb_build_object('status', 'future'); end if;
  insert into public.attendance_punches (org_id, staff_item_id, at, direction, source, note, created_by)
  values (p_org, p_staff, p_at, case when p_direction in ('in', 'out') then p_direction else 'auto' end, 'manual', left(btrim(p_note), 300), auth.uid());
  return jsonb_build_object('status', 'ok');
end $$;

create or replace function public.attendance_punch_delete(p_punch uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_src text;
begin
  select org_id, source into v_org, v_src from public.attendance_punches where id = p_punch;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.is_org_admin(v_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  delete from public.attendance_punches where id = p_punch;
  return jsonb_build_object('status', 'ok');
end $$;

-- ═══ الاعداد والاجهزة ═══
create or replace function public.attendance_settings_get(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  return to_jsonb(public.attendance_settings_of(p_org)) - 'org_id' - 'updated_by'
    || jsonb_build_object('can_admin', public.is_org_admin(p_org),
         'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'serial', d.serial, 'name', d.name, 'status', d.status,
                              'last_seen_at', d.last_seen_at, 'punches_total', d.punches_total) order by d.created_at)
                              from public.attendance_devices d where d.org_id = p_org), '[]'::jsonb));
end $$;

create or replace function public.attendance_settings_save(p_org uuid, p_settings jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.attendance_settings;
begin
  if not public.is_org_admin(p_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  s := public.attendance_settings_of(p_org);
  if p_settings ? 'work_start' then s.work_start := (p_settings->>'work_start')::time; end if;
  if p_settings ? 'work_end' then s.work_end := (p_settings->>'work_end')::time; end if;
  if p_settings ? 'grace_minutes' then s.grace_minutes := (p_settings->>'grace_minutes')::integer; end if;
  if p_settings ? 'weekend_days' and jsonb_typeof(p_settings->'weekend_days') = 'array' then
    s.weekend_days := array(select distinct (x::text)::integer from jsonb_array_elements_text(p_settings->'weekend_days') x where x ~ '^[0-6]$');
  end if;
  if p_settings ? 'app_enabled' then s.app_enabled := (p_settings->>'app_enabled')::boolean; end if;
  if p_settings ? 'geofence_lat' then s.geofence_lat := nullif(p_settings->>'geofence_lat', '')::numeric; end if;
  if p_settings ? 'geofence_lng' then s.geofence_lng := nullif(p_settings->>'geofence_lng', '')::numeric; end if;
  if p_settings ? 'geofence_radius_m' then s.geofence_radius_m := nullif(p_settings->>'geofence_radius_m', '')::integer; end if;
  if p_settings ? 'tracking_since' then s.tracking_since := nullif(p_settings->>'tracking_since', '')::date; end if;
  if s.grace_minutes not between 0 and 240 or s.work_end <= s.work_start
     or (s.geofence_radius_m is not null and s.geofence_radius_m not between 20 and 20000)
     or (s.geofence_lat is not null and s.geofence_lat not between -90 and 90)
     or (s.geofence_lng is not null and s.geofence_lng not between -180 and 180) then
    return jsonb_build_object('status', 'bad_value');
  end if;
  insert into public.attendance_settings values (p_org, s.work_start, s.work_end, s.grace_minutes, s.weekend_days, s.timezone,
    s.app_enabled, s.geofence_lat, s.geofence_lng, s.geofence_radius_m, now(), auth.uid(), s.tracking_since)
  on conflict (org_id) do update set work_start = excluded.work_start, work_end = excluded.work_end,
    tracking_since = excluded.tracking_since,
    grace_minutes = excluded.grace_minutes, weekend_days = excluded.weekend_days, app_enabled = excluded.app_enabled,
    geofence_lat = excluded.geofence_lat, geofence_lng = excluded.geofence_lng, geofence_radius_m = excluded.geofence_radius_m,
    updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('status', 'ok');
exception when invalid_text_representation or invalid_datetime_format then
  return jsonb_build_object('status', 'bad_value');
end $$;

create or replace function public.attendance_device_register(p_org uuid, p_serial text, p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sn text := upper(btrim(coalesce(p_serial, ''))); v_seen timestamptz;
begin
  if not public.is_org_admin(p_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if v_sn !~ '^[A-Z0-9]{6,32}$' then return jsonb_build_object('status', 'bad_serial'); end if;
  if exists (select 1 from public.attendance_devices where serial = v_sn) then return jsonb_build_object('status', 'taken'); end if;
  select last_seen_at into v_seen from public.attendance_unknown_devices where serial = v_sn;
  insert into public.attendance_devices (org_id, serial, name, created_by, last_seen_at)
  values (p_org, v_sn, left(btrim(coalesce(p_name, '')), 80), auth.uid(), v_seen);
  delete from public.attendance_unknown_devices where serial = v_sn;
  return jsonb_build_object('status', 'ok', 'seen_before', v_seen is not null);
end $$;

create or replace function public.attendance_device_set(p_device uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select org_id into v_org from public.attendance_devices where id = p_device;
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.is_org_admin(v_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if p_status = 'delete' then delete from public.attendance_devices where id = p_device;
  elsif p_status in ('active', 'disabled') then update public.attendance_devices set status = p_status where id = p_device;
  else return jsonb_build_object('status', 'bad_value'); end if;
  return jsonb_build_object('status', 'ok');
end $$;

-- ═══ للخادم وحده: نبض الجهاز وسطور ATTLOG ═══
create or replace function public.attendance_device_seen(p_secret text, p_serial text, p_ip text)
returns text language plpgsql security definer set search_path = public as $$
declare v_sn text := upper(btrim(coalesce(p_serial, ''))); v_status text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if v_sn !~ '^[A-Z0-9]{6,32}$' then return 'bad'; end if;
  update public.attendance_devices set last_seen_at = now(), last_ip = left(p_ip, 64) where serial = v_sn returning status into v_status;
  if v_status is null then
    insert into public.attendance_unknown_devices (serial, last_ip) values (v_sn, left(p_ip, 64))
    on conflict (serial) do update set last_seen_at = now(), last_ip = excluded.last_ip, hits = attendance_unknown_devices.hits + 1;
    return 'unknown';
  end if;
  return v_status;
end $$;

-- p_lines: [{pin, at: 'YYYY-MM-DD HH:MI:SS' بتوقيت الجهاز المحلي, status}]
create or replace function public.attendance_device_ingest(p_secret text, p_serial text, p_lines jsonb, p_ip text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.attendance_devices; s public.attendance_settings; l jsonb; v_at timestamptz; v_staff uuid; n_in integer := 0; n_skip integer := 0; v_pin text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select * into d from public.attendance_devices where serial = upper(btrim(coalesce(p_serial, '')));
  if d.id is null then perform public.attendance_device_seen(p_secret, p_serial, p_ip); return jsonb_build_object('status', 'unknown'); end if;
  if d.status <> 'active' then return jsonb_build_object('status', 'disabled'); end if;
  s := public.attendance_settings_of(d.org_id);
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) limit 2000 loop
    begin
      v_pin := btrim(l->>'pin');
      v_at := ((l->>'at')::timestamp) at time zone s.timezone;
      if v_pin is null or v_pin = '' or v_at > now() + interval '1 day' or v_at < now() - interval '400 days' then n_skip := n_skip + 1; continue; end if;
      select st.id into v_staff from public.attendance_staff(d.org_id, (v_at at time zone s.timezone)::date, (v_at at time zone s.timezone)::date) st
       where st.pin = v_pin limit 1;
      insert into public.attendance_punches (org_id, staff_item_id, pin, at, direction, source, device_id)
      values (d.org_id, v_staff, v_pin, v_at,
              case l->>'status' when '0' then 'in' when '1' then 'out' else 'auto' end, 'device', d.id)
      on conflict do nothing;
      if found then n_in := n_in + 1; end if;
    exception when others then n_skip := n_skip + 1;
    end;
  end loop;
  update public.attendance_devices set last_seen_at = now(), last_ip = left(p_ip, 64), punches_total = punches_total + n_in where id = d.id;
  return jsonb_build_object('status', 'ok', 'stored', n_in, 'skipped', n_skip);
end $$;

-- بصمات جهاز سبقت ربط الموظف برقمه: تربط حين يكتب رقم البصمة على عنصره
create or replace function public.attendance_relink(p_org uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.hr_visible_me(p_org, 'hr') then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  update public.attendance_punches p set staff_item_id = st.id
    from public.attendance_staff(p_org, current_date - 400, current_date + 1) st
   where p.org_id = p_org and p.staff_item_id is null and p.pin = st.pin;
  get diagnostics n = row_count;
  return jsonb_build_object('status', 'ok', 'linked', n,
    'unlinked_pins', coalesce((select jsonb_agg(distinct pin) from public.attendance_punches where org_id = p_org and staff_item_id is null), '[]'::jsonb));
end $$;

-- ═══ الصلاحيات ═══
revoke all on function public.attendance_settings_of(uuid), public.attendance_staff(uuid, date, date),
  public.attendance_my_staff(uuid) from public, anon, authenticated;
revoke all on function public.attendance_days(uuid, date, date), public.attendance_close_month(uuid, date),
  public.attendance_reopen_month(uuid, date), public.attendance_punch_me(uuid, numeric, numeric, integer),
  public.attendance_my_status(uuid), public.attendance_manual_punch(uuid, uuid, timestamptz, text, text),
  public.attendance_punch_delete(uuid), public.attendance_settings_get(uuid), public.attendance_settings_save(uuid, jsonb),
  public.attendance_device_register(uuid, text, text), public.attendance_device_set(uuid, text), public.attendance_relink(uuid) from public, anon;
grant execute on function public.attendance_days(uuid, date, date), public.attendance_close_month(uuid, date),
  public.attendance_reopen_month(uuid, date), public.attendance_punch_me(uuid, numeric, numeric, integer),
  public.attendance_my_status(uuid), public.attendance_manual_punch(uuid, uuid, timestamptz, text, text),
  public.attendance_punch_delete(uuid), public.attendance_settings_get(uuid), public.attendance_settings_save(uuid, jsonb),
  public.attendance_device_register(uuid, text, text), public.attendance_device_set(uuid, text), public.attendance_relink(uuid) to authenticated;
revoke all on function public.attendance_device_seen(text, text, text), public.attendance_device_ingest(text, text, jsonb, text) from public, authenticated;
grant execute on function public.attendance_device_seen(text, text, text), public.attendance_device_ingest(text, text, jsonb, text) to anon, service_role;

-- ═══ الخدمة: كل الحزم الا الشخصية، وكل الاقسام (الموظف في اي قسم يسجل حضوره) ═══
do $$
declare p text;
begin
  for p in select distinct pack_key from public.pack_services where pack_key <> 'individual' loop
    if not exists (select 1 from public.pack_services where pack_key = p and service = 'attendance') then
      insert into public.pack_services (pack_key, service, sort_order, label)
      values (p, 'attendance', coalesce((select max(sort_order) from public.pack_services where pack_key = p and service <> 'settings'), 0) + 1,
              jsonb_build_object('ar', 'الحضور والانصراف', 'en', 'Attendance', 'fr', 'Présences', 'ur', 'حاضری'));
      update public.pack_services set sort_order = sort_order + 1 where pack_key = p and service = 'settings';
    end if;
  end loop;
end $$;
insert into public.department_services (department, service)
select d, 'attendance' from (select distinct department from public.department_services) x(d)
where not exists (select 1 from public.department_services y where y.department = x.d and y.service = 'attendance');

-- ═══ المسيّر يقرأ الحضور من الشهر المقفل ═══
-- (اعادة تعريف payroll_generate من 0175 كما هي، والفرق وحده مصدر الغياب والتاخر)
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

    -- الحضور: الشهر المقفل في attendance_months (0178)، ومنه وحده الغياب والتأخر
    select am.absent, am.late_minutes into v_abs, v_late
      from public.attendance_months am
     where am.org_id = p_org and am.staff_item_id = r.id and am.month = v_from;

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

