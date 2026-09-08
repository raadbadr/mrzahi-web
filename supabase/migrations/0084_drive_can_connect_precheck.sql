-- ============================================================
-- 0084 - فحص الدور قبل ارسال العضو الى شاشة موافقة جوجل.
-- بلا هذا الفحص كان العضو العادي يمضي الى جوجل ويمنح المنصة اذن
-- الوصول الى درايفه الشخصي فعلا، ثم يرد عليه not_admin بعد فوات
-- الاوان فيرمى الرمز ويبقى في حسابه اذن ممنوح لتطبيق لا يستعمله.
-- (رصدتها جلسة البوت والمستندات في مراجعتها لـ 0067 و0068.)
--
-- الرقم مأخوذ من اخر رقم مستعمل في مجلد الهجرات لا من الذاكرة،
-- لان الارقام تتصادم بين الجلسات المتوازية.
-- ============================================================

create or replace function public.drive_conn_can_connect(p_secret text, p_org uuid, p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.check_worker_secret(p_secret) then raise exception 'unauthorized' using errcode = '42501'; end if;
  if not public.drive_conn_admin(p_org, p_user) then return jsonb_build_object('status', 'not_admin'); end if;
  return jsonb_build_object('status', 'ok');
end $$;

revoke all on function public.drive_conn_can_connect(text, uuid, uuid) from public;
grant execute on function public.drive_conn_can_connect(text, uuid, uuid) to anon, service_role;
