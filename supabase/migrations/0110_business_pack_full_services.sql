-- الترحيل كما طبق على Supabase (version 20260905223723, name business_pack_full_services); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- «الواجهة الحالية تنفع لكيان قانوني أو إدارة قانونية أو شركة كاملة عادي» (المهندس رعد):
-- فالكيان التجاري يأخذ الخدمات التسع نفسها، والفرق بينه وبين الإدارة القانونية في الاسم والتعريف.
delete from public.pack_services where pack_key = 'business';
insert into public.pack_services (pack_key, service, sort_order, label) values
 ('business','dashboard',1,null), ('business','cases',2,null), ('business','violations',3,null),
 ('business','expenses',4,null), ('business','documents',5,null), ('business','processes',6,null),
 ('business','risks',7,null), ('business','team',8,null), ('business','settings',9,null);

update public.ui_packs
   set hints = '{"ar":"وثيقة عمل حر أو مؤسسة أو شركة كاملة: كل الخدمات","en":"Freelance permit, establishment or full company: every service","fr":"Permis freelance, etablissement ou societe complete : tous les services","ur":"فری لانس اجازت نامہ، ادارہ یا مکمل کمپنی: تمام خدمات"}'
 where key = 'business';
