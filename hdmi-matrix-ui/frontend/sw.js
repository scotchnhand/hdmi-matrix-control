// Caches the static app shell so the PWA opens instantly; /api/* is always
// fetched live (never cached) since it's the whole point of the app.
const APP_VERSION = '1.4.0'; // x-release-please-version
// Bump the shell revision when frontend assets change outside a release
// version bump, so installed PWAs replace their cached app shell.
const CACHE_NAME = `hdmi-matrix-shell-${APP_VERSION}-__APP_BUILD_REVISION__-2`;
const SHELL_FILES = [
  '/',
  '/styles.css',
  '/app.js',
  '/manifest.json',
  '/icons/icon.svg',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith('/api/')) return; // never cache live state/commands

  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/')));
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const network = fetch(event.request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
