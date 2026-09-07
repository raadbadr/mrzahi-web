-- ثلاث ثغرات تسرب بيانات شركة إلى عضو شركة أخرى، ومنحة تنفيذ ناقصة للوركر.
-- الحارس مشروط بوجود مستخدم مسجل: النداءات الداخلية من دوال الوركر (auth.uid() = null)
-- محمية أصلا بـ check_worker_secret، ولو حجبت لتعطل مسار البوت.

-- 1) قائمة القضايا المرشحة كانت تقبل أي org_id من أي مستخدم مسجل
create or replace function public.parent_candidates(p_org uuid, p_hint text default null, p_limit integer default 8)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  with base as (
    select i.id, i.item_number, i.title, i.client_name, i.case_number, i.data->>'violation_number' as violation_number, i.due_at, i.category
    from public.items i
    where i.org_id = p_org
      and ((select auth.uid()) is null or p_org in (select public.current_org_ids()))
      and i.status = 'open' and i.parent_id is null
      and (i.category in ('جلسة', 'مخالفة') or i.case_number is not null or (i.data->>'violation_number') is not null or i.category is null)
  ), hinted as (
    select * from base
    where p_hint is null or btrim(p_hint) = ''
       or case_number ilike '%' || btrim(p_hint) || '%' or violation_number ilike '%' || btrim(p_hint) || '%'
       or client_name ilike '%' || btrim(p_hint) || '%' or title ilike '%' || btrim(p_hint) || '%' or item_number ilike '%' || btrim(p_hint) || '%'
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'item_number', item_number, 'title', title, 'client_name', client_name,
           'case_number', case_number, 'violation_number', violation_number, 'due_at', due_at) order by due_at asc nulls last), '[]'::jsonb)
  from (select * from hinted order by due_at asc nulls last limit greatest(1, least(coalesce(p_limit, 8), 30))) x
$$;

-- 2) أسماء المسؤولين عن عنصر كانت تقرأ بمعرف العنصر وحده
create or replace function public.item_roles_text(p_item uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select string_agg(r.role || ': ' || coalesce(p.full_name, p.email, ''), ' · ' order by array_position(array['A','R','S','I'], r.role))
  from public.item_roles r left join public.profiles p on p.id = r.user_id
  where r.item_id = p_item
    and ((select auth.uid()) is null or r.org_id in (select public.current_org_ids()))
$$;

-- 3) التنبيهات: رسالة زميل خاصة كان يقرؤها كل عضو في الشركة عبر هذا الجدول.
-- الجرس في الواجهة يقرأ تنبيهات صاحبه وحده أصلا (myNotifications تصفي user_id).
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications
  for select using (user_id = (select auth.uid()));

-- 4) دالة إدارة المنصة للبوت كانت بلا منح تنفيذ، فترد 401 على كل نداء
revoke all on function public.telegram_platform(text, uuid) from public;
grant execute on function public.telegram_platform(text, uuid) to anon, authenticated;
