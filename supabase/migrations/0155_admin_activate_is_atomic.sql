-- المهندس رعد 2026-09-17: «الشركة دي ماهي ترايل، انا بنفسي معدلها امس». وهو صادق:
-- في subscriptions اشتراك enterprise نشط منذ 16-09 الى 16-10، لكن بطاقة لوحة
-- الادارة تقرا organizations.plan_code وهو ما زال trial.
--
-- السبب: adminActivate كان يعمل خطوتين من المتصفح — يدخل الاشتراك (ينجح) ثم يحدث
-- organizations (يصمت). سياسة orgs_update هي is_org_admin(id) وحدها، ومدير المنصة
-- ليس مالكا ولا مديرا في Test بل عضوا، فلم يطابق التحديث اي صف. وPostgREST لا يعد
-- «صفر صف» خطا، فمر بلا انذار. ولذلك نجح التفعيل في الشركات التي يملكها وحدها.
--
-- العلاج: التفعيل صار عملا واحدا في القاعدة لا خطوتين في المتصفح. دالة
-- SECURITY DEFINER تتحقق ان المنادي مدير منصة، وتكتب الاشتراك وتحدث المنشاة في
-- معاملة واحدة، فاما ان ينجح الاثنان او لا شيء. ولا تفتح orgs_update لاحد.

begin;

create or replace function public.admin_activate_subscription(
  p_org uuid,
  p_plan text,
  p_months int default 0,
  p_note text default null
)
returns public.subscriptions
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_expires timestamptz;
  v_row public.subscriptions;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_PLATFORM_ADMIN' using errcode = '42501';
  end if;
  if p_org is null or coalesce(p_plan, '') = '' then
    raise exception 'ORG_AND_PLAN_REQUIRED' using errcode = '22023';
  end if;
  if not exists (select 1 from public.plans where code = p_plan) then
    raise exception 'UNKNOWN_PLAN' using errcode = '22023';
  end if;

  v_expires := case when coalesce(p_months, 0) > 0
                    then now() + (p_months || ' months')::interval
                    else null end;

  insert into public.subscriptions (org_id, plan_code, status, expires_at, activated_by, note)
  values (p_org, p_plan, 'active', v_expires, auth.uid(), p_note)
  returning * into v_row;

  update public.organizations
     set plan_code = p_plan, plan_expires_at = v_expires
   where id = p_org;

  return v_row;
end $function$;

revoke all on function public.admin_activate_subscription(uuid, text, int, text) from public;
grant execute on function public.admin_activate_subscription(uuid, text, int, text) to authenticated;

-- تصحيح ما انحرف بالفعل: كل منشاة اشتراكها النشط يخالف عمودها (اليوم: Test وحدها،
-- enterprise حتى 16-10-2026 وعمودها يقول trial ينتهي 17-09-2026).
update public.organizations o
   set plan_code = s.plan_code,
       plan_expires_at = s.expires_at
  from (
    select distinct on (x.org_id) x.org_id, x.plan_code, x.expires_at
      from public.subscriptions x
     where x.status = 'active' and (x.expires_at is null or x.expires_at > now())
     order by x.org_id, x.created_at desc
  ) s
 where s.org_id = o.id
   and (o.plan_code is distinct from s.plan_code
        or o.plan_expires_at is distinct from s.expires_at);

commit;

-- تحقق: لا منشاة يخالف عمودها اشتراكها الفعلي
select count(*) as munharifa
  from public.organizations o
 where o.plan_code is distinct from public.effective_plan(o.id);
