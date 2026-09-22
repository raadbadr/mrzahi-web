-- 0169 — المهندس رعد 2026-09-22: «ضيف اجتماعات لكل الاقسام لانو دا شي عام».
-- خدمة «اجتماعات» كانت لحزمة المحاماة وحدها (0147) فلا يظهر فلتر الاجتماعات
-- في تقويم بقية الحزم ولا تصنف عناصرها اجتماعات ولا يحمل قالب الاستيراد
-- ورقتها. تضاف الى كل حزمة في ui_packs بالتسمية نفسها بالاربع لغات، في آخر
-- ترتيب الحزمة كما هي في المحاماة (بعد الاعدادات؛ لا عنصر لها في الشريط
-- الجانبي فلا يتغير الشريط، والفلتر يتبع الترتيب). المحاماة كما هي.
begin;

insert into public.pack_services (pack_key, service, sort_order, label)
select p.key, 'meetings',
       coalesce((select max(s.sort_order) from public.pack_services s where s.pack_key = p.key), 0) + 1,
       jsonb_build_object('ar', 'اجتماعات', 'en', 'Meetings', 'fr', 'Reunions', 'ur', 'میٹنگز')
  from public.ui_packs p
 where not exists (select 1 from public.pack_services s where s.pack_key = p.key and s.service = 'meetings');

commit;

select pack_key, sort_order, label->>'ar' as ar
  from public.pack_services where service = 'meetings' order by pack_key;
