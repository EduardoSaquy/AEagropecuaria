/* NÚCLEO COMUM DOS APPS (AE Matriz, AE Pecuária, AE Cana, AE Cereais, AE Combustível)
 *
 * O que é igual nos apps mora aqui, uma vez só. Antes, cada app tinha a própria cópia e as cópias foram se
 * afastando (um conserto entrava num app e ficava de fora dos outros). Carregado por <script src="core.js?v=...">
 * ANTES do script do app; as funções são globais, como sempre foram. O ?v= é a impressão digital do arquivo:
 * depois de mudar este arquivo rode `python atualiza_nucleo.py` (ele troca o ?v= nos apps; o teste confere).
 * O que depende de um app (chaves de armazenamento, state, db) continua no app: aqui só se usa no momento da chamada. */

/* ===================== AVISOS NA PÁGINA (07/11/2026) =====================
 * O alert() do navegador trava a tela até a pessoa tocar em OK, tem a cara do navegador e, no tablet e no celular do
 * campo, some atrás do teclado. Os alert() dos apps agora viram um aviso na própria tela (no topo, para não cobrir o
 * botão Salvar nem o botão +): não trava, tem botão de fechar, Esc fecha, e some sozinho, MENOS o de erro
 * ("Não foi possível...", "Erro...", "Falha..."), que fica até a pessoa fechar. O texto entra como texto (nunca como
 * HTML) e a quebra de linha da mensagem é mantida. confirm() continua nativo: pergunta que precisa de resposta.
 * Cada aviso também vai para window.__AVISOS__ e para o console ("[aviso] ...") — é por onde os testes leem. */
let TEMPO_AVISO_MS = 9000;
window.__AVISOS__ = [];
function avisar(msg){
  const texto = String(msg == null ? '' : msg);
  const erro = /^(n[aã]o foi poss[ií]vel|erro|falha|ocorreu um erro|os dados n[aã]o carregaram)/i.test(texto.trim());
  window.__AVISOS__.push({texto, erro, quando: Date.now()});
  try{ console.info('[aviso] ' + texto); }catch(e){ /* console indisponível */ }
  let caixa = document.getElementById('avisos');
  if(!caixa){
    caixa = document.createElement('div');
    caixa.id = 'avisos'; caixa.className = 'avisos';
    caixa.setAttribute('role', 'region'); caixa.setAttribute('aria-label', 'Avisos');
    document.body.appendChild(caixa);
  }
  const el = document.createElement('div');
  el.className = 'aviso ' + (erro ? 'aviso-erro' : 'aviso-info');
  el.setAttribute('role', erro ? 'alert' : 'status');
  const corpo = document.createElement('div'); corpo.className = 'aviso-texto'; corpo.textContent = texto;
  const fechaBtn = document.createElement('button');
  fechaBtn.type = 'button'; fechaBtn.className = 'aviso-fechar'; fechaBtn.setAttribute('aria-label', 'Fechar aviso'); fechaBtn.textContent = '×';
  const fechar = ()=>{ if(el.parentNode) el.parentNode.removeChild(el); };
  fechaBtn.onclick = fechar;
  el.appendChild(corpo); el.appendChild(fechaBtn);
  while(caixa.children.length >= 4) caixa.removeChild(caixa.firstChild);
  caixa.appendChild(el);
  if(!erro) setTimeout(fechar, Math.max(TEMPO_AVISO_MS, Math.min(20000, texto.length * 60)));
  return el;
}
document.addEventListener('keydown', e=>{
  if(e.key === 'Escape'){ const c = document.getElementById('avisos'); if(c && c.lastChild) c.removeChild(c.lastChild); }
});
window.alert = avisar;


/* ---------- Sessão e perfil guardado no aparelho ---------- */
async function sessaoInicial(){
  const daBiblioteca = db.auth.getSession().then(r=>r.data.session).catch(()=>null);
  if(!sessaoGuardadaNoAparelho()) return daBiblioteca;
  const limite = new Promise(res=>setTimeout(()=>res(undefined), aparelhoSemRede() ? 0 : LIMITE_ESPERA_LOGIN_MS));
  const s = await Promise.race([daBiblioteca, limite]);
  // null = a biblioteca respondeu "sem sessao": se foi por login revogado
  // ela ja apagou a guardada (volta pro login); se foi por falta de rede,
  // a guardada continua la e o app abre com ela.
  return s || sessaoGuardadaNoAparelho();
}
// Perfil: sem rede nem tenta (cairia na mesma espera de ~25 s); com rede
// lenta, desiste no limite e usa o ultimo perfil guardado.
function buscarPerfilDoBanco(uid){
  if(aparelhoSemRede()) return Promise.resolve({data:null, error:{message:'Failed to fetch (aparelho sem rede)'}});
  const busca = db.from('profiles').select('*').eq('id', uid).single();
  const limite = new Promise(res=>setTimeout(()=>res({data:null, error:{message:'Failed to fetch (demorou demais)'}}), LIMITE_ESPERA_LOGIN_MS + 1000));
  return Promise.race([busca, limite]);
}
function sessaoGuardadaNoAparelho(){
  try{
    const s = JSON.parse(localStorage.getItem(CHAVE_SESSAO_SUPABASE)||'null');
    return (s && s.user && s.access_token) ? s : null;
  }catch(e){ return null; }
}
function lerPerfilCache(uid){
  try{
    const cache = JSON.parse(localStorage.getItem(PERFIL_CACHE_KEY)||'null');
    return (cache && cache.uid===uid) ? cache.perfil : null;
  }catch(e){ return null; }
}
function salvarPerfilCache(uid, perfil){
  try{ localStorage.setItem(PERFIL_CACHE_KEY, JSON.stringify({uid, perfil})); }
  catch(e){ /* localStorage indisponível (modo privado etc.) — sem o que fazer aqui */ }
}
function normalizeUsuario(s){ return String(s||'').trim().toLowerCase().replace(/[^a-z0-9._-]/g,''); }
function aparelhoSemRede(){ return typeof navigator!=='undefined' && navigator.onLine===false; }
// Administrador e Proprietario enxergam tudo. souAdmin() sozinho nao servia
// para isso: ele so reconhece papel='admin', entao os proprietarios caiam na
// matriz de modulos como um colaborador qualquer e enxergavam UMA tela do app,
// sendo donos do negocio.
//
// O AE Matriz e o AE Pecuaria ja tratavam proprietario como acesso total;
// so a lavoura discordava, desde antes da divisao Cana/Cereais. Mesma
// divergencia que o banco tinha com is_admin() e que o is_dono() corrigiu.
//
// souAdmin() continua so para o que e de administrador mesmo (a tela de
// Usuarios), igual ao Matriz.
function acessoTotal(){
  return state.perfil?.papel === 'admin' || state.perfil?.papel === 'proprietario';
}
// Pode ver/editar o modulo? Administrador e Proprietario sempre; os demais pela matriz de modulos do perfil.
// Uma so para os cinco apps (07/11/2026): o Combustivel usava souAdmin() e por isso tratava o proprietario como
// colaborador comum; a Pecuaria e o Matriz tinham o mesmo resultado escrito de outro jeito.
function temPermissao(modulo, nivel){
  if(!state.perfil) return false;
  if(acessoTotal()) return true;
  const atual = state.perfil.permissoes?.[modulo];
  if(nivel==='visualizar') return atual==='visualizar' || atual==='editar';
  return atual==='editar';
}
// Operador pode editar (quando tiver permissão do módulo), mas nunca pode
// excluir nada já registrado -- o botão Excluir some pra esse papel, mesmo
// onde antes aparecia junto com o Editar. Não afeta "Remover da fila"
// (item ainda não sincronizado, local só desse aparelho).
function souOperador(){ return state.perfil?.papel === 'operador'; }

