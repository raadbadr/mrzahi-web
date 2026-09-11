-- سجل التدقيق: من فعل ماذا ومتى، وما كانت القيمة قبل وبعد (امر المهندس رعد 2026-09-11:
-- «سجل تدقيق دا مهم اصلا بالذات لو فيه فريق نعرف مين مسح البيانات»).
--
-- وهو التزام نظامي لا ميزة: المادة 6/3 من اللائحة التنفيذية لنظام التعاملات الالكترونية
-- تلزم بـ«تسجيل جميع الحالات التي يتم فيها الاطلاع على تلك السجلات، او الوصول اليها،
-- او التغيير فيها او في بياناتها».
--
-- السلسلة على نمط الفاتورة الالكترونية (هيئة الزكاة والضريبة والجمارك تفرض هاش الفاتورة
-- السابقة PIH): كل قيد يحمل هاش القيد الذي سبقه في المنشاة نفسها، فاي تعديل وسطي يكسر
-- السلسلة ويكشف بالحساب. لا سلسلة موزعة ولا نشر خارجي.
--
-- pgcrypto في مخطط extensions على Supabase، والدوال هنا تعمل بـ search_path = public فتؤهل digest صراحة.
-- التصميم: الفرق وحده يحفظ عند التعديل (لا الصف كاملا) فلا ينتفخ الحجم، والصف كاملا
-- يحفظ عند الحذف قبل اختفائه — وهو جوهر السؤال «مين مسح وايش كان فيه».

create table if not exists public.ledger (
  seq          bigserial primary key,
  org_id       uuid not null references public.organizations(id) on delete cascade,
  at           timestamptz not null default now(),
  actor        uuid,          -- auth.uid() وقت الفعل؛ فارغ للافعال الخلفية (الوركر والمهام)
  actor_name   text,          -- لقطة الاسم وقت الفعل: لا يضيع بحذف العضوية او تغير الاسم
  entity_type  text not null check (entity_type in ('item','attachment','member','record')),
  entity_id    uuid,
  action       text not null check (action in ('insert','update','delete','read')),
  summary      text,          -- عنوان مقروء وقت الفعل: «قضية تجارية رقم 1002»
  before       jsonb,         -- عند التعديل: الحقول المتغيرة وحدها. عند الحذف: الصف كاملا
  after        jsonb,
  row_hash     text not null,
  prev_hash    text not null,
  hash         text not null
);

comment on table public.ledger is 'سجل تدقيق بالالحاق فقط: كل قيد يقفل ما قبله بهاشه. لا يعدل ولا يحذف.';

create index if not exists ledger_org_seq_idx    on public.ledger (org_id, seq desc);
create index if not exists ledger_entity_idx     on public.ledger (org_id, entity_type, entity_id, seq desc);
create index if not exists ledger_actor_idx      on public.ledger (org_id, actor, seq desc);

-- ── ختم القيد: يحسب السلسلة قبل الادراج ───────────────────────────────────────
-- القفل الاستشاري لكل منشاة يمنع قيدين متزامنين من قراءة السلف نفسه فتتفرع السلسلة.
create or replace function public.ledger_seal()
returns trigger language plpgsql as $$
declare v_prev text;
begin
  perform pg_advisory_xact_lock(hashtext('mrzahi.ledger:' || new.org_id::text));
  select l.hash into v_prev from public.ledger l where l.org_id = new.org_id order by l.seq desc limit 1;
  new.prev_hash := coalesce(v_prev, repeat('0', 64));
  new.row_hash := encode(extensions.digest(
      coalesce(new.entity_type, '') || '|' || coalesce(new.entity_id::text, '') || '|' ||
      new.action || '|' || coalesce(new.before::text, '') || '|' || coalesce(new.after::text, ''),
      'sha256'), 'hex');
  new.hash := encode(extensions.digest(
      new.prev_hash || '|' || new.seq::text || '|' ||
      to_char(new.at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
      coalesce(new.actor::text, '') || '|' || new.row_hash,
      'sha256'), 'hex');
  return new;
end $$;

drop trigger if exists ledger_seal_before_insert on public.ledger;
create trigger ledger_seal_before_insert before insert on public.ledger
  for each row execute function public.ledger_seal();

-- ── المنع: لا تعديل ولا حذف، ولا للمالك ──────────────────────────────────────
-- قيد صريح لا اعتمادا على غياب سياسة RLS: المحفز يرفض حتى لمن يتجاوز RLS.
-- الحذف الوحيد المسموح: الحذف المتتالي مع حذف المنشاة نفسها (المنشاة تكون قد اختفت لحظة المحفز)،
-- امتثالا لحق الاتلاف؛ وما عدا ذلك يرفض حتى لمن يتجاوز RLS.
create or replace function public.ledger_immutable()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.organizations o where o.id = old.org_id) then
    return old;
  end if;
  raise exception 'سجل التدقيق لا يعدل ولا يحذف (mrzahi ledger is append-only)';
end $$;

drop trigger if exists ledger_no_change on public.ledger;
create trigger ledger_no_change before update or delete on public.ledger
  for each row execute function public.ledger_immutable();

alter table public.ledger enable row level security;

drop policy if exists ledger_read on public.ledger;
create policy ledger_read on public.ledger for select
  using (org_id in (select public.current_org_ids()) or public.is_platform_admin());

revoke all on public.ledger from anon, authenticated;
grant select on public.ledger to authenticated;
revoke all on sequence public.ledger_seq_seq from anon, authenticated;

