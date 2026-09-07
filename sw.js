/* MrZahi — تخزين مؤقت للتصفح دون اتصال (نفس أصل الموقع فقط) */
const CACHE_NAME = "mrzahi-offline-v6";

/* المسارات كما يخدمها الموقع فعلا: صفحة بلاحقة .html تحول إلى المسار النظيف،
   والاستجابة المحفوظة عن تحويل يرفض المتصفح إعادة تشغيلها في تنقل، فيموت
   التصفح دون اتصال بصمت. */
const PRECACHE_URLS = [
  "./",
  "./about",
  "./privacy",
  "./terms",
  "./pricing",
  "./header.css",
  "./footer.css",
  "./rial-symbol.png",
  "./Monoton-Regular.ttf",
  "./mrzahi-logo-dark.png",
  "./mrzahi-logo-light.png",
  "./robots.txt",
  "./sitemap.xml",
  "./login",
  "./mrzahi-og.png",
  "./404.html"
];

function scopeBase() {
  return self.registration.scope;
}

function isDocumentRequest(request, url) {
  if (request.mode === "navigate") return true;
  const p = url.pathname;
  if (p.endsWith(".html")) return true;
  if (p === "/" || p.endsWith("/")) return true;
  return false;
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) =>
        Promise.allSettled(
          PRECACHE_URLS.map((path) =>
            cache.add(new URL(path, scopeBase()).href).catch(() => {})
          )
        )
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  );
});

/* طلب لا يعود لا ينجح ولا يفشل، فلا يصل الدور إلى الكاش ولا إلى أي معالج:
   المتصفح يبقى واقفا على العامل. هنا يسابق كل طلب بمهلة، فينتهي الأمر دائما. */
function raceNetwork(request, ms) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error("sw_network_timeout"));
    }, ms);
    fetch(request).then(
      (response) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(response);
      },
      (err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    );
  });
}

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  /* بيانات حية (خريطة النمو، أرقام المنصة): لا تعترض إطلاقا.
     الكاش-أولا هنا كان يجمد البيانات الجديدة على أجهزة الزوار. */
  if (url.pathname.startsWith("/api/")) return;

  /* صفحات HTML + CSS/JS: الشبكة أولا حتى تصل التحديثات فورا —
     الكاش-أولا هنا جمد تعديلات footer.css على أجهزة الزوار */
  const p = url.pathname;
  /* الأيقونات مع الأنماط والسكربتات: الشبكة أولا. كانت الصور كاشا-أولا،
     فبقيت أيقونة الاسم القديم على التبويبات بعد تغيير العلامة. */
  const isIcon = /favicon|apple-touch-icon|logo/.test(p) && /\.(png|ico|svg)$/.test(p);
  const isFreshAsset = p.endsWith(".css") || p.endsWith(".js") || p.endsWith(".webmanifest") || isIcon;
  if (isDocumentRequest(request, url) || isFreshAsset) {
    event.respondWith(
      raceNetwork(request, 5000)
        .then((response) => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)).catch(() => {});
          }
          return response;
        })
        .catch(() =>
          caches.match(request).then((cached) => {
            if (cached) return cached;
            /* سقوط الصفحة الرئيسية للمستندات فقط — لا يصلح بديلا لأصل CSS/JS */
            if (isFreshAsset) return Response.error();
            return caches
              .match(new URL("./", scopeBase()).href)
              .then((page) => page || Response.error());
          })
        )
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return raceNetwork(request, 8000)
        .then((response) => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)).catch(() => {});
          }
          return response;
        })
        .catch(() => Response.error());
    })
  );
});
