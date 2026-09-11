-- الترحيل كما طبق على Supabase (version 20260903201759, name tracker_0015_exclude_self_from_invite_list); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- لا معنى لدعوة النفس: يُستبعد المستخدم الحالي من قائمة الدعوة دائماً.
create or replace function public.find_profile_for_invite(p_query text)
returns table (id uuid, full_name text, email text, phone text, profile_number text)
language plpgsql
security definer
set search_path = public
as $$
declare q text;
begin
  q := lower(btrim(coalesce(p_query, '')));

  if public.is_platform_admin() then
    return query
      select p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      where p.id <> auth.uid()
        and (q = ''
             or lower(coalesce(p.email, '')) like '%' || q || '%'
             or coalesce(p.phone, '') like '%' || q || '%'
             or lower(coalesce(p.full_name, '')) like '%' || q || '%'
             or lower(coalesce(p.profile_number, '')) like '%' || q || '%')
      order by p.created_at desc
      limit 50;
  elsif q = '' then
    return query
      select distinct p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      join public.org_members m on m.user_id = p.id
      where m.org_id in (select current_org_ids())
        and p.id <> auth.uid()
      limit 50;
  else
    return query
      select p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      where p.id <> auth.uid()
        and (lower(coalesce(p.email, '')) = q
             or coalesce(p.phone, '') = q
             or lower(coalesce(p.profile_number, '')) = q)
      limit 1;
  end if;
end $$;

revoke all on function public.find_profile_for_invite(text) from public, anon;
grant execute on function public.find_profile_for_invite(text) to authenticated;
