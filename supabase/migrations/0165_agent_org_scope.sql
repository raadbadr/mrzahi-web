-- 0165: نطاق الحساب للمساعد — «دا حساب ودا حساب» (أمر المهندس رعد 2026-09-20)
--
-- العطل: كل دوال المساعد (17 دالة) تحدد نطاقها بـ telegram_user_org(s) ومعيارهما
-- المستخدم لا الحساب، فمن له أكثر من حساب ولا ربط تيليغرام محدد يقرأ ويكتب عبر
-- حساباته كلها مجتمعة: يفتح حسابه الشخصي ويقول «أنجزت الإيجار» فيصيب عنصرا في
-- حساب الشركة. قياس 2026-09-20 على جدة: 15 مستخدما لهم عضوية نشطة، منهم 6
-- متعددو الحسابات، و4 من هؤلاء بلا ربط تيليغرام نشط — فهم متأثرون فعلا.
--
-- الإصلاح مركزي بلا تغيير توقيع دالة واحدة، فلا نداء في الـ Worker يتغير ولا
-- نافذة عطل: يضاف «الحساب الذي اختاره صاحبه للمساعد» ويقدم على ما عداه، ويبقى
-- السلوك القائم حرفيا حين لا اختيار (ربط تيليغرام، ثم كل الحسابات).

alter table public.profiles add column if not exists agent_org_id uuid references public.organizations(id) on delete set null;

-- يضبطه الموقع عند كل طلب دردشة بالحساب المفتوح على الشاشة، ويضبطه زر «الشركة» في البوت
create or replace function public.agent_set_org(p_secret text, p_user_id uuid, p_org uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_name text; v_personal boolean;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select o.name into v_name from public.org_members m join public.organizations o on o.id = m.org_id
  where m.user_id = p_user_id and m.org_id = p_org and m.status = 'active';
  if v_name is null then return jsonb_build_object('status', 'not_member'); end if;
  select coalesce(p.entity_type = 'individual', false) into v_personal from public.org_profiles p where p.org_id = p_org;
  update public.profiles set agent_org_id = p_org where id = p_user_id;
  return jsonb_build_object('status', 'ok', 'name', v_name, 'personal', coalesce(v_personal, false));
end $$;
revoke all on function public.agent_set_org(text, uuid, uuid) from public;
grant execute on function public.agent_set_org(text, uuid, uuid) to anon, service_role;

-- حساب واحد للكتابة: اختيار المساعد، ثم ربط تيليغرام، ثم أول حساب (كما كانت)
create or replace function public.telegram_user_org(p_user_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.agent_org_id
       from public.profiles p
       join public.org_members m on m.org_id = p.agent_org_id and m.user_id = p_user_id and m.status = 'active'
      where p.id = p_user_id and p.agent_org_id is not null),
    (select l.active_org_id
       from public.channel_links l
       join public.org_members m on m.org_id = l.active_org_id and m.user_id = p_user_id and m.status = 'active'
      where l.user_id = p_user_id and l.channel = 'telegram' and l.verified_at is not null and l.active_org_id is not null
      order by l.verified_at desc limit 1),
    (select o.id from public.organizations o
       join public.org_members m on m.org_id = o.id
      where m.user_id = p_user_id and m.status = 'active'
      order by (m.role = 'owner') desc, (m.role = 'admin') desc, m.created_at asc limit 1)
  )
$$;

-- نطاق القراءة: الحساب المختار وحده إن وجد اختيار، وإلا كل الحسابات (كما كانت)
create or replace function public.telegram_user_orgs(p_user_id uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  with pick as (
    select coalesce(
      (select p.agent_org_id
         from public.profiles p
         join public.org_members m on m.org_id = p.agent_org_id and m.user_id = p_user_id and m.status = 'active'
        where p.id = p_user_id and p.agent_org_id is not null),
      (select l.active_org_id
         from public.channel_links l
         join public.org_members m on m.org_id = l.active_org_id and m.user_id = p_user_id and m.status = 'active'
        where l.user_id = p_user_id and l.channel = 'telegram' and l.verified_at is not null and l.active_org_id is not null
        order by l.verified_at desc limit 1)
    ) as org
  )
  select m.org_id from public.org_members m, pick
   where m.user_id = p_user_id and m.status = 'active'
     and (pick.org is null or m.org_id = pick.org)
$$;

-- زر «الشركة» في البوت يكتب الاثنين، فلا يطغى اختيار ويب قديم على اختياره الآن
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
  update public.profiles set agent_org_id = p_org where id = p_user_id;
  return jsonb_build_object('status', 'ok', 'name', v_name, 'personal', coalesce(v_personal, false));
end $$;

-- دفاع في العمق: العمود لا يكتبه الا الدالتان (agent_set_org و telegram_set_org).
-- منح UPDATE على جدول profiles يشمل كل الاعمدة، و revoke على عمود واحد لا يلغيه
-- (قيس: بعد revoke بقيت الصلاحية) — فالمنع بمشغل يرد القيمة القديمة لمن ينفذ بدور
-- authenticated او anon، بينما الدالتان تعملان بدور المالك فتمران.
-- والقراءة في telegram_user_org/orgs تشترط عضوية نشطة اصلا، ففحص 2026-09-20 داخل
-- معاملة ملغاة: uuid لمنظمة غير عضو فيها ابقى النطاق على حساباته هو (3 من 3).
-- بلا security definer عمدا: داخل دالة تعمل بدور المالك يصير current_user هو
-- المالك، فيمر كل شيء. قيس: النسخة الاولى بـ definer لم تمنع تحديث المستخدم.
create or replace function public.profiles_guard_agent_org()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then new.agent_org_id := old.agent_org_id; end if;
  return new;
end $$;
drop trigger if exists profiles_guard_agent_org on public.profiles;
create trigger profiles_guard_agent_org before update on public.profiles
for each row execute function public.profiles_guard_agent_org();
