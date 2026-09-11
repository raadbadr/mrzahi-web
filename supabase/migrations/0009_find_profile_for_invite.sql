-- الترحيل كما طبق على Supabase (version 20260903194441, name tracker_0009_find_profile_for_invite); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- البحث عن مستخدم مسجّل لدعوته: مطابقة تامة للبريد أو رقم الجوال فقط، حتى لا
-- تتسرب قائمة مستخدمي المنصة لأي مستأجر. مديرو المنصة يرون الجميع.
create or replace function public.find_profile_for_invite(p_query text)
returns table (id uuid, full_name text, email text, phone text, profile_number text)
language plpgsql
security definer
set search_path = public
as $$
declare q text;
begin
  q := lower(btrim(coalesce(p_query, '')));
  if q = '' then return; end if;

  if public.is_platform_admin() then
    return query
      select p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      where lower(coalesce(p.email, '')) like '%' || q || '%'
         or coalesce(p.phone, '') like '%' || q || '%'
         or lower(coalesce(p.full_name, '')) like '%' || q || '%'
      order by p.created_at desc
      limit 20;
  else
    return query
      select p.id, p.full_name, p.email, p.phone, p.profile_number
      from public.profiles p
      where lower(coalesce(p.email, '')) = q
         or coalesce(p.phone, '') = q
         or coalesce(p.profile_number, '') = upper(btrim(coalesce(p_query, '')))
      limit 1;
  end if;
end $$;

revoke all on function public.find_profile_for_invite(text) from public, anon;
grant execute on function public.find_profile_for_invite(text) to authenticated;
