-- اسماء الباقات على تصنيف الهيئة العامة للمنشآت الصغيرة والمتوسطة (قرار المهندس رعد 2026-09-11: «نمشي بالنظام»):
-- متناهية الصغر 1-5 موظفين، صغيرة 6-49، متوسطة 50-249، كبيرة فوق ذلك. الرموز لا تتغير.
update public.plans set name_ar = 'منشأة متناهية الصغر وصغيرة', name_en = 'Micro & Small Enterprise',
       name_fr = 'Micro et petite entreprise', name_ur = 'مائیکرو اور چھوٹا ادارہ' where code = 'business';
update public.plans set name_ar = 'منشأة متوسطة وكبيرة', name_en = 'Medium & Large Enterprise',
       name_fr = 'Moyenne et grande entreprise', name_ur = 'درمیانہ اور بڑا ادارہ' where code = 'enterprise';
