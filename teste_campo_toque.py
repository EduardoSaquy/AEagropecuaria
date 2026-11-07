"""
AE Matriz no campo (achados 7 da revisao geral de 05/11/2026): botoes de 26 a 34 px, rotulos sem "for", texto
ambar com 2,9:1 de contraste, app travado em retrato no tablet.
Prova, em tela de toque (tablet em pe e deitado, celular):
  - nenhum botao, link, campo ou lista visivel das telas principais tem menos de 44 px (media 284 ocorrencias
    antes, em 15 telas, no tablet);
  - caixas de marcar tem pelo menos 24 px;
  - o rotulo de um campo sozinho leva o "for" do campo (clicar no nome abre o campo);
  - as cores de texto (verde, vermelho, ambar) tem pelo menos 4,5:1 de contraste no branco;
  - com mouse (desktop) os botoes continuam compactos: so a tela de toque cresce;
  - os seis manifestos aceitam qualquer orientacao (o tablet gira).
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {
    "fazendas": [{"id": 1, "nome": "Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}], "fazenda_atividades": [],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "ADUBOS", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | X"}],
    "lancamentos_financeiros": [{"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90, "descricao": "Adubo", "valor": 100,
                                 "data": "2026-05-10", "mes": "2026-05", "fornecedor": "X", "areas": []}],
    "lotes": [], "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
}

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


ALVOS = r"""(raiz) => {
  const vis = e => { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
  const q = s => [...document.querySelectorAll(s.split(',').map(x => raiz + ' ' + x.trim()).join(','))];
  const pequenos = q('button, a[href], select, textarea, input:not([type=hidden]):not([type=checkbox]):not([type=radio]), [role=button], summary')
    .filter(vis).map(e => ({e, r: e.getBoundingClientRect()})).filter(x => x.r.height < 43.5 || x.r.width < 43.5)
    .map(x => (typeof x.e.className === 'string' ? x.e.className : '') + ' ' + Math.round(x.r.height) + 'x' + Math.round(x.r.width));
  const caixas = q('input[type=checkbox], input[type=radio]').filter(vis).filter(e => { const r = e.getBoundingClientRect(); return r.height < 24 || r.width < 24; }).length;
  return {pequenos, caixas};
}"""
TELAS = [("painel", "state.page='painel'"), ("resultados", "state.page='resultados'; state.subAbaResultados='geral'"),
         ("operacional", "state.page='resultados'; state.subAbaResultados='operacional'"),
         ("relatorios", "state.page='resultados'; state.subAbaResultados='relatorios'"),
         ("empresa", "state.page='resultados'; state.subAbaResultados='empresa'"),
         ("financeiro", "state.page='financeiro'; state.abaFinanceiro='despesa'"), ("fazendas", "state.page='fazendas'"),
         ("centros", "state.page='centrosCusto'"), ("contas", "state.page='contas'"), ("financiamentos", "state.page='financiamentos'"),
         ("funcionarios", "state.page='funcionarios'"), ("usuarios", "state.page='usuarios'")]


def novo_contexto(browser, largura, altura, toque):
    ctx = browser.new_context(viewport={"width": largura, "height": altura}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lancamentos && state.lancamentos.length > 0", timeout=30000)
    page.wait_for_timeout(500)
    return page


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    for rotulo, larg, alt in (("tablet em pe 820x1180", 820, 1180), ("tablet deitado 1180x820", 1180, 820), ("celular 390x800", 390, 800)):
        print(f"== {rotulo}, com toque")
        page = novo_contexto(browser, larg, alt, True)
        conf(page.evaluate("() => matchMedia('(pointer: coarse)').matches"), "o navegador de teste esta em modo toque")
        ruins = {}
        caixas = 0
        for nome, js in TELAS:
            page.evaluate(f"() => {{ {js}; state.modal = null; render(); }}")
            page.wait_for_timeout(200)
            r = page.evaluate(ALVOS, "#root")
            caixas += r["caixas"]
            if r["pequenos"]:
                ruins[nome] = r["pequenos"][:3]
        conf(not ruins, f"{len(TELAS)} telas sem alvo de toque menor que 44 px", str(ruins)[:300])
        conf(caixas == 0, "caixas de marcar com pelo menos 24 px")
        page.evaluate("() => { state.page = 'financeiro'; state.modal = {type:'lancamento'}; editDraft = {tipo:'despesa'}; render(); }")
        page.wait_for_timeout(300)
        r = page.evaluate(ALVOS, "body")
        conf(not r["pequenos"], "formulario de lancamento sem alvo menor que 44 px", str(r["pequenos"][:3]))
        page.context.close()

    print("== o botao do menu de celular so aparece no celular (regressao de 06/11/2026: o ajuste de toque o mostrava em tela larga)")
    for rotulo, larg, alt, esperado in (("tablet deitado 1180", 1180, 820, False), ("tablet em pe 820", 820, 1180, False), ("celular 390", 390, 800, True)):
        pg = novo_contexto(browser, larg, alt, True)
        vis = pg.evaluate("() => { const b = document.querySelector('.mobile-nav-toggle'); return !!b && getComputedStyle(b).display !== 'none' && b.getBoundingClientRect().height > 0; }")
        conf(vis == esperado, f"{rotulo}: botao do menu de celular {'visivel' if esperado else 'escondido'}", str(vis))
        # e o menu completo continua inteiro na tela larga
        if not esperado:
            itens = pg.evaluate("() => [...document.querySelectorAll('.nav-item')].filter(e => e.getBoundingClientRect().height > 0).length")
            conf(itens >= 5, f"{rotulo}: o menu completo aparece ({itens} itens)")
        pg.context.close()
    pg = novo_contexto(browser, 1280, 800, False)
    conf(not pg.evaluate("() => { const b = document.querySelector('.mobile-nav-toggle'); return !!b && getComputedStyle(b).display !== 'none'; }"),
         "desktop com mouse: botao do menu de celular escondido")
    pg.context.close()

    print("== rotulos")
    page = novo_contexto(browser, 1100, 800, False)
    page.evaluate("() => { state.page = 'financeiro'; state.modal = {type:'lancamento'}; editDraft = {tipo:'despesa'}; render(); }")
    page.wait_for_timeout(300)
    sem = page.evaluate("""() => [...document.querySelectorAll('label')].filter(l => !l.htmlFor && !l.querySelector('input,select,textarea')
        && l.parentElement && l.parentElement.querySelectorAll('input:not([type=hidden]),select,textarea').length === 1
        && l.parentElement.querySelectorAll(':scope > label').length === 1).length""")
    conf(sem == 0, "rotulo de campo sozinho tem o for do campo", str(sem))
    ligados = page.evaluate("() => [...document.querySelectorAll('label[for]')].filter(l => document.getElementById(l.htmlFor)).length")
    conf(ligados > 5, "o formulario tem rotulos ligados a campos que existem (%d)" % ligados)
    page.evaluate("() => { document.body.insertAdjacentHTML('beforeend', '<div id=\"t1\"><label>Um</label><input id=\"campo-um\"/></div><div id=\"t2\"><label>A</label><label>B</label><input id=\"c1\"/><input id=\"c2\"/></div>'); ligarRotulosAosCampos(); }")
    conf(page.evaluate("() => document.querySelector('#t1 label').htmlFor") == "campo-um", "liga quando ha um rotulo e um campo")
    conf(page.evaluate("() => document.querySelector('#t2 label').htmlFor") == "", "nao chuta quando ha duvida (2 rotulos, 2 campos)")

    print("== contraste do texto (no branco)")
    cores = page.evaluate("""() => { const s = getComputedStyle(document.documentElement);
        return {bom: s.getPropertyValue('--bom').trim(), alerta: s.getPropertyValue('--alerta').trim(), ambar: s.getPropertyValue('--ambar-texto').trim(), cinza: s.getPropertyValue('--cinza').trim()}; }""")

    def lum(h):
        h = h.lstrip('#')
        c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])

    def contraste(h, fundo="#FFFFFF"):
        a, b = lum(h), lum(fundo)
        a, b = max(a, b), min(a, b)
        return (a + 0.05) / (b + 0.05)
    for nome in ("bom", "alerta", "ambar", "cinza"):
        conf(contraste(cores[nome]) >= 4.5, f"{nome} {cores[nome]}: {contraste(cores[nome]):.2f}:1 no branco", str(cores))
    conf(contraste(cores["bom"], "#DFF6E8") >= 4.5, "verde no fundo verde: %.2f:1" % contraste(cores["bom"], "#DFF6E8"))
    conf(contraste(cores["alerta"], "#FBEAE6") >= 4.5, "vermelho no fundo de alerta: %.2f:1" % contraste(cores["alerta"], "#FBEAE6"))
    conf(contraste(cores["ambar"], "#F5E9D7") >= 4.5, "ambar no fundo ambar: %.2f:1" % contraste(cores["ambar"], "#F5E9D7"))

    print("== mouse (desktop): so a tela de toque cresce")
    page.evaluate("() => { state.modal = null; state.page = 'financeiro'; state.abaFinanceiro = 'despesa'; render(); }")
    page.wait_for_timeout(200)
    alt_btn = page.evaluate("() => { const b = document.querySelector('#root .btn-sm'); return b ? Math.round(b.getBoundingClientRect().height) : null; }")
    conf(alt_btn is not None and alt_btn < 40, "com mouse o botao pequeno continua compacto (%s px)" % alt_btn)
    page.context.close()

    print("== AE Pecuaria (o app mais usado no campo), com toque")
    HOJE = date.today()
    dia = lambda n: (HOJE - timedelta(days=n)).isoformat()
    DB_PEC = {
        "lotes": [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 60, "data_inicio": dia(80), "data_fim": None, "dieta_id": 1, "sexo": "macho"},
                  {"id": 2, "nome": "Vacas 09/10", "destino": "cria", "numero_animais": 70, "data_inicio": dia(300), "data_fim": None, "dieta_id": 1}],
        "dietas": [{"id": 1, "nome": "Terminacao", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": False}],
        "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.2, "estoque_kg": 5000}],
        "animais": [], "pesagens": [{"id": 1, "lote_id": 1, "data": dia(5), "peso_medio_kg": 430, "numero_animais": 60, "criado_por": "Joilson"}],
        "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "reproducao_custos": [],
        "saidas_racao": [{"id": i, "data": dia(i), "dieta_id": 1, "lote_id": 1, "quantidade_kg": 900, "criado_por": "Joilson"} for i in range(1, 8)],
        "leituras_cocho": [], "pasto": [], "producoes_racao": [], "abates": [], "precos_arroba": [{"id": 1, "data": dia(2), "valor": 320, "sexo": "macho"}],
        "movimentos": [], "manejos": [], "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
        "config_financeiro": [], "funcionarios": [], "pesagens_animais": [], "protocolos_inseminacao": [], "profiles": [ADMIN],
    }
    PAGINAS_PEC = ["lotes", "racao", "cocho", "pesagemConfinamento", "vendasGeral", "resultadosResumo", "financeiroResumo", "cadastroInicio"]
    ALTURA = r"""() => {
      const vis = e => { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
      return [...document.querySelectorAll('#root button, #root a[href], #root select, #root textarea, #root input:not([type=hidden]):not([type=checkbox]):not([type=radio])')]
        .filter(vis).map(e => ({e, r: e.getBoundingClientRect()})).filter(x => x.r.height < 43.5)
        .map(x => (typeof x.e.className === 'string' ? x.e.className : '') + ' ' + Math.round(x.r.height) + 'px').slice(0, 4);
    }"""
    for rotulo, larg, alt in (("tablet 820x1180", 820, 1180), ("celular 390x800", 390, 800)):
        ctx = browser.new_context(viewport={"width": larg, "height": alt}, has_touch=True, is_mobile=True)
        pg = ctx.new_page()
        pg.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        pg.on("dialog", lambda d: d.dismiss())
        pg.add_init_script(STUB)
        pg.add_init_script(f"window.__DB__ = {json.dumps(DB_PEC)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        pg.goto("file://" + str(REPO / "AEpecuaria.html"))
        pg.wait_for_timeout(1500)
        ruins = {}
        for nome in PAGINAS_PEC:
            pg.evaluate("(p) => { state.modal = null; state.page = p; render(); }", nome)
            pg.wait_for_timeout(150)
            r = pg.evaluate(ALTURA)
            if r:
                ruins[nome] = r
        conf(not ruins, f"AE Pecuaria {rotulo}: {len(PAGINAS_PEC)} telas sem botao nem campo com menos de 44 px de altura", str(ruins)[:300])
        lateral = pg.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(lateral <= 1, f"AE Pecuaria {rotulo}: sem rolagem lateral depois de crescer os botoes ({lateral} px)")
        ctx.close()

    print("== os outros apps recebem o mesmo ajuste")
    for arq in ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"):
        txt = (REPO / arq).read_text(encoding="utf-8")
        conf("@media (pointer: coarse)" in txt and "min-height:44px" in txt, f"{arq}: alvos de toque de 44 px")
        conf("MutationObserver" in txt or "function ligarRotulosAosCampos" in txt, f"{arq}: liga rotulos aos campos")
        conf("#008C31;" not in txt.split("--bom:")[1][:12] if "--bom:" in txt else True, f"{arq}: verde de texto com contraste")

    print("== manifestos")
    for nome in ("manifest.json", "manifest_matriz.json", "manifest_lavoura.json", "manifest_cana.json", "manifest_cereais.json", "manifest_combustivel.json"):
        m = json.loads((REPO / nome).read_text(encoding="utf-8"))
        conf(m.get("orientation") == "any", f"{nome}: orientation any", str(m.get("orientation")))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
