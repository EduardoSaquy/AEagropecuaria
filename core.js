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


/* ---------- Rodinha do mouse não muda número de campo (09/11/2026) ----------
 * Pedido do Eduardo (as secretárias): com o cursor parado em cima de um campo numérico que ainda está selecionado
 * (ex.: nº de parcelas da conta a pagar), girar a rodinha para rolar a tela somava ou tirava 1 do campo, e a conta
 * refazia o valor de cada parcela sem ninguém ver. Agora a rodinha só rola: o campo perde a seleção na hora e o
 * navegador rola a página (ou a janela aberta) em vez de mudar o número. Teclado (setas) e digitar continuam iguais.
 * Fase de captura e sem preventDefault (passive): roda antes de qualquer ouvinte do app e não trava a rolagem. */
function campoQueARodinhaMudaria(el){
  return !!el && el.tagName === 'INPUT' && String(el.type).toLowerCase() === 'number';
}
document.addEventListener('wheel', e=>{
  const foco = document.activeElement;
  if(campoQueARodinhaMudaria(foco) && (e.target === foco || (foco.contains && foco.contains(e.target)))) foco.blur();
}, {capture: true, passive: true});

/* ---------- Hora do último uso do aparelho (12/11/2026) ----------
 * Pedido do Eduardo: o AE Matriz (financeiro) pede o login de novo depois de 20 minutos sem uso, para um computador do
 * escritório esquecido aberto não deixar o financeiro à mostra. Os cinco apps dividem o mesmo login no mesmo navegador,
 * então qualquer toque, tecla ou rolagem em QUALQUER um deles marca a hora aqui (no máximo uma gravação a cada 15 s);
 * só o AE Matriz confere e sai (MINUTOS_SEM_USO_PARA_SAIR, lá). Quem está usando a Pecuária no mesmo navegador não
 * perde o login por estar fora do Matriz. */
