-- المهندس رعد 2026-09-08: «اذا شخص دخل سجل ممكن يكون حاب ينضم لشركة موجودة اصلا».
--
-- الدعوة اليوم تبدا من صاحب الحساب وحده: يكتب بريد العضو فتقبل دعوته تلقائيا عند
-- اول دخول. من لم يدع لا باب له. هذا الطلب يفتح الباب من الجهة الاخرى: يكتب رقم
-- الحساب فيصل صاحبه طلب، وهو وحده من يقبل او يرفض. لا احد يدخل حسابا بلا اذن.
--
-- الطلبات في جدول مستقل لا في org_members: حالة العضوية محصورة في invited/active،
-- وطلب معلق ليس عضوية، فلا يحسب من مقاعد الباقة ولا يظهر في قائمة الفريق.

create table if not exists public.join_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  note text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id)
);

-- طلب معلق واحد لكل شخص في كل حساب
create unique index if not exists join_requests_one_open
  on public.join_requests (org_id, user_id) where status = 'pending';
create index if not exists join_requests_org_pending
  on public.join_requests (org_id) where status = 'pending';

alter table public.join_requests enable row level security;
-- لا سياسة: الوصول كله عبر الدوال ادناه، فلا يقرا احد طلبات غيره
revoke all on table public.join_requests from anon, authenticated;

-- الطلب: برقم الحساب وحده. لا يكشف الرقم الخاطئ شيئا، ولا يرى الطالب الحساب
-- قبل ان يقبله صاحبه.
create or replace function public.request_join_org(p_code text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid(); v_code text; v_org uuid; v_name text; v_owner uuid; v_id uuid; v_actor_name text;
begin
  if v_actor is null then raise exception 'forbidden' using errcode = '42501'; end if;
  v_code := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  if v_code = '' then raise exception 'CODE_REQUIRED' using errcode = 'P0001'; end if;
  select id, name, owner_id into v_org, v_name, v_owner
  from public.organizations where upper(org_number) = v_code limit 1;
  if v_org is null then raise exception 'ORG_NOT_FOUND' using errcode = 'P0001'; end if;
  if exists (select 1 from public.org_members where org_id = v_org and user_id = v_actor and status = 'active') then
    raise exception 'ALREADY_MEMBER' using errcode = 'P0001';
  end if;

  select id into v_id from public.join_requests
  where org_id = v_org and user_id = v_actor and status = 'pending' limit 1;
  if v_id is null then
    insert into public.join_requests (org_id, user_id, note) values (v_org, v_actor, nullif(btrim(coalesce(p_note, '')), ''))
    returning id into v_id;
    select coalesce(p.full_name, p.email) into v_actor_name from public.profiles p where p.id = v_actor;
    -- صاحب الحساب ومدراؤه يرون الطلب في جرس الاشعارات
    perform public.notify_inapp(v_org, m.user_id, jsonb_build_object(
      'kind', 'join_request',
      'title', 'طلب انضمام الى ' || coalesce(v_name, ''),
      'org_id', v_org,
      'org_name', v_name,
      'actor', v_actor_name,
      'request_id', v_id
    ))
    from public.org_members m
    where m.org_id = v_org and m.status = 'active' and m.role in ('owner', 'admin');
  end if;
  return jsonb_build_object('id', v_id, 'org_name', v_name, 'status', 'pending');
end $$;

-- طلباتي انا: ليعرف الطالب اين وصل طلبه
create or replace function public.my_join_requests()
returns table (id uuid, org_id uuid, org_name text, status text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select r.id, r.org_id, o.name, r.status, r.created_at
  from public.join_requests r join public.organizations o on o.id = r.org_id
  where r.user_id = auth.uid()
  order by r.created_at desc;
$$;

-- طلبات حسابي: للمالك والمدير وحدهما
create or replace function public.org_join_requests(p_org uuid)
returns table (id uuid, user_id uuid, full_name text, email text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.org_members m
                 where m.org_id = p_org and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select r.id, r.user_id, p.full_name, p.email, r.note, r.created_at
    from public.join_requests r left join public.profiles p on p.id = r.user_id
    where r.org_id = p_org and r.status = 'pending'
    order by r.created_at asc;
end $$;

-- القرار: القبول يضيف عضوا نشطا (حد المقاعد يحرسه الترجر كما لاي عضو)، والرفض يقفل الطلب
create or replace function public.decide_join_request(p_id uuid, p_accept boolean, p_role text default 'member')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid(); v_org uuid; v_user uuid; v_role text; v_name text;
begin
  if v_actor is null then raise exception 'forbidden' using errcode = '42501'; end if;
  select org_id, user_id into v_org, v_user from public.join_requests where id = p_id and status = 'pending';
  if v_org is null then raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.org_members m
                 where m.org_id = v_org and m.user_id = v_actor and m.status = 'active' and m.role in ('owner', 'admin'))
  then raise exception 'forbidden' using errcode = '42501'; end if;

  if p_accept then
    v_role := case when p_role in ('admin', 'member') then p_role else 'member' end;
    insert into public.org_members (org_id, user_id, role, status, invited_by)
    values (v_org, v_user, v_role, 'active', v_actor)
    on conflict (org_id, user_id) do update set status = 'active', role = excluded.role;
    update public.join_requests set status = 'accepted', decided_at = now(), decided_by = v_actor where id = p_id;
    select name into v_name from public.organizations where id = v_org;
    perform public.notify_inapp(v_org, v_user, jsonb_build_object(
      'kind', 'join_accepted',
      'title', 'قبل انضمامك الى ' || coalesce(v_name, ''),
      'org_id', v_org,
      'org_name', v_name
    ));
  else
    update public.join_requests set status = 'rejected', decided_at = now(), decided_by = v_actor where id = p_id;
  end if;
  return jsonb_build_object('id', p_id, 'accepted', p_accept);
end $$;

revoke all on function public.request_join_org(text, text) from public;
revoke all on function public.my_join_requests() from public;
revoke all on function public.org_join_requests(uuid) from public;
revoke all on function public.decide_join_request(uuid, boolean, text) from public;
grant execute on function public.request_join_org(text, text) to authenticated;
grant execute on function public.my_join_requests() to authenticated;
grant execute on function public.org_join_requests(uuid) to authenticated;
grant execute on function public.decide_join_request(uuid, boolean, text) to authenticated;
