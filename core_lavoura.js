/* NÚCLEO DA LAVOURA (AE Cana e AE Cereais)
 *
 * Os dois apps nasceram do mesmo modelo e o estoque de insumos é o mesmo nos dois. Carregado depois de core.js,
 * com o ?v= mantido por `python atualiza_nucleo.py`. */


/* ---------- Estoque de insumos (Cana e Cereais) ---------- */
function PageEstoqueInsumos(frente){
  const categoriasOpt = frente==='Cana' ? OPCOES.CATEGORIAS_INSUMO_CANA : OPCOES.CATEGORIAS_INSUMO_GRAOS;
  const insumos = state['insumos'+frente].filter(i=>i.ativo!==false);
  if(insumos.length===0){
    return `<div class="card">${Empty('Nenhum insumo ativo', `Cadastre um insumo em Operações · ${frente==='Cana'?'Cana':'Grãos'} > Insumos para acompanhar o estoque.`)}</div>`;
  }
  const linhas = insumos.map(i=>{
    const saldo = saldoInsumo(frente, i.id);
    const precoMedio = precoMedioInsumo(frente, i.id);
    const baixo = i.estoqueMinimo!=null && saldo < Number(i.estoqueMinimo);
    return {i, saldo, precoMedio, baixo};
  });
  const valorTotalEstoque = linhas.reduce((a,l)=> a + (l.precoMedio!=null ? l.saldo*l.precoMedio : 0), 0);
  const alertas = linhas.filter(l=>l.baixo).length;
  return `
  <div class="stat-row">
    <div class="stat-card"><div class="stat-label">Insumos cadastrados</div><div class="stat-value">${insumos.length}</div></div>
    <div class="stat-card"><div class="stat-label">Valor aprox. em estoque</div><div class="stat-value">R$ ${fmt(valorTotalEstoque)}</div></div>
    <div class="stat-card"><div class="stat-label">Alertas de estoque baixo</div><div class="stat-value ${alertas>0?'alerta':''}">${alertas}</div></div>
  </div>
  <div class="card">
    <table>
      <thead><tr><th>Nível</th><th>Insumo</th><th>Categoria</th><th>Saldo</th><th>Preço médio</th><th>Status</th></tr></thead>
      <tbody>
        ${linhas.map(l=>{
          const pct = pctEstoque(l.saldo, l.i.estoqueMinimo);
          return `
          <tr>
            <td><div class="silo-wrap"><div class="silo"><div class="silo-fill ${l.baixo?'alerta':''}" style="height:${pct}%"></div></div></div></td>
            <td><strong>${esc(l.i.nome)}</strong></td>
            <td>${(categoriasOpt.find(o=>o.value===l.i.categoria)||{}).label || '—'}</td>
            <td class="mono">${fmt(l.saldo)} ${l.i.unidade} ${l.i.estoqueMinimo?`<span class="hint">/ mín. ${fmt(l.i.estoqueMinimo)} ${l.i.unidade}</span>`:''}</td>
            <td class="mono">${l.precoMedio==null ? '—' : `R$ ${fmt(l.precoMedio,4)}/${l.i.unidade}`}</td>
            <td>${l.baixo ? '<span class="pill pill-alerta">Estoque baixo</span>' : '<span class="pill pill-ok">Normal</span>'}</td>
          </tr>`;
        }).join('')}
      </tbody>
    </table>
  </div>`;
}
/* Fazenda → cadastra o talhão (nome, ha, cultura) direto ali embaixo,
 * sem precisar ir pra aba Talhões e escolher a fazenda de novo. */
