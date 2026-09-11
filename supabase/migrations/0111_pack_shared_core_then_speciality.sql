-- الترحيل كما طبق على Supabase (version 20260905223806, name pack_shared_core_then_speciality); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- «كل الشركات تحتاج لوحة تحكم ومصاريف التشغيل والمستندات، والباقي يفصل حسب كل تخصص» (المهندس رعد 2026-09-06).
-- النواة المشتركة في كل حزمة: لوحة التحكم + مصاريف التشغيل + المستندات + الإعدادات؛ وما بعدها تخصص.
delete from public.pack_services where pack_key in ('individual','business','trainer');
insert into public.pack_services (pack_key, service, sort_order, label) values
 -- شخص: النواة وحدها، بكلماته هو
 ('individual','dashboard',1,'{"ar":"لوحتي","en":"My board","fr":"Mon tableau","ur":"میرا بورڈ"}'),
 ('individual','documents',2,'{"ar":"أوراقي الرسمية","en":"My papers","fr":"Mes papiers","ur":"میرے کاغذات"}'),
 ('individual','expenses',3,'{"ar":"مصاريفي","en":"My expenses","fr":"Mes depenses","ur":"میرے اخراجات"}'),
 ('individual','settings',4,null),
 -- كيان تجاري: النواة ثم الفريق والإجراءات والمخاطر (القضايا والمخالفات تخصص قانوني)
 ('business','dashboard',1,null),
 ('business','expenses',2,null),
 ('business','documents',3,null),
 ('business','team',4,null),
 ('business','processes',5,null),
 ('business','risks',6,null),
 ('business','settings',7,null),
 -- مدرب أو محاضر: النواة بكلمات التدريب، ثم الدورات وفريق التدريب
 ('trainer','dashboard',1,null),
 ('trainer','cases',2,'{"ar":"الدورات","en":"Courses","fr":"Formations","ur":"کورسز"}'),
 ('trainer','expenses',3,'{"ar":"الفواتير والمصاريف","en":"Invoices and expenses","fr":"Factures et depenses","ur":"رسیدیں اور اخراجات"}'),
 ('trainer','documents',4,'{"ar":"الشهادات والمستندات","en":"Certificates and documents","fr":"Attestations et documents","ur":"اسناد اور دستاویزات"}'),
 ('trainer','team',5,'{"ar":"المدربون والمساعدون","en":"Trainers and assistants","fr":"Formateurs et assistants","ur":"ٹرینرز اور معاونین"}'),
 ('trainer','settings',6,null);

update public.ui_packs
   set hints = '{"ar":"وثيقة عمل حر أو مؤسسة أو شركة: لوحة ومصاريف ومستندات وفريق وإجراءات ومخاطر","en":"Freelance permit, establishment or company: board, expenses, documents, team, processes and risks","fr":"Permis freelance, etablissement ou societe : tableau, depenses, documents, equipe, procedures et risques","ur":"فری لانس اجازت نامہ، ادارہ یا کمپنی: بورڈ، اخراجات، دستاویزات، ٹیم، طریقہ کار اور خطرات"}'
 where key = 'business';
