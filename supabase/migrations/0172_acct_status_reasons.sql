-- تتمة 0171 (امر المهندس رعد 2026-09-23، الربط المحاسبي): بطاقة الربط في الاعدادات
-- تقول لصاحب الحساب لماذا ينتظر عنصر ولم يرسل (لم يختر حساب المصروفات، او عنصر
-- بلا جهة، او بلا مبلغ...) لا عدده وحده، فيعرف ما يكمله. الدالة نفسها بما تعيده
-- كله، وزيادة «waiting»: كم عنصرا ينتظر لكل سبب. لا جدول ولا صلاحية جديدة.

begin;

create or replace function public.acct_link_status(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_link public.accounting_links; v_role text; v_counts jsonb; v_waiting jsonb; v_last record;
begin
  select m.role into v_role from public.org_members m
   where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active' limit 1;
  if v_role is null then return null; end if;
  select * into v_link from public.accounting_links where org_id = p_org;
  if not found then
    return jsonb_build_object('connected', false, 'can_manage', v_role in ('owner', 'admin'));
  end if;
  select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) into v_counts
    from (select status, count(*) as n from public.accounting_pushes
           where org_id = p_org and provider = v_link.provider group by status) c;
  select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) into v_waiting
    from (select coalesce(error, 'other') as reason, count(*) as n from public.accounting_pushes
           where org_id = p_org and provider = v_link.provider and status = 'waiting' group by 1) w;
  select p.updated_at, p.status, p.error into v_last
    from public.accounting_pushes p
   where p.org_id = p_org and p.provider = v_link.provider and p.status in ('sent', 'failed')
   order by p.updated_at desc limit 1;
  return jsonb_build_object(
    'connected', true, 'can_manage', v_role in ('owner', 'admin'),
    'provider', v_link.provider, 'key_hint', v_link.key_hint, 'settings', v_link.settings,
    'connected_at', v_link.connected_at, 'counts', v_counts, 'waiting', v_waiting,
    'last_at', v_last.updated_at, 'last_status', v_last.status,
    'last_error', case when v_last.status = 'failed' then v_last.error end);
end $$;

revoke all on function public.acct_link_status(uuid) from public;
grant execute on function public.acct_link_status(uuid) to authenticated;

commit;

select has_function_privilege('authenticated', 'public.acct_link_status(uuid)', 'execute') as li_authenticated,
       not has_function_privilege('anon', 'public.acct_link_status(uuid)', 'execute') as la_li_anon;
