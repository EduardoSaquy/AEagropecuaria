// Aposentado. Todos os apps passaram a usar um service worker so (sw.js).
//
// Cinco service workers disputavam o mesmo escopo e cada um apagava o cache
// dos outros, entao o offline funcionava so para o ultimo app aberto.
//
// Este arquivo continua existindo para se desfazer sozinho em quem ainda o
// tenha registrado: ele limpa o proprio cache e cancela o registro. Sem
// isso, um navegador que nao abrisse o app de novo ficaria com um service
// worker morto no meio do caminho.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.map((k) => caches.delete(k))))
      .then(() => self.registration.unregister())
      .then(() => self.clients.matchAll())
      .then((cs) => cs.forEach((c) => c.navigate(c.url)))
  );
});
