-- 0134 — اسم الخدمة لا يختفي، والواجهة تتبع نوع الحساب، وقرار الإدارة ينفذ فعلا.
-- شكويان من المهندس رعد 2026-09-16: «ليش الحساب الشخصي مافيه المستندات مين لغاه»
-- و«تغيير الواجهة من هنا مايسوي شي… مايحفظ ولا هو مربوط».

-- ---------- 1) المستندات تظهر باسمها في الحزمة الشخصية ----------
-- الحزمة الشخصية كانت تسمي الخدمة «أوراقي الرسمية»، فاختفت كلمة «المستندات» عن
-- المستخدم فظنها ملغاة. التسمية التي تخفي اسم الخدمة تربك، فترد إلى الافتراضي.
update public.pack_services set label = null
 where pack_key = 'individual' and service = 'documents';
-- ومعها المفتاح الميت documentsTitle في ui_packs: لا يقرؤه أي كود اليوم، وبقاؤه
-- يعيد التسمية القديمة متى قرئ.
update public.ui_packs set labels = coalesce(labels, '{}'::jsonb) - 'documentsTitle'
 where key = 'individual';

-- ---------- 2) الواجهة الافتراضية تتبع نوع الحساب ----------
-- الحزمة الشخصية هي is_default، فكل حساب بلا حزمة صريحة كان يقع عليها ولو كان
-- شركة: «Non» (شركة بحزمة فارغة) و«Test» (بلا ملف أصلا) كلاهما على الواجهة
-- الشخصية اليوم. الافتراضي يحترم entity_choices المعلنة في ui_packs، فلا يقع
-- كيان تجاري على واجهة شخصية أبدا (entity_choices للشخصية = {individual}).
create or replace function public.pack_for(p_org uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    (select p.ui_pack from public.org_profiles p
       join public.ui_packs u on u.key = p.ui_pack and u.active
      where p.org_id = p_org),
    (select 'individual' from public.org_profiles op
      where op.org_id = p_org and op.entity_type = 'individual'
        and exists (select 1 from public.ui_packs where key = 'individual' and active)),
    (select u.key from public.ui_packs u
      where u.active
        and coalesce((select op.entity_type from public.org_profiles op where op.org_id = p_org), 'company')
            = any (u.entity_choices)
      order by u.sort_order limit 1),
    (select key from public.ui_packs where active and is_default order by sort_order limit 1)
  )
$function$;

-- ---------- 3) قرار الإدارة في الواجهة نافذ على الحساب وأعضائه ----------
-- admin_set_org_pack تكتب على org_profiles وحدها، بينما pack_for_member تفضل
-- org_members.ui_pack. فمن سبق أن اختار واجهته من الشريط العلوي يبقى تجاوزه
-- غالبا ولا يرى أثرا لقرار الإدارة أبدا. وكانت تفتقر إلى حارسي نوع الكيان
-- الموجودين في set_org_pack (ترحيل 0072)، فأعطت شركة الواجهة الشخصية.
create or replace function public.admin_set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_entity text; v_old text;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select entity_type, ui_pack into v_entity, v_old from public.org_profiles where org_id = p_org;
  if p_pack = 'individual' and coalesce(v_entity, 'company') <> 'individual' then
    raise exception 'personal interface is for a personal account' using errcode = '22023';
  end if;
  if p_pack is not null and p_pack <> 'individual' and v_entity = 'individual' then
    raise exception 'a personal account keeps the personal interface' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  -- قرار الإدارة يمحو التجاوزات الشخصية كي يظهر على شاشة كل عضو، ولا يمحو شيئا
  -- حين لا يتغير شيء. ومن أراد واجهة أخرى بعده يختارها من الشريط العلوي كما كان.
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null where org_id = p_org and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

-- ---------- 4) المالك يرى أثر اختياره هو ----------
-- العلة نفسها في مسار المالك: يغير واجهة الحساب من الإعدادات فلا تتغير شاشته
-- لأن تجاوزه الشخصي يغلب. فيمحى تجاوزه وحده؛ وتجاوزات بقية الأعضاء تبقى لهم.
create or replace function public.set_org_pack(p_org uuid, p_pack text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_role text; v_entity text; v_old text;
begin
  select role into v_role from public.org_members
   where org_id = p_org and user_id = auth.uid() and status = 'active';
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_pack is not null and not exists (select 1 from public.ui_packs where key = p_pack and active) then
    raise exception 'unknown pack' using errcode = '22023';
  end if;
  select entity_type, ui_pack into v_entity, v_old from public.org_profiles where org_id = p_org;
  if p_pack = 'individual' and coalesce(v_entity, 'company') <> 'individual' then
    raise exception 'personal interface is for a personal account' using errcode = '22023';
  end if;
  if p_pack is not null and p_pack <> 'individual' and v_entity = 'individual' then
    raise exception 'a personal account keeps the personal interface' using errcode = '22023';
  end if;
  insert into public.org_profiles (org_id, ui_pack) values (p_org, p_pack)
    on conflict (org_id) do update set ui_pack = excluded.ui_pack;
  if p_pack is distinct from v_old then
    update public.org_members set ui_pack = null
     where org_id = p_org and user_id = auth.uid() and ui_pack is not null;
  end if;
  return public.pack_for(p_org);
end $function$;

-- ---------- 5) تصحيح ما أنتجه العطل ----------
-- كيان تجاري يحمل الواجهة الشخصية صراحة: حالة يمنعها الحارس الآن وقد وقعت فعلا
-- (PARKINZI). ينقل إلى واجهة الأعمال وتمحى تجاوزات أعضائه ليستقر على قرار واحد.
-- والحسابات ذات الحزمة الفارغة لا تحتاج تصحيحا: الافتراضي في 2 صار يحترم نوعها.
update public.org_members m set ui_pack = null
 where m.ui_pack is not null
   and exists (select 1 from public.org_profiles p
                where p.org_id = m.org_id and p.ui_pack = 'individual'
                  and coalesce(p.entity_type, 'company') <> 'individual');
update public.org_profiles set ui_pack = 'business'
 where ui_pack = 'individual' and coalesce(entity_type, 'company') <> 'individual';
