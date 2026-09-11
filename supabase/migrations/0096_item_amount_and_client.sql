-- الترحيل كما طبق على Supabase (version 20260903201428, name tracker_0014_item_amount_and_client); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- المحامي يخدم عدة شركات: لكل عنصر (مخالفة أو قضية) عميلٌ ومبلغ، ليُجمع ويُرتَّب.
alter table public.items add column if not exists amount numeric(14,2);
alter table public.items add column if not exists client_name text;

create index if not exists items_client_idx on public.items (org_id, client_name);
create index if not exists items_amount_idx on public.items (org_id) where amount is not null;

-- مجاميع المخالفات لكل عميل داخل الشركة الواحدة
create or replace function public.client_totals(p_org uuid, p_category text default null)
returns table (client_name text, items_count bigint, total_amount numeric, open_count bigint, overdue_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(i.client_name, '') as client_name,
         count(*) as items_count,
         coalesce(sum(i.amount), 0) as total_amount,
         count(*) filter (where i.status = 'open') as open_count,
         count(*) filter (where i.status = 'open' and i.due_at < now()) as overdue_count
  from public.items i
  where i.org_id = p_org
    and (p_category is null or i.category ilike '%' || p_category || '%')
  group by coalesce(i.client_name, '')
  order by total_amount desc, items_count desc;
$$;

grant execute on function public.client_totals(uuid, text) to authenticated;
