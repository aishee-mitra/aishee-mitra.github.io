const CACHE = 'tgif-v2';
const ASSETS = [
  '/',
  '/index.html',
  '/about/',
  '/archive/',
  '/assets/css/style.css',
  '/assets/icons/favicon-32.png',
  '/assets/icons/favicon-192.png',
  '/assets/icons/favicon-256.png',
  '/assets/icons/apple-touch-icon.png',
  '/assets/img/avatar.png',
  '/manifest.webmanifest',
  '/assets/sw.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      cache.addAll(ASSETS).catch(() => {
        // Best-effort precache; missing assets won't block installation.
      })
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const fetched = fetch(event.request).then((response) => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE).then((cache) => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => cached);

      return cached || fetched;
    })
  );
});
