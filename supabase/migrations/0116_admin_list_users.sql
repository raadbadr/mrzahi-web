-- الترحيل كما طبق على Supabase (version 20260906083156, name admin_list_users); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- إدارة المنصة تعرض المستخدمين كما تعرض الشركات (أمر المهندس رعد 2026-09-06).
-- لمدير المنصة وحده، وقراءة فقط: لا تعديل ولا حذف من هذه الدالة.
create or replace function public.admin_list_users(p_limit integer default 500)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not public.is_platform_admin() then null else
    coalesce((select jsonb_agg(u order by u->>'created_at' desc) from (
      select jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'email', p.email,
        'phone', p.phone,
        'profile_number', p.profile_number,
        'lang', p.lang,
        'is_platform_admin', p.is_platform_admin,
        'created_at', p.created_at,
        'orgs', (select count(*) from public.org_members m where m.user_id = p.id and m.status = 'active'),
        'owns', (select count(*) from public.organizations o where o.owner_id = p.id),
        'org_names', (select coalesce(jsonb_agg(o.name order by o.created_at), '[]'::jsonb)
                        from public.org_members m join public.organizations o on o.id = m.org_id
                       where m.user_id = p.id and m.status = 'active')
      ) as u
      from public.profiles p
      order by p.created_at desc
      limit greatest(1, least(coalesce(p_limit, 500), 2000))
    ) rows), '[]'::jsonb)
  end
$$;
revoke all on function public.admin_list_users(integer) from public, anon;
grant execute on function public.admin_list_users(integer) to authenticated;
