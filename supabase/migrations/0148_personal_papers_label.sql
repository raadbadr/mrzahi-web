-- المهندس رعد 2026-09-16: «ودي لين الان ماتعدلت في الشخصي» — بطاقة المستندات
-- في الحساب الشخصي ما زالت تقول «مستندات الشركة».
--
-- الشيفرة تتبع التسمية اصلا (applyPackTitle تقرا ui_packs.labels.documentsTitle)
-- لكن الحزمة الشخصية بلا تسمية على القاعدة الحية، فتقع على النص الافتراضي.
-- التسمية هنا: العنوان في الصفحة، والخدمة في الشريط الجانبي وفي فلاتر التقويم.

begin;

update public.ui_packs
   set labels = coalesce(labels, '{}'::jsonb) || jsonb_build_object(
         'documentsTitle', jsonb_build_object('ar', 'أوراقي الرسمية', 'en', 'My papers', 'fr', 'Mes papiers', 'ur', 'میرے کاغذات'))
 where key = 'individual';

update public.pack_services
   set label = jsonb_build_object('ar', 'أوراقي الرسمية', 'en', 'My papers', 'fr', 'Mes papiers', 'ur', 'میرے کاغذات')
 where pack_key = 'individual' and service = 'documents';

commit;
