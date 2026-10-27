-- لوحة مؤشرات الاداء في صفحة ادارة المنصة (امر صاحب المشروع 2026-10-27: «نفذ لوحة
-- المؤشرات في صفحة الإدارة»)، على جدول المؤشرات الثمانية: العملاء الدافعون، والايراد
-- السنوي المتكرر، والتحويل من التجربة، والاستعمال الاسبوعي، وعمق الاستعمال، والتجديد،
-- وتكلفة جلب العميل، والاعطال. الستة الاولى تحسب هنا من القاعدة، والاخيران لا مصدر
-- لهما فيها فتقول الواجهة ذلك صراحة.
--
-- قواعد الحساب، وسببها مقيس على جدة يوم الكتابة:
-- * الحسابات الداخلية تستبعد من كل مؤشر تجاري: منشاة مالكها مدير منصة
--   (profiles.is_platform_admin). الدفعات الثلاث «approved» الموجودة كلها لحساب
--   المالك نفسه (دفعات تجربة PayPal بلا paid_at)، فلو عدت لظهر عميل دافع وايراد
--   15500 ريال وهما غير موجودين.
-- * العميل الدافع: منشاة غير داخلية لها دفعة approved تغطي اليوم. التغطية من
--   coalesce(paid_at, created_at) سنة للدفع السنوي وشهرا للشهري.
-- * الايراد السنوي المتكرر: لكل عميل دافع آخر دفعة تغطي اليوم، بلا ضريبة (base_sar،
--   والا amount_sar ناقص vat_sar)، والشهري مضروب في 12.
-- * التفعيل اليدوي بلا دفعة (تحويل بنكي مثلا) لا يدخل الايراد لانه لا مبلغ له في
--   القاعدة؛ يعد وحده في manual_active حتى لا يختفي عن العين.
-- * حالة الاشتراك «active» لا تكفي: اشتراك Test مكتوب active وانتهى في 2026-10-16،
--   فالسريان بـ expires_at > now().

begin;

create or replace function public.platform_kpis()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  result jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  with internal_orgs as (
    select distinct m.org_id
      from public.org_members m
      join public.profiles p on p.id = m.user_id
     where m.status = 'active' and m.role = 'owner' and p.is_platform_admin
  ),
  payment_coverage as (
    select pay.org_id,
           coalesce(pay.paid_at, pay.created_at) as covered_from,
           coalesce(pay.paid_at, pay.created_at)
             + case when pay.period = 'monthly' then interval '1 month' else interval '1 year' end as covered_until,
           coalesce(pay.base_sar, pay.amount_sar - coalesce(pay.vat_sar, 0), 0)
             * case when pay.period = 'monthly' then 12 else 1 end as annual_value_sar
      from public.payments pay
     where pay.status = 'approved'
       and pay.org_id not in (select org_id from internal_orgs)
  ),
  paying_now as (
    select distinct on (org_id) org_id, annual_value_sar
      from payment_coverage
     where covered_until > now()
     order by org_id, covered_from desc
  ),
  manual_active as (
    select distinct s.org_id
      from public.subscriptions s
     where s.plan_code not in ('trial', 'expired')
       and s.expires_at > now()
       and s.org_id not in (select org_id from internal_orgs)
       and s.org_id not in (select org_id from paying_now)
  ),
  trial_orgs as (
    select distinct s.org_id
      from public.subscriptions s
     where s.plan_code = 'trial'
       and s.org_id not in (select org_id from internal_orgs)
  ),
  trials_active as (
    select distinct s.org_id
      from public.subscriptions s
     where s.plan_code = 'trial' and s.status = 'active' and s.expires_at > now()
       and s.org_id not in (select org_id from internal_orgs)
       and s.org_id not in (select org_id from paying_now)
  ),
  converted as (
    select distinct t.org_id
      from trial_orgs t
     where exists (select 1 from payment_coverage pc where pc.org_id = t.org_id)
  ),
  paying_members as (
    select m.org_id, m.user_id
      from public.org_members m
     where m.status = 'active' and m.org_id in (select org_id from paying_now)
  ),
  week_actions as (
    select l.org_id, l.actor
      from public.ledger l
     where l.at > now() - interval '7 days'
       and l.actor is not null
       and l.org_id not in (select org_id from internal_orgs)
  ),
  renewals_due as (
    select distinct pc.org_id, pc.covered_until
      from payment_coverage pc
     where pc.covered_until <= now()
  ),
  renewed as (
    select distinct d.org_id
      from renewals_due d
     where exists (select 1 from payment_coverage later
                    where later.org_id = d.org_id
                      and later.covered_from >= d.covered_until - interval '30 days')
  )
  select jsonb_build_object(
    'generated_at',          now(),
    'paying_customers',      (select count(*) from paying_now),
    'arr_sar',               (select coalesce(round(sum(annual_value_sar), 2), 0) from paying_now),
    'manual_active',         (select count(*) from manual_active),
    'trials_active',         (select count(*) from trials_active),
    'trial_orgs',            (select count(*) from trial_orgs),
    'trial_converted',       (select count(*) from converted),
    'conversion_pct',        (select case when count(*) = 0 then null
                                      else round(100.0 * (select count(*) from converted) / count(*), 1) end
                                from trial_orgs),
    'paying_members',        (select count(*) from paying_members),
    'paying_members_active7',(select count(distinct pm.user_id)
                                from paying_members pm
                               where exists (select 1 from week_actions w where w.org_id = pm.org_id and w.actor = pm.user_id)),
    'weekly_active_pct',     (select case when count(*) = 0 then null
                                      else round(100.0 * count(*) filter (
                                             where exists (select 1 from week_actions w where w.org_id = pm.org_id and w.actor = pm.user_id)
                                           ) / count(*), 1) end
                                from paying_members pm),
    'paying_actions7',       (select count(*) from week_actions where org_id in (select org_id from paying_now)),
    'depth_per_customer',    (select case when (select count(*) from paying_now) = 0 then null
                                      else round((select count(*) from week_actions where org_id in (select org_id from paying_now))::numeric
                                                 / (select count(*) from paying_now), 1) end),
    'platform_active7',      (select count(distinct actor) from week_actions),
    'platform_actions7',     (select count(*) from week_actions),
    'renewals_due',          (select count(distinct org_id) from renewals_due),
    'renewals_done',         (select count(*) from renewed),
    'renewal_pct',           (select case when count(distinct org_id) = 0 then null
                                      else round(100.0 * (select count(*) from renewed) / count(distinct org_id), 1) end
                                from renewals_due),
    'internal_orgs',         (select count(*) from internal_orgs)
  ) into result;

  return result;
end $$;

-- كل دالة جديدة تمنح لـ PUBLIC تلقائيا: تسحب صراحة، ثم تمنح للمسجلين، والحارس
-- داخلها (is_platform_admin) يرد غير مدير المنصة بـ 42501.
revoke all on function public.platform_kpis() from public, anon;
grant execute on function public.platform_kpis() to authenticated, service_role;

commit;

select p.oid::regprocedure as tawqi3, coalesce(array_to_string(p.proacl, ' | '), '(bila acl)') as salahiyat
  from pg_proc p where p.proname = 'platform_kpis';
