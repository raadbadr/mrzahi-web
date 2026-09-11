-- الترحيل كما طبق على Supabase (version 20260903194424, name tracker_0008_canonical_numbers); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
-- أرقام قياسية بنفس أسلوب باركينزي (generate_canonical_number):
-- USR للمستخدم، ORG للشركة، ITM للعنصر — بصيغة TYPE-DDMMYYYY-0001.

alter table public.profiles      add column if not exists profile_number text;
alter table public.organizations add column if not exists org_number text;
alter table public.items         add column if not exists item_number text;

create unique index if not exists profiles_profile_number_key on public.profiles (profile_number) where profile_number is not null;
create unique index if not exists organizations_org_number_key on public.organizations (org_number) where org_number is not null;
create unique index if not exists items_item_number_key on public.items (item_number) where item_number is not null;

create or replace function public.generate_canonical_number(p_type text, p_date_string text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  num_type text;
  effective_date text;
  number_prefix text;
  current_max integer := 0;
  next_sequence integer;
begin
  num_type := upper(btrim(coalesce(p_type, '')));
  if num_type not in ('USR', 'ORG', 'ITM') then
    raise exception 'invalid type: %', num_type;
  end if;

  effective_date := btrim(coalesce(p_date_string, to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY')));
  number_prefix := num_type || '-' || effective_date || '-';

  perform pg_advisory_xact_lock(hashtext('tracker_canonical_number'), hashtext(number_prefix));

  if num_type = 'USR' then
    select coalesce(max(right(p.profile_number, 4)::integer), 0) into current_max
    from public.profiles p
    where p.profile_number like number_prefix || '%'
      and length(p.profile_number) = length(number_prefix) + 4
      and right(p.profile_number, 4) ~ '^[0-9]{4}$';
  elsif num_type = 'ORG' then
    select coalesce(max(right(o.org_number, 4)::integer), 0) into current_max
    from public.organizations o
    where o.org_number like number_prefix || '%'
      and length(o.org_number) = length(number_prefix) + 4
      and right(o.org_number, 4) ~ '^[0-9]{4}$';
  else
    select coalesce(max(right(i.item_number, 4)::integer), 0) into current_max
    from public.items i
    where i.item_number like number_prefix || '%'
      and length(i.item_number) = length(number_prefix) + 4
      and right(i.item_number, 4) ~ '^[0-9]{4}$';
  end if;

  next_sequence := current_max + 1;
  if next_sequence > 9999 then
    raise exception 'canonical sequence overflow for prefix %', number_prefix using errcode = 'check_violation';
  end if;

  return number_prefix || lpad(next_sequence::text, 4, '0');
end $$;

revoke all on function public.generate_canonical_number(text, text) from public;
grant execute on function public.generate_canonical_number(text, text) to authenticated, service_role;

-- مشغّلات تعبئة الرقم تلقائياً
create or replace function public.set_profile_number()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.profile_number is null then
    new.profile_number := public.generate_canonical_number('USR', to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY'));
  end if;
  return new;
end $$;

create or replace function public.set_org_number()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.org_number is null then
    new.org_number := public.generate_canonical_number('ORG', to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY'));
  end if;
  return new;
end $$;

create or replace function public.set_item_number()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.item_number is null then
    new.item_number := public.generate_canonical_number('ITM', to_char(now() at time zone 'Asia/Riyadh', 'DDMMYYYY'));
  end if;
  return new;
end $$;

drop trigger if exists profiles_set_number on public.profiles;
create trigger profiles_set_number before insert on public.profiles
  for each row execute function public.set_profile_number();

drop trigger if exists organizations_set_number on public.organizations;
create trigger organizations_set_number before insert on public.organizations
  for each row execute function public.set_org_number();

drop trigger if exists items_set_number on public.items;
create trigger items_set_number before insert on public.items
  for each row execute function public.set_item_number();

revoke all on function public.set_profile_number() from public, anon, authenticated;
revoke all on function public.set_org_number() from public, anon, authenticated;
revoke all on function public.set_item_number() from public, anon, authenticated;

-- ترقيم الصفوف الموجودة
update public.profiles p set profile_number = public.generate_canonical_number('USR', to_char(p.created_at at time zone 'Asia/Riyadh', 'DDMMYYYY')) where p.profile_number is null;
update public.organizations o set org_number = public.generate_canonical_number('ORG', to_char(o.created_at at time zone 'Asia/Riyadh', 'DDMMYYYY')) where o.org_number is null;
update public.items i set item_number = public.generate_canonical_number('ITM', to_char(i.created_at at time zone 'Asia/Riyadh', 'DDMMYYYY')) where i.item_number is null;
