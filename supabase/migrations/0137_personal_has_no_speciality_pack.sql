-- 0137 — الحساب الشخصي واجهته الشخصية وحدها، وواجهات التخصص للكيان التجاري.
-- أمر المهندس رعد 2026-09-16: «اقل حساب عندنا شخصي، دا الطبيعي العادي… بعد كدا
-- الشخص اختار شركة ويبغى واجهة اعمال يبغى واجهة محاماة يغير من داخل الشركة».
-- فالقرار الأول نوع الحساب، وتغيير الواجهة بعده من داخل الكيان التجاري وحده.
-- كانت entity_choices تسمح للحساب الشخصي بواجهات محاماة وتدريب وتصميم، وهو ما
-- يناقض حارس set_org_pack منذ 0072، فيصير المرجع واحدا.
begin;

update public.ui_packs
   set entity_choices = array_remove(entity_choices, 'individual')
 where key <> 'individual' and 'individual' = any (entity_choices);

-- ما خالف القاعدة قبل اليوم يعود إلى واجهة نوعه: حساب شخصي على واجهة تدريب.
update public.org_members m set ui_pack = null
 where m.ui_pack is not null
   and exists (select 1 from public.org_profiles p
                where p.org_id = m.org_id
                  and not exists (select 1 from public.ui_packs u
                                   where u.key = m.ui_pack and u.active
                                     and coalesce(p.entity_type, 'company') = any (u.entity_choices)));
update public.org_profiles p set ui_pack = null
 where p.ui_pack is not null
   and not exists (select 1 from public.ui_packs u
                    where u.key = p.ui_pack and u.active
                      and coalesce(p.entity_type, 'company') = any (u.entity_choices));

commit;
