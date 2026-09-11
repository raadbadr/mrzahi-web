-- الترحيل كما طبق على Supabase (version 20260903103947, name wipe_maher_for_tracker); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- تفريغ مشروع Maher بالكامل وتخصيصه لمستر زاهي (قرار المهندس رعد 2026-09-03)
drop schema public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to postgres, anon, authenticated, service_role;
delete from auth.users;
