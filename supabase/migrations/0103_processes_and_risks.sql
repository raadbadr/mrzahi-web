-- الترحيل كما طبق على Supabase (version 20260904105458, name tracker_0021_processes_and_risks); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- مكتبة الإجراءات وسجل المخاطر (مأخوذتان من Mejdaf Operations Hub ومكيّفتان لمكتب المحاماة)

create table if not exists public.processes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text,
  name text not null,
  area text,                       -- المجال: دعاوى، مخالفات، عقود، تراخيص…
  description text,
  trigger_text text,               -- ما الذي يبدأ الإجراء
  inputs text,
  outputs text,
  frequency text,
  owner_id uuid references auth.users(id),
  steps jsonb not null default '[]'::jsonb,   -- [{id,type,title,role,R,A,C,I,note,next,yesTarget,noTarget}]
  status text not null default 'draft' check (status in ('draft','review','published','archived')),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists processes_org_idx on public.processes (org_id, status);
create index if not exists processes_owner_idx on public.processes (owner_id);
create index if not exists processes_created_by_idx on public.processes (created_by);

create table if not exists public.risks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text,
  title text not null,
  category text,                   -- قانوني، إجرائي، مالي، امتثال، سمعة، تشغيلي
  client_name text,
  case_number text,
  process_id uuid references public.processes(id) on delete set null,
  owner_id uuid references auth.users(id),
  description text,
  identified_at date default current_date,
  review_at date,
  root_cause text,
  consequences text,
  existing_controls text,
  likelihood smallint check (likelihood between 1 and 5),
  impact smallint check (impact between 1 and 5),
  res_likelihood smallint check (res_likelihood between 1 and 5),
  res_impact smallint check (res_impact between 1 and 5),
  strategy text not null default 'mitigate' check (strategy in ('mitigate','accept','transfer','avoid')),
  status text not null default 'open' check (status in ('open','in_progress','monitoring','closed')),
  actions jsonb not null default '[]'::jsonb,  -- [{title, owner_id, due, done, item_id}]
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists risks_org_idx on public.risks (org_id, status);
create index if not exists risks_owner_idx on public.risks (owner_id);
create index if not exists risks_process_idx on public.risks (process_id);
create index if not exists risks_created_by_idx on public.risks (created_by);

alter table public.processes enable row level security;
alter table public.risks enable row level security;

create policy processes_read on public.processes for select using (org_id in (select current_org_ids()) or is_platform_admin());
create policy processes_write on public.processes for insert with check (org_id in (select current_org_ids()) and created_by = (select auth.uid()));
create policy processes_update on public.processes for update using (org_id in (select current_org_ids())) with check (org_id in (select current_org_ids()));
create policy processes_delete on public.processes for delete using (created_by = (select auth.uid()) or is_org_admin(org_id));

create policy risks_read on public.risks for select using (org_id in (select current_org_ids()) or is_platform_admin());
create policy risks_write on public.risks for insert with check (org_id in (select current_org_ids()) and created_by = (select auth.uid()));
create policy risks_update on public.risks for update using (org_id in (select current_org_ids())) with check (org_id in (select current_org_ids()));
create policy risks_delete on public.risks for delete using (created_by = (select auth.uid()) or is_org_admin(org_id));

grant select, insert, update, delete on public.processes, public.risks to authenticated;

-- الترقيم القياسي: PRC للإجراء، RSK للخطر
create or replace function public.generate_canonical_number(p_type text, p_date_string text)
returns text language plpgsql security definer set search_path = public as $$
declare num_type text; effective_date text; number_prefix text; current_max integer := 0; next_sequence integer;
begin
  num_type := upper(btrim(coalesce(p_type, '')));
  if num_type not in ('USR','ORG','ITM','PRC','RSK') then raise exception 'invalid type: %', num_type; end if;
  effective_date := btrim(coalesce(p_date_string, to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY')));
  number_prefix := num_type || '-' || effective_date || '-';
  perform pg_advisory_xact_lock(hashtext('tracker_canonical_number'), hashtext(number_prefix));
  if num_type = 'USR' then
    select coalesce(max(right(p.profile_number, 4)::integer), 0) into current_max from public.profiles p
    where p.profile_number like number_prefix || '%' and length(p.profile_number) = length(number_prefix) + 4 and right(p.profile_number, 4) ~ '^[0-9]{4}$';
  elsif num_type = 'ORG' then
    select coalesce(max(right(o.org_number, 4)::integer), 0) into current_max from public.organizations o
    where o.org_number like number_prefix || '%' and length(o.org_number) = length(number_prefix) + 4 and right(o.org_number, 4) ~ '^[0-9]{4}$';
  elsif num_type = 'ITM' then
    select coalesce(max(right(i.item_number, 4)::integer), 0) into current_max from public.items i
    where i.item_number like number_prefix || '%' and length(i.item_number) = length(number_prefix) + 4 and right(i.item_number, 4) ~ '^[0-9]{4}$';
  elsif num_type = 'PRC' then
    select coalesce(max(right(x.code, 4)::integer), 0) into current_max from public.processes x
    where x.code like number_prefix || '%' and length(x.code) = length(number_prefix) + 4 and right(x.code, 4) ~ '^[0-9]{4}$';
  else
    select coalesce(max(right(x.code, 4)::integer), 0) into current_max from public.risks x
    where x.code like number_prefix || '%' and length(x.code) = length(number_prefix) + 4 and right(x.code, 4) ~ '^[0-9]{4}$';
  end if;
  next_sequence := current_max + 1;
  if next_sequence > 9999 then raise exception 'canonical sequence overflow for prefix %', number_prefix using errcode = 'check_violation'; end if;
  return number_prefix || lpad(next_sequence::text, 4, '0');
end $$;

create or replace function public.set_process_code() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.code is null then new.code := public.generate_canonical_number('PRC', to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY')); end if;
  new.updated_at := now();
  return new;
end $$;
create or replace function public.set_risk_code() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.code is null then new.code := public.generate_canonical_number('RSK', to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY')); end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists processes_set_code on public.processes;
create trigger processes_set_code before insert or update on public.processes for each row execute function public.set_process_code();
drop trigger if exists risks_set_code on public.risks;
create trigger risks_set_code before insert or update on public.risks for each row execute function public.set_risk_code();
revoke all on function public.set_process_code() from public, anon, authenticated;
revoke all on function public.set_risk_code() from public, anon, authenticated;
