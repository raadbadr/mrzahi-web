-- قرار المهندس رعد 2026-09-11 (الاخير): اربع باقات مدفوعة — شخصي، وثيقة عمل حر، منشأة متناهية الصغر، منشأة كبيرة.
update public.plans set name_ar = 'منشأة متناهية الصغر', name_en = 'Micro Enterprise', name_fr = 'Micro-entreprise', name_ur = 'مائیکرو ادارہ' where code = 'business';
update public.plans set active = true, name_ar = 'منشأة كبيرة', name_en = 'Large Enterprise', name_fr = 'Grande entreprise', name_ur = 'بڑا ادارہ' where code = 'enterprise';