function linhaTalhoesDaFazenda(fazenda, podeEditar, colspanTotal){
  const aberto = !!state.fazendaTalhoesAbertos[fazenda.id];
  const talhoes = state.talhoes.filter(t=>t.fazendaId===fazenda.id && t.tipo==='talhao');
  return `
  <tr class="fazenda-talhoes-row">
    <td colspan="${colspanTotal}" style="padding:0;">
      <div class="despesa-grupo-header" style="cursor:pointer;" data-fazenda-talhoes-toggle="${fazenda.id}">
        <span class="despesa-grupo-seta">${aberto?'▼':'▶'}</span>
        <span class="despesa-grupo-nome">Talhões desta fazenda</span>
        <span class="hint">${talhoes.length} talhão(ões)</span>
      </div>
      ${aberto ? `
      <div style="padding:0 16px 16px;">
        ${talhoes.length===0 ? `<p class="hint">Nenhum talhão cadastrado ainda nesta fazenda.</p>` : `
        <table class="despesa-grupo-tabela">
          <thead><tr><th>Nome</th><th>Área (ha)</th><th>Cultura</th><th>Status</th><th></th></tr></thead>
          <tbody>
            ${talhoes.map(t=>`
              <tr>
                <td>${esc(t.nome)}</td>
                <td class="mono">${t.areaHa?fmt(t.areaHa)+' ha':'—'}</td>
                <td>${t.culturaId!=null ? `<span class="pill ${frenteDoTalhao(t)==='graos'?'pill-graos':'pill-cana'}">${fkNome('culturas', t.culturaId)}</span>` : '—'}</td>
                <td><span class="status-dot ${t.ativo?'ativo':'inativo'}"></span>${t.ativo?'Ativo':'Inativo'}</td>
                <td style="display:flex; gap:6px;">
                  <button class="btn-ghost btn-sm" data-historico-talhao="${t.id}">Histórico</button>
                  ${podeEditar ? `<button class="btn-ghost btn-sm" data-edit-cadastro="talhoes:${t.id}">Editar</button>` : ''}
                  ${podeEditar && !souOperador() ? `<button class="btn-danger-ghost" data-del-cadastro="talhoes:${t.id}">Excluir</button>` : ''}
                </td>
              </tr>
            `).join('')}
          </tbody>
        </table>`}
        ${podeEditar ? `<button class="btn btn-primary btn-sm" style="margin-top:10px;" data-novo-cadastro="talhoes" data-preset-fazenda="${fazenda.id}">+ Novo Talhão</button>` : ''}
      </div>` : ''}
    </td>
  </tr>`;
}
/* Corta tudo que nao e desta frente na ENTRADA dos dados, e nao em cada
 * tela. Assim toda lista, todo seletor e todo calculo ja nascem certos,
 * sem depender de alguem lembrar de filtrar em cada lugar novo. */
function filtrarPelaFrente(fazendaAtividades){
  state.culturas = state.culturas.filter(c => c.frente === FRENTE);
  const idsCultura = new Set(state.culturas.map(c=>c.id));
  state.safras  = state.safras.filter(s  => s.culturaId!=null && idsCultura.has(s.culturaId));
  state.talhoes = state.talhoes.filter(t => t.culturaId!=null && idsCultura.has(t.culturaId));

  // Uma fazenda entra se DECLAROU a atividade ou se ja tem talhao desta
  // frente. A segunda condicao existe para nunca esconder fazenda que tem
  // trabalho de verdade so porque faltou declarar a area no Matriz.
  const daFrente = new Set([
    ...fazendaAtividades.filter(a => a.atividade===ATIVIDADE && Number(a.area_ha||0)>0)
                        .map(a => a.fazenda_id),
    ...state.talhoes.map(t => t.fazendaId),
  ]);
  state.fazendas = state.fazendas.filter(f => daFrente.has(f.id));
}
function precoMedioInsumo(frente, insumoId){
  const entradas = state['entradasInsumo'+frente].filter(e=>e.insumoId===insumoId && e.precoPago!=null && e.precoPago!=='');
  const qtd = entradas.reduce((a,e)=>a+Number(e.quantidade||0),0);
  if(qtd<=0) return null;
  const valor = entradas.reduce((a,e)=>a+Number(e.quantidade||0)*Number(e.precoPago||0),0);
  return valor/qtd;
}
function frenteDoTalhao(t){
  if(!t || t.culturaId==null) return null;
  const c = state.culturas.find(x=>x.id===t.culturaId);
  return c ? c.frente : null;
}
function saldoInsumo(frente, insumoId){
  return totalEntradasInsumo(frente, insumoId) - totalAplicacoesInsumo(frente, insumoId);
}
function totalEntradasInsumo(frente, insumoId){
  return state['entradasInsumo'+frente].filter(e=>e.insumoId===insumoId).reduce((a,e)=>a+Number(e.quantidade||0),0);
}
function totalAplicacoesInsumo(frente, insumoId){
  return state['aplicacoes'+frente].filter(a=>a.insumoId===insumoId).reduce((a,x)=>a+Number(x.quantidade||0),0);
}
function pctEstoque(saldo, minimo){
  if(!minimo || minimo<=0) return saldo>0 ? 100 : 0;
  return Math.round(Math.max(0, Math.min(saldo/(minimo*2), 1)) * 100);
}

