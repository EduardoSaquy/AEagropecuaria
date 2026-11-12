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
//
// v4: entra AECombustivel.html, que ate aqui registrava o proprio
// sw_combustivel.js (aposentado) e nunca tinha cache offline nenhum.
//
// v5: o offline nao abria app nenhum. Tres causas:
//   1. a biblioteca do Supabase vem do CDN (jsdelivr) e nunca era
//      guardada - offline o HTML abria do cache, mas o script do Supabase
//      falhava e o app parava antes de desenhar a tela;
//   2. o cache so era preenchido na instalacao do service worker - a
//      copia offline ficava congelada na versao daquele dia, mesmo com o
//      app sendo usado online todo dia depois;
//   3. sem limite de tempo na rede: com sinal fraco no campo o fetch
//      ficava pendurado em vez de cair pro cache.
// Agora: CDN e fontes ficam no cache (usa o guardado e atualiza por
// tras), toda pagina buscada com sucesso atualiza o cache, e a pagina
// cai pro cache se a rede nao responder em TEMPO_REDE_MS. Online, a
// pagina e sempre revalidada com o servidor (cache: 'no-cache') - entra
// a versao nova assim que ela e publicada.
//
// (15/10/2026, sem trocar a versao do cache: trocar apagaria a copia
// guardada na hora em que o site estivesse fora do ar.) A pagina tambem cai
// pro cache quando o site RESPONDE erro (404, 5xx): foi o que aconteceu
// ao trocar o repositorio do GitHub - ver teste_site_fora_do_ar.py.
// ============================================================
const CACHE = 'ae-v5';

// Sinal fraco: espera isso pela rede antes de abrir a copia guardada (a
// resposta da rede, se chegar depois, ainda atualiza o cache).
const TEMPO_REDE_MS = 4000;

// Fontes de fora (o app abre sem elas, mas fica com a letra certa).
// (12/11/2026, sem trocar a versao do cache) A biblioteca do Supabase deixou de vir do CDN (jsdelivr): fica no proprio site,
// em vendor/ (entra no SHELL abaixo). Um CDN invadido poderia mandar codigo que le o login de quem usa o app; do proprio
// site, so quem publica no repositorio muda o arquivo. Versao FIXA no nome do arquivo: trocar nos 5 apps, aqui e em
// atualiza_nucleo.py (grep supabase-js-) so depois de testar login, carga e fila offline com a versao nova.
const HOSTS_ESTATICOS = ['fonts.googleapis.com', 'fonts.gstatic.com'];

// (07/11/2026, sem trocar a versao do cache) core.js e core_lavoura.js: as funcoes que os apps tinham copiadas passaram
// para esses arquivos. Entram aqui para o app abrir offline; o ?v= que os HTML usam e ignorado ao achar a copia guardada.
const SHELL = [
  './vendor/supabase-js-2.118.0.js',
  './core.js', './core_lavoura.js',
  './AEMatriz.html',      './manifest_matriz.json',
  './AEpecuaria.html',    './manifest.json',
  './AECana.html',        './manifest_cana.json',
  './AECereais.html',     './manifest_cereais.json',
  './AECombustivel.html', './manifest_combustivel.json',
  './AELavoura.html',
  './Adubacao.html',
  './icon-pecuaria-192.png',    './icon-pecuaria-512.png',
  './icon-matriz-192.png',      './icon-matriz-512.png',
  './icon-cana-192.png',        './icon-cana-512.png',
  './icon-cereais-192.png',     './icon-cereais-512.png',
  './icon-combustivel-192.png', './icon-combustivel-512.png',
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

// Arquivo com ?v= (core.js?v=...): ao guardar a versao nova, as antigas do mesmo arquivo saem do cache. Sem isso, a busca
// que ignora o ?v= devolveria a MAIS ANTIGA e o app offline juntaria o HTML novo com o nucleo velho.
function limpaVersoesAntigas(c, req) {
  const u = new URL(req.url);
  if (!u.search) return Promise.resolve();
  return c.keys().then((ks) => Promise.all(ks
    .filter((k) => { const ku = new URL(k.url); return ku.pathname === u.pathname && ku.search !== u.search; })
    .map((k) => c.delete(k))));
}

// Paginas e arquivos do proprio site: rede primeiro, cache como reserva.
// O contrario entregaria tela velha a quem tem sinal - e foi por isso que
// a v1 chegou a servir uma copia apontando para o banco antigo.
function redePrimeiro(req) {
  const daRede = fetch(req, { cache: 'no-cache' }).then((resp) => {
    if (resp && resp.ok) {
      const copia = resp.clone();
      caches.open(CACHE).then((c) => c.put(req, copia).then(() => limpaVersoesAntigas(c, req)));
    }
    return resp;
  });
  // Primeiro a copia do endereco EXATO (com o ?v= do nucleo); so se nao houver, qualquer versao do mesmo arquivo.
  const doCache = () => caches.match(req).then((exata) => exata || caches.match(req, { ignoreSearch: true }));
  const limite = new Promise((resolve) => setTimeout(resolve, TEMPO_REDE_MS));
  return Promise.race([daRede.catch(() => null), limite]).then((resp) => {
    if (resp && resp.ok) return resp;
    // Rede falhou, demorou OU o site respondeu erro (404 quando o GitHub
    // Pages esta fora do ar, 5xx quando o GitHub cai): usa a copia guardada.
    // So a rede nao bastava: resposta de erro e rapida e antes era entregue
    // como se fosse a pagina - todo mundo via "404", ate com o app instalado.
    // Sem copia guardada, entrega o que a rede respondeu (o erro de verdade)
    // ou espera a rede (melhor demorar do que dar erro na primeira abertura).
    return doCache().then((guardada) => guardada || resp || daRede);
  });
}

// Fontes: usa o guardado na hora e atualiza por tras. Sao arquivos
// que quase nunca mudam.
function cachePrimeiro(req) {
  return caches.open(CACHE).then((c) =>
    c.match(req).then((guardada) => {
      const daRede = fetch(req).then((resp) => {
        if (resp && (resp.ok || resp.type === 'opaque')) c.put(req, resp.clone());
        return resp;
      });
      if (guardada) { daRede.catch(() => null); return guardada; }
      return daRede;
    })
  );
}

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin === self.location.origin) {
    e.respondWith(redePrimeiro(e.request));
  } else if (HOSTS_ESTATICOS.includes(url.hostname)) {
    e.respondWith(cachePrimeiro(e.request));
  }
  // Resto (API do Supabase etc.): nao intercepta. Dado e login nunca vem
  // de copia guardada - cada app ja tem o proprio cache local de dados.
});
