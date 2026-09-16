-- 0146 — المهندس رعد 2026-09-16: «في الشخصي ضيف كمان صحتي، بحيث لو الشخص
-- عندو علاجات ادوية ياخدها بشكل منتظم يكون فيه تذكير».
-- «صحتي» خدمة في الواجهة الشخصية وحدها: ادوية وعلاجات ومواعيد مراجعة، تمر
-- بالتذكير كأي عنصر. وهي packOnly في الشريط فلا تدخل واجهات الشركات.
begin;

insert into public.department_services (department, service)
values ('management', 'health')
on conflict do nothing;

insert into public.pack_services (pack_key, service, sort_order, label)
values ('individual', 'health', 3,
        '{"ar":"صحتي","en":"My health","fr":"Ma sante","ur":"میری صحت"}'::jsonb)
on conflict (pack_key, service) do update set sort_order = excluded.sort_order, label = excluded.label;

update public.pack_services set sort_order = 4 where pack_key = 'individual' and service = 'expenses';
update public.pack_services set sort_order = 5 where pack_key = 'individual' and service = 'settings';

-- الدواء المنتظم: عنصر يحمل data.repeat (daily / weekly / monthly)، وحين يعلّم
-- منجزا تنشأ جرعته التالية وحدها بموعدها، فيبقى التذكير قائما بلا عمل يدوي.
-- من فات موعده لا تتراكم عليه جرعات ماضية: التالية تحسب الى ما بعد الآن.
create or replace function public.item_repeat_next()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_step interval; v_next timestamptz;
begin
  if new.status <> 'done' or old.status = 'done' then return new; end if;
  if new.due_at is null then return new; end if;
  v_step := case new.data->>'repeat'
              when 'daily'   then interval '1 day'
              when 'weekly'  then interval '7 days'
              when 'monthly' then interval '1 month'
              else null end;
  if v_step is null then return new; end if;
  v_next := new.due_at + v_step;
  while v_next <= now() loop v_next := v_next + v_step; end loop;
  if exists (select 1 from public.items i
              where i.org_id = new.org_id and i.status = 'open'
                and i.data->>'repeat_of' = new.id::text) then
    return new;
  end if;
  insert into public.items (org_id, record_id, title, category, due_at, status, assignee_id,
                            amount, client_name, remind_before, data, created_by)
  values (new.org_id, new.record_id, new.title, new.category, v_next, 'open', new.assignee_id,
          new.amount, new.client_name, new.remind_before,
          (new.data - 'repeat_of') || jsonb_build_object('repeat_of', new.id::text),
          new.created_by);
  return new;
end $function$;

drop trigger if exists items_repeat_next on public.items;
create trigger items_repeat_next
  after update of status on public.items
  for each row execute function public.item_repeat_next();

commit;
