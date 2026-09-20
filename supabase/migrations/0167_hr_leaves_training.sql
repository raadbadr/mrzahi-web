-- المهندس رعد 2026-09-20: «نحتاج نشتغل على واجهة الموارد البشرية اليوم بحيث تكون
-- افضل وجاهزة لقسم الموارد، بحيث يقدر موظف الموارد يضيف معلومات الموظف: اسمه
-- وراتبه ووظيفته ودوراته ومؤهلاته، يعني كل الذي يحتاجه كموظف موارد، واجازاته
-- والموافقات عليها والمرضية».
--
-- ترحيل 0162 اعطى حزمة hr خدمة «الموظفون» (staff) صفا في القاعدة ولم تكتب لها
-- شاشة في الواجهة حتى اليوم. هذا الترحيل يكمل الحزمة بخدمتين على النمط نفسه
-- (نوع لوحة في dashboard.html، لا صفحة ولا جدول ولا عمود جديد، وكل الحقول في
-- items.data كما تفعل العقود والفواتير):
--   leaves   «الاجازات»: الموظف ونوع الاجازة (سنوية، مرضية، اضطرارية، بلا راتب،
--            امومة، ابوة، زواج، وفاة، حج، دراسية) ومن والى وعدد الايام وتاريخ
--            المباشرة، والاعتماد (بانتظار الاعتماد / معتمدة / مرفوضة / ملغاة)
--            ومن اعتمدها ومتى. يوم بدايتها هو due_at فتدخل التقويم والمربعات
--            وتنبيهات Telegram بلا مسار تنبيه جديد. والاعتماد يقود status:
--            بانتظار الاعتماد = open، معتمدة = done، مرفوضة او ملغاة = cancelled،
--            فتعد المربعات ما ينتظر قرارا لا ما اعتمد ومضى.
--   training «الدورات والمؤهلات»: الموظف ونوع السجل (دورة تدريبية، مؤهل علمي،
--            شهادة مهنية) والجهة المانحة والتاريخ والساعات والدرجة والتخصص
--            وانتهاء الشهادة. الدورة القادمة موعدها due_at، وما مضى يذكر بانتهاء
--            شهادته ان كان لها انتهاء.
-- والموظف نفسه (staff): العنوان اسمه، case_number رقمه الوظيفي (تسمية الحزمة
-- «الرقم الوظيفي» منذ 0113)، amount راتبه الاجمالي، و due_at اقرب انتهاء لاقامته
-- او عقده. ورصيد اجازته السنوية يحسب من ايام السنوية المعتمدة في السنة.
--
-- الخدمتان في حزمة hr وحدها (packOnly في الشريط الجانبي) فلا تظهران عند غيرها،
-- وبقية الحزم لا تمس بحرف. وحين كتب هذا الترحيل لم يكن اي حساب على حزمة hr
-- (org_profiles.ui_pack = hr: صفر) فلا ترتيب يتبدل تحت يد مستخدم.

begin;

-- 1) الصلاحية في القاعدة لا في الشيفرة: الاجازات والدورات عمل الموارد البشرية،
--    والمالك والمدير وقسم الادارة ياخذون اتحاد الخدمات كلها في my_services.
insert into public.department_services (department, service) values
  ('hr', 'leaves'),
  ('hr', 'training')
on conflict do nothing;

-- 2) الخدمتان في حزمة hr وحدها بعد «الموظفون» مباشرة، بالاربع لغات
insert into public.pack_services (pack_key, service, sort_order, label) values
  ('hr', 'leaves', 3, jsonb_build_object(
     'ar', 'الاجازات', 'en', 'Leaves', 'fr', 'Conges', 'ur', 'چھٹیاں')),
  ('hr', 'training', 4, jsonb_build_object(
     'ar', 'الدورات والمؤهلات', 'en', 'Training and qualifications',
     'fr', 'Formations et diplomes', 'ur', 'کورسز اور قابلیت'))
on conflict (pack_key, service) do update
   set sort_order = excluded.sort_order, label = excluded.label;

-- 3) بقية خدمات الحزمة تنزل درجتين خلفهما. لا خدمة تحذف ولا تخفى.
update public.pack_services set sort_order = 5 where pack_key = 'hr' and service = 'team';
update public.pack_services set sort_order = 6 where pack_key = 'hr' and service = 'expenses';
update public.pack_services set sort_order = 7 where pack_key = 'hr' and service = 'documents';
update public.pack_services set sort_order = 8 where pack_key = 'hr' and service = 'processes';
update public.pack_services set sort_order = 9 where pack_key = 'hr' and service = 'settings';

-- 4) مربعات hr كانت «طلبات مفتوحة / تستحق خلال 7 ايام / تاخرت / انجزت» وهي تعد
--    الموظفين والاجازات والدورات معا، فتسمى بكلمة لا تسمي نوعا كما فعل 0166 لبقية
--    الحزم. الايقونات والمقاييس كما هي.
update public.ui_packs
   set tiles = jsonb_set(jsonb_set(jsonb_set(jsonb_set(tiles,
                 '{default,0,label}', '{"ar": "سجلات مفتوحة", "en": "Open records", "fr": "Dossiers ouverts", "ur": "کھلے ریکارڈ"}', false),
                 '{default,1,label}', '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}', false),
                 '{default,2,label}', '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}', false),
                 '{default,3,label}', '{"ar": "انجزت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}', false)
 where key = 'hr'
   and jsonb_array_length(tiles->'default') = 4;

commit;

-- تحقق (1): ترتيب خدمات hr وتسمياتها بعد الترحيل
select service, sort_order, coalesce(label ->> 'ar', '— اسم الخدمة الافتراضي —') as ar
  from public.pack_services
 where pack_key = 'hr'
 order by sort_order;

-- تحقق (2): الصلاحيتان مسجلتان، ولا حزمة اخرى اخذت الخدمتين، ومربعات hr بالكلمة الجديدة
select (select count(*) from public.department_services where service in ('leaves', 'training')) as salahiyat,
       (select count(*) from public.pack_services where service in ('leaves', 'training') and pack_key <> 'hr') as huzam_ukhra,
       (select tiles->'default'->0->'label'->>'ar' from public.ui_packs where key = 'hr') as murabba_hr;
