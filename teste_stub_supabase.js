// Banco falso para os testes. Imita o pedaco do supabase-js que os apps
// usam, contra os dados em window.__DB__. Nao tenta ser fiel ao Supabase
// inteiro: so ao que estes arquivos chamam.
//
// insert/update/delete gravam de verdade em window.__DB__ (nao so
// registram a intencao) desde que o teste de Financiamentos passou a
// clicar em "Salvar" de verdade -- os tres arquivos de teste antigos nunca
// exercitavam esse caminho, entao isso nao muda nenhum deles.
//
// O Contas a Pagar tinha chegado numa versao mais simples de insert()
// (so fingia um id, sem gravar a linha) -- reconciliado com esta na fusao
// do bundle de 26/08: teste_contas.py so confere window.__ESCRITAS__, que
// as duas versoes gravam igual, entao nada quebrou ao ficar com a que
// persiste de verdade.
// REDE CAIDA (07/11/2026): com window.__SEM_REDE__ ou localStorage.__sem_rede = '1' toda consulta e gravacao falha como o navegador
// falha sem internet (TypeError "Failed to fetch"). O localStorage sobrevive a recarregar a pagina, para testar o app abrindo sem sinal.
function semRede() {
  try { return !!window.__SEM_REDE__ || localStorage.getItem('__sem_rede') === '1'; } catch (e) { return !!window.__SEM_REDE__; }
}
// JWT de mentira so com o que o app le (aal): window.__jwt('aal1' | 'aal2')
window.__jwt = (aal) => 'e30.' + btoa(JSON.stringify({ aal, sub: 'u1', exp: 9999999999 })).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_') + '.assinatura';
const ERRO_REDE = { name: 'TypeError', message: 'Failed to fetch' };
const SEM_RESPOSTA = () => Promise.resolve({ data: null, error: ERRO_REDE });
window.supabase = {
  createClient() {
    function tabela(nome) {
      // lancamentos_rateados e a view que reparte um lancamento "geral" do
      // ERP entre atividade/fazenda. Nenhum teste monta lancamento
      // rateado a mao (isso so acontece na importacao do ERP), entao a
      // view sempre cai no ramo "nao rateado": os mesmos lancamentos, so
      // com lancamento_id no lugar de id (a view nao tem coluna "id") e
      // rateio_id/rateado marcando que nao foi rateado.
      let linhas = nome === 'lancamentos_rateados'
        ? () => (window.__DB__.lancamentos_financeiros || []).map(r => ({ ...r, lancamento_id: r.id, rateio_id: null, rateado: false }))
        : () => (window.__DB__[nome] || []).slice();
      const q = {
        _rows: null,
        _filtros: [],
        _pendingUpdate: undefined,
        _pendingDelete: false,
        select() { this._rows = linhas(); return this; },
        eq(col, val) { this._filtros.push(r => String(r[col]) === String(val)); return this; },
        in(col, vals) { const s = new Set((vals || []).map(String)); this._filtros.push(r => s.has(String(r[col]))); return this; },
        order() { return this; },
        limit(n) { this._limit = n; return this; },
        range(de, ate) {
          if (semRede()) return SEM_RESPOSTA();
          const r = this._aplicar();
          return Promise.resolve({ data: r.slice(de, ate + 1), error: null });
        },
        single() {
          if (semRede()) return SEM_RESPOSTA();
          const r = this._aplicar();
          return Promise.resolve({ data: r[0] || null, error: null });
        },
        _aplicar() {
          // Linhas reais (mesma referencia de objeto que window.__DB__[nome]):
          // update/delete precisam mutar o objeto de verdade, nao uma copia.
          let r = this._rows || linhas();
          this._filtros.forEach(f => { r = r.filter(f); });
          if (this._limit != null) r = r.slice(0, this._limit);
          return r;
        },
        then(res, rej) {
          if (semRede()) return SEM_RESPOSTA().then(res, rej);
          if (this._pendingUpdate !== undefined) {
            const alvo = this._aplicar();
            alvo.forEach(r => Object.assign(r, this._pendingUpdate));
            return Promise.resolve({ data: alvo, error: null }).then(res, rej);
          }
          if (this._pendingDelete) {
            const alvo = new Set(this._aplicar());
            window.__DB__[nome] = (window.__DB__[nome] || []).filter(r => !alvo.has(r));
            return Promise.resolve({ data: null, error: null }).then(res, rej);
          }
          return Promise.resolve({ data: this._aplicar(), error: null }).then(res, rej);
        },
        insert(v) {
          if (semRede()) {
            return { select() { return { single: SEM_RESPOSTA, then: (res, rej) => SEM_RESPOSTA().then(res, rej) }; }, then: (res, rej) => SEM_RESPOSTA().then(res, rej) };
          }
          window.__ESCRITAS__.push({ tabela: nome, op: 'insert', v });
          if (!window.__DB__[nome]) window.__DB__[nome] = [];
          let proximoId = window.__DB__[nome].reduce((m, r) => Math.max(m, Number(r.id) || 0), 0) + 1;
          const linhasNovas = (Array.isArray(v) ? v : [v]).map(row => ({ id: proximoId++, ...row }));
          window.__DB__[nome].push(...linhasNovas);
          // Suporta tanto `await insert(v)` direto (data:null, como sempre foi)
          // quanto `insert(v).select().single()` / `.select()` (padrao usado
          // ao criar fazenda/funcionario/financiamento, pra pegar o id gerado).
          return {
            select() {
              return {
                single: () => Promise.resolve({ data: linhasNovas[0] || null, error: null }),
                then: (res, rej) => Promise.resolve({ data: linhasNovas, error: null }).then(res, rej),
              };
            },
            then: (res, rej) => Promise.resolve({ data: null, error: null }).then(res, rej),
          };
        },
        update(v) { window.__ESCRITAS__.push({ tabela: nome, op: 'update', v }); this._pendingUpdate = v; return this; },
        delete() { window.__ESCRITAS__.push({ tabela: nome, op: 'delete' }); this._pendingDelete = true; return this; },
      };
      return q;
    }
    return {
      from: tabela,
      // Funcao do banco (rpc): so existe se o teste registrar um tratador em window.__RPC__[nome];
      // sem ele responde como o PostgREST quando a funcao nao existe (PGRST202), que e o que os apps
      // tratam como "use o caminho antigo".
      rpc: (nome, args) => {
        if (semRede()) return SEM_RESPOSTA();
        const h = window.__RPC__ && window.__RPC__[nome];
        if (h) { window.__CHAMADAS_RPC__.push({ nome, args }); return Promise.resolve(h(args)); }
        return Promise.resolve({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + nome + ' in the schema cache' } });
      },
      functions: { invoke: () => Promise.resolve({ data: {}, error: null }) },
      auth: {
        getSession: () => Promise.resolve({ data: { session: window.__SESSAO__ } }),
        // guarda os ouvintes para o teste poder disparar eventos de sessao (window.__authCallbacks[i]('TOKEN_REFRESHED', sessao))
        onAuthStateChange: (cb) => { (window.__authCallbacks = window.__authCallbacks || []).push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
        signInWithPassword: () => Promise.resolve({ data: { session: window.__SESSAO__ }, error: null }),
        signOut: () => Promise.resolve({}),
        updateUser: () => Promise.resolve({ error: null }),
        // SEGUNDO FATOR (07/11/2026): window.__MFA__ = {fatores: [...]} guarda os celulares; o codigo certo e window.__MFA_CODIGO__ (padrao 123456).
        // Ao confirmar, a sessao vira aal2 (window.__jwt('aal2')) e o ouvinte recebe MFA_CHALLENGE_VERIFIED, como no supabase-js.
        mfa: {
          listFactors: () => { const f = (window.__MFA__ = window.__MFA__ || { fatores: [] }).fatores; return Promise.resolve({ data: { all: f.slice(), totp: f.filter((x) => x.status === 'verified') }, error: null }); },
          enroll: (o) => {
            const m = (window.__MFA__ = window.__MFA__ || { fatores: [] });
            if (m.fatores.some((x) => x.friendly_name === o.friendlyName)) return Promise.resolve({ data: null, error: { message: 'A factor with the friendly name "' + o.friendlyName + '" for this user already exists' } });
            const id = 'f' + (m.fatores.length + 1) + '_' + Date.now();
            m.fatores.push({ id, friendly_name: o.friendlyName, factor_type: 'totp', status: 'unverified' });
            // O QR do Supabase de verdade (conferido no codigo do GoTrue, 08/11/2026): SVG do goqrsvg + SVGo, bloco de 3 px, SEM viewBox,
            // um <rect> por quadradinho (preto e branco), quase 300 KB, e o supabase-js poe 'data:image/svg+xml;utf-8,' na frente.
            // Aqui: 29x29 quadradinhos com os tres cantos de posicao (7x7) e o resto em padrao fixo. window.__QR_FORMATO__ = 'hex' usa
            // fill="#000000" (cor com '#', que cortava o endereco) e 'ilegivel' manda um SVG sem quadradinhos (cai no plano B).
            const formato = window.__QR_FORMATO__ || 'gotrue', n = 29, B = 3, W = n * B + 8 * B;
            const escuro = (c, l) => {
              for (const [cx, cl] of [[0, 0], [n - 7, 0], [0, n - 7]]) {
                const dx = c - cx, dl = l - cl;
                if (dx >= 0 && dl >= 0 && dx <= 6 && dl <= 6) { const anel = Math.max(Math.abs(dx - 3), Math.abs(dl - 3)); return anel === 3 || anel <= 1; }
              }
              return (c * 7 + l * 13 + c * l) % 3 === 0;
            };
            let rects = '';
            for (let l = 0; l < n; l++) for (let c = 0; c < n; c++) {
              const e = escuro(c, l);
              rects += formato === 'hex'
                ? '<rect x="' + (12 + c * B) + '" y="' + (12 + l * B) + '" width="' + B + '" height="' + B + '" fill="' + (e ? '#000000' : '#ffffff') + '"/>\n'
                : '<rect x="' + (12 + c * B) + '" y="' + (12 + l * B) + '" width="' + B + '" height="' + B + '" style="fill:' + (e ? 'black' : 'white') + ';stroke:none" />\n';
            }
            const qr = formato === 'ilegivel'
              ? 'data:image/svg+xml;utf-8,<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><circle cx="5" cy="5" r="5" fill="#123456"/></svg>'
              : 'data:image/svg+xml;utf-8,<?xml version="1.0"?>\n<!-- Generated by SVGo -->\n<svg width="' + W + '" height="' + W + '"\n     xmlns="http://www.w3.org/2000/svg"\n     xmlns:xlink="http://www.w3.org/1999/xlink">\n' + rects + '</svg>\n';
            // window.__MFA_SEM_URI__: o servidor nao manda o endereco otpauth (o app monta o QR so com a chave); __MFA_SO_SERVIDOR__: nao manda
            // endereco nem chave (so o SVG do servidor); __MFA_NADA__: nao manda QR, endereco nem chave.
            const uri = (window.__MFA_SEM_URI__ || window.__MFA_SO_SERVIDOR__ || window.__MFA_NADA__) ? '' : 'otpauth://totp/Teste:eduardo@example.com?algorithm=SHA1&digits=6&issuer=Teste&period=30&secret=JBSWY3DPEHPK3PXP';
            const chave = (window.__MFA_SO_SERVIDOR__ || window.__MFA_NADA__) ? '' : 'JBSWY3DPEHPK3PXP';
            return Promise.resolve({ data: { id, type: 'totp', totp: { qr_code: window.__MFA_NADA__ ? '' : qr, secret: chave, uri } }, error: null });
          },
          challengeAndVerify: ({ factorId, code }) => {
            const m = (window.__MFA__ = window.__MFA__ || { fatores: [] });
            const f = m.fatores.find((x) => x.id === factorId);
            (window.__CHAMADAS_MFA__ = window.__CHAMADAS_MFA__ || []).push({ factorId, code });
            if (semRede()) return SEM_RESPOSTA();
            if (!f || code !== (window.__MFA_CODIGO__ || '123456')) return Promise.resolve({ data: null, error: { message: 'Invalid TOTP code entered', code: 'mfa_verification_failed' } });
            f.status = 'verified';
            const sessao = window.__SESSAO__ || { user: { id: 'u1' } };
            window.__SESSAO__ = Object.assign({}, sessao, { access_token: window.__jwt('aal2'), user: Object.assign({}, sessao.user, { factors: m.fatores.filter((x) => x.status === 'verified') }) });
            (window.__authCallbacks || []).forEach((cb) => cb('MFA_CHALLENGE_VERIFIED', window.__SESSAO__));
            return Promise.resolve({ data: { access_token: window.__SESSAO__.access_token }, error: null });
          },
          unenroll: ({ factorId }) => {
            const m = (window.__MFA__ = window.__MFA__ || { fatores: [] });
            m.fatores = m.fatores.filter((x) => x.id !== factorId);
            return Promise.resolve({ data: { id: factorId }, error: null });
          },
        },
      },
    };
  },
};
window.__ESCRITAS__ = [];
window.__CHAMADAS_RPC__ = [];
