-- 0170 — المهندس رعد 2026-09-22: «سوي صفحة اجتماعات في الشريط لكل الاقسام».
-- صفحة «الاجتماعات» (dashboard.html?type=meetings) تدخل الشريط الجانبي عبر
-- NAV_ITEMS، والشريط يحجب ما لا تسمح به my_services، وهي تقرا department_services
-- لا pack_services. فتضاف خدمة meetings لكل قسم. وترتيبها في الشريط يتبع
-- pack_services.sort_order، وكانت في 0147/0169 بعد الاعدادات؛ فتقدم قبل
-- الاعدادات في كل حزمة كي لا تظهر الصفحة تحت «الاعدادات».
begin;

insert into public.department_services (department, service)
select d.department, 'meetings'
  from (select distinct department from public.department_services) d
 where not exists (select 1 from public.department_services x
                    where x.department = d.department and x.service = 'meetings');

-- الاجتماعات تاخذ مرتبة الاعدادات، والاعدادات تتاخر مرتبة واحدة
update public.pack_services m
   set sort_order = s.sort_order
  from public.pack_services s
 where s.pack_key = m.pack_key and s.service = 'settings'
   and m.service = 'meetings' and m.sort_order > s.sort_order;

update public.pack_services s
   set sort_order = s.sort_order + 1
 where s.service = 'settings'
   and exists (select 1 from public.pack_services m
                where m.pack_key = s.pack_key and m.service = 'meetings' and m.sort_order = s.sort_order);

-- تسمية الخدمة تترك فارغة: الشريط يقول «الاجتماعات» من NAV_ITEMS كاخوته
-- («المستندات»، «الفريق»)، وفلتر التقويم يقول «اجتماعات» من قاموسه كاخوته
-- («قضايا»، «مخالفات»)؛ التسمية الواحدة كانت تفرض كلمة واحدة على الموضعين.
update public.pack_services set label = null where service = 'meetings' and label is not null;

commit;

select department, string_agg(service, ',' order by service) from public.department_services group by department order by department;
select pack_key, string_agg(service || ':' || sort_order, ', ' order by sort_order, service) from public.pack_services group by pack_key order by pack_key;
