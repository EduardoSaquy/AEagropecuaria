// ============================================================
// SERVICE WORKER UNICO DA AE AGROPECUARIA
//
// POR QUE UM SO
//
// Antes existiam cinco: sw.js, sw_matriz.js, sw_lavoura.js, sw_cana.js e
// sw_cereais.js. Todos eram registrados a partir da raiz do site, entao
// todos disputavam o MESMO escopo ('./'). Um escopo aceita um service
// worker por vez: registrar o segundo substitui o primeiro. E como cada um
// apagava, no activate, todo cache com nome diferente do seu, abrir um app
// derrubava o cache offline dos outros.
//
// Resultado pratico: o offline funcionava para o ultimo app aberto e
// falhava para os demais, sem nenhum aviso - justamente no campo, que e
// onde ele precisa funcionar.
//
// Agora e um so, com a lista de todos os apps. Cada app continua com seu
// proprio manifest (nome e icone na tela de inicio), que e independente do
// service worker.
//
// TROCAR A VERSAO a cada mudanca importante: o navegador so descarta o
// cache antigo quando o nome muda.
//
// v3: um service worker so, e entram AECana.html e AECereais.html. A v2
// guardava AELavoura.html como se fosse o app; ele agora e so a pagina que
// encaminha para os dois.
// ============================================================
const CACHE = 'ae-v3';

const SHELL = [
  './AEMatriz.html',   './manifest_matriz.json',
  './AEpecuaria.html', './manifest.json',
  './AECana.html',     './manifest_cana.json',
  './AECereais.html',  './manifest_cereais.json',
  './AELavoura.html',
  './icon-pecuaria-192.png', './icon-pecuaria-512.png',
  './icon-matriz-192.png',   './icon-matriz-512.png',
  './icon-cana-192.png',     './icon-cana-512.png',
  './icon-cereais-192.png',  './icon-cereais-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      // Um por vez, com catch: addAll rejeita tudo se UM arquivo faltar, e
      // ai a instalacao inteira falha e o app fica sem offline nenhum por
      // causa de um icone que nao existe.
      Promise.all(SHELL.map((url) =>
        // cache: 'reload' forca buscar da rede, ignorando o cache HTTP do
        // navegador. Sem isso a instalacao da versao nova poderia guardar
        // de novo a copia velha que o navegador ainda tivesse em maos.
        c.add(new Request(url, { cache: 'reload' })).catch(() => null)
      ))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Rede primeiro, cache como reserva. O contrario entregaria tela velha a
// quem tem sinal - e foi por isso que a v1 chegou a servir uma copia
// apontando para o banco antigo.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});
