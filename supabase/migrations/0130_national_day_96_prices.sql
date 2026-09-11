-- اليوم الوطني السعودي الـ 96 (23 سبتمبر 2026): الاسعار على الرقم 96 (قرار المهندس رعد 2026-09-11 «زبط الارقام عليه»).
update public.plans set price_monthly_sar = 96,  price_yearly_sar = 960  where code = 'personal';
update public.plans set price_monthly_sar = 196, price_yearly_sar = 1960 where code = 'freelance';
update public.plans set price_monthly_sar = 496, price_yearly_sar = 4960 where code = 'business';
update public.plans set price_monthly_sar = 696, price_yearly_sar = 6996 where code = 'enterprise';
