-- أسعار المهندس رعد: المؤسسات والشركات الناشئة 5,000 سنويا، والشركة الكبيرة
-- 7,000 سنويا، كلاهما بلا ضريبة القيمة المضافة ولا سعر شهري لهما.
update public.plans
   set price_yearly_sar = 5000, price_monthly_sar = null,
       limits = limits || '{"vat_excluded":true}'::jsonb
 where code = 'business';
update public.plans
   set price_yearly_sar = 7000, price_monthly_sar = null,
       limits = limits || '{"vat_excluded":true}'::jsonb
 where code = 'enterprise';
