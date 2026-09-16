-- المهندس رعد 2026-09-16: «المفروض الفلتر حسب الواجهة، يعني ليش تظهر قضايا
-- ومخالفات ومهام وانا شخصي»، و«دي تظهر فقط لقسم المحاماة، كل قسم وواجهة ليها
-- فلاتر خاصة مو كلهم نفس الشي».
--
-- فلاتر التقويم كانت خمسة ازرار مكتوبة في dashboard.html نفسها، فرات في كل
-- واجهة بلا استثناء. صارت تبنى من خدمات الحزمة (my_pack_config) بترتيبها
-- وتسميتها، فتحتاج «مهام» و«اجتماعات» صفين هنا لان لا لوحة لهما في الشريط
-- الجانبي: يبقيان لواجهة المحاماة وحدها كما هما اليوم، ولا يظهران في الشخصي
-- ولا في بقية الواجهات.
--
-- لا اثر على الشريط الجانبي: packOrdered لا يعرض الا خدمة لها عنصر في
-- NAV_ITEMS، ولا عنصر لـ tasks ولا لـ meetings.

begin;

insert into public.pack_services (pack_key, service, sort_order, label) values
  ('legal', 'tasks',    10, jsonb_build_object('ar', 'مهام',     'en', 'Tasks',    'fr', 'Taches',   'ur', 'کام')),
  ('legal', 'meetings', 11, jsonb_build_object('ar', 'اجتماعات', 'en', 'Meetings', 'fr', 'Reunions', 'ur', 'میٹنگز'))
on conflict (pack_key, service) do update set sort_order = excluded.sort_order, label = excluded.label;

commit;
