-- المهندس رعد 2026-09-17: «مو معقول كل الواجهات نحصل نفس الشي العام الخاص
-- بالمحامين» — والمالية كانت اظهر مثال: حزمة finance هي expenses + documents +
-- risks + team بتسميات فقط. «المصاريف والإيرادات» شاشة مصاريف تشغيل بحقول عامة
-- (عنوان وتاريخ ومبلغ وحالة مفتوح/منجز)، و«الفواتير والمستندات» شاشة مستندات.
-- فالمحاسب لا يجد حقلا واحدا يخص عمله: لا رقم فاتورة، ولا تاريخ اصدار، ولا
-- ضريبة، ولا محصل ولا متبق، ولا تمييز بين مدين ودائن.
--
-- شاشة «الفواتير والمستحقات» نوع لوحة متخصص (invoices) على نمط «العقود» في
-- المحاماة و«صحتي» في الشخصي: رقم الفاتورة وجهتها وتاريخ اصدارها، وتاريخ
-- استحقاقها (هو due_at نفسه فيدخل التقويم والتذكير والمربعات)، ومبلغها
-- وضريبتها والمحصل منها والمتبقي، واتجاهها مدين (فاتورة على عميل) او دائن
-- (فاتورة من مورد). وحالتها محسوبة لا مخترعة: مستحقة، محصلة جزئيا، متاخرة،
-- محصلة، ملغاة.
--
-- الضريبة 15% كقاعدة المشروع: تحسب مرة واحدة عند الحفظ وتخزن (base_sar و
-- vat_rate و vat_sar و total_sar كما في جدول payments) ولا تحسب من جديد عند
-- القراءة ابدا. و amount يبقى الاجمالي شامل الضريبة، فمجاميع اللوحة والتقويم
-- والمربعات تبقى صحيحة بلا سطر واحد يعدل فيها.
--
-- كل حقول الشاشة في items.data كما تفعل العقود: لا جدول جديد ولا عمود جديد ولا
-- صفحة HTML جديدة.
--
-- النطاق: حزمة finance وحدها. وحين كتب هذا الترحيل لم يكن اي حساب عليها
-- (org_profiles: صفر، profiles: صفر)، فلا بيانات تخفى عن احد ولا ترتيب يتبدل
-- تحت يد مستخدم. بقية الحزم لا تمس بحرف: المحاماة والشخصي والمبيعات والعيادة
-- وغيرها كما هي.

begin;

-- 1) الصلاحية في القاعدة لا في الشيفرة: الفواتير عمل قسم المالية، والادارة
--    تراها كما ترى كل خدمة.
insert into public.department_services (department, service) values
  ('finance', 'invoices'),
  ('management', 'invoices')
on conflict do nothing;

-- 2) الخدمة في حزمة finance وحدها، ثانية بعد لوحة التحكم، بالاربع لغات
insert into public.pack_services (pack_key, service, sort_order, label) values
  ('finance', 'invoices', 2, jsonb_build_object(
     'ar', 'الفواتير والمستحقات',
     'en', 'Invoices and dues',
     'fr', 'Factures et echeances',
     'ur', 'رسیدیں اور واجبات'))
on conflict (pack_key, service) do update
   set sort_order = excluded.sort_order, label = excluded.label;

-- 3) بقية خدمات المالية تنزل درجة واحدة خلفها. لا خدمة تحذف ولا تخفى.
update public.pack_services set sort_order = 3 where pack_key = 'finance' and service = 'expenses';
update public.pack_services set sort_order = 4 where pack_key = 'finance' and service = 'documents';
update public.pack_services set sort_order = 5 where pack_key = 'finance' and service = 'risks';
update public.pack_services set sort_order = 6 where pack_key = 'finance' and service = 'team';
update public.pack_services set sort_order = 7 where pack_key = 'finance' and service = 'settings';

-- 4) تسميتان كانتا تعدان بما ليس فيهما، وقاعدة ترحيل 0134 تمنع التسمية التي
--    تربك المستخدم:
--    expenses كانت «المصاريف والإيرادات» ولا ايراد فيها اصلا، والايراد صار في
--    شاشته، فتعود الى اسم خدمتها كما هو في الشريط (label فارغ = «مصاريف التشغيل»).
update public.pack_services set label = null
 where pack_key = 'finance' and service = 'expenses';
--    documents كانت «الفواتير والمستندات»، والفواتير لها شاشتها الان، فتبقى
--    «المستندات» في اسمها ومعها وصفها المالي.
update public.pack_services set label = jsonb_build_object(
     'ar', 'المستندات المالية',
     'en', 'Financial documents',
     'fr', 'Documents financiers',
     'ur', 'مالی دستاویزات')
 where pack_key = 'finance' and service = 'documents';

commit;

-- تحقق (1): ترتيب خدمات المالية وتسمياتها بعد الترحيل
select service, sort_order,
       coalesce(label ->> 'ar', '— اسم الخدمة الافتراضي —') as ar,
       coalesce(label ->> 'en', '— default —') as en,
       coalesce(label ->> 'fr', '— default —') as fr,
       coalesce(label ->> 'ur', '— default —') as ur
  from public.pack_services
 where pack_key = 'finance'
 order by sort_order;

-- تحقق (2): الصلاحية مسجلة، ولا حزمة اخرى اخذت الخدمة
select (select count(*) from public.department_services where service = 'invoices') as salahiyat_invoices,
       (select count(*) from public.pack_services where service = 'invoices' and pack_key <> 'finance') as huzam_ukhra,
       (select count(*) from public.pack_services where pack_key = 'finance') as khadamat_finance;
