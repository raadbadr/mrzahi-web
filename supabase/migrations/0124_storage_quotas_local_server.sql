-- التخزين المحلي على خادم جدة (قرار المهندس رعد 2026-09-11: الملفات اوراق ممسوحة وPDF؛
-- «الشخص ما يحتاج اكثر من 1 GB والشركات ما تحتاج اكثر من 5 GB»).
-- التجريبية 200 MB، شخصي 1 GB، عمل حر 2 GB، مؤسسة 5 GB، شركة كبيرة 10 GB. الحد للملف الواحد 100 MB.
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '1024'::jsonb) where code = 'personal';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '2048'::jsonb) where code = 'freelance'; -- عمل حر 2 GB لانه يدفع اكثر (قرار المهندس رعد)
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '5120'::jsonb) where code = 'business';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '10240'::jsonb) where code = 'enterprise'; -- شركة كبيرة 10 GB (قرار المهندس رعد)
update storage.buckets set file_size_limit = 104857600 where id = 'attachments';
