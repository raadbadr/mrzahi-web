-- الباقات بالمصطلحات النظامية واسعار المهندس رعد (2026-09-11): شخصي 99، وثيقة عمل حر 169، منشاة متناهية الصغر 499،
-- منشاة صغيرة (6-49 موظفا) تبقى 700؛ لا باقات متوسطة او كبيرة في هذه المرحلة. السنوي = 10 اشهر كما كان.
update public.plans set price_monthly_sar = 99,  price_yearly_sar = 990  where code = 'personal';
update public.plans set price_monthly_sar = 169, price_yearly_sar = 1690, name_ar = 'وثيقة عمل حر', name_en = 'Freelance Permit', name_fr = 'Permis freelance', name_ur = 'فری لانس پرمٹ' where code = 'freelance';
update public.plans set price_monthly_sar = 499, price_yearly_sar = 4990, name_ar = 'منشأة متناهية الصغر', name_en = 'Micro Enterprise', name_fr = 'Micro-entreprise', name_ur = 'مائیکرو ادارہ' where code = 'business';
update public.plans set name_ar = 'منشأة صغيرة', name_en = 'Small Enterprise', name_fr = 'Petite entreprise', name_ur = 'چھوٹا ادارہ' where code = 'enterprise';
