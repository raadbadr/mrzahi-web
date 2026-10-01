-- 0177 — المهندس رعد 2026-10-01: «نحتاج نضيف الية onboarding، offboarding، payroll،
-- حضور وانصراف ويكون مربوط مع الاجهزة او التطبيق، كلو على قسم الموارد البشرية».
-- القسمة بين الوكلاء: الرواتب (0175 و0176) والحضور (0178) لوكيل «تفضيل اللغة
-- الثابت»، والالتحاق وانهاء الخدمة هنا.
--
-- شاشتان على نمط «الموظفون» و«الاجازات» (نوع لوحة في dashboard.html، لا صفحة ولا
-- جدول): كل خطوة مهمة عنصر بفئة «مهمة التحاق» او «مهمة انهاء خدمة»، وفي data:
-- hr_task (onboarding|offboarding) و employee_id (عنصر الموظف) و step_code (رمز
-- خطوة الاجراء الجاهز HR-05..HR-11) و step_role (المسؤول عنها). المفتاح hr_task
-- في مشغل items_set_visibility منذ 0173، فالمهام لقسم الموارد البشرية والادارة
-- والمالك والمشرف وحدهم، ولا يراها البوت ولا التقويم الخارجي.
-- والخطوات تولد من الاجراءات الجاهزة نفسها في مكتبة الاجراءات (app/processes/
-- hr-templates.csv) فلا نص مكرر ولا خطوة مخترعة.
--
-- الخدمتان في حزمة hr وحدها (packOnly في الشريط الجانبي)، بعد «العروض الوظيفية»؛
-- والصلاحية لقسم hr (والمالك والمدير وقسم الادارة ياخذون اتحاد الخدمات كلها).
-- التسمية فارغة فيقول الشريط اسمه من NAV_ITEMS بالاربع لغات.
begin;

insert into public.department_services (department, service) values
  ('hr', 'onboarding'), ('hr', 'offboarding')
on conflict do nothing;

-- مكانهما بعد «العروض الوظيفية» (4): ما بعدها يتاخر مرتبتين، مرة واحدة فقط
update public.pack_services set sort_order = sort_order + 2
 where pack_key = 'hr' and sort_order > 4
   and not exists (select 1 from public.pack_services x where x.pack_key = 'hr' and x.service in ('onboarding', 'offboarding'));

insert into public.pack_services (pack_key, service, sort_order, label) values
  ('hr', 'onboarding', 5, null),
  ('hr', 'offboarding', 6, null)
on conflict (pack_key, service) do nothing;

commit;

select service, sort_order from public.pack_services where pack_key = 'hr' order by sort_order;
select department, service from public.department_services where service in ('onboarding', 'offboarding');
