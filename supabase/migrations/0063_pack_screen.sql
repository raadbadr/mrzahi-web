-- الحزمة تكتب الشاشة: خانات إعداد على ui_packs — الفارغ يعني «ابق على ما في الشيفرة اليوم».
-- طُبقت على القاعدة في الجلسة نفسها (migration: pack_screen_tiles_and_columns).
alter table public.ui_packs add column if not exists views        jsonb;
alter table public.ui_packs add column if not exists tiles        jsonb;
alter table public.ui_packs add column if not exists list_columns jsonb;
alter table public.ui_packs add column if not exists form         jsonb;
alter table public.ui_packs add column if not exists papers       jsonb;
alter table public.ui_packs add column if not exists bot          jsonb;

-- my_pack_config ترسل الخانات الست مع ما كانت ترسله، في النداء نفسه، فلا خطوة إقلاع جديدة ولا وميض.
-- (النص الكامل في سجل الهجرات الحي؛ التوقيع والصلاحيات كما هي: revoke من public وgrant للموثق.)

-- لوحة الشخص: مربعاته الأربعة وأعمدة قائمته وحقول نموذجه. لا سطر يمس صف الإدارة القانونية.
update public.ui_packs set
  tiles = '{"default":[
     {"metric":"count.open","icon":"list","accent":"users","label":{"ar":"مهامي المفتوحة","en":"My open tasks","fr":"Mes taches ouvertes","ur":"میرے کھلے کام"}},
     {"metric":"count.due7","icon":"calendar","accent":"spots","label":{"ar":"خلال 7 ايام","en":"Within 7 days","fr":"Sous 7 jours","ur":"سات دن میں"}},
     {"metric":"count.papers_expiring","icon":"bell","accent":"overdue","label":{"ar":"اوراق تنتهي قريبا","en":"Papers expiring soon","fr":"Papiers expirant bientot","ur":"جلد ختم ہونے والے کاغذات"}},
     {"metric":"count.done","icon":"check","accent":"cars","label":{"ar":"انجزت","en":"Done","fr":"Terminees","ur":"مکمل"}}
   ]}'::jsonb,
  list_columns = '{"default":[
     {"cell":"title+category","label":{"ar":"العنصر","en":"Item","fr":"Element","ur":"آئٹم"}},
     {"cell":"due+left","label":{"ar":"الموعد","en":"Due","fr":"Echeance","ur":"آخری تاریخ"}},
     {"cell":"status","label":{"ar":"الحالة","en":"Status","fr":"Statut","ur":"حالت"}},
     {"cell":"actions","label":{"ar":"الإجراءات","en":"Actions","fr":"Actions","ur":"اقدامات"}}
   ]}'::jsonb,
  form = '{"hide":["assignee","client_en","case_number"]}'::jsonb
 where key = 'individual';
