// public/liveness-sw.js
//
// Service worker for caching the liveness detection assets (3.5MB JS + 327KB CSS).
// Registered only from the liveness_detector Stimulus controller — active only
// on the identity submission page.
//
// Strategy: stale-while-revalidate for liveness bundles only.
// Does NOT intercept Turbo, API calls, CSRF tokens, or any other app resources.
//
// On Haiti's mobile networks, this ensures returning users don't re-download
// the entire Amplify bundle if their connection drops mid-wizard.

const CACHE_NAME = "bonid-liveness-v1"

// Install: activate immediately without waiting for open tabs to close
self.addEventListener("install", () => {
  self.skipWaiting()
})

// Activate: clean up old cache versions, claim all clients
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k.startsWith("bonid-liveness-") && k !== CACHE_NAME)
          .map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  )
})

// Fetch: cache-first for liveness assets, pass-through for everything else
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url)

  // Only intercept liveness JS + CSS bundles (with or without content hash)
  const isLivenessAsset =
    (url.pathname.includes("/liveness.") || url.pathname.match(/\/liveness-[a-f0-9]+\./)) &&
    (url.pathname.endsWith(".js") || url.pathname.endsWith(".css"))

  if (!isLivenessAsset) return

  event.respondWith(
    caches.match(event.request).then((cached) => {
      // Background update: fetch from network and update cache
      const networkFetch = fetch(event.request)
        .then((response) => {
          if (response.ok) {
            const clone = response.clone()
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone))
          }
          return response
        })
        .catch(() => cached) // Network unavailable — cached version is still served

      // Return cached immediately if available, otherwise wait for network
      return cached || networkFetch
    })
  )
})
