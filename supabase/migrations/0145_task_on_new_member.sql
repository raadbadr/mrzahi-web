-- 0145 — المهندس رعد 2026-09-16: «اول ما يوصل بعد الدعوة، مهمة تنحط لصاحب
-- الحساب لازم يعين المستخدم الجديد ويكون فيه تذكير»، «ماينفع يفضل كدا طاير».
-- المنصة منصة تذكير، فالتنبيه مهمة حقيقية لها تاريخ استحقاق يدخل عليها التذكير
-- كأي عنصر، لا لافتة على شاشة تنسى. وتغلق وحدها حين يضبط قسم العضو ونوعه.
begin;

create or replace function public.tasks_record_for(p_org uuid, p_actor uuid)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_rec uuid;
begin
  select id into v_rec from public.records
   where org_id = p_org and name in ('المهام','Tasks','Taches','ٹاسک')
   order by created_at asc limit 1;
  if v_rec is null then
    insert into public.records (org_id, name, columns, created_by)
    values (p_org, 'المهام', '[]'::jsonb, p_actor) returning id into v_rec;
  end if;
  return v_rec;
end $function$;

create or replace function public.member_name_for(p_user uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.full_name_en), ''),
                  split_part(u.email, '@', 1), 'عضو جديد')
    from auth.users u left join public.profiles p on p.id = u.id
   where u.id = p_user
$function$;

create or replace function public.task_setup_new_member()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_owner uuid; v_rec uuid; v_name text;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' then return new; end if;
  if new.role = 'owner' then return new; end if;
  select owner_id into v_owner from public.organizations where id = new.org_id;
  if v_owner is null then return new; end if;
  if exists (select 1 from public.items i
              where i.org_id = new.org_id and i.status = 'open'
                and i.data->>'kind' = 'member_setup'
                and i.data->>'member' = new.user_id::text) then
    return new;
  end if;
  v_name := public.member_name_for(new.user_id);
  v_rec := public.tasks_record_for(new.org_id, v_owner);
  insert into public.items (org_id, record_id, title, category, due_at, status, assignee_id, data, created_by)
  values (new.org_id, v_rec, 'تعيين العضو الجديد: ' || v_name, 'مهمة',
          now() + interval '1 day', 'open', v_owner,
          jsonb_build_object('kind', 'member_setup', 'member', new.user_id::text,
                             'why', 'اضبط قسمه ونوعه وواجهته لتظهر له خدماته الصحيحة'),
          v_owner);
  return new;
end $function$;

drop trigger if exists org_members_setup_task on public.org_members;
create trigger org_members_setup_task
  after insert or update of status on public.org_members
  for each row execute function public.task_setup_new_member();

create or replace function public.task_close_member_setup()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.department is null or new.person_kind is null then return new; end if;
  update public.items
     set status = 'done', completed_at = now(), updated_at = now()
   where org_id = new.org_id and status = 'open'
     and data->>'kind' = 'member_setup'
     and data->>'member' = new.user_id::text;
  return new;
end $function$;

drop trigger if exists org_members_setup_done on public.org_members;
create trigger org_members_setup_done
  after update of department, person_kind, role on public.org_members
  for each row execute function public.task_close_member_setup();

commit;
