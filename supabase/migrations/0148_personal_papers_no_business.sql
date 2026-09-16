-- 0148 — المهندس رعد 2026-09-16: «اوراقي الرسمية في شخصي المفروض ما فيها اي
-- شي تجاري»، «سجل تجاري عقد تأسيس مدري ايش دي ما تظهر في واجهة شخصي ابدا»،
-- «اذا المستخدم يبغى اشياء تجارية يحول حساب تجاري سواء وثيقة مؤسسة او شركة».
-- واوراقه الشخصية: هوية وجواز ورخصة قيادة واستمارة وتأمين، وتأميناته
-- الاجتماعية، وعقد عمله وشهادات خبرته وسيرته الذاتية، وعقد ايجار سكنه
-- والتزام اقساطه.
begin;

delete from public.required_docs where entity_type = 'individual';

insert into public.required_docs (entity_type, kind, required, renews, sort_order) values
  ('individual', 'id_document',            true,  true,  1),
  ('individual', 'passport',               false, true,  2),
  ('individual', 'driving_license',        false, true,  3),
  ('individual', 'vehicle_registration',   false, true,  4),
  ('individual', 'insurance_policy',       false, true,  5),
  ('individual', 'gosi_certificate',       false, false, 6),
  ('individual', 'employment_contract',    false, false, 7),
  ('individual', 'experience_certificate', false, false, 8),
  ('individual', 'cv',                     false, false, 9),
  ('individual', 'lease_contract',         false, true, 10),
  ('individual', 'installment_plan',       false, false, 11);

-- سجل تجاري في حساب شخصي: الحساب يتحول شركة. ورقة تجارية تعني كيانا تجاريا،
-- فلا يبقى مصنفا شخصيا ولا تبقى عليه الواجهة الشخصية.
create or replace function public.convert_org_to_company(p_org uuid, p_entity text, p_number text, p_name text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_old text; v_entity text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  v_entity := case when p_entity in ('company','establishment','freelance','nonprofit','government')
                   then p_entity else 'company' end;
  select entity_type into v_old from public.org_profiles where org_id = p_org;
  if coalesce(v_old, '') not in ('individual', '') then
    return jsonb_build_object('status', 'unchanged', 'entity_type', v_old);
  end if;
  insert into public.org_profiles (org_id, entity_type, cr_number, license_number, updated_by)
  values (p_org, v_entity,
          case when v_entity in ('company','establishment') then nullif(btrim(coalesce(p_number,'')), '') end,
          case when v_entity = 'freelance' then nullif(btrim(coalesce(p_number,'')), '') end,
          auth.uid())
  on conflict (org_id) do update set
    entity_type = excluded.entity_type,
    cr_number = coalesce(excluded.cr_number, public.org_profiles.cr_number),
    license_number = coalesce(excluded.license_number, public.org_profiles.license_number),
    ui_pack = case when public.org_profiles.ui_pack = 'individual' then null else public.org_profiles.ui_pack end,
    updated_by = auth.uid(), updated_at = now();
  update public.org_members set ui_pack = null where org_id = p_org and ui_pack = 'individual';
  if nullif(btrim(coalesce(p_name,'')), '') is not null then
    update public.organizations set name = btrim(p_name) where id = p_org and coalesce(btrim(name),'') = '';
  end if;
  return jsonb_build_object('status', 'converted', 'from', v_old, 'entity_type', v_entity,
                            'pack', public.pack_for(p_org));
end $function$;

grant execute on function public.convert_org_to_company(uuid, text, text, text) to authenticated;

commit;
