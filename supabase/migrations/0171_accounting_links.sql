-- المهندس رعد 2026-09-23: «نبغى يكون فيه طريقة ربط سهلة مع قيود المحاسبي، او مع اي
-- منصة محاسبية يفضلها العميل». وسئل عن الاتجاه فاختار: الارسال من مستر زاهي الى
-- المحاسبة، فما يدخل في مستر زاهي من مصاريف وفواتير ينشا في المنصة المحاسبية فلا
-- يدخل مرتين.
--
-- النواة عامة لا باسم منصة: جدول ربط واحد لكل حساب (provider يسمي المنصة، واول ما
-- يقبله «qoyod»)، وجدول لكل ارسال. والمنصات الاخرى تضاف قيمة في provider ومحولا
-- في الوركر (src/accounting.js) بلا جدول جديد.
--
-- مفتاح المنصة المحاسبية سر: لا يحفظ نصا في جدول، بل في supabase_vault مشفرا،
-- والجدول يحمل معرفه وحده. ولا سياسة RLS على الجدولين فلا يصل اليهما المتصفح
-- اطلاقا؛ كل كتابة وقراءة عبر دوال security definer محمية بسر الوركر، وحالة الربط
-- للمتصفح بدالة تعيد ما ليس سرا وحده ولعضو الحساب النشط وحده.
--
-- الربط قرار مالك الحساب او مشرفه (كتخزين Google Drive)، والنطاق بالحساب org_id
-- لا بالمستخدم. ولا يرسل الا ما انشئ بعد الربط، فلا يغمر دفاتر المنشاة بقديمها.

begin;

-- 1) الربط: حساب واحد مع منصة واحدة
create table if not exists public.accounting_links (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null unique references public.organizations(id) on delete cascade,
  provider text not null check (provider in ('qoyod')),
  secret_id uuid not null,                         -- معرف المفتاح في vault.secrets، لا المفتاح نفسه
  key_hint text,                                   -- اخر اربعة محارف للعرض وحدها
  settings jsonb not null default '{}'::jsonb,     -- ليس سرا: الفرع وحساب المصروفات ومنتج البيع والمورد الافتراضي
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.accounting_links enable row level security;
revoke all on public.accounting_links from public, anon, authenticated;

-- 2) سجل الارسال: صف لكل عنصر ارسل او ينتظر، يمنع التكرار ويحفظ معرفه عند المنصة
create table if not exists public.accounting_pushes (
  item_id uuid not null references public.items(id) on delete cascade,
  provider text not null,
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null,                              -- expense | purchase_bill | sales_invoice
  status text not null check (status in ('pending', 'sent', 'failed', 'waiting', 'skipped')),
  external_id text,
  external_ref text,
  error text,
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (item_id, provider)
);
create index if not exists accounting_pushes_org_status on public.accounting_pushes (org_id, status);
alter table public.accounting_pushes enable row level security;
revoke all on public.accounting_pushes from public, anon, authenticated;

-- سجل التدقيق: من ربط ومن غير الاعدادات ومن فك الربط (قاعدة 0131: كل جدول يحمل
-- قرارا يخص العميل يسجل). المفتاح نفسه في vault فلا يدخل السجل.
drop trigger if exists accounting_links_ledger on public.accounting_links;
create trigger accounting_links_ledger after insert or delete or update on public.accounting_links
  for each row execute function public.ledger_capture('accounting_link');

-- 3) الدور: مالك او مشرف نشط يدير الربط، وعضو نشط يرى حالته
create or replace function public.acct_role(p_secret text, p_org uuid, p_user uuid)
returns text language plpgsql stable security definer set search_path to 'public' as $$
declare v_role text;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select m.role into v_role from public.org_members m
   where m.org_id = p_org and m.user_id = p_user and m.status = 'active' limit 1;
  if v_role is null then return 'none'; end if;
  return case when v_role in ('owner', 'admin') then 'admin' else 'member' end;
end $$;

