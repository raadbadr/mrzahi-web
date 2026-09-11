-- الترحيل كما طبق على Supabase (version 20260906083228, name admin_packs_read_and_set); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- إدارة المنصة ترى واجهة كل حساب وتغيرها (أمر المهندس رعد 2026-09-06):
-- «أعرف المستخدمين وأي واجهة هم عليها وأقدر أغيرها… لأني ممكن أسحبها من المستخدم العادي».
create or replace function public.admin_list_orgs_packs()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not public.is_platform_admin() then null else
    coalesce((select jsonb_agg(jsonb_build_object(
      'org_id', o.id,
      'name', o.name,
      'owner_id', o.owner_id,
      'entity_type', p.entity_type,
      'ui_pack', p.ui_pack,                      -- ما اختير صراحة (قد يكون فارغا)
      'resolved_pack', public.pack_for(o.id),    -- ما يراه صاحب الحساب فعلا
      'created_at', o.created_at
    ) order by o.created_at desc)
    from public.organizations o
    left join public.org_profiles p on p.org_id = o.id), '[]'::jsonb)
  end
$$;
revoke all on function public.admin_list_orgs_packs() from public, anon;
grant execute on function public.admin_list_orgs_packs() to authenticated;

-- مدير المنصة يغير واجهة أي حساب ولو لم يكن عضوا فيه
create or replace function public.admin_set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  return public.pack_for(p_org);
end $$;
revoke all on function public.admin_set_org_pack(uuid, text) from public, anon;
grant execute on function public.admin_set_org_pack(uuid, text) to authenticated;
