-- 0166 — المهندس رعد 2026-09-20: «كيف الكل يطلع على القضايا والقضايا مايطلع شي»،
-- ثم «نفذ (ب)».
-- مربعات الرئيسية تعد كل الانواع (count.open/due7/overdue/done على كل عناصر
-- المنشاة)، لكن 0155 سماها بكلمة نوع واحد: «قضايا مفتوحة» في المحاماة وهي
-- 13 عنصرا لا قضية بينها، و«مشاريع جارية» و«حملات قائمة» و«صفقات مفتوحة»
-- و«مستحقات قائمة» كذلك. ومنذ 2026-09-20 تتبع المربعات فلتر التقويم، فحين
-- يختار المستخدم «قضايا» يقرا «قضايا مفتوحة 0» تحت الرقم نفسه الذي قال 13 مع
-- «الكل». الارقام صادقة والكلمة كاذبة.
-- الاصلاح: كلمات «الكل» لا تسمي نوعا: «اعمال مفتوحة / مواعيد خلال 7 ايام /
-- متاخرة عن موعدها / اغلقت» وما يوازيها في كل حزمة، بالاربع لغات بلا تشكيل.
-- الايقونات والمقاييس كما هي (jsonb_set على التسمية وحدها). كلمة النوع
-- («قضايا مفتوحة»، «مخالفات مفتوحة») تظهر مع الفلتر من الشيفرة (tileWord) لا
-- من هنا. business و design و hr و individual لا تصادم فيها فلم تمس.
begin;

create or replace function pg_temp.tile_words(p_key text, p0 jsonb, p1 jsonb, p2 jsonb, p3 jsonb)
returns void language plpgsql as $$
begin
  update public.ui_packs
     set tiles = jsonb_set(jsonb_set(jsonb_set(jsonb_set(tiles,
                   '{default,0,label}', p0, false),
                   '{default,1,label}', p1, false),
                   '{default,2,label}', p2, false),
                   '{default,3,label}', p3, false)
   where key = p_key
     and jsonb_array_length(tiles->'default') = 4;
  if not found then
    raise exception 'ui_packs.tiles for % is not the four-tile default expected by 0166', p_key;
  end if;
end $$;

-- المحاماة: كانت «قضايا مفتوحة / جلسات خلال 7 ايام»
select pg_temp.tile_words('legal',
  '{"ar": "اعمال مفتوحة", "en": "Open work", "fr": "Travaux ouverts", "ur": "کھلے امور"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "اغلقت", "en": "Closed", "fr": "Cloturees", "ur": "بند شدہ"}');

-- الهندسة: كانت «مشاريع جارية / تسليمات خلال 7 ايام / تاخر تسليمها / سلمت»
select pg_temp.tile_words('engineer',
  '{"ar": "اعمال جارية", "en": "Work in progress", "fr": "Travaux en cours", "ur": "جاری کام"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "انجزت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}');

-- التسويق: كانت «حملات قائمة / تنطلق خلال 7 ايام / تاخر اطلاقها / انتهت»
select pg_temp.tile_words('marketing',
  '{"ar": "اعمال قائمة", "en": "Active work", "fr": "Travaux actifs", "ur": "جاری کام"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "انتهت", "en": "Finished", "fr": "Terminees", "ur": "ختم"}');

-- المشتريات: كانت «اوامر شراء قائمة / توريدات خلال 7 ايام / تاخر توريدها / استلمت»
select pg_temp.tile_words('procurement',
  '{"ar": "اعمال قائمة", "en": "Active work", "fr": "Travaux actifs", "ur": "جاری کام"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "انجزت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}');

-- التدريب: كانت «برامج قائمة / حصص خلال 7 ايام / حصص فاتت / اكتملت»
select pg_temp.tile_words('trainer',
  '{"ar": "اعمال قائمة", "en": "Active work", "fr": "Travaux actifs", "ur": "جاری کام"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "اكتملت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}');

-- العيادة: كانت «مراجعون قيد المتابعة / مواعيد خلال 7 ايام / مواعيد فاتت / انتهت متابعتهم»
select pg_temp.tile_words('clinic',
  '{"ar": "اعمال قيد المتابعة", "en": "Work in follow-up", "fr": "Travaux en suivi", "ur": "زیر پیروی کام"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "مواعيد فاتت", "en": "Missed dates", "fr": "Echeances manquees", "ur": "چھوٹی تاریخیں"}',
  '{"ar": "انجزت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}');

-- المبيعات: كانت «صفقات مفتوحة / متابعات خلال 7 ايام / فاتت متابعتها / اغلقت»
select pg_temp.tile_words('sales',
  '{"ar": "اعمال مفتوحة", "en": "Open work", "fr": "Travaux ouverts", "ur": "کھلے امور"}',
  '{"ar": "مواعيد خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}',
  '{"ar": "اغلقت", "en": "Closed", "fr": "Conclues", "ur": "بند شدہ"}');

-- المالية: كانت «مستحقات قائمة / تستحق خلال 7 ايام / تجاوزت موعدها / سددت»
select pg_temp.tile_words('finance',
  '{"ar": "اعمال قائمة", "en": "Active work", "fr": "Travaux actifs", "ur": "جاری کام"}',
  '{"ar": "تستحق خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeance sous 7 jours", "ur": "سات دن میں واجب"}',
  '{"ar": "تجاوزت موعدها", "en": "Past due", "fr": "Echues", "ur": "میعاد گزر گئی"}',
  '{"ar": "انجزت", "en": "Completed", "fr": "Terminees", "ur": "مکمل"}');

commit;

select key, tiles->'default'->0->'label'->>'ar' as t0, tiles->'default'->1->'label'->>'ar' as t1,
       tiles->'default'->2->'label'->>'ar' as t2, tiles->'default'->3->'label'->>'ar' as t3
  from public.ui_packs where tiles is not null order by key;
