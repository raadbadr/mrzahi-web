-- الترحيل كما طبق على Supabase (version 20260903212452, name tracker_0018_activity_feed); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- الخط الزمني للإنجازات: أحداث الشركة من الجداول كلها في مسار واحد
create or replace function public.activity_feed(p_org uuid, p_limit integer default 30)
returns table (at timestamptz, kind text, title text, meta jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with events as (
    select i.created_at as at, 'item_created'::text as kind, i.title,
           jsonb_build_object('item_number', i.item_number, 'category', i.category, 'amount', i.amount, 'client', i.client_name) as meta
    from public.items i where i.org_id = p_org

    union all
    select i.updated_at, 'item_done', i.title,
           jsonb_build_object('item_number', i.item_number, 'category', i.category, 'amount', i.amount, 'client', i.client_name)
    from public.items i where i.org_id = p_org and i.status = 'done' and i.updated_at is not null

    union all
    select im.created_at, 'import', coalesce(im.filename, ''),
           jsonb_build_object('rows', im.rows_count)
    from public.imports im where im.org_id = p_org

    union all
    select a.created_at, 'attachment', a.name,
           jsonb_build_object('size', a.size_bytes, 'item_id', a.item_id)
    from public.attachments a where a.org_id = p_org

    union all
    select m.created_at, 'member', coalesce(p.full_name, p.email, ''),
           jsonb_build_object('role', m.role)
    from public.org_members m
    left join public.profiles p on p.id = m.user_id
    where m.org_id = p_org

    union all
    select s.created_at, 'subscription', s.plan_code,
           jsonb_build_object('status', s.status, 'expires_at', s.expires_at)
    from public.subscriptions s where s.org_id = p_org
  )
  select at, kind, title, meta
  from events
  where at is not null
  order by at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
$$;

grant execute on function public.activity_feed(uuid, integer) to authenticated;

-- ملخص الإنجاز: ما أُنجز هذا الشهر
create or replace function public.achievements(p_org uuid)
returns table (done_this_month bigint, items_total bigint, files_total bigint, imports_total bigint, amount_closed numeric)
language sql
stable
security invoker
set search_path = public
as $$
  select
    (select count(*) from public.items i where i.org_id = p_org and i.status = 'done'
       and i.updated_at >= date_trunc('month', now())),
    (select count(*) from public.items i where i.org_id = p_org),
    (select count(*) from public.attachments a where a.org_id = p_org),
    (select count(*) from public.imports im where im.org_id = p_org),
    (select coalesce(sum(i.amount), 0) from public.items i where i.org_id = p_org and i.status = 'done');
$$;

grant execute on function public.achievements(uuid) to authenticated;
