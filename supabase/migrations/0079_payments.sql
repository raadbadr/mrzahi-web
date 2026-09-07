-- الدفع داخل النظام: كل عملية تسجل، وعند نجاح التحصيل يفعل الاشتراك
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

create or replace function public.pay_start(p_secret text, p_user uuid, p_org uuid, p_plan text, p_period text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_amount numeric; v_id uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select role into v_role from public.org_members
   where org_id = p_org and user_id = p_user and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_period not in ('monthly','yearly') then raise exception 'bad period' using errcode = '22023'; end if;
  select case when p_period = 'yearly' then price_yearly_sar else price_monthly_sar end
    into v_amount from public.plans where code = p_plan and active;
  if v_amount is null or v_amount <= 0 then raise exception 'plan has no price' using errcode = '22023'; end if;
  insert into public.payments (org_id, user_id, plan_code, period, amount_sar)
  values (p_org, p_user, p_plan, p_period, v_amount)
  returning id into v_id;
  return jsonb_build_object('payment_id', v_id, 'amount_sar', v_amount);
end $function$;

create or replace function public.pay_mark_order(p_secret text, p_payment uuid, p_order text)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  update public.payments set order_id = p_order, status = 'approved' where id = p_payment;
end $function$;

create or replace function public.pay_complete(p_secret text, p_order text, p_charged numeric, p_currency text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare r record; v_expires timestamptz;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select * into r from public.payments where order_id = p_order;
  if r.id is null then raise exception 'unknown order' using errcode = '22023'; end if;
  if r.status = 'paid' then return jsonb_build_object('plan', r.plan_code, 'already', true); end if;
  v_expires := now() + (case when r.period = 'yearly' then interval '1 year' else interval '1 month' end);
  update public.payments
     set status = 'paid', paid_at = now(), amount_charged = p_charged, currency = coalesce(p_currency, currency)
   where id = r.id;
  update public.subscriptions set status = 'ended'
   where org_id = r.org_id and status = 'active';
  insert into public.subscriptions (org_id, plan_code, status, starts_at, expires_at, activated_by, note)
  values (r.org_id, r.plan_code, 'active', now(), v_expires, r.user_id, 'paypal ' || p_order);
  update public.organizations set plan_code = r.plan_code, plan_expires_at = v_expires where id = r.org_id;
  return jsonb_build_object('plan', r.plan_code, 'expires', v_expires);
end $function$;

revoke all on function public.pay_start(text, uuid, uuid, text, text) from public;
revoke all on function public.pay_mark_order(text, uuid, text) from public;
revoke all on function public.pay_complete(text, text, numeric, text) from public;
grant execute on function public.pay_start(text, uuid, uuid, text, text) to anon, authenticated;
grant execute on function public.pay_mark_order(text, uuid, text) to anon, authenticated;
grant execute on function public.pay_complete(text, text, numeric, text) to anon, authenticated;
