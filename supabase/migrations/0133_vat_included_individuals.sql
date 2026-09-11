-- قرار المهندس رعد النهائي: سعر الفرد (شخصي، وثيقة عمل حر) شامل ضريبة القيمة
-- المضافة، وسعر المنشآت (متناهية الصغر، كبيرة) لا يشملها وتضاف عند الشراء.
-- plans.limits.vat_excluded: false = السعر شامل (المحصل = السعر، الاساس = السعر ÷ 1.15)،
-- true = السعر اساس (المحصل = السعر × 1.15). النسبة 15% في الحالتين وتسجل مفصولة.
update public.plans set limits = jsonb_set(limits, '{vat_excluded}', 'false'::jsonb) where code in ('personal', 'freelance');
update public.plans set limits = jsonb_set(limits, '{vat_excluded}', 'true'::jsonb)  where code in ('business', 'enterprise');

create or replace function public.pay_start(p_secret text, p_user uuid, p_org uuid, p_plan text, p_period text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_price numeric; v_base numeric; v_rate numeric := 0.15; v_vat numeric; v_total numeric; v_id uuid; v_excl boolean;
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
    into v_price, v_excl from public.plans where code = p_plan and active;
  if v_price is null or v_price <= 0 then raise exception 'plan has no price' using errcode = '22023'; end if;
  if v_excl then
    -- السعر اساس بلا ضريبة: تضاف عند الشراء.
    v_base := v_price; v_vat := round(v_base * v_rate, 2); v_total := v_base + v_vat;
  else
    -- السعر شامل الضريبة: المحصل هو السعر نفسه، والاساس يستخرج منه، والفرق ضريبة (لا كسور ضائعة).
    v_total := v_price; v_base := round(v_price / (1 + v_rate), 2); v_vat := v_total - v_base;
  end if;
  insert into public.payments (org_id, user_id, plan_code, period, amount_sar, base_sar, vat_rate, vat_sar)
  values (p_org, p_user, p_plan, p_period, v_total, v_base, v_rate, v_vat)
  returning id into v_id;
  return jsonb_build_object('payment_id', v_id, 'amount_sar', v_total,
                            'base_sar', v_base, 'vat_rate', v_rate, 'vat_sar', v_vat, 'vat_included', not v_excl);
end $function$;
