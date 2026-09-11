-- الترحيل كما طبق على Supabase (version 20260903203046, name tracker_0016_case_number_link); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- ربط المخالفة بالقضية: رقم الدعوى عمودٌ حقيقي على العنصر ليجمع المخالفة وقضيتها
-- وملفاتهما تحت رقم واحد.
alter table public.items add column if not exists case_number text;
create index if not exists items_case_number_idx on public.items (org_id, case_number) where case_number is not null;

update public.items
set case_number = nullif(btrim(coalesce(data->>'رقم الدعوى', data->>'رقم القضية', data->>'case_number', '')), '')
where case_number is null;

-- كل ما يخص رقم قضية واحد: العناصر ومرفقاتها
create or replace function public.case_bundle(p_org uuid, p_case text)
returns table (
  item_id uuid, item_number text, title text, category text, due_at timestamptz,
  status text, amount numeric, client_name text, attachments bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select i.id, i.item_number, i.title, i.category, i.due_at, i.status, i.amount, i.client_name,
         (select count(*) from public.attachments a where a.item_id = i.id) as attachments
  from public.items i
  where i.org_id = p_org and i.case_number = p_case
  order by i.due_at nulls last, i.created_at;
$$;

grant execute on function public.case_bundle(uuid, text) to authenticated;
