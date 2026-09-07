-- مهمة حذف الحسابات المنتهية مهلتها كانت ترجع 401 كل خمس دقائق منذ إنشائها:
-- الدالة أُنشئت بلا منح تنفيذ للدور anon، والوركر ينادي بمفتاح anon ومعه p_secret.
-- كل دوال الوركر الأخرى ممنوحة لـ anon بالنمط نفسه، والحماية داخل الدالة:
-- check_worker_secret(p_secret) يرفع 42501 لمن لا يحمل السر.
revoke all on function public.purge_expired_account_deletions(text) from public;
grant execute on function public.purge_expired_account_deletions(text) to anon, authenticated;
