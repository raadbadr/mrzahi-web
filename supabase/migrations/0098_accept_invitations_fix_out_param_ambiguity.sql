-- الترحيل كما طبق على Supabase (version 20260903202629, name accept_invitations_fix_out_param_ambiguity); اضيف الى المستودع 2026-09-11 لسد فجوة الترحيلات
drop function if exists public.accept_my_invitations();
drop function if exists public.accept_invitations_for(uuid);

create or replace function public.accept_invitations_for(u uuid)
returns table (joined_org_id uuid, joined_org_name text, joined_role text)
language plpgsql security definer set search_path = public as $$
declare
  mail text;
  inv record;
  joined boolean;
begin
  if u is null then return; end if;
  select lower(email) into mail from auth.users where id = u;
  if mail is null or mail = '' then return; end if;

  for inv in
    select i.id, i.org_id as oid, i.role as r, i.invited_by as by
    from public.invitations i
    where lower(i.email) = mail and i.accepted_at is null
    order by i.created_at
  loop
    joined := true;
    begin
      insert into public.org_members as m (org_id, user_id, role, status, invited_email, invited_by)
      values (inv.oid, u, inv.r, 'active', mail, inv.by)
      on conflict (org_id, user_id) do nothing;
    exception when others then
      joined := false;
    end;
    if joined then
      update public.invitations set accepted_at = now() where id = inv.id;
      return query
        select o.id, o.name, inv.r from public.organizations o where o.id = inv.oid;
    end if;
  end loop;
end $$;

revoke all on function public.accept_invitations_for(uuid) from public, anon, authenticated;

create or replace function public.accept_my_invitations()
returns table (joined_org_id uuid, joined_org_name text, joined_role text)
language sql security definer set search_path = public as $$
  select * from public.accept_invitations_for(auth.uid());
$$;

revoke all on function public.accept_my_invitations() from public, anon;
grant execute on function public.accept_my_invitations() to authenticated;
