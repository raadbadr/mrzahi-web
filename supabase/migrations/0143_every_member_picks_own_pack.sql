-- 0143 — المهندس رعد 2026-09-16: «اي شي فيه شركة وفيه اعضاء لازم يكون قادر على
-- تغيير الواجهة، والمدير يقدر يعطيه ايش الواجهة اللي يدخل عليها».
-- الموظف العادي في القسم الهندسي يرى واجهة الهندسة: يختارها بنفسه، او يعينها
-- له مديره فتظهر عنده. فتحت set_my_pack لكل عضو نشط بدل المالك والمدير وحدهما؛
-- وواجهة الحساب كله (set_org_pack) تبقى للمالك والمدير كما كانت.
begin;

create or replace function public.set_my_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select entity_type into v_entity from public.org_profiles where org_id = p_org;
  perform public.pack_guard(v_entity, p_pack);
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  update public.org_members set ui_pack = p_pack
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  return public.pack_for_member(p_org, auth.uid());
end $function$;

-- الحزمة الافتراضية للحساب بلا نوع تصير «أعمال» لا «شخصي»: كل دوال القاعدة
-- تعامل الحساب المجهول النوع بـ coalesce(entity_type,'company')، والافتراضي
-- وحده كان يقول «شخصي»، فكان حساب فيه اربعة اعضاء يعمل على واجهة شخص واحد.
update public.ui_packs set is_default = false where is_default and key <> 'business';
update public.ui_packs set is_default = true where key = 'business';

commit;
