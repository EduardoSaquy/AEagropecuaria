// Versao do cache. TROCAR ESTE NUMERO a cada mudanca importante do app:
// o navegador so descarta o cache antigo quando o nome muda.
//
// v2: unificacao dos bancos. A v1 guardava a versao do AEpecuaria.html que
// apontava para o projeto Supabase antigo. Se alguem abrisse o app sem sinal,
// receberia aquela copia e lancaria no banco morto sem perceber.
const CACHE = 'confinar-v2';
const SHELL = ['./AEpecuaria.html', './manifest.json', './icon-pecuaria-192.png', './icon-pecuaria-512.png'];

self.addEventListener('install', (e) => {
  // cache: 'reload' forca buscar da rede, ignorando o cache HTTP do
  // navegador. Sem isso, a instalacao da versao nova poderia guardar de novo
  // a copia velha que o navegador ainda tivesse em maos.
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      c.addAll(SHELL.map((url) => new Request(url, { cache: 'reload' })))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  // Rede primeiro, cache so como recurso de emergencia quando esta offline.
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});
