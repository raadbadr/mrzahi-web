-- الحساب بلا نوع مسجل يسقط على الواجهة الشخصية لا على أوسع واجهة.
update public.ui_packs set is_default = false where is_default;
update public.ui_packs set is_default = true where key = 'individual';

-- التسعير على أربع شرائح بحسب نوع الحساب. القديمتان تبقيان في الجدول
-- ولا تُحذفان، لكن تُطفآن فلا تظهران لأحد.
alter table public.plans add column if not exists active boolean not null default true;
update public.plans set active = false where code in ('monthly', 'yearly');

insert into public.plans (code, name_ar, name_en, name_fr, name_ur, price_monthly_sar, price_yearly_sar, limits, sort_order, active)
values
  ('personal', 'شخصي', 'Personal', 'Personnel', 'ذاتی', 19, 190,
   '{"items":300,"members":1,"calendar":["ics","google"],"channels":[],"storage_mb":200,"imports_per_month":2}'::jsonb, 2, true),
  ('freelance', 'عمل حر', 'Freelance', 'Indépendant', 'فری لانس', 39, 390,
   '{"items":1500,"members":1,"calendar":["ics","google"],"channels":["telegram"],"storage_mb":1000,"imports_per_month":10}'::jsonb, 3, true),
  ('business', 'مؤسسة وشركة ناشئة', 'Business', 'Entreprise', 'کاروبار', 99, 990,
   '{"items":10000,"members":3,"calendar":["ics","google"],"channels":["telegram"],"storage_mb":5000,"imports_per_month":null,"seat_price_sar":25}'::jsonb, 4, true),
  ('enterprise', 'شركة كبيرة', 'Enterprise', 'Grande entreprise', 'بڑا ادارہ', 249, 2490,
   '{"items":100000,"members":5,"calendar":["ics","google"],"channels":["telegram"],"storage_mb":50000,"imports_per_month":null,"priority_support":true,"seat_price_sar":25}'::jsonb, 5, true)
on conflict (code) do update set
  name_ar = excluded.name_ar, name_en = excluded.name_en, name_fr = excluded.name_fr, name_ur = excluded.name_ur,
  price_monthly_sar = excluded.price_monthly_sar, price_yearly_sar = excluded.price_yearly_sar,
  limits = excluded.limits, sort_order = excluded.sort_order, active = excluded.active;

update public.plans set sort_order = 1 where code = 'trial';
update public.plans set sort_order = 9, active = false where code = 'expired';
