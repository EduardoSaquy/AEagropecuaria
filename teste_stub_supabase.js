// Banco falso para os testes. Imita o pedaco do supabase-js que os apps
// usam, contra os dados em window.__DB__. Nao tenta ser fiel ao Supabase
// inteiro: so ao que estes arquivos chamam.
//
// insert/update/delete gravam de verdade em window.__DB__ (nao so
// registram a intencao) desde que o teste de Financiamentos passou a
// clicar em "Salvar" de verdade -- os tres arquivos de teste antigos nunca
// exercitavam esse caminho, entao isso nao muda nenhum deles.
window.supabase = {
  createClient() {
    function tabela(nome) {
      let linhas = () => (window.__DB__[nome] || []).slice();
      const q = {
        _rows: null,
        _filtros: [],
        _pendingUpdate: undefined,
        _pendingDelete: false,
        select() { this._rows = linhas(); return this; },
        eq(col, val) { this._filtros.push(r => String(r[col]) === String(val)); return this; },
        order() { return this; },
        range(de, ate) {
          const r = this._aplicar();
          return Promise.resolve({ data: r.slice(de, ate + 1), error: null });
        },
        single() {
          const r = this._aplicar();
          return Promise.resolve({ data: r[0] || null, error: null });
        },
        _aplicar() {
          // Linhas reais (mesma referencia de objeto que window.__DB__[nome]):
          // update/delete precisam mutar o objeto de verdade, nao uma copia.
          let r = this._rows || linhas();
          this._filtros.forEach(f => { r = r.filter(f); });
          return r;
        },
        then(res, rej) {
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
      functions: { invoke: () => Promise.resolve({ data: {}, error: null }) },
      auth: {
        getSession: () => Promise.resolve({ data: { session: window.__SESSAO__ } }),
        onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
        signInWithPassword: () => Promise.resolve({ data: { session: window.__SESSAO__ }, error: null }),
        signOut: () => Promise.resolve({}),
        updateUser: () => Promise.resolve({ error: null }),
      },
    };
  },
};
window.__ESCRITAS__ = [];