const CHAVE_ULTIMO_USO = 'ae_ultimo_uso_v1';
let ultimoUsoGravadoAqui = 0;
function marcarUso(forcar){
  const agora = Date.now();
  if(!forcar && agora - ultimoUsoGravadoAqui < 15000) return;
  ultimoUsoGravadoAqui = agora;
  try{ localStorage.setItem(CHAVE_ULTIMO_USO, String(agora)); }catch(e){ /* sem espaço: o Matriz só não sai sozinho */ }
}
function horaDoUltimoUso(){
  try{ const v = Number(localStorage.getItem(CHAVE_ULTIMO_USO)); return Number.isFinite(v) && v > 0 ? v : 0; }catch(e){ return 0; }
}
['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach(ev=>document.addEventListener(ev, ()=>marcarUso(), {capture: true, passive: true}));


/* ---------- Datas no formato do Brasil, em qualquer navegador (09/11/2026) ----------
 * Pedido do Eduardo: "as datas têm aparecido tipo data americana". O campo de data do navegador (<input type="date">,
 * "month" e "datetime-local") se desenha no idioma do NAVEGADOR, não no do app: num Chrome em inglês 9 de novembro
 * aparece 11/09/2026, e não há como mudar isso por fora. Por isso todo campo de data dos apps vira, assim que aparece
 * na tela, um campo de texto que mostra e aceita dd/mm/aaaa (mm/aaaa no mês; dd/mm/aaaa hh:mm com hora):
 * - el.value continua devolvendo e recebendo o formato do banco (2026-11-09; 2026-11; 2026-11-09T08:30), como o campo
 *   do navegador fazia: o resto do código lê e grava sem mudar nada. Data incompleta ou impossível devolve '' (igual ao
 *   navegador). Ao sair do campo, ano com 2 números vira 20xx (09/11/26 -> 09/11/2026) e dia/mês de 1 número ganha o 0.
 * - digitando só números as barras entram sozinhas (09112026 -> 09/11/2026); teclado numérico no celular.
 * - o calendário continua: o ícone à direita é um campo de data de verdade, invisível, por cima do ícone (no iPad o
 *   calendário só abre tocando num campo de data de verdade; showPicker() não funciona lá).
 * - "change" sai quando a data fica completa (como no campo do navegador) e não se repete ao sair do campo.
 * Feito uma vez aqui para os cinco apps: um observador converte cada campo novo depois de cada redesenho. */
const VALOR_NATIVO_CAMPO = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
const FORMATOS_DATA = {
  'date':           {grupos:[2,2,4],     seps:['/','/'],         modelo:'dd/mm/aaaa',       ano:2},
  'month':          {grupos:[2,4],       seps:['/'],             modelo:'mm/aaaa',          ano:1},
  'datetime-local': {grupos:[2,2,4,2,2], seps:['/','/',' ',':'], modelo:'dd/mm/aaaa hh:mm', ano:2},
};
const SELETOR_CAMPO_DATA = Object.keys(FORMATOS_DATA).map(t=>`input[type="${t}"]:not(.campo-data-seletor)`).join(', ');
// Formato do banco -> partes na ordem da tela ([dia, mês, ano(, hora, minuto)]); null se não for desse formato.
function partesDoIsoData(tipo, v){
  const m = /^\s*(\d{4})-(\d{2})(?:-(\d{2}))?(?:[T ](\d{2}):(\d{2}))?/.exec(String(v ?? ''));
  if(!m) return null;
  const [, a, me, d, h, mi] = m;
  if(tipo === 'month') return [me, a];
  if(!d) return null;
  return tipo === 'date' ? [d, me, a] : [d, me, a, h || '00', mi || '00'];
}
// Texto digitado -> partes. Separador digitado fecha a parte (mesmo curta: "09/1/2026" é o mês sendo corrigido);
// número corrido enche cada parte e passa para a próxima. aoSair: completa o 0 do dia/mês/hora e o 20 do ano.
function analisarTextoData(tipo, texto, aoSair){
  const f = FORMATOS_DATA[tipo], s = String(texto ?? '');
  const doBanco = partesDoIsoData(tipo, s);
  if(doBanco) return {partes: doBanco, sepNoFim: false};
  const partes = [];
  for(let t of s.split(/\D+/)){
    if(!t) continue;
    while(t && partes.length < f.grupos.length){
      const tam = f.grupos[partes.length];
      partes.push(t.slice(0, tam)); t = t.slice(tam);
    }
    if(partes.length >= f.grupos.length) break;
  }
  const sepNoFim = partes.length > 0 && partes.length < f.grupos.length && /\D\s*$/.test(s);
  const ult = partes.length - 1;
  if(sepNoFim && f.grupos[ult] === 2) partes[ult] = partes[ult].padStart(2, '0');   // "9/" -> "09/"
  if(aoSair){
    partes.forEach((p, i)=>{
      if(f.grupos[i] === 2 && p.length === 1) partes[i] = '0' + p;
      if(i === f.ano && p.length === 2) partes[i] = '20' + p;
    });
  }
  return {partes, sepNoFim};
}
function textoDasPartesData(tipo, a){
  const f = FORMATOS_DATA[tipo];
  let out = a.partes.map((p, i)=>(i ? f.seps[i-1] : '') + p).join('');
  if(a.sepNoFim) out += f.seps[a.partes.length-1];
  return out;
}
function mascararData(tipo, texto){ return textoDasPartesData(tipo, analisarTextoData(tipo, texto, false)); }
// Texto -> formato do banco. '' se faltar algo, se o ano não tiver 4 números ou se a data não existir.
function isoDoTextoData(tipo, texto){
  const f = FORMATOS_DATA[tipo];
  const p = analisarTextoData(tipo, texto, false).partes;
  if(p.length !== f.grupos.length || p.some((x, i)=>x.length !== f.grupos[i])) return '';
  const ano = Number(p[f.ano]);
  if(ano < 1900 || ano > 2100) return '';
  if(tipo === 'month'){ const m = Number(p[0]); return m >= 1 && m <= 12 ? `${p[1]}-${p[0]}` : ''; }
  const d = Number(p[0]), m = Number(p[1]);
  if(m < 1 || m > 12 || d < 1 || d > new Date(Date.UTC(ano, m, 0)).getUTCDate()) return '';
  const dia = `${p[2]}-${p[1]}-${p[0]}`;
  if(tipo === 'date') return dia;
  return Number(p[3]) <= 23 && Number(p[4]) <= 59 ? `${dia}T${p[3]}:${p[4]}` : '';
}
function textoDoValorData(tipo, v){
  if(v === null || v === undefined || v === '') return '';
  const p = partesDoIsoData(tipo, v);
  return p ? textoDasPartesData(tipo, {partes: p, sepNoFim: false}) : mascararData(tipo, v);
}
const TIPO_DATA_TEM_CALENDARIO = {};
function navegadorTemCalendario(tipo){
  if(!(tipo in TIPO_DATA_TEM_CALENDARIO)){
    const i = document.createElement('input'); i.setAttribute('type', tipo);
    TIPO_DATA_TEM_CALENDARIO[tipo] = i.type === tipo;   // Firefox no computador não tem o de mês: fica só digitando
  }
  return TIPO_DATA_TEM_CALENDARIO[tipo];
}
function sincronizarCalendarioDoCampo(el){
  const sel = el.__calendario;
  if(sel) VALOR_NATIVO_CAMPO.set.call(sel, el.value || '');
}
function abrirCalendarioDoCampo(el){
  const sel = el.__calendario;
  if(!sel || sel.disabled) return;
  sincronizarCalendarioDoCampo(el);
  try{ sel.showPicker ? sel.showPicker() : sel.focus(); }catch(_){ try{ sel.focus(); }catch(__){} }
}
// Ao sair: completa o 0 e o ano, e marca de vermelho o que não é uma data.
function completarCampoData(el){
  const tipo = el.__tipoData, texto = VALOR_NATIVO_CAMPO.get.call(el);
  if(texto.trim()){
    const novo = textoDasPartesData(tipo, analisarTextoData(tipo, texto, true));
    if(novo !== texto) VALOR_NATIVO_CAMPO.set.call(el, novo);
  }
  el.classList.toggle('campo-data-invalido', !!VALOR_NATIVO_CAMPO.get.call(el).trim() && !el.value);
  sincronizarCalendarioDoCampo(el);
}
const ICONE_CAMPO_DATA = '<svg class="campo-data-icone" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4.5" width="18" height="16.5" rx="2"/><path d="M16 2.5v4M8 2.5v4M3 10h18"/></svg>';
function converterCampoData(el){
  const tipo = el.getAttribute('type');
  if(!FORMATOS_DATA[tipo] || el.__tipoData || !el.parentNode) return;
  const f = FORMATOS_DATA[tipo];
  const doBanco = VALOR_NATIVO_CAMPO.get.call(el);    // o navegador já validou: '' ou o formato do banco
  const tinhaFoco = document.activeElement === el;
  el.__tipoData = tipo;
  el.type = 'text';
  el.setAttribute('data-tipo-data', tipo);
  el.setAttribute('inputmode', 'numeric');
  el.setAttribute('autocomplete', 'off');
  if(!el.getAttribute('placeholder')) el.setAttribute('placeholder', f.modelo);
  el.classList.add('campo-data');
  Object.defineProperty(el, 'value', {
    configurable: true,
    get(){ return isoDoTextoData(tipo, VALOR_NATIVO_CAMPO.get.call(el)); },
    set(v){
      VALOR_NATIVO_CAMPO.set.call(el, textoDoValorData(tipo, v));
      el.__ultimaData = el.value;
      el.classList.remove('campo-data-invalido');
      sincronizarCalendarioDoCampo(el);
    },
  });
  VALOR_NATIVO_CAMPO.set.call(el, textoDoValorData(tipo, doBanco));
  el.__ultimaData = el.value;
  // caixa com o ícone e o calendário de verdade por cima dele
  const caixa = document.createElement('span');
  caixa.className = 'campo-data-caixa';
  if(el.hidden) caixa.hidden = true;
  el.parentNode.insertBefore(caixa, el);
  caixa.appendChild(el);
  caixa.insertAdjacentHTML('beforeend', ICONE_CAMPO_DATA);
  if(navegadorTemCalendario(tipo)){
    const sel = document.createElement('input');
    sel.type = tipo;
    sel.className = 'campo-data-seletor';
    sel.tabIndex = -1;
    sel.setAttribute('aria-hidden', 'true');
    sel.title = 'Abrir o calendário';
    ['min', 'max', 'step'].forEach(a=>{ if(el.hasAttribute(a)) sel.setAttribute(a, el.getAttribute(a)); });
    sel.disabled = el.disabled || el.readOnly;
    caixa.appendChild(sel);
    el.__calendario = sel;
    sincronizarCalendarioDoCampo(el);
    sel.addEventListener('pointerdown', ()=>sincronizarCalendarioDoCampo(el));
    sel.addEventListener('click', ()=>{ try{ if(sel.showPicker) sel.showPicker(); }catch(_){ /* já aberto ou sem suporte: o toque abre */ } });
    const escolheu = (e)=>{
      e.stopPropagation();   // o app só vê o campo de texto
      const v = VALOR_NATIVO_CAMPO.get.call(sel);
      if(!v || v === el.value || !el.isConnected) return;
      el.value = v;
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
    };
    sel.addEventListener('input', escolheu);
    sel.addEventListener('change', escolheu);
  } else {
    caixa.classList.add('sem-calendario');
  }
  if(tinhaFoco) el.focus();
  el.addEventListener('input', ()=>{
    const texto = VALOR_NATIVO_CAMPO.get.call(el);
    const cursor = el.selectionStart ?? texto.length;
    const novo = mascararData(tipo, texto);
    if(novo !== texto){
      let pos = novo.length;
      if(cursor < texto.length){
        const digitos = (texto.slice(0, cursor).match(/\d/g) || []).length;
        pos = 0; let vistos = 0;
        while(pos < novo.length && vistos < digitos){ if(/\d/.test(novo[pos])) vistos++; pos++; }
      }
      VALOR_NATIVO_CAMPO.set.call(el, novo);
      try{ el.setSelectionRange(pos, pos); }catch(_){}
    }
    el.classList.remove('campo-data-invalido');
    sincronizarCalendarioDoCampo(el);
    const v = el.value;
    if(v && v !== el.__ultimaData){ el.__ultimaData = v; el.dispatchEvent(new Event('change', {bubbles: true})); }
  });
  el.addEventListener('keydown', (e)=>{
    if((e.key === 'ArrowDown' && e.altKey) || e.key === 'F4'){ e.preventDefault(); abrirCalendarioDoCampo(el); return; }
    const ini = el.selectionStart, fim = el.selectionEnd, t = VALOR_NATIVO_CAMPO.get.call(el);
    if(ini === null || ini !== fim) return;
    // apagar em cima da barra apaga o número do lado (a barra voltaria sozinha)
    if(e.key === 'Backspace' && ini > 0 && ini < t.length && /\D/.test(t[ini-1])) el.setSelectionRange(ini-1, ini-1);
    if(e.key === 'Delete' && ini < t.length && /\D/.test(t[ini])) el.setSelectionRange(ini+1, ini+1);
  });
  el.addEventListener('blur', ()=>completarCampoData(el));
}
// "change" que o navegador manda ao sair do campo: completa a data antes do app ler e não repete o que já saiu
// quando a data ficou completa (o app redesenharia a tela de novo à toa). Captura no documento: roda antes do app.
document.addEventListener('change', (e)=>{
  const el = e.target;
  if(!e.isTrusted || !el || !el.__tipoData) return;
  completarCampoData(el);
  const v = el.value;
  if(v === el.__ultimaData) e.stopImmediatePropagation();
  else el.__ultimaData = v;
}, true);
function prepararCamposData(raiz){
  const r = raiz || document;
  if(r.matches && r.matches(SELETOR_CAMPO_DATA)) converterCampoData(r);
  if(r.querySelectorAll) r.querySelectorAll(SELETOR_CAMPO_DATA).forEach(converterCampoData);
}
(function(){
  const css = document.createElement('style');
  css.id = 'estilo-campo-data';
  css.textContent = `
  .campo-data-caixa{position:relative; display:block; min-width:0; max-width:100%;}
  .campo-data-caixa > input.campo-data{padding-right:40px; font-variant-numeric:tabular-nums;}
  .campo-data-caixa.sem-calendario > input.campo-data{padding-right:12px;}
  .campo-data-icone{position:absolute; right:12px; top:50%; width:18px; height:18px; margin-top:-9px; color:var(--cinza, #6E756C); pointer-events:none;}
  .campo-data-caixa.sem-calendario .campo-data-icone{display:none;}
  .campo-data-caixa > input:disabled ~ .campo-data-icone{opacity:.45;}
  .campo-data-caixa > input.campo-data-seletor{position:absolute !important; top:0 !important; right:0 !important; bottom:0 !important; left:auto !important;
    width:44px !important; min-width:0 !important; max-width:none !important; height:100% !important; min-height:0 !important;
    margin:0 !important; padding:0 !important; border:0 !important; opacity:0 !important; background:transparent !important;
    box-shadow:none !important; font-size:16px !important; cursor:pointer; z-index:1;}
  .campo-data-caixa > input.campo-data-seletor:disabled{cursor:default;}
  input.campo-data.campo-data-invalido{border-color:var(--alerta, #B03A24);}`;
  (document.head || document.documentElement).appendChild(css);
  new MutationObserver(lista=>{
    for(const m of lista) for(const n of m.addedNodes) if(n.nodeType === 1) prepararCamposData(n);
  }).observe(document.documentElement, {childList: true, subtree: true});
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ()=>prepararCamposData(document));
  else prepararCamposData(document);
})();


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
/* ---------- Dinheiro (R$) só para quem tem acesso total (12/11/2026) ----------
 * Decisão do Eduardo: o financeiro é só dele e dos proprietários. Nos apps da operação (Pecuária, Cana, Cereais, Combustível) e no
 * Painel do Matriz, valor, custo, preço médio e resultado aparecem só para administrador e proprietário; quem trabalha na operação vê
 * kg, litros, cabeças e ganho de peso. Três exceções, decididas por ele:
 *  - quem registra uma compra (insumo, nota de diesel) ou o custo de um protocolo digita o preço no formulário de entrada, mas não vê
 *    totais, custo médio nem valor em estoque nas listas;
 *  - quem vende animais (permissão Vendas) vê o valor na tela de Vendas (veValorDeVenda);
 *  - o consultor que formula as dietas vê o custo da dieta e o preço dos ingredientes (podeVerPrecoInsumo, no AE Pecuária).
 * O banco tranca de verdade o que é financeiro (lançamentos, visão rateada, contas, financiamentos: seguranca_06); preço de ingrediente,
 * de dieta e de nota fica nas tabelas da operação e é escondido só na tela. */