/* ---------- Ícones ---------- */
function iconGrao(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2c2 2 2 5 0 7-2-2-2-5 0-7Z"/><path d="M12 9v13"/><path d="M8 13c0 3 2 4 4 4M16 13c0 3-2 4-4 4M6 17c0 2.5 2.5 3.5 6 3.5M18 17c0 2.5-2.5 3.5-6 3.5"/></svg>`; }
function iconPlantio(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22v-9"/><path d="M12 13c0-4 3-7 7-7 0 4-3 7-7 7Z"/><path d="M12 13C12 9 9 6 5 6c0 4 3 7 7 7Z"/></svg>`; }
function iconResultado(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17 9 11 13 15 21 7"/><path d="M15 7h6v6"/></svg>`; }

function salvarCacheLocal(){
  try{
    const snapshot = {};
    CADASTRO_KEYS.forEach(k=>{ snapshot[k] = state[k]; });
    // Guarda tambem as atividades das fazendas: sem elas o corte por frente
    // na abertura offline nao teria como saber quais fazendas sao desta
    // frente, e cairia so nos talhoes.
    snapshot.__fazendaAtividades = state.fazendaAtividades || [];
    localStorage.setItem(CACHE_LOCAL_KEY, JSON.stringify(snapshot));
  }catch(e){ /* localStorage indisponível ou cheio — segue sem cache offline */ }
}
function carregarCacheLocal(){
  try{
    const raw = localStorage.getItem(CACHE_LOCAL_KEY);
    if(!raw) return;
    const snapshot = JSON.parse(raw);
    Object.keys(snapshot).forEach(k=>{ if(CADASTROS[k]) state[k] = snapshot[k]; });
    // O cache tambem tem que passar pelo corte por frente: ele e pintado na
    // tela antes de loadAll() rodar. Sem fazendaAtividades gravada, o corte
    // usa so os talhoes - que ja bastam, porque toda fazenda desta frente
    // tem talhao dela.
    filtrarPelaFrente(snapshot.__fazendaAtividades || []);
  }catch(e){ /* cache corrompido — ignora e segue vazio até conseguir carregar do servidor */ }
}
async function loadAll(){
  const results = await Promise.all([
    ...CADASTRO_KEYS.map(k => {
      const cfg = CADASTROS[k];
      return fetchAllRows(()=>db.from(cfg.table).select('*').order(cfg.orderBy || 'nome', {ascending: !cfg.orderDesc}).order('id'));
    }),
    db.from('profiles').select('*').order('nome'),
    db.from('fazenda_atividades').select('*'),
  ]);
  CADASTRO_KEYS.forEach((k,i)=>{ state[k] = (results[i].data||[]).map(row=>rowToCadastro(row, CADASTROS[k])); });
  state.perfis = (results[CADASTRO_KEYS.length].data||[]).map(rowToPerfil);
  state.fazendaAtividades = (results[CADASTRO_KEYS.length+1].data) || [];
  filtrarPelaFrente(state.fazendaAtividades);
  salvarCacheLocal();
  render();
}
function render(){
  const root = document.getElementById('root');
  if(!state.authChecked){ root.innerHTML = `<div class="login-loading">Carregando...</div>`; return; }
  if(!state.session){ root.innerHTML = LoginPage(); attachEvents(); return; }
  if(!state.perfil || !state.perfil.ativo){ root.innerHTML = AguardandoLiberacao(); attachEvents(); return; }

  const grupos = gruposVisiveis();
  const semModulos = grupos.length===0;
  root.innerHTML = `
    <div class="app">
      ${Topbar()}
      ${BotaoMenuCelular()}
      ${TabsRow()}
      <div class="main">
        ${semModulos ? Empty('Nenhum módulo liberado','Fale com o administrador do sistema para liberar o acesso aos cadastros.') : `
        ${Header()}
        ${SubTabs()}
        ${paginaCustom(state.page)}
        `}
      </div>
    </div>
    ${state.modal ? Modal() : ''}
  `;

  // EXCLUIR E SO DE ADMIN OU PROPRIETARIO, em todo o app - a mesma regra
  // que o banco aplica em pode_excluir().
  //
  // Varre o DOM depois de montar, em vez de condicionar cada botao um a
  // um. Sao dezenas de botoes espalhados; um esquecido viraria um clique
  // que NAO da erro nenhum: a RLS nega o delete em silencio (apaga zero
  // linhas sem reclamar), a tela recarrega e o registro continua la. A
  // pessoa clica de novo achando que nao pegou.
  //
  // As linhas que o app apaga por conta propria (movimentos ao editar uma
  // saida de racao, desfazer um manejo que falhou) nao passam por botao,
  // entao continuam funcionando para quem nao e dono.
  if(!podeExcluir()){
    root.querySelectorAll('[class*="danger"], button, a').forEach(el=>{
      for(const attr of el.attributes){
        if(attr.name.startsWith('data-del-')){ el.remove(); return; }
      }
    });
  }
  attachEvents();
}
// Excluir e so de admin ou proprietario, em todo o app. Mesma regra que o
// banco aplica em pode_excluir(); aqui e so para nao mostrar um botao que
// vai falhar - e falhar calado, porque a RLS nega delete sem dar erro.
function podeExcluir(){ return acessoTotal(); }
function primeiraPaginaVisivel(){
  for(const [,g] of gruposVisiveis()){
    if(g.pages[0]) return g.pages[0].key;
  }
  return null;
}
function TabsRow(){
  const activeGroup = currentGroupKey();
  return `
  <div class="tabsrow">
    ${gruposVisiveis().map(([key,g])=>ItemDoMenu({chave:key, rotulo:g.label, icone:g.icon, ativo:activeGroup===key, botao:`data-nav-group="${key}"`,
      subs:g.pages.map(p=>({rotulo:p.label, valor:p.key, ativo:state.page===p.key}))})).join('')}
  </div>`;
}
function brandMark(){
  return `<svg class="brand-mark" viewBox="0 0 32 32" fill="none">
    <path d="M16 3v26" stroke="#1B4332" stroke-width="2.4" stroke-linecap="round"/>
    <path d="M13 4c-2 3-2 6-2 9s0 6 2 9" stroke="#95D5B2" stroke-width="2" stroke-linecap="round"/>
    <path d="M19 4c2 3 2 6 2 9s0 6-2 9" stroke="#40916C" stroke-width="2" stroke-linecap="round"/>
    <path d="M16 8c3-2 6-2 8 0M16 22c-3-2-6-2-8 0" stroke="#2D6A4F" stroke-width="1.8" stroke-linecap="round"/>
  </svg>`;
}
function iconMoney(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v10M15 9.8c0-1.5-1.3-2.6-3-2.6s-3 1-3 2.3c0 3 6 1.4 6 4.4 0 1.4-1.3 2.6-3 2.6s-3-1.1-3-2.6"/></svg>`; }
function fkNome(entityKey, id){
  if(id===null || id===undefined || id==='') return '—';
  const item = (state[entityKey]||[]).find(x=>String(x.id)===String(id));
  return item ? item.nome : '—';
}
function celulaValor(f, item){
  if(f.type==='computed') return f.compute(item);
  const val = item[f.key];
  if(f.type==='fk') return esc(fkNome(f.refEntity, val));
  if(f.type==='select') return esc((f.options.find(o=>o.value===val)||{}).label || val || '—');
  if(f.type==='date') return fmtData(val);
  if(f.type==='number') return (val===null||val===undefined||val==='') ? '—' : `${fmt(val, f.dec ?? 2)}${f.suffix||''}`;
  return esc(val || '—');
}
function novoCadastroDraft(key){
  const cfg = CADASTROS[key];
  const draft = {};
  cfg.fields.forEach(f=>{
    if(f.type==='checkbox') draft[f.key] = f.default!==undefined ? f.default : true;
    else if(f.type==='select') draft[f.key] = f.options[0]?.value ?? '';
    else if(f.type==='fixed' || f.type==='computed') draft[f.key] = f.value;
    else if(f.type==='fk') draft[f.key] = (state[f.refEntity]||[]).filter(f.filter||(()=>true)).find(x=>x.ativo!==false)?.id ?? '';
    else if(f.key==='unidade') draft[f.key] = 'L';
    else draft[f.key] = '';
  });
  return draft;
}
async function excluirCadastro(key, id){
  const cfg = CADASTROS[key];
  if(!confirm(`Excluir este(a) ${cfg.singular.toLowerCase()}? Essa ação não pode ser desfeita.`)) return;
  const { error } = await db.from(cfg.table).delete().eq('id', id);
  if(error){ alert('Não foi possível excluir: ' + mensagemErroSupabase(error)); return; }
  await loadAll();
}
function mensagemErroSupabase(error){
  if(error?.code==='23505') return 'Já existe um registro com esse nome (talvez nesta fazenda). Use outro nome ou edite o existente.';
  if(error?.code==='23503') return 'Não é possível excluir: existem outros cadastros vinculados a este registro.';
  if(error?.code==='23514') return 'Verifique os valores informados.';
  return error?.message || 'Erro desconhecido.';
}
function campoHtml(f, d){
  if(f.type==='fixed' || f.type==='computed') return '';
  const val = d[f.key] ?? '';
  const id = `f-${f.key}`;
  if(f.type==='checkbox'){
    return `<div class="field"><label><input type="checkbox" id="${id}" ${val?'checked':''} style="width:auto; margin-right:6px;"/> ${f.label}</label></div>`;
  }
  if(f.type==='textarea'){
    return `<div class="field"><label>${f.label}</label><textarea id="${id}" rows="3" autocomplete="off">${esc(val)}</textarea></div>`;
  }
  if(f.type==='select'){
    return `<div class="field"><label>${f.label}</label><select id="${id}">${f.options.map(o=>`<option value="${o.value}" ${val===o.value?'selected':''}>${o.label}</option>`).join('')}</select></div>`;
  }
  if(f.type==='fk'){
    const lista = (state[f.refEntity]||[]).filter(x=>x.ativo!==false).filter(f.filter||(()=>true));
    return `<div class="field"><label>${f.label}</label>
      <select id="${id}">
        ${f.required?'':'<option value="">—</option>'}
        ${lista.map(o=>`<option value="${o.id}" ${String(val)===String(o.id)?'selected':''}>${esc(o.nome)}</option>`).join('')}
      </select>
      ${lista.length===0?`<span class="hint">Cadastre ${CADASTROS[f.refEntity].singular.toLowerCase()} antes.</span>`:''}
    </div>`;
  }
  if(f.type==='date'){
    return `<div class="field"><label>${f.label}</label><input type="date" id="${id}" value="${val}"/></div>`;
  }
  if(f.type==='number'){
    return `<div class="field"><label>${f.label}</label><input type="number" step="${f.step||'1'}" id="${id}" value="${val}" autocomplete="off"/>${f.hint?`<span class="hint">${f.hint}</span>`:''}</div>`;
  }
  return `<div class="field"><label>${f.label}</label><input type="text" id="${id}" value="${esc(val)}" autocomplete="off" ${f.placeholder?`placeholder="${f.placeholder}"`:''}/></div>`;
}
function lerCampoDOM(f){
  if(f.type==='fixed') return f.value;
  const el = document.getElementById(`f-${f.key}`);
  if(!el) return undefined;
  return f.type==='checkbox' ? el.checked : el.value;
}
function ModalPermissoes(){
  const d = editDraft;
  return `
  <div class="overlay" data-close-overlay="1">
    <div class="modal" data-stop="1">
      <div class="modal-head"><h3>Editar acesso — ${esc(d.nome)}</h3><button class="modal-close" data-close="1">&times;</button></div>
      <div class="modal-body">
        <div class="field"><label>Usuário</label><input value="${d.usuario}" disabled/></div>
        <div class="field"><label>Perfil</label>
          <select id="f-papelusuario">
            ${opcoesDePapel([['operador','Operador'], ['colaborador','Colaborador'], ['encarregado','Encarregado'], ['gestor','Gestor'], ['proprietario','Proprietário'], ['admin','Administrador']], d.papel)}
          </select>
        </div>
        <div class="field"><label><input type="checkbox" id="f-ativousuario" ${d.ativo?'checked':''} style="width:auto; margin-right:6px;"/> Conta ativa</label></div>
        <p class="hint">Administrador e proprietário têm acesso total. Cada módulo abaixo é independente: dá para liberar só os cadastros, só as operações, ou os dois. <strong>Visualizar</strong> deixa ver sem mexer; <strong>Editar</strong> deixa criar, alterar e excluir. Financeiro e resultados ficam no AE Matriz, com permissão própria de lá.</p>
        <table class="perm-matrix">
          <thead><tr><th>Módulo</th><th>Permissão</th></tr></thead>
          <tbody>
            ${MODULOS_PERMISSAO.map(([key,label])=>`
              <tr>
                <td>${label}</td>
                <td>
                  <select data-perm-modulo="${key}">
                    <option value="nenhum" ${(!d.permissoes[key] || d.permissoes[key]==='nenhum')?'selected':''}>Nenhum</option>
                    <option value="visualizar" ${d.permissoes[key]==='visualizar'?'selected':''}>Visualizar</option>
                    <option value="editar" ${d.permissoes[key]==='editar'?'selected':''}>Editar</option>
                  </select>
                </td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-close="1">Cancelar</button>
        <button class="btn btn-primary" data-save="permissoes">Salvar</button>
      </div>
    </div>
  </div>`;
}
function Modal(){
  if(state.modal.type==='cadastro') return ModalCadastro();
  if(state.modal.type==='usuario') return ModalUsuario();
  if(state.modal.type==='permissoes') return ModalPermissoes();
  if(state.modal.type==='trocarSenha') return ModalTrocarSenha();
  if(state.modal.type==='historicoTalhao') return ModalHistoricoTalhao();
  return '';
}

/* ---------- Ganchos do login para o Cana e o Cereais (as funções de login estão no core.js) ---------- */
function corrigirPaginaDoPerfil(){
  if(!paginaAcessivel(state.page)){
    const primeira = primeiraPaginaVisivel();
    if(primeira) state.page = primeira;
  }
}
function aoIniciarApp(){ carregarCacheLocal(); }
function aoSair(){ state.page = 'talhoes'; }
