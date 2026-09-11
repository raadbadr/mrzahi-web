-- التخزين المحلي على خادم جدة (قرار المهندس رعد 2026-09-11: الملفات اوراق ممسوحة وPDF؛
-- «الشخص ما يحتاج اكثر من 1 GB والشركات ما تحتاج اكثر من 5 GB»).
-- التجريبية 200 MB، شخصي وعمل حر 1 GB، مؤسسة وشركة كبيرة 5 GB. الحد للملف الواحد 100 MB.
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '1024'::jsonb) where code in ('personal', 'freelance');
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '5120'::jsonb) where code in ('business', 'enterprise');
update storage.buckets set file_size_limit = 104857600 where id = 'attachments';
