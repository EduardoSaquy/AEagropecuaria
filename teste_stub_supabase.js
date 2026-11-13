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
// Como no banco depois do seguranca_07b: as colunas de preco nao saem direto da tabela.
window.__PRECOS_TRANCADOS__ = window.__PRECOS_TRANCADOS__ || {
  ingredientes: ['preco_kg'], movimentos: ['preco_kg'], abates: ['valor_arroba', 'valor_por_animal', 'valor_kg'],
  reproducao_custos: ['custo'], entradas_estoque: ['valor_total'], manutencoes: ['custo'],
  entradas_insumo_cana: ['preco_pago'], entradas_insumo_graos: ['preco_pago'],
};
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
      // <tabela>_leitura (seguranca_07): visao com as mesmas linhas da tabela; o preco vem vazio se o
      // teste disser que a pessoa nao pode ve-lo (window.__SEM_PRECO__[tabela] = [colunas]).
      // window.__PRECOS_TRANCADOS__[tabela] = [colunas]: ler essas colunas direto da tabela (ou '*')
      // da erro de permissao, como no banco depois do 07b.
      const visao = /_leitura$/.test(nome);
      const base = visao ? nome.replace(/_leitura$/, '') : nome;
      let linhas = nome === 'lancamentos_rateados'
        ? () => (window.__DB__.lancamentos_financeiros || []).map(r => ({ ...r, lancamento_id: r.id, rateio_id: null, rateado: false }))
        : visao
          ? () => (window.__DB__[base] || []).map(r => {
              const cols = (window.__SEM_PRECO__ || {})[base];
              if (!cols) return { ...r };
              const c = { ...r }; cols.forEach(k => { if (k in c) c[k] = null; }); return c;
            })
          : () => (window.__DB__[nome] || []).slice();
      const q = {
        _rows: null,
        _filtros: [],
        _pendingUpdate: undefined,
        _pendingDelete: false,
        select(cols) {
          const trancadas = (window.__PRECOS_TRANCADOS__ || {})[nome];
          if (trancadas && this._pendingUpdate === undefined) {
            const pedidas = (cols == null || String(cols).trim() === '*') ? ['*'] : String(cols).split(',').map(x => x.trim());
            if (pedidas.includes('*') || pedidas.some(c => trancadas.includes(c))) {
              this._erro = { code: '42501', message: 'permission denied for table ' + nome };
              (window.__LEITURAS_BARRADAS__ = window.__LEITURAS_BARRADAS__ || []).push(nome + ':' + (cols || '*'));
            }
          }
          this._rows = linhas(); return this;
        },
        eq(col, val) { this._filtros.push(r => String(r[col]) === String(val)); return this; },
        in(col, vals) { const s = new Set((vals || []).map(String)); this._filtros.push(r => s.has(String(r[col]))); return this; },
        // not(col, 'in', '(1,2,3)') como no PostgREST; outros operadores: so 'eq'.
        not(col, op, val) {
          if (op === 'in') { const s = new Set(String(val).replace(/^\(|\)$/g, '').split(',').map(x => x.trim())); this._filtros.push(r => !s.has(String(r[col]))); }
          else if (op === 'eq') this._filtros.push(r => String(r[col]) !== String(val));
          return this;
        },
        order() { return this; },
        limit(n) { this._limit = n; return this; },
        range(de, ate) {
          if (semRede()) return SEM_RESPOSTA();
          if (this._erro) return Promise.resolve({ data: null, error: this._erro });
          const r = this._aplicar();
          return Promise.resolve({ data: r.slice(de, ate + 1), error: null });
        },
        single() {
          if (semRede()) return SEM_RESPOSTA();
          if (this._erro) return Promise.resolve({ data: null, error: this._erro });
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
            // como o JSON do supabase-js: chave com undefined nao vai ao banco
            const v = Object.fromEntries(Object.entries(this._pendingUpdate).filter(([, x]) => x !== undefined));
            alvo.forEach(r => Object.assign(r, v));
            return Promise.resolve({ data: alvo, error: null }).then(res, rej);
          }
          if (this._pendingDelete) {
            const alvo = new Set(this._aplicar());
            window.__DB__[nome] = (window.__DB__[nome] || []).filter(r => !alvo.has(r));
            return Promise.resolve({ data: null, error: null }).then(res, rej);
          }
          if (this._erro) return Promise.resolve({ data: null, error: this._erro }).then(res, rej);
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
            // O app nao mostra mais o QR (decisao do Eduardo, 09/11/2026: so a chave e o botao de abrir no app autenticador), mas o servidor ainda
            // manda qr_code, secret e uri. window.__MFA_SEM_URI__: nao manda o endereco otpauth (o app o monta com a chave); __MFA_NADA__: nao manda a chave.
            const uri = (window.__MFA_SEM_URI__ || window.__MFA_NADA__) ? '' : 'otpauth://totp/Teste:eduardo@example.com?algorithm=SHA1&digits=6&issuer=Teste&period=30&secret=JBSWY3DPEHPK3PXP';
            const chave = window.__MFA_NADA__ ? '' : 'JBSWY3DPEHPK3PXP';
            return Promise.resolve({ data: { id, type: 'totp', totp: { qr_code: 'data:image/svg+xml;utf-8,<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>', secret: chave, uri } }, error: null });
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
// (12/11/2026) A biblioteca de verdade passou a vir do proprio site (vendor/supabase-js-*.js), que o teste nao intercepta
// quando abre o app por file://. Ela faz `var supabase = ...` ao carregar: o stub fica no lugar e essa atribuicao e ignorada.
(function () {
  const stub = window.supabase;
  try { Object.defineProperty(window, 'supabase', { get() { return stub; }, set() {}, configurable: false }); } catch (e) { /* ja protegido */ }
})();
