-- الدفع داخل النظام: كل عملية تُسجَّل، وعند نجاح التحصيل يُفعَّل الاشتراك
-- تلقائيا في المعاملة نفسها بلا تدخل أحد. الحارس سر الوركر.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid,
  provider text not null default 'paypal',
  order_id text unique,
  plan_code text not null,
  period text not null,
  amount_sar numeric not null,
  currency text not null default 'USD',
  amount_charged numeric,
  status text not null default 'created',
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists payments_org_idx on public.payments (org_id, created_at desc);
alter table public.payments enable row level security;
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments for select
  using (org_id in (select public.current_org_ids()));
-- الدوال الثلاث (pay_start / pay_mark_order / pay_complete) في هجرة القاعدة الحية.
