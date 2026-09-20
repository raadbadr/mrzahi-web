-- 0168 — تصويب كلمات 0166 بعد المراجعة (2026-09-20): العيادة بقي مربعاها الثاني
-- والثالث بالعربية يسميان «المواعيد» وهي خدمة الحزمة نفسها («المراجعون
-- والمواعيد») بينما صارت بقية اللغات عامة؛ والفرنسية: المربع الاول مذكر
-- («Travaux») والرابع كان مؤنثا من 0155 («Cloturees/Terminees/Conclues»)؛
-- والمالية «Echeance» مفردا وبقية الحزم بالجمع. التسمية وحدها، والايقونات
-- والمقاييس كما هي. بلا تشكيل ولا حروف معلمة كما في الصفوف القائمة.
begin;

create or replace function pg_temp.tile_label(p_key text, p_idx int, p_label jsonb)
returns void language plpgsql as $$
begin
  update public.ui_packs
     set tiles = jsonb_set(tiles, array['default', p_idx::text, 'label'], p_label, false)
   where key = p_key
     and jsonb_array_length(tiles->'default') = 4;
  if not found then
    raise exception 'ui_packs.tiles for % is not the four-tile default expected by 0168', p_key;
  end if;
end $$;

-- العيادة: الكلمات الاربع عامة في اللغات الاربع
select pg_temp.tile_label('clinic', 0, '{"ar": "اعمال قيد المتابعة", "en": "Under follow-up", "fr": "Travaux en suivi", "ur": "زیر پیروی کام"}');
select pg_temp.tile_label('clinic', 1, '{"ar": "تستحق خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}');
select pg_temp.tile_label('clinic', 2, '{"ar": "متاخرة عن موعدها", "en": "Past their date", "fr": "En retard", "ur": "تاخیر شدہ"}');
select pg_temp.tile_label('clinic', 3, '{"ar": "انجزت", "en": "Completed", "fr": "Termines", "ur": "مکمل"}');

-- الفرنسية: الرابع مذكر جمع كالاول
select pg_temp.tile_label('legal',       3, '{"ar": "اغلقت", "en": "Closed", "fr": "Clotures", "ur": "بند شدہ"}');
select pg_temp.tile_label('sales',       3, '{"ar": "اغلقت", "en": "Closed", "fr": "Conclus", "ur": "بند شدہ"}');
select pg_temp.tile_label('engineer',    3, '{"ar": "انجزت", "en": "Completed", "fr": "Termines", "ur": "مکمل"}');
select pg_temp.tile_label('marketing',   3, '{"ar": "انتهت", "en": "Finished", "fr": "Termines", "ur": "ختم"}');
select pg_temp.tile_label('procurement', 3, '{"ar": "انجزت", "en": "Completed", "fr": "Termines", "ur": "مکمل"}');
select pg_temp.tile_label('trainer',     3, '{"ar": "اكتملت", "en": "Completed", "fr": "Termines", "ur": "مکمل"}');
select pg_temp.tile_label('finance',     3, '{"ar": "انجزت", "en": "Completed", "fr": "Termines", "ur": "مکمل"}');

-- المالية: الجمع كبقية الحزم
select pg_temp.tile_label('finance', 1, '{"ar": "تستحق خلال 7 ايام", "en": "Due within 7 days", "fr": "Echeances sous 7 jours", "ur": "سات دن میں واجب"}');

commit;

select key, tiles->'default'->0->'label'->>'fr' as fr0, tiles->'default'->1->'label'->>'fr' as fr1,
       tiles->'default'->2->'label'->>'ar' as ar2, tiles->'default'->3->'label'->>'fr' as fr3
  from public.ui_packs where key in ('clinic','legal','sales','engineer','marketing','procurement','trainer','finance') order by key;
