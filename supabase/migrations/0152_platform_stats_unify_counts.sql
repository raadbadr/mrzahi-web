-- توحيد: وكيلان اصلحا «الشركات 19» في اللحظة نفسها بترحيلين برقم 0151، فدهس
-- الثاني الاول على قاعدة جدة. هذا الترحيل يجمع النهجين فلا يكسر اي مستهلك:
--   organizations   = الشركات وحدها (نهج 0151_public_orgs_count_companies_only،
--                     فيصح كل ما يقرا المفتاح القديم بلا تعديل: الرئيسية والبوت وMCP)
--   companies       = الشركات نفسها، مفتاح صريح لمن يريد اسما لا يلتبس
--   personalSpaces  = المساحات الشخصية (لكل مستخدم مساحة باسمه، وليست شركة)
--   accountsTotal   = كل صفوف organizations، حتى لا يضيع العدد الكلي
-- الشركة = ما ليس entity_type = 'individual'، وهو الفصل نفسه في لوحة ادارة المنصة.

begin;

create or replace function public.platform_stats()
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'organizations', (select count(*) from public.organizations o
                       left join public.org_profiles p on p.org_id = o.id
                      where coalesce(p.entity_type, 'company') <> 'individual'),
    'companies', (select count(*) from public.organizations o
                   left join public.org_profiles p on p.org_id = o.id
                  where coalesce(p.entity_type, 'company') <> 'individual'),
    'personalSpaces', (select count(*) from public.organizations o
                        join public.org_profiles p on p.org_id = o.id
                       where p.entity_type = 'individual'),
    'accountsTotal', (select count(*) from public.organizations),
    'records', (select count(*) from public.records),
    'items', (select count(*) from public.items),
    'itemsUpcoming', (select count(*) from public.items where status = 'open' and due_at >= now()),
    'itemsOverdue', (select count(*) from public.items where status = 'open' and due_at < now()),
    'itemsNoDue', (select count(*) from public.items where status = 'open' and due_at is null),
    'itemsDone', (select count(*) from public.items where status = 'done'),
    'notifications', (select count(*) from public.notifications where status = 'sent'),
    'notifInapp', (select count(*) from public.notifications where status = 'sent' and channel = 'inapp'),
    'notifEmail', (select count(*) from public.notifications where status = 'sent' and channel = 'email'),
    'notifTelegram', (select count(*) from public.notifications where status = 'sent' and channel = 'telegram'),
    'notifWhatsapp', (select count(*) from public.notifications where status = 'sent' and channel = 'whatsapp'),
    'notifSms', (select count(*) from public.notifications where status = 'sent' and channel = 'sms'),
    'telegramMessages', (select count(*) from public.telegram_messages)
  )
$function$;

commit;

-- تحقق: الشركات + المساحات الشخصية = كل الحسابات، والمفتاح القديم يساوي الشركات
select (public.platform_stats() ->> 'organizations')::int  as qadim_sharikat,
       (public.platform_stats() ->> 'companies')::int      as sharikat,
       (public.platform_stats() ->> 'personalSpaces')::int as shakhsi,
       (public.platform_stats() ->> 'accountsTotal')::int  as kul;
