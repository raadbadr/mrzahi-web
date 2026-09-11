-- فحص معيار Google Drive من الخادم لكل الحسابات المرتبطة (امر المهندس رعد 2026-09-11:
-- «كل المستخدمين اذا قديم النظام يشيك يشوف الفولدر يعدله على المعايير العالية، اذا جديد يسويه منظم»).
-- يعيد لكل شركة مرتبطة رمز التجديد ومعرفات ملفاتها على درايف كي يجد الـ Worker مجلدها الاصلي.
create or replace function public.drive_conn_sweep_list(p_secret text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'org_id', d.org_id,
           'org_name', coalesce(nullif(o.name, ''), nullif(o.name_en, ''), 'Company'),
           'refresh_token', d.refresh_token,
           'file_ids', coalesce((select jsonb_agg(a.drive_file_id order by a.created_at desc)
                                 from public.attachments a where a.org_id = d.org_id and a.drive_file_id is not null), '[]'::jsonb)
         )), '[]'::jsonb)
    into result
  from public.drive_connections d join public.organizations o on o.id = d.org_id;
  return result;
end $$;
revoke all on function public.drive_conn_sweep_list(text) from public, anon;
grant execute on function public.drive_conn_sweep_list(text) to authenticated, service_role;
