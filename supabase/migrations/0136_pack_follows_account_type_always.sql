-- 0136 — الواجهة تتبع نوع الحساب، ولا يختارها المستخدم يدويا.
-- أمر المهندس رعد 2026-09-16: «اذا اخترت شخصي خلاص يحولني على واجهة الشخصي،
-- واذا اخترت الشركة او المنشاة خلاص يحولني على الشركة او المنشاة، ولكن يفضل
-- الحساب الشخصي موجود». فاختيار نوع الحساب هو القرار الوحيد، والواجهة نتيجته.
begin;

-- حين يتغير نوع الحساب (أو ينشأ) تسقط أي حزمة لا تناسب النوع الجديد، فتعود
-- pack_for إلى الحزمة المناسبة له: شخصي ← الواجهة الشخصية، وشركة أو مؤسسة أو
-- وثيقة عمل حر ← واجهة الأعمال. entity_choices في ui_packs هي المرجع.
create or replace function public.pack_follows_entity()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if tg_op = 'UPDATE' and new.entity_type is not distinct from old.entity_type then
    return new;
  end if;
  if new.ui_pack is not null and not exists (
       select 1 from public.ui_packs u
        where u.key = new.ui_pack and u.active
          and coalesce(new.entity_type, 'company') = any (u.entity_choices)) then
    new.ui_pack := null;
  end if;
  return new;
end $function$;
drop trigger if exists org_profiles_pack_follows on public.org_profiles;
create trigger org_profiles_pack_follows before insert or update on public.org_profiles
  for each row execute function public.pack_follows_entity();

-- وتجاوزات الأعضاء التي لا تناسب النوع الجديد تسقط معها، وإلا بقي العضو يرى
-- واجهة حساب لم يعد قائما.
create or replace function public.clear_member_packs_on_entity_change()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.entity_type is distinct from old.entity_type then
    update public.org_members m set ui_pack = null
     where m.org_id = new.org_id and m.ui_pack is not null
       and not exists (select 1 from public.ui_packs u
                        where u.key = m.ui_pack and u.active
                          and coalesce(new.entity_type, 'company') = any (u.entity_choices));
  end if;
  return new;
end $function$;
drop trigger if exists org_profiles_clear_member_packs on public.org_profiles;
create trigger org_profiles_clear_member_packs after update on public.org_profiles
  for each row execute function public.clear_member_packs_on_entity_change();

-- تصحيح ما لا يناسب نوعه اليوم: وزارة الحج والعمرة حسابها شخصي وواجهتها تدريب.
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
