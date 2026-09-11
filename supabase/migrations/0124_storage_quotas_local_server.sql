-- التخزين المحلي على خادم جدة معيار مستر زاهي (امر المهندس رعد 2026-09-11): حصص اكبر بلا Google Drive.
-- التجريبية تبقى 200 MB؛ شخصي 1 GB، عمل حر 5 GB، مؤسسة 20 GB، شركة كبيرة 100 GB. الحد للملف الواحد 100 MB (storage.buckets).
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '1024'::jsonb)   where code = 'personal';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '5120'::jsonb)   where code = 'freelance';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '20480'::jsonb)  where code = 'business';
update public.plans set limits = jsonb_set(limits, '{storage_mb}', '102400'::jsonb) where code = 'enterprise';
update storage.buckets set file_size_limit = 104857600 where id = 'attachments';
