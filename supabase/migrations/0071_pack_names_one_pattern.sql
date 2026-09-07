-- أسماء الواجهات على نمط واحد: اسم المجال مجردا، بلا «أو» ولا «و»، متقارب الطول
-- في اللغات الأربع. التفصيل يبقى في سطر الوصف تحت كل واجهة في شاشة الاختيار.
update public.ui_packs set names = jsonb_build_object('ar','شخصي','en','Personal','fr','Personnel','ur','ذاتی') where key = 'individual';
update public.ui_packs set names = jsonb_build_object('ar','أعمال','en','Business','fr','Entreprise','ur','کاروبار') where key = 'business';
update public.ui_packs set names = jsonb_build_object('ar','محاماة','en','Legal','fr','Juridique','ur','قانونی') where key = 'legal';
update public.ui_packs set names = jsonb_build_object('ar','تدريب','en','Training','fr','Formation','ur','تربیت') where key = 'trainer';
update public.ui_packs set names = jsonb_build_object('ar','عيادة','en','Clinic','fr','Clinique','ur','کلینک') where key = 'clinic';
update public.ui_packs set names = jsonb_build_object('ar','هندسة','en','Engineering','fr','Ingénierie','ur','انجینئرنگ') where key = 'engineer';
update public.ui_packs set names = jsonb_build_object('ar','موارد بشرية','en','Human resources','fr','Ressources humaines','ur','انسانی وسائل') where key = 'hr';
update public.ui_packs set names = jsonb_build_object('ar','مالية','en','Finance','fr','Finance','ur','مالیات') where key = 'finance';
update public.ui_packs set names = jsonb_build_object('ar','مبيعات','en','Sales','fr','Ventes','ur','فروخت') where key = 'sales';
update public.ui_packs set names = jsonb_build_object('ar','مشتريات','en','Procurement','fr','Achats','ur','خریداری') where key = 'procurement';
update public.ui_packs set names = jsonb_build_object('ar','تسويق','en','Marketing','fr','Marketing','ur','مارکیٹنگ') where key = 'marketing';
update public.ui_packs set names = jsonb_build_object('ar','تصميم','en','Design','fr','Design','ur','ڈیزائن') where key = 'design';