/* ---------- Telas comuns ---------- */
function ModalTrocarSenha(){
  const d = editDraft;
  return `
  <div class="overlay" data-close-overlay="1">
    <div class="modal" data-stop="1">
      <div class="modal-head"><h3>Trocar senha</h3><button class="modal-close" data-close="1">&times;</button></div>
      <div class="modal-body">
        <div class="field"><label>Senha atual</label><input id="f-senhaatual" type="password" autocomplete="current-password" value="${d.senhaAtual}"/></div>
        <div class="field"><label>Nova senha</label><input id="f-novasenha" type="password" autocomplete="new-password" value="${d.novaSenha}"/></div>
        <div class="field"><label>Confirmar nova senha</label><input id="f-confirmarsenha" type="password" autocomplete="new-password" value="${d.confirmarSenha}"/></div>
        <p class="hint">A nova senha precisa ter pelo menos 6 caracteres.</p>
        ${acessoTotal() ? `<div class="field" style="margin-top:18px; padding-top:14px; border-top:1px solid rgba(0,0,0,.1);">
          <label>Verificação em duas etapas</label>
          <button type="button" class="btn btn-ghost" data-mfa-abrir="1">Ativar ou gerenciar</button>
          <span class="hint">Depois da senha, o app pede um código do celular. Recomendado para quem tem acesso total.</span>
        </div>` : ''}
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-close="1">Cancelar</button>
        <button class="btn btn-primary" data-save="trocarSenha">Salvar nova senha</button>
      </div>
    </div>
  </div>`;
}
function Empty(title, sub){
  return `<div class="empty">
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#6E756C" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><path d="M9 10h.01M15 10h.01M8 15c1 1.2 2.4 2 4 2s3-.8 4-2"/></svg>
    <h4>${title}</h4>
    <div class="page-desc" style="margin:0 auto;">${sub}</div>
  </div>`;
}
function headerHtml(eyebrow,title,desc){
  return `<div class="page-header"><div><p class="eyebrow">${eyebrow}</p><h1>${title}</h1><p class="page-desc">${desc}</p></div></div>`;
}

/* ---------- Cadastros (Cana, Cereais e Combustível) ---------- */
function ModalCadastro(){
  const key = state.modal.key;
  const cfg = CADASTROS[key];
  const d = editDraft;
  return `
  <div class="overlay" data-close-overlay="1">
    <div class="modal" data-stop="1">
      <div class="modal-head"><h3>${d._editId?'Editar':'Novo(a)'} ${cfg.singular}</h3><button class="modal-close" data-close="1">&times;</button></div>
      <div class="modal-body">
        ${state.cadastroError ? `<div class="login-error">${state.cadastroError}</div>` : ''}
        ${cfg.fields.map(f=>campoHtml(f, d)).join('')}
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-close="1">Cancelar</button>
        <button class="btn btn-primary" data-save-cadastro="${key}" ${state.cadastroLoading?'disabled':''}>${state.cadastroLoading?'Salvando...':'Salvar'}</button>
      </div>
    </div>
  </div>`;
}
function abrirEditarCadastro(key, id){
  const item = state[key].find(x=>x.id===id);
  if(!item) return;
  editDraft = {...item, _editId:item.id};
  state.cadastroError = '';
  state.modal = {type:'cadastro', key};
}
function rowToCadastro(row, cfg){
  const obj = {id: row.id};
  cfg.fields.forEach(f=>{ obj[f.key] = row[toSnake(f.key)]; });
  return obj;
}
// camelCase (usado no JS) <-> snake_case (usado no Postgres), genérico,
// para não precisar de um par rowToX/xToRow escrito à mão por entidade.
function toSnake(s){ return s.replace(/[A-Z]/g, m => '_'+m.toLowerCase()); }
function toCamel(s){ return s.replace(/_([a-z0-9])/g, (_,c)=>c.toUpperCase()); }
function fmtData(iso){ return iso ? iso.split('-').reverse().join('/') : '—'; }

