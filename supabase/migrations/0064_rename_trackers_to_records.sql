-- 0064 — Mr.Zahi — لا اسم قديم في القاعدة: trackers صارت records و tracker_id صار record_id
-- امر المهندس رعد 2026-09-10: «ابغى كل شي يسير مستر زاهي». «السجل» هو اسم الوعاء عنده منذ 2026-09-08،
-- فترجمته records، والاعمدة والقيود والفهارس والـ policy والـ trigger والدوال تتبعه في transaction واحدة.

-- 1) الجدول والاعمدة
alter table public.trackers rename to records;
alter table public.items          rename column tracker_id to record_id;
alter table public.imports        rename column tracker_id to record_id;
alter table public.reminder_rules rename column tracker_id to record_id;

-- 2) القيود
alter table public.records        rename constraint trackers_pkey            to records_pkey;
alter table public.records        rename constraint trackers_org_id_fkey     to records_org_id_fkey;
alter table public.records        rename constraint trackers_created_by_fkey to records_created_by_fkey;
alter table public.items          rename constraint items_tracker_id_fkey          to items_record_id_fkey;
alter table public.imports        rename constraint imports_tracker_id_fkey        to imports_record_id_fkey;
alter table public.reminder_rules rename constraint reminder_rules_tracker_id_fkey to reminder_rules_record_id_fkey;

-- 3) الفهارس
alter index public.trackers_org_idx            rename to records_org_idx;
alter index public.trackers_created_by_idx     rename to records_created_by_idx;
alter index public.items_tracker_idx           rename to items_record_idx;
alter index public.imports_tracker_idx         rename to imports_record_idx;
alter index public.reminder_rules_tracker_idx  rename to reminder_rules_record_idx;

-- 4) الـ policy
alter policy trackers_rw on public.records rename to records_rw;

-- 5) الدوال: كل دالة يرد فيها الاسم القديم تعاد بنصها نفسه بعد الاستبدال.
--    تسقط اولا لان بعضها يغير اسم وسيطه (p_tracker_name -> p_record_name) وهو ما لا يقبله create or replace.
--    الـ trigger يسقط قبلها لان دالته من ضمنها، ويعاد بناؤه بعدها باسمه الجديد.
do $mig$
declare r record; d text;
begin
  set local check_function_bodies = off;
  drop trigger if exists trackers_default_rule on public.records;
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args, pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and pg_get_functiondef(p.oid) ilike '%tracker%'
  loop
    d := replace(replace(r.def, 'tracker', 'record'), 'Tracker', 'Record');
    execute format('drop function if exists public.%I(%s)', r.proname, r.args);
    execute d;
  end loop;
  execute 'create trigger records_default_rule after insert on public.records for each row execute function public.record_default_rule()';
end
$mig$;

-- 6) «متتبع» لغة قديمة الغيت من المشروع كله: التعليق داخل telegram_save_document يقول «سجل»
do $c$
declare r record; d text;
begin
  set local check_function_bodies = off;
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args, pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%متتبع%'
  loop
    d := replace(replace(r.def, 'متتبعات', 'سجلات'), 'متتبع', 'سجل');
    execute format('drop function if exists public.%I(%s)', r.proname, r.args);
    execute d;
  end loop;
end
$c$;
