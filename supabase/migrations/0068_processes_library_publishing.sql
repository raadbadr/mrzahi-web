-- ============================================================
-- 0068 — مكتبة الإجراءات: دورة النشر كاملة كما طلب المهندس رعد
-- (مسودة ← قيد المراجعة ← منشور، مع «طلب تعديلات»)، وحالة تفعيل
-- لكل إجراء منشور، وملاحظة المراجع، ومن نشره ومتى.
-- ============================================================

alter table public.processes add column if not exists active boolean not null default true;
alter table public.processes add column if not exists review_note text;
alter table public.processes add column if not exists published_at timestamptz;
alter table public.processes add column if not exists published_by uuid references auth.users(id);

alter table public.processes drop constraint if exists processes_status_check;
alter table public.processes add constraint processes_status_check
  check (status = any (array['draft','review','published','changes','archived']));
