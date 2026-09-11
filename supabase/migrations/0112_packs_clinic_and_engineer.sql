-- الترحيل كما طبق على Supabase (version 20260905224417, name packs_clinic_and_engineer); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- ست واجهات باختيار واحد عند إنشاء الحساب (المهندس رعد 2026-09-06):
-- شخص، شركة، مدرب، محامي، عيادة، مهندس. الحزمتان الجديدتان صفا بيانات لا شيفرة — وهذا اختبار المعمارية.
insert into public.ui_packs (key, names, hints, icon, sort_order, entity_default, entity_choices, labels, active, is_default) values
 ('legal',
  '{"ar":"محاماة وإدارة قانونية","en":"Law practice or legal department","fr":"Cabinet ou service juridique","ur":"وکالت یا قانونی شعبہ"}',
  '{"ar":"للمحامي والمكتب والإدارة القانونية: قضايا ومخالفات ومستندات وفريق وإجراءات ومخاطر","en":"For a lawyer, a firm or a legal department: cases, violations, documents, team, processes and risks","fr":"Pour un avocat, un cabinet ou un service juridique : affaires, infractions, documents, equipe","ur":"وکیل، فرم یا قانونی شعبے کے لیے: مقدمات، خلاف ورزیاں، دستاویزات، ٹیم"}',
  'M12 3l9 4v6c0 5.25-3.75 10.15-9 11.5C6.75 23.15 3 18.25 3 13V7l9-4zm-1 6v2H9v2h2v2h2v-2h2v-2h-2V9h-2z',
  4, 'company', '{company,establishment,nonprofit,government,freelance,individual}', '{}', true, true),
 ('clinic',
  '{"ar":"عيادة","en":"Clinic","fr":"Cabinet medical","ur":"کلینک"}',
  '{"ar":"مواعيد المراجعين وتراخيص المنشأة وفواتيرها وطاقمها","en":"Patient appointments, facility licences, invoices and staff","fr":"Rendez-vous, licences, factures et personnel","ur":"مریضوں کی اپائنٹمنٹس، لائسنس، رسیدیں اور عملہ"}',
  'M19 8h-2V3H7v5H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2v-9a2 2 0 00-2-2zM9 5h6v3H9V5zm4 11h-2v2h-2v-2H7v-2h2v-2h2v2h2v2z',
  5, 'establishment', '{establishment,company,freelance}',
  '{"fieldClient":{"ar":"المراجع","en":"Patient","fr":"Patient","ur":"مریض"},"fieldCaseNumber":{"ar":"رقم الملف الطبي","en":"Medical record number","fr":"Numero de dossier medical","ur":"طبی ریکارڈ نمبر"}}',
  true, false),
 ('engineer',
  '{"ar":"مهندس أو مكتب هندسي","en":"Engineer or engineering office","fr":"Ingenieur ou bureau d''etudes","ur":"انجینئر یا انجینئرنگ آفس"}',
  '{"ar":"مشاريعك ومستخلصاتها ورخصها ومخاطرها وفريقها","en":"Your projects, payment claims, permits, risks and team","fr":"Vos projets, decomptes, permis, risques et equipe","ur":"آپ کے منصوبے، ادائیگیاں، اجازت نامے، خطرات اور ٹیم"}',
  'M22 9L12 2 2 9h3v11h5v-6h4v6h5V9h3zm-9 3h-2v-2h2v2z',
  6, 'establishment', '{establishment,company,freelance}',
  '{"fieldClient":{"ar":"المالك أو الجهة","en":"Owner or client","fr":"Maitre d''ouvrage","ur":"مالک یا ادارہ"},"fieldCaseNumber":{"ar":"رقم المشروع","en":"Project number","fr":"Numero de projet","ur":"منصوبے کا نمبر"}}',
  true, false)
on conflict (key) do update set
  names = excluded.names, hints = excluded.hints, icon = excluded.icon, sort_order = excluded.sort_order,
  entity_default = excluded.entity_default, entity_choices = excluded.entity_choices, labels = excluded.labels,
  active = excluded.active, is_default = excluded.is_default;

delete from public.pack_services where pack_key in ('clinic','engineer');
insert into public.pack_services (pack_key, service, sort_order, label) values
 -- عيادة: النواة ثم المواعيد والطاقم
 ('clinic','dashboard',1,null),
 ('clinic','cases',2,'{"ar":"المراجعون والمواعيد","en":"Patients and appointments","fr":"Patients et rendez-vous","ur":"مریض اور اپائنٹمنٹس"}'),
 ('clinic','expenses',3,'{"ar":"الفواتير والمصاريف","en":"Invoices and expenses","fr":"Factures et depenses","ur":"رسیدیں اور اخراجات"}'),
 ('clinic','documents',4,'{"ar":"التراخيص والمستندات","en":"Licences and documents","fr":"Licences et documents","ur":"لائسنس اور دستاویزات"}'),
 ('clinic','team',5,'{"ar":"الطاقم الطبي","en":"Medical staff","fr":"Personnel medical","ur":"طبی عملہ"}'),
 ('clinic','settings',6,null),
 -- مهندس: النواة ثم المشاريع ومخاطرها وفريقها
 ('engineer','dashboard',1,null),
 ('engineer','cases',2,'{"ar":"المشاريع","en":"Projects","fr":"Projets","ur":"منصوبے"}'),
 ('engineer','expenses',3,'{"ar":"المستخلصات والمصاريف","en":"Payment claims and expenses","fr":"Decomptes et depenses","ur":"ادائیگیاں اور اخراجات"}'),
 ('engineer','documents',4,'{"ar":"الرخص والمخططات","en":"Permits and drawings","fr":"Permis et plans","ur":"اجازت نامے اور نقشے"}'),
 ('engineer','risks',5,'{"ar":"مخاطر المشاريع","en":"Project risks","fr":"Risques des projets","ur":"منصوبوں کے خطرات"}'),
 ('engineer','team',6,'{"ar":"فريق المشروع","en":"Project team","fr":"Equipe du projet","ur":"منصوبے کی ٹیم"}'),
 ('engineer','settings',7,null);
