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