-- 4) حفظ الربط بعد ان يتحقق الوركر من المفتاح عند المنصة نفسها
create or replace function public.acct_link_save(p_secret text, p_org uuid, p_user uuid, p_provider text,
                                                 p_key text, p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_link public.accounting_links; v_secret uuid; v_key text := btrim(coalesce(p_key, ''));
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if public.acct_role(p_secret, p_org, p_user) <> 'admin' then return jsonb_build_object('status', 'not_admin'); end if;
  if p_provider is null or p_provider not in ('qoyod') then return jsonb_build_object('status', 'bad_provider'); end if;
  if v_key = '' then return jsonb_build_object('status', 'no_key'); end if;

  select * into v_link from public.accounting_links where org_id = p_org;
  if found then
    perform vault.update_secret(v_link.secret_id, v_key);
    update public.accounting_links
       set provider = p_provider,
           key_hint = right(v_key, 4),
           settings = case when provider = p_provider then settings || coalesce(p_settings, '{}'::jsonb) else coalesce(p_settings, '{}'::jsonb) end,
           connected_by = p_user,
           connected_at = case when provider = p_provider then connected_at else now() end,
           updated_at = now()
     where org_id = p_org;
  else
    v_secret := vault.create_secret(v_key, 'acct:' || p_org::text, 'accounting key for org ' || p_org::text);
    insert into public.accounting_links (org_id, provider, secret_id, key_hint, settings, connected_by)
    values (p_org, p_provider, v_secret, right(v_key, 4), coalesce(p_settings, '{}'::jsonb), p_user);
  end if;
  return jsonb_build_object('status', 'saved');
end $$;

-- 5) اعدادات ليست سرا: تدمج فوق القائم، والقيمة null تمحو مفتاحها
create or replace function public.acct_link_settings(p_secret text, p_org uuid, p_user uuid, p_settings jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if public.acct_role(p_secret, p_org, p_user) <> 'admin' then return jsonb_build_object('status', 'not_admin'); end if;
  update public.accounting_links
     set settings = jsonb_strip_nulls(settings || coalesce(p_settings, '{}'::jsonb)), updated_at = now()
   where org_id = p_org;
  if not found then return jsonb_build_object('status', 'not_connected'); end if;
  return jsonb_build_object('status', 'saved');
end $$;

-- 6) فك الربط: يحذف المفتاح من vault والربط معه، ويبقى سجل ما ارسل
create or replace function public.acct_link_forget(p_secret text, p_org uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_secret uuid;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if public.acct_role(p_secret, p_org, p_user) <> 'admin' then return jsonb_build_object('status', 'not_admin'); end if;
  delete from public.accounting_links where org_id = p_org returning secret_id into v_secret;
  if v_secret is not null then delete from vault.secrets where id = v_secret; end if;
  return jsonb_build_object('status', 'forgotten');
end $$;

-- 7) للوركر وحده: المفتاح مفكوكا مع الاعدادات، لحساب بعينه
create or replace function public.acct_link_key(p_secret text, p_org uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select jsonb_build_object('provider', l.provider, 'key', s.decrypted_secret, 'settings', l.settings,
                            'connected_at', l.connected_at, 'updated_at', l.updated_at)
    into v
    from public.accounting_links l
    join vault.decrypted_secrets s on s.id = l.secret_id
   where l.org_id = p_org;
  return v;
end $$;

-- 8) حالة الربط للمتصفح: ما ليس سرا وحده، ولعضو الحساب النشط وحده
create or replace function public.acct_link_status(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_link public.accounting_links; v_role text; v_counts jsonb; v_last record;
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
  select p.updated_at, p.status, p.error into v_last
    from public.accounting_pushes p
   where p.org_id = p_org and p.provider = v_link.provider and p.status in ('sent', 'failed')
   order by p.updated_at desc limit 1;
  return jsonb_build_object(
    'connected', true, 'can_manage', v_role in ('owner', 'admin'),
    'provider', v_link.provider, 'key_hint', v_link.key_hint, 'settings', v_link.settings,
    'connected_at', v_link.connected_at, 'counts', v_counts,
    'last_at', v_last.updated_at, 'last_status', v_last.status,
    'last_error', case when v_last.status = 'failed' then v_last.error end);
end $$;

-- 9) ما ينتظر الارسال: عناصر مالية انشئت بعد الربط، ولم ترسل، او فشلت ويعاد حقها،
--    او تنتظر بيانا ثم تغيرت هي او اعدادات الربط. التصنيف الدقيق في الوركر بمنطق
--    الواجهة نفسه؛ هنا مرشح عريض يكفي كي لا يمر كل عنصر في المنشاة.
create or replace function public.acct_pending(p_secret text, p_org uuid default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(x.row order by x.created_at), '[]'::jsonb) into v
  from (
    select i.created_at,
           jsonb_build_object('id', i.id, 'org_id', i.org_id, 'provider', l.provider, 'title', i.title,
             'category', i.category, 'amount', i.amount, 'client_name', i.client_name,
             'case_number', i.case_number, 'due_at', i.due_at, 'created_at', i.created_at,
             'status', i.status, 'data', i.data, 'push_status', p.status) as row
      from public.items i
      join public.accounting_links l on l.org_id = i.org_id
      left join public.accounting_pushes p on p.item_id = i.id and p.provider = l.provider
     where (p_org is null or i.org_id = p_org)
       and i.created_at >= l.connected_at
       and coalesce(i.status, '') <> 'cancelled'
       and not (coalesce(i.data, '{}'::jsonb) ? 'document_kind')
       and (   coalesce(i.data, '{}'::jsonb) ? 'fin_dir'
            or coalesce(i.category, '') ~* '(مصروف|مصاريف|expense|d.pense|اخراجات)'
            or (coalesce(i.category, '') = '' and coalesce(i.title, '') ~* '(مصروف|مصاريف|expense|d.pense|اخراجات)'))
       and (   p.item_id is null
            or (p.status = 'failed' and p.attempts < 5 and p.updated_at < now() - interval '15 minutes')
            or (p.status in ('waiting', 'skipped') and (i.updated_at > p.updated_at or l.updated_at > p.updated_at))
            or (p.status = 'pending' and p.updated_at < now() - interval '30 minutes'))
     order by i.created_at
     limit greatest(1, least(coalesce(p_limit, 20), 50))
  ) x;
  return v;
