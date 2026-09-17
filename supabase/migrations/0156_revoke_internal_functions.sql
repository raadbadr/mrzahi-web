-- 0156 — سحب صلاحيات زائدة عن دوال داخلية كانت مكشوفة لغير المسجلين.
-- الثغرة: Postgres يمنح كل دالة جديدة لـ PUBLIC تلقائيا، فالدالة الداخلية
-- تصير قابلة للنداء من المتصفح بلا تسجيل دخول ما لم تسحب من PUBLIC صراحة.
-- واخطرها tasks_record_for: تنشئ سجلا في اي حساب بنداء واحد.
-- الثلاث تنادى من دوال اخرى داخل القاعدة ولا تنادى من المتصفح ابدا،
-- عدا packs_allowed_for التي تحتاجها الواجهة للعضو المسجل وحده.
begin;

revoke execute on function public.tasks_record_for(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.member_name_for(uuid) from public, anon, authenticated;
revoke execute on function public.packs_allowed_for(uuid, uuid) from public, anon;
grant  execute on function public.packs_allowed_for(uuid, uuid) to authenticated;

commit;

select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('tasks_record_for','member_name_for','packs_allowed_for')
order by p.proname;
