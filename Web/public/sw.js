// Lets the home-screen app open without a connection: the page files are fetched from the
// network when possible (so updates show up at once) and from this cache otherwise.
// The board itself is kept by the page (localStorage) and synced through /api.
const CACHE = "best-planner-v6";
const FILES = ["/", "/index.html", "/style.css", "/app.js", "/merge.js", "/i18n.js", "/tags.js", "/manifest.webmanifest", "/icon-180.png", "/icon-192.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.startsWith("/api/")) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return res; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match("/")))
  );
});
