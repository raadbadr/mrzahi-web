-- المهندس رعد 2026-09-16: «في التلغرام مو يظهر اي شركة يكتب اسمي، لا ابغاه
-- يكتب شخصي»، و«اولوية الترتيب دايما شخصي، ثم شركة انا المدير عليها، ثم شركة
-- انا مشرف عليها، واخيرا شركة انا فقط موظف فيها»، و«ترتيب بناء على التحكم
-- والقدرة على الادارة».
--
-- قائمة الحسابات في البوت كانت ترتب بالدور ثم تاريخ الانشاء، فوقع الحساب
-- الشخصي بين الشركات وظهر باسم صاحبه لا بكلمة «شخصي». وزيادة على ذلك كان
-- notify_target ياخذ اسم اول شركة يملكها، فيخالف الحساب النشط الذي يشتغل
-- عليه البوت فعلا بعد التبديل.

begin;

-- قائمة الحسابات في البوت: الشخصي اولا دائما، ثم بحسب التحكم (مالك، مشرف،
-- موظف)، ثم الاقدم. وعلامة personal تقول للـ Worker ان يكتب «شخصي» بلغة
-- المحادثة بدل اسم صاحب الحساب.
create or replace function public.telegram_org_choices(p_secret text, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'role', m.role,
           'personal', coalesce(pr.entity_type = 'individual', false),
           'active', (o.id = (select l.active_org_id from public.channel_links l
                              where l.user_id = p_user_id and l.channel = 'telegram' and l.verified_at is not null
                              order by l.verified_at desc limit 1)))
         order by coalesce(pr.entity_type = 'individual', false) desc,   -- حساب بلا بطاقة يعطي NULL، وNULL في DESC يتصدر القائمة
                  case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
                  o.created_at), '[]'::jsonb)
  into result
  from public.org_members m
  join public.organizations o on o.id = m.org_id
  left join public.org_profiles pr on pr.org_id = o.id
  where m.user_id = p_user_id and m.status = 'active';
  return result;
end $$;

-- اسم الحساب في تحية الربط وفي سياق المساعد: الحساب النشط في البوت نفسه
-- (telegram_user_org) لا اول شركة يملكها، ومعه علامة الشخصي.
create or replace function public.notify_target(p_secret text, p_user_id uuid, p_channel text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  if not public.check_worker_secret(p_secret) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_org := public.telegram_user_org(p_user_id);
  return jsonb_build_object(
    'email', (select email from public.profiles where id = p_user_id),
    'full_name', (select full_name from public.profiles where id = p_user_id),
    'full_name_en', (select full_name_en from public.profiles where id = p_user_id),
    'lang', coalesce((select lang from public.profiles where id = p_user_id), 'ar'),
    'tz', coalesce((select tz from public.profiles where id = p_user_id), 'Asia/Riyadh'),
    'time_format', coalesce((select time_format from public.profiles where id = p_user_id), '24'),
    'org_id', v_org,
    'org_name', (select o.name from public.organizations o where o.id = v_org),
    'org_personal', coalesce((select p.entity_type = 'individual' from public.org_profiles p where p.org_id = v_org), false),
    'external_id', (select external_id from public.channel_links
                    where user_id = p_user_id and channel = p_channel and verified_at is not null)
  );
end $$;

-- لوحة البوت: العلامة نفسها حتى لا يكتب اسم صاحب الحساب مكان اسم الجهة
create or replace function public.telegram_overview(p_secret text, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_org_name text; v_personal boolean; result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  v_org := public.telegram_user_org(p_user_id);
  if v_org is null then return jsonb_build_object('status', 'no_org'); end if;
  select name into v_org_name from public.organizations where id = v_org;
  select coalesce(p.entity_type = 'individual', false) into v_personal from public.org_profiles p where p.org_id = v_org;

  select jsonb_build_object(
    'status', 'ok',
    'org_name', v_org_name,
    'personal', coalesce(v_personal, false),
    'total', (select count(*) from public.items i where i.org_id = v_org),
    'open',  (select count(*) from public.items i where i.org_id = v_org and i.status = 'open'),
    'done',  (select count(*) from public.items i where i.org_id = v_org and i.status = 'done'),
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', t.name,
               'open', (select count(*) from public.items i where i.record_id = t.id and i.status = 'open'),
               'done', (select count(*) from public.items i where i.record_id = t.id and i.status = 'done'),
               'next_due', (select min(i.due_at) from public.items i where i.record_id = t.id and i.status = 'open' and i.due_at is not null))
             order by (select count(*) from public.items i where i.record_id = t.id and i.status = 'open') desc)
      from public.records t where t.org_id = v_org), '[]'::jsonb),
    'kinds', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k.kind, 'open', k.open_count, 'done', k.done_count) order by k.open_count desc)
      from (
        select public.item_kind(i.category, i.case_number, i.data, i.parent_id) as kind,
               count(*) filter (where i.status = 'open') as open_count,
               count(*) filter (where i.status = 'done') as done_count
        from public.items i
        where i.org_id = v_org
        group by 1
      ) k), '[]'::jsonb)
  ) into result;

  return result;
end $$;

-- تاكيد التبديل يقول «شخصي» ايضا لا اسم صاحب الحساب
create or replace function public.telegram_set_org(p_secret text, p_user_id uuid, p_org uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_name text; v_personal boolean;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select o.name into v_name from public.org_members m join public.organizations o on o.id = m.org_id
  where m.user_id = p_user_id and m.org_id = p_org and m.status = 'active';
  if v_name is null then return jsonb_build_object('status', 'not_member'); end if;
  select coalesce(p.entity_type = 'individual', false) into v_personal from public.org_profiles p where p.org_id = p_org;
  update public.channel_links set active_org_id = p_org where user_id = p_user_id and channel = 'telegram' and verified_at is not null;
  return jsonb_build_object('status', 'ok', 'name', v_name, 'personal', coalesce(v_personal, false));
end $$;

commit;
