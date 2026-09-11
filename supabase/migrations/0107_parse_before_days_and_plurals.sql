-- الترحيل كما طبق على Supabase (version 20260905105721, name parse_before_days_and_plurals); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
create or replace function public.telegram_parse_before(p_before text)
returns interval language plpgsql immutable as $$
declare t text := lower(btrim(coalesce(p_before, ''))); v interval; n int;
begin
  if t = '' then return null; end if;
  -- رقم مجرد = أيام («نبهني قبلها بـ 3») قبل أي تفسير آخر، وإلا قرأه بوستجرس ثواني
  if t ~ '^\d+$' then return make_interval(days => t::int); end if;

  if t ~ 'يومين' then return interval '2 days'; end if;
  if t ~ 'ساعتين' then return interval '2 hours'; end if;
  if t ~ 'نصف\s*ساعة' then return interval '30 minutes'; end if;
  if t ~ 'أسبوعين|اسبوعين' then return interval '14 days'; end if;
  if t ~ 'أسبوع|اسبوع' then return interval '7 days'; end if;

  n := nullif(regexp_replace(t, '\D', '', 'g'), '')::int;
  if t ~ 'دقيق' then return make_interval(mins => coalesce(n, 30)); end if;
  if t ~ 'ساع'  then return make_interval(hours => coalesce(n, 1)); end if;
  if t ~ 'يوم|أيام|ايام' then return make_interval(days => coalesce(n, 1)); end if;
  if t ~ 'شهر|أشهر|اشهر|شهور' then return make_interval(days => 30 * coalesce(n, 1)); end if;

  begin v := t::interval; exception when others then v := null; end;
  return v;
end $$;
