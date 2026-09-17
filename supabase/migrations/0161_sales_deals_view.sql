-- المهندس رعد 2026-09-17: «المبيعات تحتاج اعادة تصميم، مو معقول كل الواجهات نحصل
-- نفس الشي العام الخاص بالمحامين»، ثم: «يلا ابدا بالمبيعات».
--
-- كانت واجهة المبيعات هي واجهة المحاماة نفسها بتسميات: cases باسم «العملاء
-- والصفقات» (بحقول القضية: رقم الدعوى والعميل)، و expenses باسم «الفواتير
-- والتحصيل»، و documents باسم «العقود والعروض». فالبائع يفتح صفقة فيجد حقول
-- قضية وحالة «مفتوح/منجز» لا مراحل بيع.
--
-- شاشة «الصفقات» نوع لوحة متخصص (deals) على نمط «العقود» في المحاماة و«صحتي» في
-- الشخصي: مراحلها وقيمتها واحتمال اغلاقها. وتحل محل cases في حزمة المبيعات وحدها
-- فلا تبقى شاشتان للشيء نفسه. وحين كتب هذا الترحيل لم يكن اي حساب على حزمة sales،
-- فلا بيانات تخفى عن احد.
--
-- واجهتا المحاماة والشخصي لا تمسان باي حرف (امر المهندس رعد).

begin;

-- الصلاحية: المبيعات عمل الادارة والعمليات
insert into public.department_services (department, service) values
  ('management', 'deals'),
  ('operations', 'deals')
on conflict do nothing;

-- الخدمة في حزمة المبيعات وحدها، مكان cases
delete from public.pack_services where pack_key = 'sales' and service = 'cases';

insert into public.pack_services (pack_key, service, sort_order, label) values
  ('sales', 'deals', 2, jsonb_build_object(
     'ar', 'الصفقات', 'en', 'Deals', 'fr', 'Affaires', 'ur', 'سودے'))
on conflict (pack_key, service) do update set sort_order = excluded.sort_order, label = excluded.label;

-- الفاظ المبيعات داخل الشاشات
update public.ui_packs
   set labels = coalesce(labels, '{}'::jsonb) || jsonb_build_object(
         'fieldClient', jsonb_build_object('ar', 'العميل', 'en', 'Client', 'fr', 'Client', 'ur', 'گاہک'),
         'fieldCaseNumber', jsonb_build_object('ar', 'رقم الصفقة', 'en', 'Deal number', 'fr', 'Numero d''affaire', 'ur', 'سودے کا نمبر'))
 where key = 'sales';

commit;

-- تحقق: deals في المبيعات، و cases خرجت منها، والصلاحية مسجلة
select (select string_agg(service, ',' order by sort_order) from public.pack_services where pack_key = 'sales') as khadamat_sales,
       (select count(*) from public.department_services where service = 'deals') as salahiyat_deals;
