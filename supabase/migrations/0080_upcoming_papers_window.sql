-- «المواعيد القادمة» موعد لا أرشيف: الورقة الرسمية لا تدخلها إلا حين تدخل
-- نافذة انتهائها التي تعرّفها المنصة نفسها (ثلاثون يوما في org_documents_status).
-- المهام والجلسات والمواعيد تبقى كما هي مهما بعدت، والمتأخر يبقى كله.
create or replace function public.telegram_items(p_secret text, p_user_id uuid, p_mode text, p_limit integer default 5)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', x.title, 'due_at', x.due_at, 'tracker_name', x.tracker_name, 'org_name', x.org_name,
           'client_name', x.client_name, 'case_number', x.case_number,
           'kind', public.item_kind(x.category, x.case_number, x.data, x.parent_id),
           'document_kind', x.data->>'document_kind',
           'doc_number', coalesce(x.data->>'number', x.data->'details'->>'cr_number', x.data->'details'->>'vat_number'),
           'issue_date', coalesce(x.data->'details'->>'issue_date', x.data->'details'->>'certificate_date', x.data->>'issue_date'),
           'violation_number', x.data->>'violation_number') order by x.due_at asc), '[]'::jsonb)
  into result
  from (
    select i.title, i.due_at, i.client_name, i.case_number, i.category, i.data, i.parent_id,
           t.name as tracker_name, o.name as org_name
    from public.items i
    left join public.trackers t on t.id = i.tracker_id
    left join public.organizations o on o.id = i.org_id
    where i.org_id in (select public.telegram_user_orgs(p_user_id))
      and i.status = 'open' and i.due_at is not null
      and ((p_mode = 'overdue' and i.due_at < now()) or (p_mode <> 'overdue' and i.due_at >= now()))
      and (p_mode = 'overdue'
           or not (i.data ? 'document_kind')
           or i.due_at <= now() + interval '30 days')
    order by i.due_at asc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) x;
  return result;
end $function$;