end $$;

-- 10) حجز العنصر قبل ارساله: لا يرسله نداءان معا (الكرون وزر «ارسال الان»)
create or replace function public.acct_claim(p_secret text, p_item uuid, p_org uuid, p_provider text, p_kind text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare v_ok boolean := false;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not exists (select 1 from public.items i join public.accounting_links l on l.org_id = i.org_id
                  where i.id = p_item and i.org_id = p_org and l.provider = p_provider) then
    return false;
  end if;
  insert into public.accounting_pushes (item_id, provider, org_id, kind, status, updated_at)
  values (p_item, p_provider, p_org, p_kind, 'pending', now())
  on conflict (item_id, provider) do update
     set status = 'pending', kind = excluded.kind, error = null, updated_at = now()
   where public.accounting_pushes.status in ('failed', 'waiting', 'skipped')
      or (public.accounting_pushes.status = 'pending' and public.accounting_pushes.updated_at < now() - interval '30 minutes')
  returning true into v_ok;
  return coalesce(v_ok, false);
end $$;

-- 11) نتيجة الارسال: ارسل بمعرفه عند المنصة، او فشل بسببه، او ينتظر بيانا ناقصا
create or replace function public.acct_mark(p_secret text, p_item uuid, p_provider text, p_status text,
                                            p_external_id text default null, p_ref text default null, p_error text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if p_status not in ('sent', 'failed', 'waiting', 'skipped') then raise exception 'bad status %', p_status; end if;
  update public.accounting_pushes
     set status = p_status,
         external_id = coalesce(p_external_id, external_id),
         external_ref = coalesce(p_ref, external_ref),
         error = left(p_error, 500),
         attempts = attempts + case when p_status = 'failed' then 1 else 0 end,
         updated_at = now()
   where item_id = p_item and provider = p_provider;
end $$;

-- الصلاحيات: دوال الوركر لـ anon وحده (مفتاح الوركر العام) ومحمية بالسر، وحالة
-- الربط لـ authenticated وحده. والسحب من PUBLIC صريح لان المنح الافتراضي له.
revoke all on function public.acct_role(text, uuid, uuid) from public;
revoke all on function public.acct_link_save(text, uuid, uuid, text, text, jsonb) from public;
revoke all on function public.acct_link_settings(text, uuid, uuid, jsonb) from public;
revoke all on function public.acct_link_forget(text, uuid, uuid) from public;
revoke all on function public.acct_link_key(text, uuid) from public;
revoke all on function public.acct_link_status(uuid) from public;
revoke all on function public.acct_pending(text, uuid, integer) from public;
revoke all on function public.acct_claim(text, uuid, uuid, text, text) from public;
revoke all on function public.acct_mark(text, uuid, text, text, text, text, text) from public;

grant execute on function public.acct_role(text, uuid, uuid) to anon;
grant execute on function public.acct_link_save(text, uuid, uuid, text, text, jsonb) to anon;
grant execute on function public.acct_link_settings(text, uuid, uuid, jsonb) to anon;
grant execute on function public.acct_link_forget(text, uuid, uuid) to anon;
grant execute on function public.acct_link_key(text, uuid) to anon;
grant execute on function public.acct_pending(text, uuid, integer) to anon;
grant execute on function public.acct_claim(text, uuid, uuid, text, text) to anon;
grant execute on function public.acct_mark(text, uuid, text, text, text, text, text) to anon;
grant execute on function public.acct_link_status(uuid) to authenticated;

commit;

-- تحقق: الجدولان بلا سياسات، والدوال بصلاحياتها، ولا سر واحد في vault قبل اي ربط
select (select count(*) from pg_policies where tablename in ('accounting_links', 'accounting_pushes')) as siyasat,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'acct\_%') as dawal,
       (select count(*) from vault.secrets) as asrar;
