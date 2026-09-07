-- المقاعد المدفوعة: الباقة تعطي عددا أساسيا، وما زاد يُشترى مقعدا مقعدا.
-- العدد يُسجَّل على الاشتراك نفسه، والحد يصير: أساس الباقة + المقاعد المشتراة.
alter table public.subscriptions add column if not exists extra_seats integer not null default 0;

create or replace function public.enforce_member_limit()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare lim int; cnt int; pc text; seats int;
begin
  pc := public.effective_plan(new.org_id);
  select (p.limits->>'members')::int into lim from public.plans p where p.code = pc;
  if lim is not null then
    select coalesce(max(s.extra_seats), 0) into seats
      from public.subscriptions s
     where s.org_id = new.org_id and s.status = 'active'
       and (s.expires_at is null or s.expires_at > now());
    lim := lim + coalesce(seats, 0);
    select count(*) into cnt from public.org_members where org_id = new.org_id;
    if cnt >= lim then
      if pc = 'expired' then
        raise exception 'PLAN_EXPIRED: انتهت الفترة التجريبية — فعّل اشتراكاً للمتابعة' using errcode = 'P0001';
      end if;
      raise exception 'PLAN_LIMIT_MEMBERS: الباقة الحالية تسمح بـ % عضو', lim using errcode = 'P0001';
    end if;
  end if;
  return new;
end $function$;
