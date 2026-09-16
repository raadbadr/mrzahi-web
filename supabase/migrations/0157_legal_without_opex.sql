-- المهندس رعد 2026-09-17: «مصاريف التشغيل في الشركات شيلها من واجهة المحاماة،
-- مالها دخل، دي خاصة بالاعمال ومالية الشركة»، ثم: «المصاريف اللي تظهر في واجهة
-- المحاماة تخص المخالفات والغرامات».
--
-- فخدمة expenses تخرج من حزمة legal وحدها. مالها في عمل المحامي هو غرامات
-- المخالفات، وهي في شاشة المخالفات باصل مبالغها لا في شاشة مصاريف التشغيل.
-- بقية الحزم لا تمس (الاعمال والعيادة والمهندس وغيرها تبقى كما هي).
-- وحين كتب هذا الترحيل لم يكن اي حساب على حزمة legal، فلا بيانات تخفى باخراجها.

begin;

delete from public.pack_services
 where pack_key = 'legal' and service = 'expenses';

commit;

-- تحقق: expenses خرجت من legal وبقيت في غيرها
select (select count(*) from public.pack_services where pack_key = 'legal' and service = 'expenses') as fi_legal,
       (select count(*) from public.pack_services where service = 'expenses') as fi_baqi_al_huzam;
