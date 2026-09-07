-- سلم الأسعار: فروق متقاربة، والسنوي بعشرة أشهر — شهران بلا مقابل.
update public.plans set price_monthly_sar = 150, price_yearly_sar = 1500 where code = 'personal';
update public.plans set price_monthly_sar = 300, price_yearly_sar = 3000 where code = 'freelance';
update public.plans set price_monthly_sar = 500, price_yearly_sar = 5000 where code = 'business';
update public.plans set price_monthly_sar = 700, price_yearly_sar = 7000 where code = 'enterprise';

-- التجريبية لا تتفوق على أرخص مدفوعة: حدودها حدود «شخصي»، وميزتها المدة لا السعة.
update public.plans
   set limits = '{"items":300,"members":1,"calendar":["ics","google"],"channels":["telegram"],"storage_mb":200,"trial_days":14,"imports_per_month":2}'::jsonb
 where code = 'trial';
