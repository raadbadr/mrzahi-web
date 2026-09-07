-- واجهة المحاماة والإدارة القانونية تكسب شاشتين: الأحكام والعقود.
-- كل واحدة لوحة عناصر بتصنيفها، تماما كالقضايا والمخالفات: لا جدول جديد ولا شاشة جديدة،
-- بل نوع لوحة ثالث ورابع على dashboard.html?type=rulings و type=contracts.

-- الصلاحية للقاعدة: القسم القانوني والإدارة يريان الشاشتين. المالك والمدير يأخذان اتحاد الخدمات كله.
insert into public.department_services (department, service) values
  ('legal', 'rulings'),
  ('legal', 'contracts'),
  ('management', 'rulings'),
  ('management', 'contracts')
on conflict (department, service) do nothing;

-- ترتيب شريط المحاماة: الأحكام بعد القضايا مباشرة، ثم العقود، ثم ما كان على حاله.
update public.pack_services set sort_order = sort_order + 2
 where pack_key = 'legal' and sort_order >= 3;

insert into public.pack_services (pack_key, service, sort_order) values
  ('legal', 'rulings', 3),
  ('legal', 'contracts', 4)
on conflict (pack_key, service) do update set sort_order = excluded.sort_order;