/* ---------- Datas e números ---------- */
// Data/mês de hoje no fuso horário local do aparelho -- toISOString() sempre
// devolve em UTC, que diverge da data local desde a meia-noite UTC até a
// meia-noite local (no Brasil, UTC-3, isso é todo santo dia entre ~21h e
// 23h59: o dia já virou em UTC mas ainda é "hoje" pra quem está lançando).
// Usar toISOString() aqui fazia todo "hoje" (inclusive o colapso de listas
// pra "só hoje") ficar um dia adiantado nesse intervalo.
function hojeStr(){
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}
function mesAtualStr(){
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
}
// Campos de peso/valor da Venda aceitam vírgula decimal (padrão brasileiro) —
// Number('480,5') dá NaN, então esses campos passam por aqui em vez de Number()
// direto. Valores já numéricos (vindos do banco) passam direto, sem mudança.
function numDecimal(v){
  if(typeof v === 'number') return v;
  if(v==null || v==='') return 0;
  return Number(String(v).replace(',','.')) || 0;
}
function fmtInt(n){ return Number(n||0).toLocaleString('pt-BR'); }
function areasLabel(areas){
  if(!areas || areas.length===0) return `<span class="pill pill-ok">Geral · rateado</span>`;
  return `<span class="pill pill-cat">${areas.map(a=>AREA_LABEL[a]).join(' + ')}</span>`;
}

/* ---------- Gráfico de rosca ---------- */
function polarXY(cx, cy, r, ang){ return [cx + r*Math.sin(ang), cy - r*Math.cos(ang)]; }
function donutSlicePath(cx, cy, rOut, rIn, a0, a1){
  const largeArc = (a1-a0) > Math.PI ? 1 : 0;
  const [x0,y0] = polarXY(cx,cy,rOut,a0);
  const [x1,y1] = polarXY(cx,cy,rOut,a1);
  const [x2,y2] = polarXY(cx,cy,rIn,a1);
  const [x3,y3] = polarXY(cx,cy,rIn,a0);
  return `M ${x0} ${y0} A ${rOut} ${rOut} 0 ${largeArc} 1 ${x1} ${y1} L ${x2} ${y2} A ${rIn} ${rIn} 0 ${largeArc} 0 ${x3} ${y3} Z`;
}

