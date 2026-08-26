// Banco falso para os testes. Imita o pedaco do supabase-js que os apps
// usam, contra os dados em window.__DB__. Nao tenta ser fiel ao Supabase
// inteiro: so ao que estes arquivos chamam.
window.supabase = {
  createClient() {
    function tabela(nome) {
      let linhas = () => (window.__DB__[nome] || []).slice();
      const q = {
        _rows: null,
        _filtros: [],
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
          let r = this._rows || linhas();
          this._filtros.forEach(f => { r = r.filter(f); });
          return r;
        },
        then(res) { return Promise.resolve({ data: this._aplicar(), error: null }).then(res); },
        insert(v) { window.__ESCRITAS__.push({ tabela: nome, op: 'insert', v }); return Promise.resolve({ data: null, error: null }); },
        update(v) { window.__ESCRITAS__.push({ tabela: nome, op: 'update', v }); return this; },
        delete() { window.__ESCRITAS__.push({ tabela: nome, op: 'delete' }); return this; },
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
