-- الفرد وصاحب وثيقة العمل الحر يعمل وحده: لا فريق ولا دردشة ولا ما يتبعهما.
-- الشرط في مصدر الخدمات نفسه لا في الواجهة، فيسري على الشريط والصفحة والحارس معا.
-- الجهة الحكومية والمؤسسة والشركة والجهة غير الربحية على حالها: لها إداراتها.
create or replace function public.my_services(p_org uuid)
returns text[] language sql stable security definer set search_path to 'public' as $$
  with me as (
    select m.role, coalesce(m.department, case when m.role in ('owner','admin') then 'management' else 'other' end) as department
    from public.org_members m
    where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active'
    limit 1
  ), base as (
    select case
      when not exists (select 1 from me) then '{}'::text[]
      when (select role from me) in ('owner','admin') or (select department from me) = 'management'
        then (select array_agg(distinct service order by service) from public.department_services)
      else (select coalesce(array_agg(ds.service order by ds.service), '{}'::text[])
            from public.department_services ds where ds.department = (select department from me))
    end as list
  ), solo as (
    select coalesce((select op.entity_type from public.org_profiles op where op.org_id = p_org), 'company')
             in ('individual', 'freelance') as is_solo
  )
  select case
    when (select is_solo from solo)
      then (select coalesce(array_agg(s order by s), '{}'::text[])
              from unnest((select list from base)) s where s <> 'team')
    else (select list from base)
  end
$$;
