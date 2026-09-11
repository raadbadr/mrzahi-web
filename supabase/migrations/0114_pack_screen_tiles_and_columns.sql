-- الترحيل كما طبق على Supabase (version 20260905231521, name pack_screen_tiles_and_columns); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- الحزمة تكتب الشاشة: خانات إعداد فارغة تعني «ابق على ما في الشيفرة اليوم».
-- صف الإدارة القانونية يبقى بلا إعلان فلا يتحرك فيه شيء.
alter table public.ui_packs add column if not exists views       jsonb;
alter table public.ui_packs add column if not exists tiles       jsonb;
alter table public.ui_packs add column if not exists list_columns jsonb;
alter table public.ui_packs add column if not exists form        jsonb;
alter table public.ui_packs add column if not exists papers      jsonb;
alter table public.ui_packs add column if not exists bot         jsonb;

create or replace function public.my_pack_config(p_org uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with k as (select public.pack_for(p_org) as key)
  select case when (select key from k) is null then null else jsonb_build_object(
    'pack',       (select key from k),
    'names',      (select names  from public.ui_packs where key = (select key from k)),
    'labels',     (select labels from public.ui_packs where key = (select key from k)),
    'is_default', (select is_default from public.ui_packs where key = (select key from k)),
    'services',   coalesce((select jsonb_agg(jsonb_build_object('service', s.service, 'sort', s.sort_order, 'label', s.label)
                                             order by s.sort_order, s.service)
                            from public.pack_services s where s.pack_key = (select key from k)), '[]'::jsonb),
    'views',        (select views        from public.ui_packs where key = (select key from k)),
    'tiles',        (select tiles        from public.ui_packs where key = (select key from k)),
    'list_columns', (select list_columns from public.ui_packs where key = (select key from k)),
    'form',         (select form         from public.ui_packs where key = (select key from k)),
    'papers',       (select papers       from public.ui_packs where key = (select key from k)),
    'bot',          (select bot          from public.ui_packs where key = (select key from k))
  ) end
  where exists (select 1 from public.org_members m
                 where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active')
$$;
revoke all on function public.my_pack_config(uuid) from public;
grant execute on function public.my_pack_config(uuid) to authenticated;

-- لوحة الشخص: مربعاته الأربعة وأعمدة قائمته وحقول نموذجه
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
