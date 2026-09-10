/* migration: نقل مفاتيح التخزين من الاسم القديم الى mrzahi_ مرة واحدة لكل متصفح، فلا يفقد احد لغته ولا ثيمه ولا حسابه المختار */
try{["lang","theme","org","sidebar","dash_tab","bell_seen","chat_seen","cal_mode","cal_zoom","dp_cal","drive_folder","tr"].forEach(function(k){var o=localStorage.getItem("tracker_"+k);if(o!==null&&localStorage.getItem("mrzahi_"+k)===null){localStorage.setItem("mrzahi_"+k,o);localStorage.removeItem("tracker_"+k);}});}catch(e){}
const translations = {
      ar: {
        title: "تسجيل الدخول أو إنشاء حساب",
        intro: "سجل دخولك إلى حسابك، وإن لم يكن لديك حساب فسينشأ تلقائيا عند أول تسجيل دخول.",
        googleBtn: "المتابعة بحساب Google",
        appleBtn: "المتابعة بحساب Apple",
        or: "أو",
        emailPlaceholder: "بريدك الإلكتروني",
        emailBtn: "أرسل لي رابط الدخول",
        phonePlaceholder: "+9665xxxxxxx",
        phoneBtn: "أرسل رمز التحقق",
        otpPlaceholder: "رمز التحقق (6 أرقام)",
        otpBtn: "تأكيد",
        newAccountNote: "ليس لديك حساب؟ سينشأ تلقائيا عند أول تسجيل دخول.",
        termsNote: "بمتابعتك فإنك توافق على شروط الاستخدام وسياسة الخصوصية.",
        statusSending: "جاري الإرسال...",
        statusRedirecting: "جاري تحويلك إلى مزود الخدمة...",
        statusEmailSent: "تحقق من بريدك الإلكتروني، فقد أرسلنا إليك رابط الدخول.",
        statusCodeSent: "أرسلنا رمز التحقق إلى جوالك.",
        statusVerifying: "جاري التحقق...",
        statusSuccess: "تم تسجيل الدخول، جاري تحويلك...",
        statusWrongCode: "رمز التحقق غير صحيح أو منتهي الصلاحية، حاول مرة أخرى.",
        statusUnavailable: "خدمة تسجيل الدخول غير متاحة حاليا، حاول لاحقا أو تواصل مع الدعم.",
        statusProviderUnavailable: "هذه الطريقة غير متاحة حاليا، جرب طريقة أخرى.",
        statusRateLimit: "محاولات كثيرة، حاول مرة أخرى بعد قليل.",
        statusInvalidEmail: "أدخل بريدا إلكترونيا صحيحا.",
        statusInvalidPhone: "أدخل رقم الجوال بالصيغة الدولية، مثل ⁦+9665xxxxxxx⁩",
        statusError: "حدث خطأ، حاول مرة أخرى.",
        backBtn: "العودة للرئيسية",
        copyrightLine2: "جميع الحقوق محفوظة",
        aboutLink: "من نحن",
        termsLink: "شروط الاستخدام",
        pricingLink: "الباقات والأسعار",
        privacyLink: "سياسة الخصوصية",
        loginLink: "تسجيل الدخول",
        dashboardLink: "لوحة التحكم",
        contactLink: "تواصل معنا",
        language: "اللغة",
        appearance: "المظهر",
        light: "فاتح",
        dark: "داكن"
      },
      en: {
        title: "Sign in or create an account",
        intro: "Sign in to your account. If you don't have one yet, it will be created automatically the first time you sign in.",
        googleBtn: "Continue with Google",
        appleBtn: "Continue with Apple",
        or: "or",
        emailPlaceholder: "Your email address",
        emailBtn: "Send me a sign-in link",
        phonePlaceholder: "+9665xxxxxxx",
        phoneBtn: "Send verification code",
        otpPlaceholder: "6-digit code",
        otpBtn: "Confirm",
        newAccountNote: "Don't have an account? It will be created automatically on your first sign-in.",
        termsNote: "By continuing, you agree to the Terms of Use and the Privacy Policy.",
        statusSending: "Sending...",
        statusRedirecting: "Redirecting you to the provider...",
        statusEmailSent: "Check your email: we sent you a sign-in link.",
        statusCodeSent: "We sent a verification code to your phone.",
        statusVerifying: "Verifying...",
        statusSuccess: "Signed in, redirecting...",
        statusWrongCode: "Incorrect or expired code, please try again.",
        statusUnavailable: "Sign-in is temporarily unavailable. Please try again later or contact support.",
        statusProviderUnavailable: "This method is not available right now, please try another one.",
        statusRateLimit: "Too many attempts, please try again in a moment.",
        statusInvalidEmail: "Enter a valid email address.",
        statusInvalidPhone: "Enter your phone number in international format, e.g. +9665xxxxxxx",
        statusError: "Something went wrong, please try again.",
        backBtn: "Back to Home",
        copyrightLine2: "All rights reserved",
        aboutLink: "About Us",
        termsLink: "Terms of Use",
        pricingLink: "Plans & Pricing",
        privacyLink: "Privacy Policy",
        loginLink: "Sign in",
        dashboardLink: "Dashboard",
        contactLink: "Contact Us",
        language: "Language",
        appearance: "Appearance",
        light: "Light",
        dark: "Dark"
      },
      fr: {
        title: "Connexion ou création de compte",
        intro: "Connectez-vous à votre compte. S'il n'existe pas encore, il sera créé automatiquement lors de votre première connexion.",
        googleBtn: "Continuer avec Google",
        appleBtn: "Continuer avec Apple",
        or: "ou",
        emailPlaceholder: "Votre adresse e-mail",
        emailBtn: "M'envoyer un lien de connexion",
        phonePlaceholder: "+9665xxxxxxx",
        phoneBtn: "Envoyer le code de vérification",
        otpPlaceholder: "Code à 6 chiffres",
        otpBtn: "Confirmer",
        newAccountNote: "Pas encore de compte ? Il sera créé automatiquement lors de votre première connexion.",
        termsNote: "En continuant, vous acceptez les Conditions d'utilisation et la Politique de confidentialité.",
        statusSending: "Envoi en cours...",
        statusRedirecting: "Redirection vers le fournisseur...",
        statusEmailSent: "Vérifiez votre boîte e-mail : nous vous avons envoyé un lien de connexion.",
        statusCodeSent: "Nous avons envoyé un code de vérification sur votre mobile.",
        statusVerifying: "Vérification en cours...",
        statusSuccess: "Connexion réussie, redirection en cours...",
        statusWrongCode: "Code incorrect ou expiré, veuillez réessayer.",
        statusUnavailable: "Le service de connexion est momentanément indisponible. Réessayez plus tard ou contactez le support.",
        statusProviderUnavailable: "Cette méthode n'est pas disponible pour le moment, essayez-en une autre.",
        statusRateLimit: "Trop de tentatives, veuillez réessayer dans quelques instants.",
        statusInvalidEmail: "Saisissez une adresse e-mail valide.",
        statusInvalidPhone: "Saisissez votre numéro au format international, par exemple +9665xxxxxxx",
        statusError: "Une erreur est survenue, veuillez réessayer.",
        backBtn: "Retour à l'accueil",
        copyrightLine2: "Tous droits réservés",
        aboutLink: "À propos",
        termsLink: "Conditions d'utilisation",
        pricingLink: "Forfaits et tarifs",
        privacyLink: "Politique de confidentialité",
        loginLink: "Connexion",
        dashboardLink: "Tableau de bord",
        contactLink: "Contactez-nous",
        language: "Langue",
        appearance: "Apparence",
        light: "Clair",
        dark: "Sombre"
      },
      ur: {
        title: "سائن ان کریں یا اکاؤنٹ بنائیں",
        intro: "اپنے اکاؤنٹ سے سائن ان کریں۔ اگر آپ کا اکاؤنٹ ابھی نہیں ہے تو پہلی بار سائن ان کرنے پر یہ خود بخود بن جائے گا۔",
        googleBtn: "Google کے ساتھ جاری رکھیں",
        appleBtn: "Apple کے ساتھ جاری رکھیں",
        or: "یا",
        emailPlaceholder: "آپ کا ای میل",
        emailBtn: "مجھے سائن ان لنک بھیجیں",
        phonePlaceholder: "+9665xxxxxxx",
        phoneBtn: "تصدیقی کوڈ بھیجیں",
        otpPlaceholder: "6 ہندسوں کا کوڈ",
        otpBtn: "تصدیق کریں",
        newAccountNote: "اکاؤنٹ نہیں ہے؟ پہلی بار سائن ان کرنے پر یہ خود بخود بن جائے گا۔",
        termsNote: "جاری رکھنے کا مطلب ہے کہ آپ استعمال کی شرائط اور رازداری کی پالیسی سے اتفاق کرتے ہیں۔",
        statusSending: "بھیجا جا رہا ہے...",
        statusRedirecting: "آپ کو فراہم کنندہ کی طرف بھیجا جا رہا ہے...",
        statusEmailSent: "اپنا ای میل چیک کریں، ہم نے آپ کو سائن ان لنک بھیج دیا ہے۔",
        statusCodeSent: "ہم نے آپ کے موبائل پر تصدیقی کوڈ بھیج دیا ہے۔",
        statusVerifying: "تصدیق کی جا رہی ہے...",
        statusSuccess: "سائن ان مکمل، آپ کو منتقل کیا جا رہا ہے...",
        statusWrongCode: "کوڈ غلط ہے یا اس کی میعاد ختم ہو گئی ہے، دوبارہ کوشش کریں۔",
        statusUnavailable: "سائن ان سروس فی الحال دستیاب نہیں ہے۔ بعد میں کوشش کریں یا سپورٹ سے رابطہ کریں۔",
        statusProviderUnavailable: "یہ طریقہ فی الحال دستیاب نہیں ہے، کوئی دوسرا طریقہ آزمائیں۔",
        statusRateLimit: "بہت زیادہ کوششیں، تھوڑی دیر بعد دوبارہ کوشش کریں۔",
        statusInvalidEmail: "درست ای میل ایڈریس درج کریں۔",
        statusInvalidPhone: "بین الاقوامی فارمیٹ میں موبائل نمبر درج کریں، مثلا ⁦+9665xxxxxxx⁩",
        statusError: "خرابی پیش آئی، دوبارہ کوشش کریں۔",
        backBtn: "واپس ہوم",
        copyrightLine2: "جملہ حقوق محفوظ ہیں",
        aboutLink: "ہمارے بارے میں",
        termsLink: "استعمال کی شرائط",
        pricingLink: "پلانز اور قیمتیں",
        privacyLink: "رازداری کی پالیسی",
        loginLink: "سائن ان",
        dashboardLink: "ڈیش بورڈ",
        contactLink: "ہم سے رابطہ کریں",
        language: "زبان",
        appearance: "ظہور",
        light: "روشن",
        dark: "اندھیرا"
      }
    };

    const lang = () => localStorage.getItem("mrzahi_lang") || "ar";
    const theme = () => localStorage.getItem("mrzahi_theme") || "dark";
    const langNames = { ar: "العربية", en: "English", fr: "Français", ur: "اردو" };
    let l = lang();
    document.documentElement.lang = l;
    document.documentElement.dir = (l === "ar" || l === "ur") ? "rtl" : "ltr";

    const placeholderKeys = { loginEmail: "emailPlaceholder", loginPhone: "phonePlaceholder", loginOtp: "otpPlaceholder" };
    function applyPlaceholders(code) {
      const dict = translations[code] || translations.ar;
      Object.keys(placeholderKeys).forEach(id => {
        const el = document.getElementById(id);
        if (el && dict[placeholderKeys[id]]) el.placeholder = dict[placeholderKeys[id]];
      });
    }

    function setLang(code) {
      localStorage.setItem("mrzahi_lang", code);
      l = code;
      document.documentElement.lang = code;
      document.documentElement.dir = (code === "ar" || code === "ur") ? "rtl" : "ltr";
      document.getElementById("currentLangDisplay").textContent = langNames[code] || code;
      ["ar","en","fr","ur"].forEach(c => {
        const el = document.getElementById("check-" + c);
        if (el) el.style.display = c === code ? "inline" : "none";
      });
      const th = theme();
      document.getElementById("currentThemeDisplay").textContent = translations[code][th === "dark" ? "dark" : "light"];
      document.querySelectorAll("[data-i18n]").forEach(el => {
        const k = el.dataset.i18n;
        if (translations[code] && translations[code][k]) el.innerHTML = translations[code][k];
      });
      applyPlaceholders(code);
      document.title = (translations[code] && translations[code].title ? translations[code].title : "Sign in") + " | MrZahi";
      if (typeof window.__mrzahiAuthRefresh === "function") window.__mrzahiAuthRefresh();
    }

    function setTheme(th) {
      localStorage.setItem("mrzahi_theme", th);
      document.documentElement.dataset.theme = th;
      const meta = document.getElementById("themeColorMeta");
      if (meta) meta.content = th === "dark" ? "#1a2933" : "#0068b8";
      const logo = document.getElementById("footerLogo");
      if (logo) logo.src = th === "dark" ? "mrzahi-logo-full-dark.png?v=2" : "mrzahi-logo-full-light.png?v=2";
      document.getElementById("themeIcon").textContent = th === "dark" ? "🌙" : "☀️";
      document.getElementById("currentThemeDisplay").textContent = translations[l][th === "dark" ? "dark" : "light"];
      document.getElementById("check-light").style.display = th === "light" ? "inline" : "none";
      document.getElementById("check-dark").style.display = th === "dark" ? "inline" : "none";
    }

    document.getElementById("langMenuBtn").addEventListener("click", e => {
      e.stopPropagation();
      document.getElementById("langDropdown").classList.toggle("show");
      document.getElementById("themeDropdown").classList.remove("show");
    });
    // زر المظهر يبدل الثيم مباشرة بضغطة واحدة بلا قائمة (طلب المهندس رعد)
    document.getElementById("themeMenuBtn").addEventListener("click", e => {
      e.stopPropagation();
      setTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
      document.getElementById("langDropdown").classList.remove("show");
    });
    document.addEventListener("click", () => {
      document.getElementById("langDropdown").classList.remove("show");
      document.getElementById("themeDropdown").classList.remove("show");
    });

    document.querySelectorAll("#langDropdown .menu-dropdown-item").forEach(item => {
      item.addEventListener("click", () => setLang(item.dataset.lang));
    });
    document.querySelectorAll("#themeDropdown .menu-dropdown-item").forEach(item => {
      item.addEventListener("click", () => {
        setTheme(item.dataset.theme);
        document.getElementById("themeDropdown").classList.remove("show");
      });
    });

    document.querySelectorAll("[data-i18n]").forEach(el => {
      const k = el.dataset.i18n;
      if (translations[l] && translations[l][k]) el.textContent = translations[l][k];
    });
    applyPlaceholders(l);
    document.getElementById("currentLangDisplay").textContent = langNames[l] || l;
    ["ar","en","fr","ur"].forEach(c => {
      const el = document.getElementById("check-" + c);
      if (el) el.style.display = l === c ? "inline" : "none";
    });
    document.title = (translations[l] && translations[l].title ? translations[l].title : "Sign in") + " | MrZahi";

    (function() {
      const th = theme();
      document.documentElement.dataset.theme = th;
      const meta = document.getElementById("themeColorMeta");
      if (meta) meta.content = th === "dark" ? "#1a2933" : "#0068b8";
      const logo = document.getElementById("footerLogo");
      if (logo) logo.src = th === "dark" ? "mrzahi-logo-full-dark.png?v=2" : "mrzahi-logo-full-light.png?v=2";
      document.getElementById("themeIcon").textContent = th === "dark" ? "🌙" : "☀️";
      document.getElementById("currentThemeDisplay").textContent = translations[l][th === "dark" ? "dark" : "light"];
      document.getElementById("check-light").style.display = th === "light" ? "inline" : "none";
      document.getElementById("check-dark").style.display = th === "dark" ? "inline" : "none";
    })();
