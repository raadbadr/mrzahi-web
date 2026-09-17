-- المهندس رعد 2026-09-17: «بالنسبة لصحتي واضافة الادوية، لازم يكون فيه التكرار
-- حسب وصفة الطبيب».
--
-- كان التكرار ثلاث درجات: يومي واسبوعي وشهري. والوصفة تقول «حبة كل ثماني ساعات
-- لمدة خمسة ايام»، فالدرجات الثلاث لا تصفها: لا جرعة تتكرر داخل اليوم، ولا نهاية
-- للوصفة فتستمر الجرعات الى الابد.
--
-- المشغل الان يفهم:
--   every_4h / every_6h / every_8h / every_12h  الى جانب daily و weekly و monthly
--   data.repeat_until  تاريخ اخر يوم في الوصفة: بعده لا تنشا جرعة تالية
-- وما دون ذلك كما كان: الجرعة التالية تحسب الى ما بعد الان فلا تتراكم الفائتة،
-- ولا تنشا ثانية ما دامت الاولى مفتوحة.

begin;

create or replace function public.item_repeat_next()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_step interval; v_next timestamptz; v_until timestamptz;
begin
  if new.status <> 'done' or old.status = 'done' then return new; end if;
  if new.due_at is null then return new; end if;
  v_step := case new.data->>'repeat'
              when 'every_4h'  then interval '4 hours'
              when 'every_6h'  then interval '6 hours'
              when 'every_8h'  then interval '8 hours'
              when 'every_12h' then interval '12 hours'
              when 'daily'     then interval '1 day'
              when 'weekly'    then interval '7 days'
              when 'monthly'   then interval '1 month'
              else null end;
  if v_step is null then return new; end if;

  v_next := new.due_at + v_step;
  while v_next <= now() loop v_next := v_next + v_step; end loop;

  -- نهاية الوصفة: اخر يوم فيها كامل الى منتصف الليل
  begin
    v_until := case when coalesce(new.data->>'repeat_until', '') = '' then null
                    else ((new.data->>'repeat_until')::date + 1)::timestamptz end;
  exception when others then v_until := null;
  end;
  if v_until is not null and v_next >= v_until then return new; end if;

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

commit;

-- تحقق: المشغل قائم على items، والدالة تعرف الخطوات السبع
select tgname from pg_trigger where tgrelid = 'public.items'::regclass and tgname = 'items_repeat_next';
