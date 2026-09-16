-- المهندس رعد 2026-09-17: «كرت المستخدم عليه بيانات المستخدم وعليه ايش داخل
-- في شركات وايش باقته. كرت المستخدم لازم يكون عليه زي البروفايل يبين كل شي
-- عن المستخدم».
--
-- فالبطاقة تحمل ما في ملفه كله: لغته ومكان حفظه وربط تيليغرام وآخر ظهور وطلب
-- الحذف ان وجد، ومعها حسابه الشخصي بباقته، وكل شركة انضم اليها بدوره فيها
-- وبباقتها. المفاتيح القديمة تبقى فلا ينكسر مستهلك قديم.

begin;

create or replace function public.admin_list_users(p_limit integer default 500)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select case when not public.is_platform_admin() then null else
    coalesce((select jsonb_agg(u order by u->>'created_at' desc) from (
      select jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'full_name_en', p.full_name_en,
        'email', p.email,
        'phone', p.phone,
        'profile_number', p.profile_number,
        'lang', p.lang,
        'tz', p.tz,
        'storage_mode', p.storage_mode,
        'is_platform_admin', p.is_platform_admin,
        'created_at', p.created_at,
        'last_seen_at', p.last_seen_at,
        'delete_requested_at', p.delete_requested_at,
        -- تيليغرام: مرتبط ام لا، بلا كشف معرفه
        'telegram_linked', exists (select 1 from public.channel_links l
                                    where l.user_id = p.id and l.channel = 'telegram' and l.verified_at is not null),
        'orgs', (select count(*) from public.org_members m where m.user_id = p.id and m.status = 'active'),
        'owns', (select count(*) from public.organizations o where o.owner_id = p.id),
        'org_names', (select coalesce(jsonb_agg(o.name order by o.created_at), '[]'::jsonb)
                        from public.org_members m join public.organizations o on o.id = m.org_id
                       where m.user_id = p.id and m.status = 'active'),
        'personal', (select jsonb_build_object('id', o.id, 'name', o.name,
                                               'plan_code', o.plan_code, 'plan_expires_at', o.plan_expires_at,
                                               'created_at', o.created_at,
                                               'items', (select count(*) from public.items i where i.org_id = o.id))
                       from public.organizations o
                       join public.org_profiles pr on pr.org_id = o.id and pr.entity_type = 'individual'
                       join public.org_members m on m.org_id = o.id and m.user_id = p.id and m.status = 'active'
                      order by o.created_at asc limit 1),
        'companies', (select coalesce(jsonb_agg(jsonb_build_object(
                                'id', o.id, 'name', o.name, 'role', m.role,
                                'entity_type', coalesce(pr.entity_type, 'company'),
                                'plan_code', o.plan_code, 'plan_expires_at', o.plan_expires_at,
                                'items', (select count(*) from public.items i where i.org_id = o.id))
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
