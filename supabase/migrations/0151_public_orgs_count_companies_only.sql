-- المهندس رعد 2026-09-17: الصفحة الرئيسية تقول «الشركات 19» وهي كاذبة.
-- على القاعدة 19 حسابا: 15 مساحة شخصية + 3 شركات + حساب بلا بطاقة. والمساحة
-- الشخصية ليست شركة، فعدها في رقم عام يراه كل زائر ادعاء لا يصح.
--
-- platform_stats عامة (anon) وتخدم الرئيسية والبوت ولوحة الادارة: يبقى كل
-- مفتاح كما هو، ويصحح organizations وحده فيعد ما ليس مساحة شخصية.

begin;

create or replace function public.platform_stats()
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select jsonb_build_object(
    'users', (select count(*) from public.profiles),
    -- الشركات: كل حساب ليس مساحة شخصية (المساحة الشخصية حساب شخص لا شركة)
    'organizations', (select count(*) from public.organizations o
                       left join public.org_profiles p on p.org_id = o.id
                      where coalesce(p.entity_type, 'company') <> 'individual'),
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
