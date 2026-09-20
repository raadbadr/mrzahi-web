-- المهندس رعد 2026-09-17: واجهة الموارد البشرية اليوم ليست واجهة موارد بشرية،
-- بل انواع اللوحات العامة نفسها بتسميات: team باسم «الموظفون»، و expenses باسم
-- «الرواتب والمصاريف»، و documents باسم «العقود والوثائق». فمن يفتح «الموظفون»
-- يجد صفحة الفريق التي تشترط حسابا في النظام ودعوة بريد، والموظف لا يلزم ان
-- يكون له حساب اصلا. ولا حقل واحد خاص بالموارد البشرية: لا رقم وظيفي، ولا قسم،
-- ولا نوع تعاقد، ولا اقامة، ولا عقد، ولا مرحلة توظيف.
--
-- شاشة «الموظفون» نوع لوحة متخصص (staff) على نمط «العقود» في المحاماة و«صحتي»
-- في الشخصي: بطاقة الموظف باسمه عربيا وانجليزيا ورقمه الوظيفي وجواله وقسمه
-- ومسماه ونوع تعاقده وتاريخ تعيينه وراتبه الاساسي، وهويته او اقامته برقمها
-- وتاريخ انتهائها، وعقده وتاريخ انتهائه، ومرحلته من مرشح الى انتهاء الخدمة.
-- وانتهاء الاقامة او العقد يصير موعد العنصر (items.due_at) فيظهر في التقويم
-- وفي المربعات وينبه على Telegram كبقية العناصر، بلا مسار تنبيه جديد.
--
-- الخدمة في حزمة hr وحدها (packOnly في الشريط الجانبي)، فلا تظهر عند غيرها.
-- وواجهات المحاماة والشخصي والمبيعات لا تمس باي حرف.
--
-- ملاحظة على تسمية team في حزمة hr: كانت «الموظفون»، وهي تسمية تخفي اسم الخدمة
-- الاصلي «الفريق» وهو ما يمنعه ترحيل 0134. وبدخول شاشة «الموظفون» صار الاسمان
-- متطابقين في الشريط الواحد. فترفع التسمية فيعود «الفريق» باسمه، ويبقى مكانه
-- وترتيبه ولا يحذف منه شيء. استرجاعها سطر واحد ان امر المهندس رعد بغيره.

begin;

-- الصلاحية: شؤون الموظفين عمل الموارد البشرية. والمالك والمدير وقسم الادارة
-- ياخذون اتحاد الخدمات كلها في my_services فلا يحتاجون صفا خاصا.
insert into public.department_services (department, service) values
  ('hr', 'staff')
on conflict do nothing;

-- الخدمة في حزمة hr وحدها، اول الشريط بعد لوحة التحكم
insert into public.pack_services (pack_key, service, sort_order, label) values
  ('hr', 'staff', 2, jsonb_build_object(
     'ar', 'الموظفون', 'en', 'Employees', 'fr', 'Employes', 'ur', 'ملازمین'))
on conflict (pack_key, service) do update set sort_order = excluded.sort_order, label = excluded.label;

-- بقية خدمات الحزمة تنزل مرتبة واحدة، بلا حذف ولا اخفاء
update public.pack_services set sort_order = 3 where pack_key = 'hr' and service = 'team';
update public.pack_services set sort_order = 4 where pack_key = 'hr' and service = 'expenses';
update public.pack_services set sort_order = 5 where pack_key = 'hr' and service = 'documents';
update public.pack_services set sort_order = 6 where pack_key = 'hr' and service = 'processes';
update public.pack_services set sort_order = 7 where pack_key = 'hr' and service = 'settings';

-- «الفريق» يعود باسمه فلا اسمان متطابقان في شريط واحد (قاعدة ترحيل 0134)
update public.pack_services set label = null where pack_key = 'hr' and service = 'team';

commit;

-- تحقق: staff في حزمة hr وحدها، وترتيب الشريط، والصلاحية مسجلة
select (select string_agg(service || ':' || sort_order, ', ' order by sort_order)
          from public.pack_services where pack_key = 'hr') as khidmat_hr,
       (select string_agg(pack_key, ',' order by pack_key)
          from public.pack_services where service = 'staff') as huzam_staff,
       (select string_agg(department, ',' order by department)
          from public.department_services where service = 'staff') as aqsam_staff;