function veValores(){ return acessoTotal(); }
function veValorDeVenda(){ return acessoTotal() || temPermissao('vendas','visualizar'); }
// Preços trancados no banco (seguranca_07a/07b, 12/11/2026): quem está logado não lê mais estas
// colunas direto da tabela. A leitura vai pela visão <tabela>_leitura, que só preenche o preço para
// quem pode (insumo: acesso total e consultor; venda: acesso total e Vendas; o resto: acesso total).
// Gravar continua na tabela de sempre. Tabela nova com preço: entra aqui e no SQL.
const TABELAS_COM_PRECO = {
  ingredientes:['preco_kg'], movimentos:['preco_kg'], abates:['valor_arroba','valor_por_animal','valor_kg'],
  reproducao_custos:['custo'], entradas_estoque:['valor_total'], manutencoes:['custo'],
  entradas_insumo_cana:['preco_pago'], entradas_insumo_graos:['preco_pago'],
};
function tabelaDeLeitura(t){ return TABELAS_COM_PRECO[t] ? t + '_leitura' : t; }
// Ao EDITAR, quem não vê o preço recebe o campo vazio; gravar o vazio apagaria o preço de
// verdade. Tira do update a coluna de preço que veio vazia de quem não pode vê-la.
function semPrecoApagado(row, colunas, podeVer){
  if(podeVer) return row;
  const r = {...row};
  colunas.forEach(c=>{ if(r[c]===null || r[c]===undefined || r[c]==='' || (typeof r[c]==='number' && isNaN(r[c]))) delete r[c]; });
  return r;
}

