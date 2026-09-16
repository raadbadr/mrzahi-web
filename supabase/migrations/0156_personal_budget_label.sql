-- المهندس رعد 2026-09-17: «شخصي ما ابغى يكون مصاريفي… خليها ميزانيتي».
-- الحزمة الشخصية وحدها: خدمة expenses تسمى «ميزانيتي» بالاربع. بقية الحزم لا تمس
-- (الاعمال تبقى «مصاريف التشغيل»، والعيادة «الفواتير والمصاريف»، وهكذا).
-- التسمية في القاعدة لا في الشيفرة، فيتبعها الشريط الجانبي وفلاتر التقويم وعنوان
-- الشاشة معا بلا لمس ملف.

begin;

update public.pack_services
   set label = jsonb_build_object(
         'ar', 'ميزانيتي',
         'en', 'My budget',
         'fr', 'Mon budget',
         'ur', 'میرا بجٹ')
 where pack_key = 'individual' and service = 'expenses';

commit;

-- تحقق: الحزمة الشخصية وحدها تغيرت، وبالاربع
select pack_key, label ->> 'ar' as ar, label ->> 'en' as en, label ->> 'fr' as fr, label ->> 'ur' as ur
  from public.pack_services
 where service = 'expenses' and pack_key in ('individual', 'business', 'clinic')
 order by pack_key;
