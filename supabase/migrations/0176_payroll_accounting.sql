-- 0176: قيد الرواتب الى المنصة المحاسبية (المرحلة الثانية من أمر المهندس رعد 2026-10-01).
--
-- يرسل المسيّر قيد يومية واحدا حين يصير «مدفوعا» لا حين يعتمد: المعتمد قد يعيد المالك
-- فتحه، والقيد في قيود لا يرسل مسودة (لا حالة Draft في journal_entries)، فلو ارسل عند
-- الاعتماد ثم فتح المسيّر لاختلفت المحاسبة عن المنصة. والمدفوع نهائي.
--
-- القيد (متوازن بالبناء):
--   مدين  مصروف الرواتب          = الاجمالي − (الغياب + الاجازة بلا راتب + التاخر + الخصومات الاخرى)
--   مدين  مصروف التامينات        = حصة صاحب العمل
--   دائن  التامينات المستحقة      = حصة الموظف + حصة صاحب العمل
--   دائن  سلف الموظفين            = خصم السلف
--   دائن  الرواتب المستحقة        = الصافي
-- والحسابات يختارها صاحب الحساب في payroll_settings.accounts (معرفات حسابات قيود).
--
-- منع التكرار كبقية الربط: حجز ذري (sending) قبل الارسال، ومرجع MZ-PAY-<المسيّر> في الوصف
-- يبحث به قبل اي اعادة، فلا يقيد المسيّر نفسه مرتين ولو انقطع الرد بعد الوصول.

alter table public.payroll_runs
  add column if not exists acct_status text check (acct_status in ('pending', 'sending', 'sent', 'failed', 'waiting')),
  add column if not exists acct_external_id text,
  add column if not exists acct_error text,
  add column if not exists acct_attempts integer not null default 0,
  add column if not exists acct_updated_at timestamptz;

-- الدفع يضع القيد في الانتظار ان كان للحساب ربط محاسبي
create or replace function public.payroll_run_queue_acct()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' and new.acct_status is null
     and exists (select 1 from public.accounting_links l where l.org_id = new.org_id) then
    new.acct_status := 'pending'; new.acct_updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists payroll_run_queue_acct on public.payroll_runs;
create trigger payroll_run_queue_acct before update on public.payroll_runs
for each row execute function public.payroll_run_queue_acct();

-- للخادم وحده: المسيّرات المنتظرة بمبالغ قيدها
create or replace function public.payroll_acct_pending(p_secret text, p_org uuid default null, p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v from (
    select r.id, r.org_id, r.period, r.acct_attempts,
           coalesce((select s.accounts from public.payroll_settings s where s.org_id = r.org_id), '{}'::jsonb) as accounts,
           (select jsonb_build_object(
              'gross', coalesce(sum(l.gross),0),
              'reductions', coalesce(sum(l.absence_deduction + l.unpaid_leave_deduction + l.late_deduction + l.other_deduction),0),
              'gosi_employee', coalesce(sum(l.gosi_employee),0), 'gosi_employer', coalesce(sum(l.gosi_employer),0),
              'advances', coalesce(sum(l.advance_deduction),0), 'net', coalesce(sum(l.net),0),
              'employees', count(*))
             from public.payroll_lines l where l.run_id = r.id) as sums
      from public.payroll_runs r
     where r.status = 'paid'
       and (p_org is null or r.org_id = p_org)
       and (r.acct_status in ('pending', 'waiting')
            or (r.acct_status = 'failed' and r.acct_attempts < 5)
            or (r.acct_status = 'sending' and r.acct_updated_at < now() - interval '30 minutes'))
     order by r.paid_at
     limit greatest(1, least(coalesce(p_limit, 10), 50))) x;
  return v;
end $$;

create or replace function public.payroll_acct_claim(p_secret text, p_run uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  update public.payroll_runs set acct_status = 'sending', acct_updated_at = now(), acct_attempts = acct_attempts + 1
   where id = p_run and status = 'paid'
     and (acct_status in ('pending', 'waiting', 'failed')
          or (acct_status = 'sending' and acct_updated_at < now() - interval '30 minutes'));
  get diagnostics n = row_count;
  return n = 1;
end $$;

create or replace function public.payroll_acct_mark(p_secret text, p_run uuid, p_status text, p_external_id text default null, p_error text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if p_status not in ('sent', 'failed', 'waiting') then raise exception 'BAD_STATUS' using errcode = 'P0001'; end if;
  update public.payroll_runs set acct_status = p_status, acct_external_id = coalesce(p_external_id, acct_external_id),
         acct_error = left(p_error, 400), acct_updated_at = now()
   where id = p_run;
end $$;

-- صاحب الحساب يعيد قيدا فشل او انتظر بعد ان يكمل اختيار الحسابات
create or replace function public.payroll_acct_retry(p_run uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_st text;
begin
  select org_id, acct_status into v_org, v_st from public.payroll_runs where id = p_run and status = 'paid';
  if v_org is null then return jsonb_build_object('status', 'not_found'); end if;
  if not public.is_org_admin(v_org) then raise exception 'NOT_ALLOWED' using errcode = '42501'; end if;
  if v_st = 'sent' then return jsonb_build_object('status', 'already_sent'); end if;
  if not exists (select 1 from public.accounting_links l where l.org_id = v_org) then return jsonb_build_object('status', 'no_link'); end if;
  update public.payroll_runs set acct_status = 'pending', acct_attempts = 0, acct_error = null, acct_updated_at = now() where id = p_run;
  return jsonb_build_object('status', 'ok');
end $$;

revoke all on function public.payroll_run_queue_acct() from public, anon, authenticated;
revoke all on function public.payroll_acct_pending(text, uuid, integer), public.payroll_acct_claim(text, uuid),
  public.payroll_acct_mark(text, uuid, text, text, text) from public, authenticated;
grant execute on function public.payroll_acct_pending(text, uuid, integer), public.payroll_acct_claim(text, uuid),
  public.payroll_acct_mark(text, uuid, text, text, text) to anon, service_role;
revoke all on function public.payroll_acct_retry(uuid) from public, anon;
grant execute on function public.payroll_acct_retry(uuid) to authenticated;