/* ---------- Ícones ---------- */
function iconAdmin(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4.5 5-6 8-6s6.5 1.5 8 6"/></svg>`; }
function iconFazenda(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 16v-4M12 16V8M17 16v-7"/></svg>`; }
// O Matriz nao tinha busca em tela nenhuma, entao nao tinha o icone.
function iconSearch(){ return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#6E756C" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>`; }
function iconResultados(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19h16"/><path d="m4 15 5-5 4 4 7-8"/></svg>`; }
function iconLeaf(){ return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 21c0-9 6-16 15-16-1 9-8 15-15 16Z"/><path d="M5 21c2-4 5-7 9-9"/></svg>`; }

/* ---------- Texto e número ---------- */
// Toda tela é montada com innerHTML a partir de texto livre do usuário
// (nome de fazenda, descrição, observação — e até dado vindo do banco do
// AE Pecuária, outro limite de confiança) — sem escapar, um <script> ou
// onerror= digitado num campo executaria na sessão de quem visualizar.
function esc(s){
  return String(s??'').replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function fmt(n, dec=2){ return Number(n||0).toLocaleString('pt-BR', {minimumFractionDigits:dec, maximumFractionDigits:dec}); }

/* ---------- Login, perfis e acesso (iguais nos cinco apps desde 07/11/2026) ---------- */
// Só administrador mesmo: tela de Usuários, criar conta, mexer na permissão dos outros (o banco só deixa is_admin()).
// "Acesso a tudo" (administrador e proprietário) é acessoTotal(), mais acima.
function souAdmin(){ return state.perfil?.papel === 'admin'; }
// Cor do perfil na lista: acesso total em destaque, gestor/consultor em amarelo, os demais em verde. O texto vem de PAPEL_LABELS
// (cada app define o seu); perfil que não está lá aparece com o nome cru.
function papelPill(papel){
  const label = PAPEL_LABELS[papel] || papel;
  const classe = (papel==='admin' || papel==='proprietario') ? 'pill-cat' : ((papel==='gestor' || papel==='consultor') ? 'pill-warn' : 'pill-ok');
  return `<span class="pill ${classe}">${esc(label)}</span>`;
}
// <option> do seletor de perfil na tela de acesso: os da lista [[valor, rótulo], ...] e, se a pessoa tem um perfil que a lista não
// tem (colaborador, consultor, gestor... conforme o app), o dela também, marcado. Sem isso o seletor cairia no primeiro item e Salvar
// rebaixaria a pessoa sem ninguém ver.
function opcoesDePapel(lista, atual){
  const opcoes = lista.map(([valor, rotulo])=>`<option value="${valor}" ${atual===valor?'selected':''}>${rotulo}</option>`);
  if(atual && !lista.some(([valor])=>valor===atual)){
    opcoes.push(`<option value="${esc(atual)}" selected>${esc(PAPEL_LABELS[atual] || atual)}</option>`);
  }
  return opcoes.join('');
}
async function fazerLogin(){
  const usuario = normalizeUsuario(state.loginDraft.usuario);
  const senha = state.loginDraft.senha;
  if(!usuario || !senha){ state.loginError = 'Informe usuário e senha.'; render(); return; }
  state.loginLoading = true; state.loginError = ''; render();
  const email = `${usuario}@${DOMINIO_LOGIN}`;
  const { data, error } = await db.auth.signInWithPassword({ email, password: senha });
  state.loginLoading = false;
  if(error){
    state.loginError = 'Usuário ou senha inválidos.';
    render();
    return;
  }
  let sessao = data.session;
  if(precisaDoSegundoFator(sessao)){
    // senha certa, mas a conta tem verificação em duas etapas: o app só abre depois do código
    state.mfaEmAndamento = true;
    const passou = await desafioMFA(sessao);
    state.mfaEmAndamento = false;
    if(!passou){ try{ await db.auth.signOut(); }catch(e){ /* sem rede: a sessão local some de qualquer jeito */ } state.loginDraft = {usuario: state.loginDraft.usuario, senha:''}; render(); return; }
    sessao = (await db.auth.getSession()).data.session || sessao;
  }
  state.session = sessao;
  await loadPerfil();
  state.loginDraft = {usuario:'', senha:''};
  render();
  if(state.perfil?.ativo){
    const carga = loadAll();
    // o app que precisa de um passo depois da carga (o Combustível confere os alertas) define aoEntrarDepoisDaCarga()
    if(typeof aoEntrarDepoisDaCarga === 'function') Promise.resolve(carga).then(aoEntrarDepoisDaCarga);
  }
}
function ModalUsuario(){
  const d = editDraft;
  return `
  <div class="overlay" data-close-overlay="1">
    <div class="modal" data-stop="1">
      <div class="modal-head"><h3>Novo usuário</h3><button class="modal-close" data-close="1">&times;</button></div>
      <div class="modal-body">
        ${state.usuarioError ? `<div class="login-error">${esc(state.usuarioError)}</div>` : ''}
        <div class="field"><label>Nome completo</label><input id="f-nomeusuario" value="${esc(d.nome)}" placeholder="Ex: João Silva" autocomplete="off"/></div>
        <div class="field"><label>Usuário (login)</label><input id="f-usuario" value="${esc(d.usuario)}" placeholder="Ex: joao.silva" autocomplete="off"/><span class="hint">Sem espaços ou acentos. É o que a pessoa vai digitar para entrar.</span></div>
        <div class="field"><label>Senha</label><input id="f-senhausuario" type="password" value="${esc(d.senha)}" autocomplete="new-password"/><span class="hint">Mínimo 6 caracteres. Pode ser trocada depois pela pessoa.</span></div>
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-close="1">Cancelar</button>
        <button class="btn btn-primary" data-criar-usuario="1" ${state.usuarioLoading?'disabled':''}>${state.usuarioLoading?'Criando...':'Criar usuário'}</button>
      </div>
    </div>
  </div>`;
}
function PageAdminUsuarios(){
  return `
  <div class="toolbar">
    <span class="hint">${state.perfis.length} usuário(s) cadastrado(s)</span>
    <button class="btn btn-primary btn-sm" data-novo-usuario="1">+ Novo usuário</button>
  </div>
  <div class="card" style="overflow-x:auto;">
    ${state.perfis.length===0 ? Empty('Nenhum usuário cadastrado','Crie contas de acesso para as pessoas da sua equipe.') : `
    <table>
      <thead><tr><th>Nome</th><th>Usuário</th><th>Perfil</th><th>Status</th><th></th></tr></thead>
      <tbody>
        ${state.perfis.map(p=>`
          <tr>
            <td><strong>${esc(p.nome)}</strong></td>
            <td class="mono">${esc(p.usuario)}</td>
            <td>${papelPill(p.papel)}</td>
            <td><span class="status-dot ${p.ativo?'ativo':'inativo'}"></span>${p.ativo?'Ativo':'Inativo'}</td>
            <td><button class="btn-ghost btn-sm" data-editar-usuario="${p.id}">Editar acesso</button></td>
          </tr>
        `).join('')}
      </tbody>
    </table>`}
  </div>`;
}

/* ---------- Navegação por grupos e leitura de tabela inteira ---------- */
// O app que troca de grupos conforme algo (o AE Cereais, pela cultura) define gruposAtuais(); os demais usam GROUPS.
function currentGroupKey(){
  const g = (typeof gruposAtuais === 'function') ? gruposAtuais() : GROUPS;
  return Object.keys(g).find(k=>g[k].pages.some(p=>p.key===state.page));
}
function gruposVisiveis(){
  const g = (typeof gruposAtuais === 'function') ? gruposAtuais() : GROUPS;
  return Object.entries(g).filter(([key])=>grupoVisivel(key));
}
// Lê uma tabela inteira, de mil em mil, até a resposta vir incompleta (sinal de que acabou). O PostgREST corta cada resposta em
// 1.000 linhas por conta própria (db-max-rows), então um .range(0, 19999) só parece trazer tudo: foi um teto, e os totais ficariam
// errados sem aviso. A consulta tem que ter ordem ESTÁVEL (um .order('id') no fim): só 'data', por exemplo, repete ou perde linha
// na fronteira entre páginas. Quem chama passa a consulta já montada, em função: fetchAllRows(()=>db.from('x').select('*').order('id')).
async function fetchAllRows(consulta){
  const PAGINA = 1000;
  let todas = [], de = 0;
  while(true){
    const { data, error } = await consulta().range(de, de + PAGINA - 1);
    if(error) return { data: todas, error };
    todas = todas.concat(data || []);
    if(!data || data.length < PAGINA) break;
    de += PAGINA;
  }
  return { data: todas, error: null };
}

/* ---------- Abertura do app, sessão e perfil (iguais nos cinco apps desde 07/11/2026) ----------
 * Cada app só define o que é dele, por funções e constantes que estas usam na hora da chamada:
 *   NOME_DO_APP (texto da marca), SLOGAN_DO_APP (opcional, linha embaixo da marca na tela de login), PERFIL_CACHE_KEY,
 *   corrigirPaginaDoPerfil() (volta para uma tela que a pessoa pode ver), aoIniciarApp() (antes de abrir a sessão),
 *   aoEntrarDepoisDaCarga() (depois da carga que o login dispara), aoRetomarSessao() (ao abrir o app já com sessão) e aoSair().
 * Todas são opcionais (typeof antes de chamar). */
const DOMINIO_LOGIN = 'aeagropecuaria.local';
// Erro de falta de sinal (e não de permissão ou de dado)? Aparelho sem rede, TypeError do fetch, ou texto de rede dos navegadores
// ("Failed to fetch" do Chrome, "Load failed" do Safari, "NetworkError..." do Firefox).
function pareceErroDeRede(err){
  if(typeof navigator!=='undefined' && navigator.onLine===false) return true;
  if(err && err.name==='TypeError') return true;
  const msg = String((err && err.message) || err || '').toLowerCase();
  return msg.includes('failed to fetch') || msg.includes('network') || msg.includes('load failed') || msg.includes('conexão');
}
function rowToPerfil(r){ return {id:r.id, nome:r.nome, usuario:r.usuario, papel:r.papel, permissoes:r.permissoes||{}, frentes:r.frentes||[], ativo:r.ativo}; }
async function loadPerfil(){
  const uid = state.session?.user?.id;
  if(!uid){ state.perfil = null; state.perfilErroRede = false; return; }
  const { data, error } = await buscarPerfilDoBanco(uid);
  state.perfilErroRede = false;
  if(data){
    state.perfil = rowToPerfil(data);
    salvarPerfilCache(uid, state.perfil);
  } else if(error && pareceErroDeRede(error)){
    // sem rede: o último perfil conhecido deste usuário; se nunca abriu online neste aparelho, avisa "sem conexão" (não "sem acesso")
    const cache = lerPerfilCache(uid);
    if(cache){ state.perfil = cache; }
    else { state.perfil = null; state.perfilErroRede = true; }
  } else {
    state.perfil = null;
  }
  if(state.perfil && state.perfil.ativo && typeof corrigirPaginaDoPerfil === 'function') corrigirPaginaDoPerfil();
}
async function initAuth(){
  if(typeof aoIniciarApp === 'function') aoIniciarApp();
  state.session = await sessaoInicial();
  if(state.session && precisaDoSegundoFator(state.session)){
    state.mfaEmAndamento = true;
    const passou = await desafioMFA(state.session);
    state.mfaEmAndamento = false;
    if(passou) state.session = (await db.auth.getSession()).data.session || state.session;
    else { try{ await db.auth.signOut(); }catch(e){ /* sem rede */ } state.session = null; }
  }
  if(state.session) await loadPerfil();
  state.authChecked = true;
  render();
  if(state.session && state.perfil?.ativo) carregarDepoisDeAbrir();

  let primeiroEvento = true;
  db.auth.onAuthStateChange(async (event, newSession)=>{
    if(primeiroEvento){ primeiroEvento = false; return; }
    if(state.mfaEmAndamento) return;   // o código do 2º fator está sendo pedido: quem segue o fluxo é fazerLogin/initAuth
    // token renovado automaticamente (a cada ~1h) não é troca de sessão de
    // verdade — o cliente supabase-js já usa o token novo sozinho; só
    // guardamos a referência, sem re-renderizar (senão um modal aberto com
    // campo digitado e ainda não salvo perderia o texto no meio da digitação).
    if(event==='TOKEN_REFRESHED' || event==='MFA_CHALLENGE_VERIFIED'){
      state.session = newSession;
      // sessão aberta só com a senha, antes de o celular ser cadastrado: a renovação traz o fator, e agora o código é pedido
      if(event==='TOKEN_REFRESHED' && precisaDoSegundoFator(newSession) && !state.mfaEmAndamento){
        state.mfaEmAndamento = true;
        const passou = await desafioMFA(newSession);
        state.mfaEmAndamento = false;
        if(passou) state.session = (await db.auth.getSession()).data.session || state.session;
        else await fazerLogout();
      }
      return;
    }
    if(event==='SIGNED_IN' && state.session?.access_token===newSession?.access_token) return;
    state.session = newSession;
    if(newSession){
      await loadPerfil();
      render();
      if(state.perfil?.ativo) carregarDepoisDeAbrir();
    } else {
      state.perfil = null;
      render();
    }
  });
}
// A carga de dados que vem depois de abrir o app com sessão (ou de a sessão trocar).
function carregarDepoisDeAbrir(){
  const carga = loadAll();
  if(typeof aoEntrarDepoisDaCarga === 'function') Promise.resolve(carga).then(aoEntrarDepoisDaCarga);
  if(typeof aoRetomarSessao === 'function') aoRetomarSessao();
}
async function fazerLogout(){
  if(typeof aoSair === 'function') aoSair();
  await db.auth.signOut();
  state.session = null;
  state.perfil = null;
  render();
}
// "Tentar novamente" da tela sem conexão: um ouvinte só para os cinco apps (o botão é desenhado por AguardandoLiberacao).
document.addEventListener('click', e=>{
  if(!(e.target && e.target.closest && e.target.closest('[data-retry-perfil]'))) return;
  (async ()=>{ await loadPerfil(); render(); if(state.perfil?.ativo) loadAll(); })();
});
function LoginPage(){
  return `
  <div class="login-wrap">
    <div class="login-card">
      <div class="login-brand">
        ${brandMark()}
        <div class="brand-name">${esc(NOME_DO_APP)}</div>
      </div>
      ${typeof SLOGAN_DO_APP !== 'undefined' ? `<p class="login-tagline">${esc(SLOGAN_DO_APP)}</p>` : ''}
      ${state.loginError ? `<div class="login-error">${esc(state.loginError)}</div>` : ''}
      <form data-login-form="1">
        <div class="login-field">
          <label>Usuário</label>
          <input type="text" autocomplete="username" data-login-usuario="1" value="${esc(state.loginDraft.usuario)}" autofocus />
        </div>
        <div class="login-field">
          <label>Senha</label>
          <input type="password" autocomplete="current-password" data-login-senha="1" value="${esc(state.loginDraft.senha)}" />
        </div>
        <button type="submit" class="btn btn-primary login-btn" ${state.loginLoading?'disabled':''}>${state.loginLoading ? 'Entrando...' : 'Entrar'}</button>
      </form>
    </div>
  </div>`;
}
function AguardandoLiberacao(){
  const semRede = state.perfilErroRede;
  return `
  <div class="login-wrap">
    <div class="login-card">
      <div class="login-brand">
        ${brandMark()}
        <div class="brand-name">${esc(NOME_DO_APP)}</div>
      </div>
      <p style="color:var(--cinza); font-size:13.5px; line-height:1.6; margin-bottom:20px;">
        ${semRede
          ? 'Não foi possível confirmar seu perfil de acesso porque este aparelho está sem conexão com a internet, e ele ainda não tem um perfil salvo de um acesso anterior. Conecte-se à internet e tente de novo.'
          : 'Seu login foi reconhecido, mas ainda não há um perfil de acesso liberado para esta conta. Fale com o administrador do sistema.'}
      </p>
      ${semRede ? `<button class="btn btn-primary login-btn" data-retry-perfil="1" style="margin-bottom:10px;">Tentar novamente</button>` : ''}
      <button class="btn btn-ghost login-btn" data-logout="1">Sair</button>
    </div>
  </div>`;
}

/* ---------- Verificação em duas etapas (TOTP), igual nos cinco apps (07/11/2026) ----------
 * Quem tem um fator confirmado (app autenticador no celular) digita um código de 6 números DEPOIS da senha. O Supabase marca o
 * login com um nível: aal1 = só a senha, aal2 = senha + código. A tela de login e a de gerenciar ficam por cima do app (não
 * dependem do render de cada app) e usam só as classes de login que todos têm. O que EXIGE o código no banco é o SQL de RLS
 * (seguranca_04): sem ele esta tela é só aviso, não proteção. Só quem tem acesso total (admin e proprietário) vê o botão de
 * ativar; quem não ativou entra como sempre.
 */
function lerJwt(token){
  try{
    const parte = String(token||'').split('.')[1];
    if(!parte) return null;
    const b64 = parte.replace(/-/g,'+').replace(/_/g,'/');
    const bin = atob(b64 + '='.repeat((4 - b64.length % 4) % 4));
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, c=>c.charCodeAt(0))));
  }catch(e){ return null; }
}
function fatoresConfirmados(sessao){
  return (sessao?.user?.factors || []).filter(f=>f.status==='verified' && (!f.factor_type || f.factor_type==='totp'));
}
// A sessão ainda pede o código? (tem fator confirmado e o login é só de senha, aal1.) Conta só com o que já está na sessão:
// funciona sem internet, e sessão sem o código de volta (aal2 guardado neste aparelho) não é desafiada de novo.
function precisaDoSegundoFator(sessao){
  const claims = lerJwt(sessao?.access_token);
  return !!claims && claims.aal === 'aal1' && fatoresConfirmados(sessao).length > 0;
}
// Tela cheia pedindo o código. Resolve true quando o código passa; false se a pessoa cancelar.
function desafioMFA(sessao){
  const fatores = fatoresConfirmados(sessao);
  return new Promise(resolve=>{
    const fundo = document.createElement('div');
    fundo.id = 'mfa-desafio';
    fundo.style.cssText = 'position:fixed; inset:0; z-index:10000; overflow:auto; background:' + (getComputedStyle(document.body).backgroundColor || '#fff');
    fundo.innerHTML = `
      <div class="login-wrap">
        <div class="login-card">
          <div class="login-brand">
            ${brandMark()}
            <div class="brand-name">${esc(NOME_DO_APP)}</div>
          </div>
          <p style="color:var(--cinza); font-size:13.5px; line-height:1.6; margin-bottom:16px;">Verificação em duas etapas. Digite o código de 6 números que aparece no app autenticador do seu celular.</p>
          <div class="login-error" id="mfa-erro" style="display:none;"></div>
          <form id="mfa-form">
            <div class="login-field">
              <label>Código</label>
              <input id="mfa-codigo" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" />
            </div>
            <button type="submit" class="btn btn-primary login-btn" id="mfa-ok">Confirmar</button>
          </form>
          <button type="button" class="btn btn-ghost login-btn" id="mfa-sair" style="margin-top:10px;">Cancelar e sair</button>
        </div>
      </div>`;
    document.body.appendChild(fundo);
    const campo = fundo.querySelector('#mfa-codigo'), botao = fundo.querySelector('#mfa-ok'), caixaErro = fundo.querySelector('#mfa-erro');
    const mostraErro = t=>{ caixaErro.textContent = t; caixaErro.style.display = 'block'; };
    let ocupado = false;
    fundo.querySelector('#mfa-form').onsubmit = async e=>{
      e.preventDefault();
      if(ocupado) return;
      const codigo = campo.value.replace(/\D/g, '');
      if(codigo.length !== 6){ mostraErro('Digite os 6 números do código.'); return; }
      if(aparelhoSemRede()){ mostraErro('Sem internet: o código só pode ser conferido com sinal.'); return; }
      ocupado = true; botao.disabled = true; botao.textContent = 'Conferindo...';
      let passou = false, faltouRede = false;
      // com mais de um celular cadastrado o código é de UM deles: tenta cada fator
      for(const f of fatores){
        const { error } = await db.auth.mfa.challengeAndVerify({ factorId: f.id, code: codigo });
        if(!error){ passou = true; break; }
        if(pareceErroDeRede(error)) faltouRede = true;
      }
      ocupado = false; botao.disabled = false; botao.textContent = 'Confirmar';
      if(passou){ fundo.remove(); resolve(true); return; }
      campo.value = ''; campo.focus();
      mostraErro(faltouRede ? 'Não consegui falar com o servidor. Confira o sinal e tente de novo.' : 'Código inválido ou vencido. Espere o próximo código aparecer no app e digite de novo.');
    };
    fundo.querySelector('#mfa-sair').onclick = ()=>{ fundo.remove(); resolve(false); };
    campo.focus();
  });
}
// O QR code do Supabase vem como data:image/svg+xml com o SVG por extenso (uns 280 KB: um <rect> por quadradinho, sem viewBox).
// Numa <img> isso é pesado, depende do navegador aceitar o endereço enorme e, sem viewBox, não encolhe (corta). Por isso o QR é
// redesenhado aqui, DENTRO da página, como um SVG pequeno (um único caminho, ~20 KB, com viewBox): carrega em qualquer navegador.
function qrSvgDoSupabase(qr){
  const texto = String(qr || ''), i = texto.indexOf(',');
  if(!texto.startsWith('data:image/svg+xml') || i < 0) return '';
  let svg = texto.slice(i + 1);
  try{ if(/%3C/i.test(svg)) svg = decodeURIComponent(svg); }catch(e){ /* já estava como texto */ }
  return svg;
}
function qrComoSvgInline(qr, tamanho){
  const svg = qrSvgDoSupabase(qr);
  const raiz = /<svg\b[^>]*>/i.exec(svg);
  if(!raiz) return '';
  const medida = (tag, nome)=>{ const r = new RegExp('\\s' + nome + '\\s*=\\s*["\']?(-?[\\d.]+)', 'i').exec(tag); return r ? Number(r[1]) : NaN; };
  let largura = medida(raiz[0], 'width'), altura = medida(raiz[0], 'height');
  const vb = /\bviewBox\s*=\s*["']\s*[-\d.]+[ ,]+[-\d.]+[ ,]+([\d.]+)[ ,]+([\d.]+)/i.exec(raiz[0]);
  if(vb){ largura = Number(vb[1]); altura = Number(vb[2]); }
  if(!(largura > 0) || !(altura > 0)) return '';
  // só os quadradinhos pretos; os que vêm em sequência na mesma linha viram um traço só
  let d = '', corrente = null, n = 0;
  const fecha = ()=>{ if(corrente){ d += 'M' + corrente.x + ' ' + corrente.y + 'h' + corrente.w + 'v' + corrente.h + 'h-' + corrente.w + 'z'; corrente = null; } };
  const preto = /fill\s*[:=]\s*["']?\s*(black|#000000|#000)\b/i;
  const re = /<rect\b[^>]*>/gi;
  let r;
  while((r = re.exec(svg))){
    const tag = r[0];
    if(!preto.test(tag)) continue;
    const x = medida(tag, 'x'), y = medida(tag, 'y'), w = medida(tag, 'width'), h = medida(tag, 'height');
    if(![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0) continue;
    n++;
    if(corrente && corrente.y === y && corrente.h === h && corrente.x + corrente.w === x) corrente.w += w;
    else { fecha(); corrente = { x, y, w, h }; }
  }
  fecha();
  if(!n) return '';
  const lado = tamanho || 220;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + largura + ' ' + altura + '" width="' + lado + '" height="' + lado + '" shape-rendering="crispEdges" role="img" aria-label="QR code para o app autenticador" style="background:#fff; display:inline-block; max-width:100%; height:auto;"><path d="' + d + '" fill="#000"/></svg>';
}
// Plano B (se o SVG vier num formato que não dá para ler): a <img> de antes, com o endereço recodificado ('#' de uma cor cortava o
// endereço) e com viewBox posto na raiz quando falta.
function qrComoImagem(qr){
  const texto = String(qr || '');
  let svg = qrSvgDoSupabase(texto);
  if(!svg) return texto;
  svg = svg.replace(/<svg\b([^>]*)>/i, (tudo, atributos)=>{
    if(/\bviewBox\s*=/i.test(atributos)) return tudo;
    const w = /\bwidth\s*=\s*["']?([\d.]+)/i.exec(atributos), h = /\bheight\s*=\s*["']?([\d.]+)/i.exec(atributos);
    return w && h ? '<svg' + atributos + ' viewBox="0 0 ' + w[1] + ' ' + h[1] + '">' : tudo;
  });
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
}
// Janela para ativar, ver e remover os celulares cadastrados (aberta pelo botão da tela "Trocar senha").
async function abrirSegundoFator(){
  if(document.getElementById('mfa-dialogo')) return;
  const caixa = document.createElement('div');
  caixa.id = 'mfa-dialogo'; caixa.className = 'overlay'; caixa.style.zIndex = '9000';
  document.body.appendChild(caixa);
  const m = { carregando: true, fatores: [], novo: null, erro: '', ocupado: false };
  const lista = async ()=>{ const { data } = await db.auth.mfa.listFactors(); return data || { all: [], totp: [] }; };
  const fecha = ()=>{
    if(m.novo) db.auth.mfa.unenroll({ factorId: m.novo.factorId });   // ativação começada e não terminada: não deixa fator pela metade
    caixa.remove();
  };
  const desenha = ()=>{
    let corpo, rodape = '';
    if(m.carregando){
      corpo = '<p class="hint">Carregando...</p>';
    } else if(m.novo){
      corpo = `
        <p class="hint">1. No celular, abra o app autenticador (Google Authenticator, Microsoft Authenticator ou Authy) e leia este QR code.</p>
        <div id="mfa-qr" style="text-align:center; margin:10px 0;">${m.novo.qrHtml || `<img src="${esc(qrComoImagem(m.novo.qr))}" alt="QR code para o app autenticador" width="220" height="220" style="background:#fff; padding:6px;"/>`}</div>
        <p class="hint">Se não conseguir ler (ou se estiver neste mesmo celular), digite esta chave no app: <strong class="mono" style="user-select:all; overflow-wrap:anywhere;">${esc(m.novo.segredo)}</strong></p>
        ${m.novo.uri && /^otpauth:\/\//i.test(m.novo.uri) ? `<p class="hint"><a class="btn btn-ghost btn-sm" id="mfa-abrir-app" href="${esc(m.novo.uri)}">Estou neste celular: abrir no app autenticador</a></p>` : ''}
        <p class="hint">2. Digite o código de 6 números que o app mostrar agora:</p>
        <div class="field"><input id="mfa-ativar-codigo" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" /></div>`;
      rodape = `<button class="btn btn-ghost" data-mfa-voltar="1">Cancelar</button>
                <button class="btn btn-primary" data-mfa-confirmar="1" ${m.ocupado ? 'disabled' : ''}>${m.ocupado ? 'Conferindo...' : 'Ativar'}</button>`;
    } else if(m.fatores.length === 0){
      corpo = `<p class="hint">Hoje o seu login é só com senha. Ativando, depois da senha o app pede um código de 6 números do app autenticador do seu celular. Recomendo cadastrar também um segundo celular, para o caso de perder o primeiro.</p>`;
      rodape = `<button class="btn btn-ghost" data-mfa-fechar="1">Fechar</button>
                <button class="btn btn-primary" data-mfa-ativar="1" ${m.ocupado ? 'disabled' : ''}>Ativar a verificação</button>`;
    } else {
      corpo = `<p class="hint">Verificação em duas etapas <strong>ativada</strong>. Aparelhos cadastrados:</p>
        <ul style="list-style:none; padding:0; margin:8px 0;">
          ${m.fatores.map(f=>`<li style="display:flex; justify-content:space-between; align-items:center; gap:10px; padding:6px 0; border-bottom:1px solid rgba(0,0,0,.08);">
            <span>${esc(f.friendly_name || 'Celular')}</span>
            <button class="btn btn-ghost btn-sm" data-mfa-remover="${esc(f.id)}">Remover</button></li>`).join('')}
        </ul>`;
      rodape = `<button class="btn btn-ghost" data-mfa-fechar="1">Fechar</button>
                <button class="btn btn-primary" data-mfa-ativar="1" ${m.ocupado ? 'disabled' : ''}>Cadastrar outro celular</button>`;
    }
    caixa.innerHTML = `
      <div class="modal">
        <div class="modal-head"><h3>Verificação em duas etapas</h3><button class="modal-close" data-mfa-fechar="1">&times;</button></div>
        <div class="modal-body">
          ${m.erro ? `<div class="login-error">${esc(m.erro)}</div>` : ''}
          ${corpo}
        </div>
        ${rodape ? `<div class="modal-foot">${rodape}</div>` : ''}
      </div>`;
    const campo = caixa.querySelector('#mfa-ativar-codigo');
    if(campo) campo.focus();
  };
  const recarrega = async ()=>{ m.fatores = (await lista()).totp || []; m.carregando = false; m.ocupado = false; desenha(); };
  caixa.addEventListener('click', async e=>{
    const alvo = e.target.closest ? e.target.closest('button') : null;
    if(!alvo){ if(e.target === caixa) fecha(); return; }
    if(alvo.dataset.mfaFechar !== undefined){ fecha(); return; }
    if(alvo.dataset.mfaVoltar !== undefined){
      if(m.novo) await db.auth.mfa.unenroll({ factorId: m.novo.factorId });
      m.novo = null; m.erro = ''; desenha(); return;
    }
    if(alvo.dataset.mfaAtivar !== undefined){
      m.ocupado = true; m.erro = ''; desenha();
      // tentativas abandonadas (fator que nunca foi confirmado) saem antes de começar outra
      for(const f of (await lista()).all || []) if(f.status !== 'verified') await db.auth.mfa.unenroll({ factorId: f.id });
      const { data, error } = await db.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Celular ' + (m.fatores.length + 1) + ' - ' + new Date().toLocaleString('pt-BR') });
      m.ocupado = false;
      if(error || !data){ m.erro = 'Não foi possível começar a ativação: ' + ((error && error.message) || 'sem resposta') + '.'; desenha(); return; }
      const totp = data.totp || {};
      let qrHtml = '';
      try{ qrHtml = qrComoSvgInline(totp.qr_code); }catch(e){ qrHtml = ''; }
      m.novo = { factorId: data.id, qr: totp.qr_code, qrHtml, segredo: totp.secret || '', uri: totp.uri || '' };
      desenha(); return;
    }
    if(alvo.dataset.mfaConfirmar !== undefined){
      const codigo = (caixa.querySelector('#mfa-ativar-codigo').value || '').replace(/\D/g, '');
      if(codigo.length !== 6){ m.erro = 'Digite os 6 números que o app mostra.'; desenha(); return; }
      m.ocupado = true; m.erro = ''; desenha();
      const { error } = await db.auth.mfa.challengeAndVerify({ factorId: m.novo.factorId, code: codigo });
      if(error){
        m.ocupado = false;
        m.erro = pareceErroDeRede(error) ? 'Sem conexão. Tente de novo com sinal.' : 'Código inválido ou vencido. Confira se o relógio do celular está certo e digite o código novo.';
        desenha(); return;
      }
      m.novo = null;
      avisar('Verificação em duas etapas ativada neste celular.');
      await recarrega(); return;
    }
    if(alvo.dataset.mfaRemover !== undefined){
      if(!confirm('Remover este celular? Se for o único, o login volta a ser só com senha.')) return;
      m.ocupado = true; desenha();
      const { error } = await db.auth.mfa.unenroll({ factorId: alvo.dataset.mfaRemover });
      m.erro = error ? 'Não foi possível remover: ' + error.message + '.' : '';
      await recarrega(); return;
    }
  });
  caixa.addEventListener('keydown', e=>{ if(e.key === 'Escape') fecha(); });
  desenha();
  await recarrega();
}
// O botão fica na tela "Trocar senha" (ModalTrocarSenha); a fase de captura passa na frente do data-stop dos modais dos apps.
document.addEventListener('click', e=>{
  if(e.target && e.target.closest && e.target.closest('[data-mfa-abrir]')){
    e.stopPropagation();
    // a tela Trocar senha do app fecha: a janela do segundo fator fica sozinha por cima
    state.modal = null; editDraft = null; render();
    abrirSegundoFator();
  }
}, true);
