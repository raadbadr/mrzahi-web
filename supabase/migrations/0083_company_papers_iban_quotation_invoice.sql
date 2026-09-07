-- حساب الشركة (الايبان) ورقة مطلوبة، وعروض الاسعار والفواتير ورقتان تحفظان في المستندات.
-- امر المهندس رعد 2026-09-08. مطبقة على القاعدة الحية باسم company_papers_add_iban_quotation_invoice.
insert into public.required_docs (entity_type, kind, required, renews, sort_order) values
  ('company',       'bank_certificate', true,  false, 45),
  ('establishment', 'bank_certificate', true,  false, 45),
  ('freelance',     'bank_certificate', true,  false, 45),
  ('nonprofit',     'bank_certificate', true,  false, 45),
  ('government',    'bank_certificate', false, false, 45),
  ('company',       'quotation',        false, false, 90),
  ('establishment', 'quotation',        false, false, 90),
  ('freelance',     'quotation',        false, false, 90),
  ('nonprofit',     'quotation',        false, false, 90),
  ('government',    'quotation',        false, false, 90),
  ('company',       'invoice',          false, false, 95),
  ('establishment', 'invoice',          false, false, 95),
  ('freelance',     'invoice',          false, false, 95),
  ('nonprofit',     'invoice',          false, false, 95),
  ('government',    'invoice',          false, false, 95)
on conflict (entity_type, kind) do update
  set required = excluded.required, renews = excluded.renews, sort_order = excluded.sort_order;
