-- الترحيل كما طبق على Supabase (version 20260907234724, name paypal_orders); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
create table if not exists public.paypal_orders (
  id text primary key,
  org_id uuid not null references public.organizations(id) on delete cascade,
  plan_code text not null references public.plans(code),
  period text not null check (period in ('monthly', 'yearly')),
  amount_usd numeric not null,
  status text not null default 'created' check (status in ('created', 'captured', 'failed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  captured_at timestamptz
);

alter table public.paypal_orders enable row level security;

drop policy if exists paypal_orders_read on public.paypal_orders;
create policy paypal_orders_read on public.paypal_orders for select
  using (public.is_org_admin(org_id));

revoke all on public.paypal_orders from anon;
