-- المهندس رعد 2026-09-17: «كيف سار عندي 19 شركة».
--
-- العدد ليس خطا: على القاعدة 19 حسابا = 15 مساحة شخصية + 3 شركات + حساب بلا
-- بطاقة. لكن لوحة الادارة عرضتها كلها في بطاقة «الشركات» لان فصلها يقرا
-- org_profiles.entity_type، وسياسة قراءة org_profiles تقصرها على حسابات
-- العضو نفسه: مدير المنصة يرى 19 منشاة في organizations (سياستها تسمح له)
-- ولا يرى الا بطاقتين في org_profiles، فيعود النوع فارغا فيقع الكل في
-- «الشركات».
--
-- الاصلاح: مدير المنصة يقرا بطاقات الجهات كما يقرا الجهات نفسها، بالقراءة
-- وحدها. لا يكتب ولا يعدل: سياسة التعديل تبقى is_org_admin كما هي.

begin;

drop policy if exists org_profiles_read on public.org_profiles;
create policy org_profiles_read on public.org_profiles for select
  using (org_id in (select public.current_org_ids()) or public.is_platform_admin());

commit;
