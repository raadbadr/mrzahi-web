-- الترحيل كما طبق على Supabase (version 20260907231221, name process_areas_follow_the_interface); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- مجالات مكتبة الإجراءات تتبع واجهة الحساب. المحاماة لا تُمس إطلاقا: تبقى null فتعمل الشيفرة بمجالاتها الست كما هي.
alter table public.ui_packs add column if not exists processes jsonb;

update public.ui_packs set processes = '[
  {"key":"papers","names":{"ar":"أوراقي","en":"My papers","fr":"Mes papiers","ur":"میرے کاغذات"}},
  {"key":"money","names":{"ar":"مالي","en":"Money","fr":"Argent","ur":"مالی"}},
  {"key":"home","names":{"ar":"المنزل","en":"Home","fr":"Maison","ur":"گھر"}},
  {"key":"health","names":{"ar":"الصحة","en":"Health","fr":"Sante","ur":"صحت"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'individual';

update public.ui_packs set processes = '[
  {"key":"sales","names":{"ar":"المبيعات","en":"Sales","fr":"Ventes","ur":"فروخت"}},
  {"key":"purchasing","names":{"ar":"المشتريات","en":"Purchasing","fr":"Achats","ur":"خریداری"}},
  {"key":"customers","names":{"ar":"العملاء","en":"Customers","fr":"Clients","ur":"گاہک"}},
  {"key":"contracts","names":{"ar":"العقود","en":"Contracts","fr":"Contrats","ur":"معاہدے"}},
  {"key":"papers","names":{"ar":"الأوراق الرسمية","en":"Official papers","fr":"Papiers officiels","ur":"سرکاری کاغذات"}},
  {"key":"finance","names":{"ar":"المالية","en":"Finance","fr":"Finance","ur":"مالیات"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'business';

update public.ui_packs set processes = '[
  {"key":"courses","names":{"ar":"الدورات","en":"Courses","fr":"Formations","ur":"کورسز"}},
  {"key":"trainees","names":{"ar":"المتدربون","en":"Trainees","fr":"Stagiaires","ur":"تربیت لینے والے"}},
  {"key":"materials","names":{"ar":"المادة التدريبية","en":"Material","fr":"Supports","ur":"مواد"}},
  {"key":"contracts","names":{"ar":"العقود","en":"Contracts","fr":"Contrats","ur":"معاہدے"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'trainer';

update public.ui_packs set processes = '[
  {"key":"patients","names":{"ar":"المرضى","en":"Patients","fr":"Patients","ur":"مریض"}},
  {"key":"appointments","names":{"ar":"المواعيد","en":"Appointments","fr":"Rendez-vous","ur":"اپائنٹمنٹس"}},
  {"key":"supplies","names":{"ar":"المستلزمات","en":"Supplies","fr":"Fournitures","ur":"سامان"}},
  {"key":"licenses","names":{"ar":"التراخيص","en":"Licences","fr":"Licences","ur":"لائسنس"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'clinic';

update public.ui_packs set processes = '[
  {"key":"projects","names":{"ar":"المشاريع","en":"Projects","fr":"Projets","ur":"منصوبے"}},
  {"key":"sites","names":{"ar":"المواقع","en":"Sites","fr":"Chantiers","ur":"سائٹس"}},
  {"key":"safety","names":{"ar":"السلامة","en":"Safety","fr":"Securite","ur":"حفاظت"}},
  {"key":"contracts","names":{"ar":"العقود","en":"Contracts","fr":"Contrats","ur":"معاہدے"}},
  {"key":"licenses","names":{"ar":"التراخيص","en":"Licences","fr":"Licences","ur":"لائسنس"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'engineer';

update public.ui_packs set processes = '[
  {"key":"hiring","names":{"ar":"التوظيف","en":"Hiring","fr":"Recrutement","ur":"بھرتی"}},
  {"key":"onboarding","names":{"ar":"الالتحاق","en":"Onboarding","fr":"Integration","ur":"شمولیت"}},
  {"key":"leave","names":{"ar":"الإجازات","en":"Leave","fr":"Conges","ur":"چھٹیاں"}},
  {"key":"payroll","names":{"ar":"الرواتب","en":"Payroll","fr":"Paie","ur":"تنخواہ"}},
  {"key":"performance","names":{"ar":"الأداء","en":"Performance","fr":"Performance","ur":"کارکردگی"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'hr';

update public.ui_packs set processes = '[
  {"key":"invoicing","names":{"ar":"الفوترة","en":"Invoicing","fr":"Facturation","ur":"بلنگ"}},
  {"key":"collection","names":{"ar":"التحصيل","en":"Collection","fr":"Recouvrement","ur":"وصولی"}},
  {"key":"payments","names":{"ar":"المدفوعات","en":"Payments","fr":"Paiements","ur":"ادائیگیاں"}},
  {"key":"budget","names":{"ar":"الموازنة","en":"Budget","fr":"Budget","ur":"بجٹ"}},
  {"key":"closing","names":{"ar":"الإقفال","en":"Closing","fr":"Cloture","ur":"اختتام"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'finance';

update public.ui_packs set processes = '[
  {"key":"leads","names":{"ar":"العملاء المحتملون","en":"Leads","fr":"Prospects","ur":"ممکنہ گاہک"}},
  {"key":"offers","names":{"ar":"العروض","en":"Offers","fr":"Offres","ur":"پیشکشیں"}},
  {"key":"contracts","names":{"ar":"العقود","en":"Contracts","fr":"Contrats","ur":"معاہدے"}},
  {"key":"collection","names":{"ar":"التحصيل","en":"Collection","fr":"Recouvrement","ur":"وصولی"}},
  {"key":"aftersales","names":{"ar":"ما بعد البيع","en":"After sales","fr":"Apres-vente","ur":"فروخت کے بعد"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'sales';

update public.ui_packs set processes = '[
  {"key":"requests","names":{"ar":"طلبات الشراء","en":"Requests","fr":"Demandes","ur":"درخواستیں"}},
  {"key":"suppliers","names":{"ar":"الموردون","en":"Suppliers","fr":"Fournisseurs","ur":"سپلائرز"}},
  {"key":"orders","names":{"ar":"أوامر الشراء","en":"Orders","fr":"Commandes","ur":"آرڈرز"}},
  {"key":"receiving","names":{"ar":"الاستلام","en":"Receiving","fr":"Reception","ur":"وصولی"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'procurement';

update public.ui_packs set processes = '[
  {"key":"campaigns","names":{"ar":"الحملات","en":"Campaigns","fr":"Campagnes","ur":"مہمات"}},
  {"key":"content","names":{"ar":"المحتوى","en":"Content","fr":"Contenu","ur":"مواد"}},
  {"key":"brand","names":{"ar":"الهوية","en":"Brand","fr":"Marque","ur":"برانڈ"}},
  {"key":"events","names":{"ar":"الفعاليات","en":"Events","fr":"Evenements","ur":"تقریبات"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'marketing';

update public.ui_packs set processes = '[
  {"key":"requests","names":{"ar":"طلبات التصميم","en":"Requests","fr":"Demandes","ur":"درخواستیں"}},
  {"key":"design","names":{"ar":"التنفيذ","en":"Design","fr":"Conception","ur":"ڈیزائن"}},
  {"key":"review","names":{"ar":"المراجعة","en":"Review","fr":"Revue","ur":"جائزہ"}},
  {"key":"delivery","names":{"ar":"التسليم","en":"Delivery","fr":"Livraison","ur":"ترسیل"}},
  {"key":"other","names":{"ar":"أخرى","en":"Other","fr":"Autre","ur":"دیگر"}}
]'::jsonb where key = 'design';
