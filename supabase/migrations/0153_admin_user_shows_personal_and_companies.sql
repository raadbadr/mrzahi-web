-- المهندس رعد 2026-09-17: «حتى الان اشوف عندي حسابات شخصية منفصلة عن
-- المستخدمون ودا غير صحيح. المفروض المستخدمون وفي داخلهم حسابهم الشخصي
-- وكمان يبين منضمين لاي شركة».
--
-- الحساب الشخصي ليس كيانا مستقلا يعرض في بطاقة الى جانب الشركات: هو جزء من
-- المستخدم نفسه. فبطاقة المستخدم تحمل حسابه الشخصي والشركات التي انضم اليها
-- ودوره في كل واحدة، وبطاقة «الشركات» تبقى للشركات وحدها.
--
-- المفاتيح القديمة (orgs، owns، org_names) تبقى كما هي فلا ينكسر مستهلك قديم.

begin;

create or replace function public.admin_list_users(p_limit integer default 500)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
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
                       where m.user_id = p.id and m.status = 'active'),
        -- حسابه الشخصي: مساحته هو، لا شركة
        'personal', (select jsonb_build_object('id', o.id, 'name', o.name, 'plan_code', o.plan_code,
                                               'created_at', o.created_at,
                                               'items', (select count(*) from public.items i where i.org_id = o.id))
                       from public.organizations o
                       join public.org_profiles pr on pr.org_id = o.id and pr.entity_type = 'individual'
                       join public.org_members m on m.org_id = o.id and m.user_id = p.id and m.status = 'active'
                      order by o.created_at asc limit 1),
        -- الشركات التي انضم اليها ودوره في كل واحدة
        'companies', (select coalesce(jsonb_agg(jsonb_build_object(
                                'id', o.id, 'name', o.name, 'role', m.role,
                                'entity_type', coalesce(pr.entity_type, 'company'))
                              order by (m.role = 'owner') desc, (m.role = 'admin') desc, o.created_at), '[]'::jsonb)
                        from public.org_members m
                        join public.organizations o on o.id = m.org_id
                        left join public.org_profiles pr on pr.org_id = o.id
                       where m.user_id = p.id and m.status = 'active'
                         and coalesce(pr.entity_type, 'company') <> 'individual')
      ) as u
      from public.profiles p
      order by p.created_at desc
      limit greatest(1, least(coalesce(p_limit, 500), 2000))
    ) rows), '[]'::jsonb)
  end
$function$;

commit;
