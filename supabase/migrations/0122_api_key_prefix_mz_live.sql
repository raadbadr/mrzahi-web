-- الترحيل كما طبق على Supabase (version 20260910204712, name api_key_prefix_mz_live); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
do $p$
declare d text;
begin
  set local check_function_bodies = off;
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'api_key_create';
  execute replace(d, 'tt_live_', 'mz_live_');
end
$p$;
