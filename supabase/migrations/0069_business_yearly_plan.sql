-- ============================================================
-- 0069 — باقة الشركات: 7000 ريال سنويا بدون ضريبة القيمة المضافة
-- (أمر المهندس رعد 2026-09-07). الباقة السنوية الحالية 490 تبقى
-- كما هي للشركات الناشئة ووثائق العمل الحر والأفراد.
-- ============================================================

insert into public.plans (code, name_ar, name_en, name_fr, name_ur, price_monthly_sar, price_yearly_sar, limits, sort_order)
values ('business', 'باقة الشركات', 'Business', 'Entreprise', 'کمپنی پیکیج', null, 7000.00,
        jsonb_build_object('items', null, 'members', null, 'calendar', jsonb_build_array('ics','google'),
                           'channels', jsonb_build_array('telegram'), 'storage_mb', 20000,
                           'priority_support', true, 'imports_per_month', null, 'vat_excluded', true),
        4)
on conflict (code) do update set
  name_ar = excluded.name_ar, name_en = excluded.name_en, name_fr = excluded.name_fr, name_ur = excluded.name_ur,
  price_yearly_sar = excluded.price_yearly_sar, limits = excluded.limits, sort_order = excluded.sort_order;