-- ── الالتقاط: محفز واحد يخدم كل الجداول ──────────────────────────────────────
-- security definer كي يكتب المحفز في السجل بينما المستخدم نفسه لا يملك insert عليه.
create or replace function public.ledger_capture()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_type text := tg_argv[0];
  v_org uuid; v_id uuid; v_summary text;
  v_before jsonb; v_after jsonb;
  v_old jsonb; v_new jsonb; v_full jsonb;
  v_skip text[] := array['updated_at'];   -- يتغير مع كل تعديل فلا يعد فرقا
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_full := coalesce(v_new, v_old);
  v_org := (v_full ->> 'org_id')::uuid;

  /* حذف الشركة يتتالى على جداولها: الشركة تختفي اولا فيسقط المفتاح الاجنبي هنا،
     ولو سجلنا لاستحال حذف الشركة اصلا. والسجل يذهب معها امتثالا لحق الاتلاف. */
  if v_org is null or not exists (select 1 from public.organizations o where o.id = v_org) then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    v_before := v_old;                    -- الصف كاملا قبل اختفائه: «مين مسح وايش كان فيه»
  elsif tg_op = 'INSERT' then
    v_after := v_new;
  else
    select jsonb_object_agg(key, value) into v_before
      from jsonb_each(v_old) where not (key = any(v_skip)) and v_new -> key is distinct from value;
    select jsonb_object_agg(key, value) into v_after
      from jsonb_each(v_new) where not (key = any(v_skip)) and v_old -> key is distinct from value;
    if v_after is null then return new; end if;   -- لمسة بلا تغيير فعلي: لا تسجل
  end if;

  v_id := case when v_type = 'member' then (v_full ->> 'user_id')::uuid else (v_full ->> 'id')::uuid end;
  v_summary := coalesce(v_full ->> 'title', v_full ->> 'name', v_full ->> 'role');

  insert into public.ledger (org_id, actor, actor_name, entity_type, entity_id, action, summary, before, after)
  values (v_org, auth.uid(),
          (select p.full_name from public.profiles p where p.id = auth.uid()),
          v_type, v_id, lower(tg_op), left(v_summary, 300), v_before, v_after);

  return coalesce(new, old);
end $$;

drop trigger if exists items_ledger        on public.items;
drop trigger if exists attachments_ledger  on public.attachments;
drop trigger if exists members_ledger      on public.org_members;
drop trigger if exists records_ledger      on public.records;

create trigger items_ledger       after insert or update or delete on public.items
  for each row execute function public.ledger_capture('item');
create trigger attachments_ledger after insert or update or delete on public.attachments
  for each row execute function public.ledger_capture('attachment');
create trigger members_ledger     after insert or update or delete on public.org_members
  for each row execute function public.ledger_capture('member');
create trigger records_ledger     after insert or update or delete on public.records
  for each row execute function public.ledger_capture('record');

-- ── تسجيل الاطلاع (م6/3) ─────────────────────────────────────────────────────
-- ينادى من التطبيق عند فتح مرفق او تنزيله. لا محفز له: القراءة لا محفز عليها.
create or replace function public.ledger_log_read(p_entity_type text, p_entity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_summary text;
begin
  if p_entity_type = 'attachment' then
    select a.org_id, a.name into v_org, v_summary from public.attachments a where a.id = p_entity_id;
  elsif p_entity_type = 'item' then
    select i.org_id, i.title into v_org, v_summary from public.items i where i.id = p_entity_id;
  else
    return;
  end if;
  if v_org is null or v_org not in (select public.current_org_ids()) then return; end if;
  insert into public.ledger (org_id, actor, actor_name, entity_type, entity_id, action, summary)
  values (v_org, auth.uid(),
          (select p.full_name from public.profiles p where p.id = auth.uid()),
          p_entity_type, p_entity_id, 'read', left(v_summary, 300));
end $$;

revoke all on function public.ledger_log_read(text, uuid) from public, anon;
grant execute on function public.ledger_log_read(text, uuid) to authenticated;

-- ── فحص سلامة السلسلة ────────────────────────────────────────────────────────
-- يعيد حساب هاش كل قيد ويقارنه بالمحفوظ ويتحقق من ارتباطه بسلفه.
create or replace function public.ledger_verify(p_org uuid)
returns table (total bigint, first_broken_seq bigint, ok boolean)
language plpgsql security definer set search_path = public as $$
declare r record; v_prev text := repeat('0', 64); v_row text; v_hash text; v_broken bigint; v_total bigint := 0;
begin
  if p_org not in (select public.current_org_ids()) and not public.is_platform_admin() then
    raise exception 'unauthorized';
  end if;
  for r in select * from public.ledger where org_id = p_org order by seq asc loop
    v_total := v_total + 1;
    v_row := encode(extensions.digest(
      coalesce(r.entity_type, '') || '|' || coalesce(r.entity_id::text, '') || '|' ||
      r.action || '|' || coalesce(r.before::text, '') || '|' || coalesce(r.after::text, ''), 'sha256'), 'hex');
    v_hash := encode(extensions.digest(
      v_prev || '|' || r.seq::text || '|' ||
      to_char(r.at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
      coalesce(r.actor::text, '') || '|' || v_row, 'sha256'), 'hex');
    if v_broken is null and (v_row <> r.row_hash or v_hash <> r.hash or v_prev <> r.prev_hash) then
      v_broken := r.seq;
    end if;
    v_prev := r.hash;
  end loop;
  return query select v_total, v_broken, v_broken is null;
end $$;

revoke all on function public.ledger_verify(uuid) from public, anon;
grant execute on function public.ledger_verify(uuid) to authenticated;
