-- قرار المهندس رعد 2026-09-11: ثلاث باقات مدفوعة فقط في هذه المرحلة — شخصي، وثيقة عمل حر، ستارت اب —
-- لان هؤلاء اصحاب الفوضى الورقية الحقيقية. باقة «منشأة صغيرة» (enterprise) تعطل لا تحذف.
update public.plans set name_ar = 'شركة ناشئة', name_en = 'Startup', name_fr = 'Startup', name_ur = 'اسٹارٹ اپ' where code = 'business';
update public.plans set active = false where code = 'enterprise';