/* ---------- Senha: no minimo 10 caracteres e troca obrigatoria (12/11/2026) ----------
 * Decisao do Eduardo: todos trocam para uma senha de 10 ou mais caracteres na proxima entrada com internet, e quem for
 * criado depois tambem troca a senha provisoria no primeiro acesso. profiles.precisa_trocar_senha (seguranca_05) diz quem
 * ainda precisa; o banco desmarca sozinho quando a senha muda de verdade (gatilho em auth.users), entao nao da para
 * pular a troca chamando a API. Antes do SQL a coluna nao existe e nada muda. */
const MIN_SENHA = 10;
function textoErroSenhaNova(error){
  const c = (error && error.code) || '', m = String((error && error.message) || '');
  if(c === 'same_password' || /different from the old/i.test(m)) return 'A senha nova tem que ser diferente da atual.';
  if(c === 'weak_password' || /at least|weak|characters/i.test(m)) return `Senha fraca: use pelo menos ${MIN_SENHA} caracteres, misturando letras e números.`;
  if(c === 'reauthentication_needed' || /reauthenticat/i.test(m)) return 'O servidor pediu para entrar de novo antes de trocar a senha: saia, entre e troque de novo.';
  if(pareceErroDeRede(error)) return 'Sem conexão com o servidor: a senha não foi trocada. Tente de novo com sinal.';
  return 'Não foi possível trocar a senha: ' + m;
}
// Confere a senha atual SEM mexer na sessao do app (um cliente a parte, que nao guarda nada no aparelho). Antes a tela
// entrava de novo com a senha no proprio cliente: para quem tem o codigo do celular, isso trocava a sessao confirmada
// (aal2) por uma so de senha (aal1), e o banco parava de responder no meio da troca.
// true = confere; false = senha errada; null = sem conexao.
async function senhaAtualConfere(senha){
  if(aparelhoSemRede()) return null;
  try{
    const avulso = supabase.createClient(db.supabaseUrl, db.supabaseKey,
      {auth: {persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'ae-confere-senha'}});
    const { data, error } = await avulso.auth.signInWithPassword({ email: `${state.perfil.usuario}@${DOMINIO_LOGIN}`, password: senha });
    if(error) return pareceErroDeRede(error) ? null : false;
    if(data && data.session){ try{ await avulso.auth.signOut({scope: 'local'}); }catch(e){ /* a sessao avulsa vence sozinha */ } }
    return true;
  }catch(e){ return pareceErroDeRede(e) ? null : false; }
}
// Tela cheia: "crie uma senha nova". Resolve true quando a senha foi trocada no servidor; false se a pessoa sair.
// Uma tela so: se o perfil for carregado de novo enquanto ela esta aberta, a mesma promessa e devolvida.
let senhaNovaEmAndamento = null;
function exigirSenhaNova(){
  if(senhaNovaEmAndamento) return senhaNovaEmAndamento;
  senhaNovaEmAndamento = new Promise(resolve=>{
    const fundo = document.createElement('div');
    fundo.id = 'senha-nova';
    fundo.style.cssText = 'position:fixed; inset:0; z-index:10000; overflow:auto; background:' + (getComputedStyle(document.body).backgroundColor || '#fff');
    fundo.innerHTML = `
      <div class="login-wrap">
        <div class="login-card">
          <div class="login-brand">
            ${brandMark()}
            <div class="brand-name">${esc(NOME_DO_APP)}</div>
          </div>
          <p style="color:var(--cinza); font-size:13.5px; line-height:1.6; margin-bottom:16px;">Por segurança, crie uma senha nova antes de continuar. Ela precisa ter pelo menos ${MIN_SENHA} caracteres. Uma frase curta fácil de lembrar, com números, funciona bem. Vale para todos os apps.</p>
          <div class="login-error" id="senha-nova-erro" style="display:none;"></div>
          <form id="senha-nova-form">
            <div class="login-field">
              <label for="senha-nova-1">Senha nova</label>
              <input id="senha-nova-1" type="password" autocomplete="new-password" />
            </div>
            <div class="login-field">
              <label for="senha-nova-2">Repita a senha nova</label>
              <input id="senha-nova-2" type="password" autocomplete="new-password" />
            </div>
            <button type="submit" class="btn btn-primary login-btn" id="senha-nova-ok">Salvar e entrar</button>
          </form>
          <button type="button" class="btn btn-ghost login-btn" id="senha-nova-sair" style="margin-top:10px;">Sair</button>
        </div>
      </div>`;
    document.body.appendChild(fundo);
    const c1 = fundo.querySelector('#senha-nova-1'), c2 = fundo.querySelector('#senha-nova-2');
    const botao = fundo.querySelector('#senha-nova-ok'), caixaErro = fundo.querySelector('#senha-nova-erro');
    const mostraErro = t=>{ caixaErro.textContent = t; caixaErro.style.display = 'block'; };
    let ocupado = false;
    fundo.querySelector('#senha-nova-form').onsubmit = async e=>{
      e.preventDefault();
      if(ocupado) return;
      const nova = c1.value;
      if(nova.length < MIN_SENHA){ mostraErro(`A senha precisa ter pelo menos ${MIN_SENHA} caracteres (tem ${nova.length}).`); return; }
      if(nova !== c2.value){ mostraErro('As duas senhas não são iguais.'); return; }
      if(aparelhoSemRede()){ mostraErro('Sem internet: a senha só pode ser trocada com sinal.'); return; }
      ocupado = true; botao.disabled = true; botao.textContent = 'Salvando...';
      const { error } = await db.auth.updateUser({ password: nova });
      ocupado = false; botao.disabled = false; botao.textContent = 'Salvar e entrar';
      if(error){ mostraErro(textoErroSenhaNova(error)); return; }
      fundo.remove();
      resolve(true);
    };
    fundo.querySelector('#senha-nova-sair').onclick = ()=>{ fundo.remove(); resolve(false); };
  }).finally(()=>{ senhaNovaEmAndamento = null; });
  return senhaNovaEmAndamento;
}

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
        <p class="hint">A nova senha precisa ter pelo menos ${MIN_SENHA} caracteres.</p>
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
/* ---- Despesa recorrente: a regra numa versão só (Matriz e Pecuária) ----
 * Uma despesa recorrente (sem mês) vale em todo mês que NÃO tenha um lançamento próprio da
 * mesma conta: se tem o do mês, ele SUBSTITUI o recorrente em vez de somar com ele.
 *
 * "A mesma conta" é a chave abaixo: descrição + centro de custo + atividade + fazenda + áreas.
 *   centro    sem ele, duas contas de nome igual em centros diferentes se apagavam.
 *   atividade não mistura Insumos Pecuários indireto com o da Cria.
 *   fazenda   sem ela, a energia lançada da Palhadão em agosto APAGAVA a recorrente da Santa
 *             Alice naquele mês (o custo sumia sem aviso e voltava no mês seguinte).
 *   áreas     separa os Insumos Pecuários do confinamento dos da cria.
 * Até 13/11/2026 o Matriz e a Pecuária tinham cada um a sua cópia (a Pecuária comparava o NOME
 * do centro); foi uma segunda cópia divergindo que fez um mês de R$ 43.928,73 virar
 * R$ 1.230.390,69. Não reescreva esta regra num app: chame vigentesNoMes.
 *
 * `campos(l)` traduz a linha do app para {descricao, centroCustoId, atividade, fazendaId, areas,
 * mes}; sem ele a linha já tem esses nomes (lançamento do Matriz).
 *
 * Desempenho (06/11/2026): Relatórios e Empresa chamam até 47 vezes com a MESMA lista de 21 mil
 * despesas; o agrupamento é feito uma vez por lista (guardado pela identidade da lista e da
 * função de campos) e cada mês só escolhe dentro dos grupos. Ordem: grupos na ordem em que
 * aparecem e, dentro de cada um, os do mês ou, se não houver, os recorrentes. */
