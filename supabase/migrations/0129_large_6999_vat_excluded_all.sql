-- المهندس رعد 2026-09-11: منشأة كبيرة 6999 سنويا، وكل الاسعار بلا ضريبة القيمة المضافة (تضاف عند الدفع).
update public.plans set price_yearly_sar = 6999 where code = 'enterprise';
update public.plans set limits = jsonb_set(limits, '{vat_excluded}', 'true'::jsonb) where code in ('personal', 'freelance', 'business', 'enterprise');
