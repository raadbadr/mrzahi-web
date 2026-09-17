-- عطل حي في تسجيل الدخول بجوجل (المهندس رعد 2026-09-17: «شيك على تسجيل الدخول
-- بجوجل لانو فيه مشكلة»).
--
-- في القاعدة نسختان من create_org_registered: القديمة باربعة معاملات والجديدة
-- بخمسة (مع p_name_en). ونداء باربعة معاملات يرد PGRST203:
--   Could not choose the best candidate function
-- فمن يدخل بمتصفح يحمل نسخة مخبأة قديمة من common.js تنادي باربعة لا تنشا له
-- مساحته الشخصية، فيدخل بجوجل بنجاح ثم لا يجد حسابا. وقع فعلا اليوم لمستخدمين
-- جديدين: som3a033@gmail.com و ismbasher@gmail.com — لهما profile وصفر عضوية.
--
-- والقديمة مفتوحة لـ PUBLIC (=X في proacl) اي ان زائرا بلا حساب يستطيع نداءها،
-- بينما الجديدة لـ authenticated وحدهم. فحذفها يغلق الالتباس والفتحة معا.
-- والجديدة لها p_name_en default NULL، فالنداء باربعة يقع عليها بعد الحذف.

begin;

drop function if exists public.create_org_registered(text, text, text, date);

commit;

-- تحقق: نسخة واحدة، وصلاحيتها لـ authenticated لا للعموم
select p.oid::regprocedure as tawqi3,
       coalesce(array_to_string(p.proacl, ' | '), '(bila acl)') as salahiyat
  from pg_proc p
 where p.proname = 'create_org_registered';