function camposDoLancamento(l){ return l; }
function chaveDoRecorrente(f){
  const areas = (f.areas||[]).slice().sort().join(',');
  return `${f.descricao}||${f.centroCustoId}||${f.atividade}||${f.fazendaId ?? ''}||${areas}`;
}
const gruposDeVigentesCache = new WeakMap();
function gruposDeVigentes(despesas, campos = camposDoLancamento){
  let porFuncao = gruposDeVigentesCache.get(despesas);
  if(!porFuncao){ porFuncao = new Map(); gruposDeVigentesCache.set(despesas, porFuncao); }
  const guardado = porFuncao.get(campos);
  if(guardado && guardado.n === despesas.length) return guardado.grupos;
  const mapa = new Map();
  despesas.forEach(l=>{
    const f = campos(l);
    const chave = chaveDoRecorrente(f);
    let g = mapa.get(chave);
    if(!g){ g = {porMes: new Map(), recorrentes: []}; mapa.set(chave, g); }
    if(f.mes){
      const doMes = g.porMes.get(f.mes);
      if(doMes) doMes.push(l); else g.porMes.set(f.mes, [l]);
    } else {
      g.recorrentes.push(l);
    }
  });
  const grupos = [...mapa.values()];
  porFuncao.set(campos, {n: despesas.length, grupos});
  return grupos;
}
function vigentesNoMes(despesas, mesStr, campos = camposDoLancamento){
  const out = [];
  for(const g of gruposDeVigentes(despesas, campos)){
    const escolhidas = g.porMes.get(mesStr) || g.recorrentes;
    for(let i = 0; i < escolhidas.length; i++) out.push(escolhidas[i]);
  }
  return out;
}

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
        <div class="field"><label>Senha</label><input id="f-senhausuario" type="password" value="${esc(d.senha)}" autocomplete="new-password"/><span class="hint">Mínimo ${MIN_SENHA} caracteres. É provisória: a pessoa cria a dela no primeiro acesso.</span></div>
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-close="1">Cancelar</button>
        <button class="btn btn-primary" data-criar-usuario="1" ${state.usuarioLoading?'disabled':''}>${state.usuarioLoading?'Criando...':'Criar usuário'}</button>
      </div>
    </div>
  </div>`;
}
// Senha provisoria para quem esqueceu (12/11/2026). Os logins usam e-mail inventado (usuario@aeagropecuaria.local), entao
// nao existe "esqueci a senha" por e-mail: o administrador poe uma senha provisoria (10+) pela funcao criar-usuario-cana
// (acao redefinir_senha, so admin) e a pessoa e marcada para criar a dela no proximo acesso (precisa_trocar_senha).
async function mensagemDaFuncao(data, error, padrao){
  let msg = (data && data.error) || (error && error.message) || padrao;
  if(error && error.context && typeof error.context.json === 'function'){
    try{ const corpo = await error.context.json(); if(corpo && corpo.error) msg = corpo.error; }catch(e){ /* corpo nao e JSON */ }
  }
  return msg;
}
function abrirRedefinirSenha(id){
  const p = (state.perfis || []).find(x=>String(x.id) === String(id));
  if(!p || document.getElementById('redefinir-senha')) return;
  const caixa = document.createElement('div');
  caixa.id = 'redefinir-senha'; caixa.className = 'overlay'; caixa.style.zIndex = '9000';
  caixa.innerHTML = `
    <div class="modal">
      <div class="modal-head"><h3>Senha provisória para ${esc(p.nome)}</h3><button class="modal-close" data-rs-fechar="1">&times;</button></div>
      <div class="modal-body">
        <div class="login-error" id="rs-erro" style="display:none;"></div>
        <p class="hint">Use quando a pessoa esqueceu a senha. Ela entra com esta senha e o app pede para criar a dela na hora.</p>
        <div class="field"><label for="rs-senha-1">Senha provisória</label><input id="rs-senha-1" type="password" autocomplete="new-password"/><span class="hint">Mínimo ${MIN_SENHA} caracteres.</span></div>
        <div class="field"><label for="rs-senha-2">Repita a senha provisória</label><input id="rs-senha-2" type="password" autocomplete="new-password"/></div>
      </div>
      <div class="modal-foot">
        <button class="btn btn-ghost" data-rs-fechar="1">Cancelar</button>
        <button class="btn btn-primary" id="rs-ok">Salvar senha provisória</button>
      </div>
    </div>`;
  document.body.appendChild(caixa);
  const erro = t=>{ const c = caixa.querySelector('#rs-erro'); c.textContent = t; c.style.display = 'block'; };
  caixa.addEventListener('click', e=>{ if(e.target === caixa || (e.target.closest && e.target.closest('[data-rs-fechar]'))) caixa.remove(); });
  const ok = caixa.querySelector('#rs-ok');
  ok.onclick = async ()=>{
    const s1 = caixa.querySelector('#rs-senha-1').value, s2 = caixa.querySelector('#rs-senha-2').value;
    if(s1.length < MIN_SENHA){ erro(`A senha precisa ter pelo menos ${MIN_SENHA} caracteres.`); return; }
    if(s1 !== s2){ erro('As duas senhas não são iguais.'); return; }
    ok.disabled = true; ok.textContent = 'Salvando...';
    const { data, error } = await db.functions.invoke('criar-usuario-cana', { body: { acao: 'redefinir_senha', usuario_id: p.id, senha: s1 } });
    ok.disabled = false; ok.textContent = 'Salvar senha provisória';
    if(error || (data && data.error)){ erro(await mensagemDaFuncao(data, error, 'Não foi possível salvar a senha.')); return; }
    caixa.remove();
    alert(`Senha provisória salva. Passe para ${p.nome}: no primeiro acesso o app pede para criar a senha dela.`);
  };
}
document.addEventListener('click', e=>{
  const b = e.target && e.target.closest && e.target.closest('[data-redefinir-senha]');
  if(b) abrirRedefinirSenha(b.getAttribute('data-redefinir-senha'));
});
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
            <td><div style="display:flex; flex-wrap:wrap; gap:6px; justify-content:flex-end;">
              <button class="btn-ghost btn-sm" data-editar-usuario="${p.id}">Editar acesso</button>
              <button class="btn-ghost btn-sm" data-redefinir-senha="${p.id}">Nova senha</button>
            </div></td>
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
/* ---------- Menu lateral: a setinha que abre as sub-abas de cada item (08/11/2026) ----------
 * Pedido do Eduardo: uma setinha nos itens do menu que têm sub-abas; ela abre a lista ali mesmo e dá para ir direto numa sub-aba,
 * sem passar antes pela tela do item. Um item aberto por vez (sanfona), para o menu não crescer demais. O que ficou aberto vale
 * enquanto o app está aberto (não fica guardado: ao abrir de novo, só o item da tela atual vem aberto; no Painel, nenhum). Item com uma página só não tem setinha (o botão sozinho,
 * como sempre foi). O desenho é só CSS de cada app: a setinha e a lista só aparecem onde o menu é uma coluna (tela larga) ou o painel
 * do celular do Matriz; na barra de cima (tablet em pé) e na barra rolável dos outros apps ficam escondidas.
 * it = {chave, rotulo, icone, ativo, botao: 'data-nav-group="x"', subs: [{rotulo, valor, ativo}]}; o app que precisa de mais que
 * "state.page = valor" na sub-aba define irParaSubAbaDoApp(valor) (o Matriz: sub-aba de Resultados, Financeiro e Contas). */
let menuAbertoMemoria = null;   // so na memoria (13/11/2026): ao abrir o app nenhuma lista vem aberta, so a do item da tela atual
try{ Object.keys(localStorage).filter(k=>k.indexOf('ae_menu_aberto_v1_') === 0).forEach(k=>localStorage.removeItem(k)); }catch(e){ /* sem armazenamento */ }
function menuAbertoAgora(){
  return menuAbertoMemoria;   // null = ainda nao mexeu: abre o item da tela atual (no Painel, nenhum)
}
function guardarMenuAberto(chave){
  menuAbertoMemoria = String(chave);
}
function iconSetaMenu(){ return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>`; }
function ItemDoMenu(it){
  const subs = it.subs || [];
  const temSubs = subs.length >= 2;
  const guardado = menuAbertoAgora();
  const aberto = temSubs && (guardado === null ? !!it.ativo : guardado === String(it.chave));
  const botao = `<button class="nav-item ${it.ativo ? 'active' : ''}" ${it.botao} data-menu-chave="${esc(it.chave)}">${it.icone} ${it.rotulo}</button>`;
  if(!temSubs) return botao;
  const nome = String(it.rotulo).replace(/<[^>]*>/g, '');
  return `<div class="nav-grupo ${aberto ? 'aberto' : ''} ${it.ativo ? 'ativo' : ''}">
    <div class="nav-linha">${botao}<button class="nav-seta" data-nav-seta="${esc(it.chave)}" aria-expanded="${aberto ? 'true' : 'false'}" aria-label="${aberto ? 'Fechar' : 'Abrir'} as sub-abas de ${esc(nome)}" title="Sub-abas">${iconSetaMenu()}</button></div>
    <div class="nav-sub">${subs.map(s=>`<button class="nav-sub-item ${s.ativo ? 'active' : ''}" data-menu-sub="${esc(s.valor)}">${s.rotulo}</button>`).join('')}</div>
  </div>`;
}
// O menu lateral não volta para o topo ao trocar de tela (13/11/2026). Pedido do Eduardo: na Pecuária, com o menu rolado, tocar num
// item fazia a coluna do menu voltar para o topo. Cada app redesenha a tela inteira (innerHTML) e o menu novo nasce com a rolagem 0.
// Aqui se guarda a rolagem do menu enquanto a pessoa rola e se devolve UMA vez a cada menu novo que aparece na tela (o mesmo elemento
// não é mexido de novo, para não brigar com quem está rolando). Vale para a coluna dos 5 apps: .tabsrow (Matriz, Pecuária, Cana,
// Cereais) e o nav da barra azul do Combustível.
const SELETOR_MENU_ROLAVEL = '.tabsrow, .sidebar nav';
let rolagemDoMenu = 0;
const menusJaAjustados = new WeakSet();
document.addEventListener('scroll', e=>{
  const el = e.target;
  if(el && el.nodeType === 1 && el.matches(SELETOR_MENU_ROLAVEL) && menusJaAjustados.has(el)) rolagemDoMenu = el.scrollTop;
}, true);
function devolverRolagemDoMenu(){
  document.querySelectorAll(SELETOR_MENU_ROLAVEL).forEach(el=>{
    if(menusJaAjustados.has(el)) return;
    menusJaAjustados.add(el);
    if(rolagemDoMenu > 0 && el.scrollHeight > el.clientHeight) el.scrollTop = rolagemDoMenu;
    if(el.getClientRects().length) rolagemDoMenu = el.scrollTop;   // menu mais curto agora: vale onde ele parou de verdade
  });
}
new MutationObserver(devolverRolagemDoMenu).observe(document.documentElement, {childList:true, subtree:true});
// Clicar no nome de um item guarda qual item fica aberto (fase de captura: roda antes do clique do app, que já redesenha com isso).
document.addEventListener('click', e=>{
  const alvo = e.target && e.target.closest ? e.target.closest('[data-menu-chave]') : null;
  if(alvo) guardarMenuAberto(alvo.getAttribute('data-menu-chave'));
}, true);
document.addEventListener('click', e=>{
  if(!e.target || !e.target.closest) return;
  const seta = e.target.closest('[data-nav-seta]');
  if(seta){
    guardarMenuAberto(seta.getAttribute('aria-expanded') === 'true' ? '' : seta.getAttribute('data-nav-seta'));
    render();
    return;
  }
  const sub = e.target.closest('[data-menu-sub]');
  if(sub){
    const valor = sub.getAttribute('data-menu-sub');
    if(typeof irParaSubAbaDoApp === 'function') irParaSubAbaDoApp(valor); else state.page = valor;
    render();
  }
});
// Menu do celular (☰) dos apps Pecuária, Cana, Cereais e Combustível (pedido do Eduardo, 09/11/2026: "coloca os 3 risquinhos
// para clicar e abrir uma janela com as abas; quero todos com a mesma cara"). Até 760 px o menu fica escondido e o botão mostra
// onde a pessoa está; tocar abre o menu inteiro (com a setinha das sub-abas), e escolher uma tela fecha. O aberto/fechado é uma
// classe no <html> (sobrevive ao redesenho). O AE Matriz tem o dele (state.mobileNavAberto), com o mesmo desenho.
let menuCelularAberto = false;
function iconMenuCelular(){ return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="18" x2="20" y2="18"/></svg>`; }
function BotaoMenuCelular(){
  const grupos = (typeof gruposAtuais === 'function') ? gruposAtuais() : (typeof GROUPS !== 'undefined' ? GROUPS : {});
  const g = grupos[currentGroupKey()] || null;
  const pagina = g && g.pages ? g.pages.find(p=>p.key === state.page) : null;
  const rotulo = !g ? 'Menu' : (pagina && g.pages.length > 1 && pagina.label !== g.label) ? `${g.label} · ${pagina.label}` : g.label;
  return `<button class="menu-celular" data-menu-celular="1" aria-expanded="${menuCelularAberto ? 'true' : 'false'}" aria-label="Abrir o menu">
    <span class="menu-celular-rotulo">${iconMenuCelular()}<span>${esc(rotulo)}</span></span><span class="menu-celular-seta">${iconSetaMenu()}</span></button>`;
}
function definirMenuCelular(aberto){
  menuCelularAberto = !!aberto;
  document.documentElement.classList.toggle('menu-celular-aberto', menuCelularAberto);
  document.querySelectorAll('[data-menu-celular]').forEach(b=>b.setAttribute('aria-expanded', menuCelularAberto ? 'true' : 'false'));
}
// Fase de captura: roda antes do clique do app (que redesenha), então o botão já nasce com o estado certo.
document.addEventListener('click', e=>{
  if(!e.target || !e.target.closest) return;
  if(e.target.closest('[data-menu-celular]')){ definirMenuCelular(!menuCelularAberto); return; }
  if(menuCelularAberto && e.target.closest('.nav-item, [data-menu-sub]')) definirMenuCelular(false);
}, true);
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
function rowToPerfil(r){ return {id:r.id, nome:r.nome, usuario:r.usuario, papel:r.papel, permissoes:r.permissoes||{}, frentes:r.frentes||[], ativo:r.ativo, precisaTrocarSenha: r.precisa_trocar_senha === true}; }
async function loadPerfil(){
  const uid = state.session?.user?.id;
  if(!uid){ state.perfil = null; state.perfilErroRede = false; return; }
  const { data, error } = await buscarPerfilDoBanco(uid);
  state.perfilErroRede = false;
  if(data){
    state.perfil = rowToPerfil(data);
    // Senha nova obrigatoria (12/11/2026): so com o perfil vindo do banco (com internet); o app nao abre antes da troca.
    if(state.perfil.precisaTrocarSenha && state.perfil.ativo){
      const trocou = await exigirSenhaNova();
      if(!trocou){ await fazerLogout(); return; }
      state.perfil.precisaTrocarSenha = false;
    }
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
    // troca de senha (updateUser) avisa USER_UPDATED: e a mesma sessao, nao recarrega nada
    if(event==='USER_UPDATED'){ if(newSession) state.session = newSession; return; }
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
      const grupos = String(m.novo.segredo).replace(/(.{4})/g, '$1 ').trim();
      corpo = `
        <p class="hint"><strong>1. Coloque esta conta no app autenticador do celular</strong> (Google Authenticator, Microsoft Authenticator ou Authy).</p>
        <p style="margin:10px 0;"><a class="btn btn-primary" id="mfa-abrir-app" href="${esc(m.novo.uri)}">Estou neste celular: abrir no app autenticador</a></p>
        <p class="hint">Se o botão não abrir o app, ou se o app está em outro aparelho: no app autenticador escolha adicionar conta, depois "inserir chave de configuração" (tipo: baseado em tempo) e digite esta chave:</p>
        <div id="mfa-chave" data-chave="${esc(m.novo.segredo)}" class="mono" style="font-size:19px; letter-spacing:1.5px; line-height:1.5; user-select:all; overflow-wrap:anywhere; background:var(--cinza-bg, #f4f5f7); border-radius:10px; padding:12px 14px; margin:8px 0;">${esc(grupos)}</div>
        <p style="margin:0 0 10px;"><button class="btn btn-ghost btn-sm" data-mfa-copiar="1">Copiar a chave</button></p>
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
    // SEM foco automatico no campo do codigo: no iPad e no celular o foco abre o teclado e rola a janela ate o campo, empurrando a chave
    // e o botao para fora da vista (foi o que o Eduardo viu em 08/11/2026). A pessoa toca no campo quando chegar a hora.
    if(m.novo && !m.novo.jaMostrado){ m.novo.jaMostrado = true; const corpoJanela = caixa.querySelector('.modal-body'); if(corpoJanela) corpoJanela.scrollTop = 0; }
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
      if(!totp.secret){
        await db.auth.mfa.unenroll({ factorId: data.id });
        m.erro = 'O servidor não mandou a chave de ativação. Tente de novo em alguns minutos.'; desenha(); return;
      }
      const uri = /^otpauth:\/\//i.test(totp.uri || '') ? totp.uri : 'otpauth://totp/AE%20Agropecuaria?secret=' + encodeURIComponent(totp.secret) + '&issuer=AE%20Agropecuaria';
      m.novo = { factorId: data.id, segredo: totp.secret, uri };
      desenha(); return;
    }
    if(alvo.dataset.mfaCopiar !== undefined){
      const chave = m.novo ? m.novo.segredo : '';
      const ok = ()=>avisar('Chave copiada. Cole no app autenticador.');
      const manual = ()=>avisar('Não consegui copiar sozinho. Toque e segure a chave para copiar.');
      try{ navigator.clipboard.writeText(chave).then(ok, manual); }catch(e){ manual(); }
      return;
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

/* Mes "2026-07" -> "Jul/2026" (13/11/2026: era copiado no Matriz e na Pecuaria). */
const NOMES_MES = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
function mesLabel(mesStr){
  if(!mesStr) return '—';
  const [ano, m] = mesStr.split('-');
  return `${NOMES_MES[Number(m)-1]}/${ano}`;
}

/* Erro do banco em portugues (13/11/2026: eram duas versoes, Combustivel e Cana/Cereais). O app pode definir
   mensagemErroDoApp(error) para os casos so dele (o Combustivel usa); se ela devolver texto, vale esse. */
function mensagemErroSupabase(error){
  if(typeof mensagemErroDoApp === 'function'){ const m = mensagemErroDoApp(error); if(m) return m; }
  if(error?.code==='23505') return 'Já existe um registro com esse nome (talvez nesta fazenda). Use outro nome ou edite o existente.';
  if(error?.code==='23503') return 'Não é possível excluir: existem outros cadastros vinculados a este registro.';
  if(error?.code==='23514') return 'Verifique os valores informados.';
  if(error?.code==='42501') return 'Sem permissão para esse registro.';
  return error?.message || 'Erro desconhecido.';
}

// Função do banco (rpc) que ainda não foi criada (SQL não rodou): o app cai no caminho antigo.
function funcaoDoBancoNaoExiste(e){
  return !!e && (e.code==='PGRST202' || e.code==='42883' || /could not find the function/i.test(e.message||''));
}
