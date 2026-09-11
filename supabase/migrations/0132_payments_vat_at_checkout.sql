-- الضريبة تضاف عند الشراء: الباقات اسعارها بلا ضريبة (plans.limits.vat_excluded)،
-- فالتحصيل الفعلي = الاساس + 15% ضريبة القيمة المضافة. كل دفعة تسجل الاساس
-- والضريبة ونسبتها منفصلة كي تفصلها اي فاتورة لاحقا. amount_sar يبقى المبلغ
-- المحصل الكامل (شامل الضريبة) لانه ما يرسل الى PayPal.
alter table public.payments add column if not exists base_sar numeric;
alter table public.payments add column if not exists vat_rate numeric not null default 0;
alter table public.payments add column if not exists vat_sar numeric not null default 0;
-- الدفعات السابقة حصلت بلا ضريبة: الاساس = المحصل، الضريبة صفر (حقيقة لا تجميل).
update public.payments set base_sar = amount_sar where base_sar is null;
alter table public.payments alter column base_sar set not null;

create or replace function public.pay_start(p_secret text, p_user uuid, p_org uuid, p_plan text, p_period text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_base numeric; v_rate numeric := 0; v_vat numeric; v_total numeric; v_id uuid; v_excl boolean;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select role into v_role from public.org_members
   where org_id = p_org and user_id = p_user and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_period not in ('monthly','yearly') then raise exception 'bad period' using errcode = '22023'; end if;
  select case when p_period = 'yearly' then price_yearly_sar else price_monthly_sar end,
         coalesce((limits->>'vat_excluded')::boolean, false)
    into v_base, v_excl from public.plans where code = p_plan and active;
  if v_base is null or v_base <= 0 then raise exception 'plan has no price' using errcode = '22023'; end if;
  if v_excl then v_rate := 0.15; end if;
  v_vat := round(v_base * v_rate, 2);
  v_total := v_base + v_vat;
  insert into public.payments (org_id, user_id, plan_code, period, amount_sar, base_sar, vat_rate, vat_sar)
  values (p_org, p_user, p_plan, p_period, v_total, v_base, v_rate, v_vat)
  returning id into v_id;
  return jsonb_build_object('payment_id', v_id, 'amount_sar', v_total,
                            'base_sar', v_base, 'vat_rate', v_rate, 'vat_sar', v_vat);
end $function$;
