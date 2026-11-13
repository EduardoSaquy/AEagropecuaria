"""
Foto mensal do rebanho e resultado economico da Pecuaria (13/11/2026).
Decisoes do Eduardo: o banco tira uma foto do rebanho todo dia 1o
(rebanho_inventario_01.sql); resultado economico = resultado de caixa +
(rebanho no fim do periodo - rebanho no comeco); lote sem pesagem usa o
peso de referencia do lote, informado no AE Pecuaria. Dados inventados.

Cobre: AE Matriz (bloco "Resultado economico" e o Rebanho estocado com o
peso de referencia) e AE Pecuaria (campo "Peso de referencia" do lote).
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
RUIDO = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))
def perto(a, b, tol=0.01): return a is not None and abs(a - b) < tol

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
LOTES = [
    {"id": 1, "nome": "Curral 2", "destino": "confinamento", "sexo": "macho", "numero_animais": 100, "data_fim": None,
     "data_inicio": "2026-07-01", "dieta_id": None, "peso_referencia_kg": None},
    {"id": 2, "nome": "Vacas 07/08", "destino": "cria", "sexo": "femea", "numero_animais": 200, "data_fim": None,
     "data_inicio": "2026-07-01", "dieta_id": None, "peso_referencia_kg": 420},
    {"id": 3, "nome": "Novilhas Eradas", "destino": "cria", "sexo": "femea", "numero_animais": 50, "data_fim": None,
     "data_inicio": "2026-07-01", "dieta_id": None, "peso_referencia_kg": None},
]
FOTOS = [
    {"id": 1, "data": "2026-12-01", "lote_id": 1, "lote_nome": "Curral 2", "cabecas": 100, "peso_medio": 450, "origem_peso": "pesagem", "valor": 480000},
    {"id": 2, "data": "2026-12-01", "lote_id": 2, "lote_nome": "Vacas 07/08", "cabecas": 200, "peso_medio": 420, "origem_peso": "referencia", "valor": 784000},
    {"id": 3, "data": "2027-01-01", "lote_id": 1, "lote_nome": "Curral 2", "cabecas": 100, "peso_medio": 500, "origem_peso": "pesagem", "valor": 533333.33},
    {"id": 4, "data": "2027-01-01", "lote_id": 2, "lote_nome": "Vacas 07/08", "cabecas": 200, "peso_medio": 420, "origem_peso": "referencia", "valor": 784000},
    {"id": 5, "data": "2027-01-01", "lote_id": 3, "lote_nome": "Novilhas Eradas", "cabecas": 50, "peso_medio": None, "origem_peso": None, "valor": None},
]
DB_MATRIZ = {
    "fazendas": [{"id": 1, "nome": "Faz. Teste", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "pecuaria", "area_ha": 300}],
    "centros_custo": [], "lancamentos_financeiros": [],
    "lotes": LOTES,
    "pesagens": [{"id": 1, "lote_id": 1, "data": "2026-11-10", "peso_medio_kg": 450}],
    "precos_arroba": [{"id": 1, "data": "2026-11-10", "valor": 320, "sexo": "macho"},
                      {"id": 2, "data": "2026-11-10", "valor": 280, "sexo": "femea"}],
    "rebanho_inventario": FOTOS,
    "ingredientes": [], "dietas": [], "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "abates": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
}

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    # ===================== AE MATRIZ =====================
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB_MATRIZ, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.fotosRebanho && state.estoquePec", timeout=15000)
    print("\n  AE MATRIZ: rebanho estocado com peso de referencia")
    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(erros[:3]))
    r = page.evaluate("() => estoquePecuaria()")
    vacas = next(x for x in r["linhas"] if x["lote"]["nome"] == "Vacas 07/08")
    conf(vacas["pesoMedio"] == 420 and vacas["porReferencia"] and perto(vacas["valor"], 200*420*0.5/15*280),
         "lote sem pesagem usa o peso de referencia (420 kg) e o preco da @ femea: 200 x 420 x 0,5/15 x 280 = R$ 784.000", json.dumps(vacas)[:200])
    curral = next(x for x in r["linhas"] if x["lote"]["nome"] == "Curral 2")
    conf(curral["pesoMedio"] == 450 and not curral["porReferencia"], "lote pesado continua pela pesagem")
    conf(r["lotesSemPeso"] == ["Novilhas Eradas"] and r["lotesPorReferencia"] == ["Vacas 07/08"],
         "sem pesagem e sem referencia fica de fora; a tela diz qual vai pela referencia", str((r["lotesSemPeso"], r["lotesPorReferencia"])))
    # lote sem a coluna (antes do SQL): nada quebra
    semcol = page.evaluate("() => { const ep = state.estoquePec; const lotes = ep.lotes; ep.lotes = lotes.map(({peso_referencia_kg, ...l}) => l);"
                           " const x = estoquePecuaria(); ep.lotes = lotes; return x.lotesSemPeso; }")
    conf(sorted(semcol) == ["Novilhas Eradas", "Vacas 07/08"], "sem a coluna nova (antes do SQL) funciona como antes", str(semcol))

    print("\n  AE MATRIZ: resultado economico")
    v = page.evaluate("() => variacaoRebanhoNoPeriodo({tipo:'mes', mes:'2026-12'})")
    conf(v["dataInicio"] == "2026-12-01" and v["dataFim"] == "2027-01-01", "dezembro: foto de 01/12 (comeco) e de 01/01 (fim)", str(v)[:120])
    conf(perto(v["variacao"], 533333.33 + 784000 - 480000 - 784000), "variacao = fim - comeco (R$ 53.333,33)", str(v["variacao"]))
    conf(v["fim"]["cabecasSemValor"] == 50 and v["fim"]["lotesSemValor"] == ["Novilhas Eradas"], "conta as cabecas sem valor da foto")
    v2 = page.evaluate("() => variacaoRebanhoNoPeriodo({tipo:'mes', mes:'2026-11'})")
    conf(v2["inicio"] is None and v2["variacao"] is None, "novembro: sem a foto de 01/11, nao ha variacao")
    va = page.evaluate("() => variacaoRebanhoNoPeriodo({tipo:'safra', safra:2026})")
    conf(va["dataInicio"] == "2026-05-01" and va["dataFim"] == "2027-05-01", "safra 2026/27: fotos de 01/05/2026 e 01/05/2027")
    vano = page.evaluate("() => variacaoRebanhoNoPeriodo({tipo:'ano', ano:2026})")
    conf(vano["dataFim"] == "2027-01-01", "ano 2026: fim em 01/01/2027")

    html = page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-12'}; return BlocoResultadoEconomicoPecuaria({resultado: 100000}); }")
    conf('data-resultado-economico-pecuaria' in html and 'R$ 153.333,33' in html,
         "resultado economico = caixa (R$ 100.000, sem investimentos) + variacao (R$ 53.333,33) = R$ 153.333,33", html[html.find('data-resultado-economico'):][:120])
    conf('Novilhas Eradas' in html and 'data-rebanho-sem-valor' in html, "avisa o lote que ficou fora do valor")
    falta = page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-11'}; return BlocoResultadoEconomicoPecuaria({resultado: 100000}); }")
    conf('data-falta-foto-rebanho' in falta and '01/11/2026' in falta and 'data-resultado-economico-pecuaria' not in falta,
         "sem as duas fotos: explica qual falta e nao mostra numero", falta[:200])
    erro = page.evaluate("() => { const f = state.fotosRebanho; state.fotosRebanho = {erro:'Não foi possível carregar as fotos do rebanho.', linhas:[]};"
                         " const h = BlocoResultadoEconomicoPecuaria({resultado: 1}); state.fotosRebanho = f; return h; }")
    conf('Não foi possível carregar' in erro, "falha ao ler as fotos aparece como aviso, sem derrubar a tela")
    # na tela de verdade
    page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-12'}; state.page='resultados'; state.subAbaResultados='operacional'; render(); }")
    page.wait_for_timeout(400)
    temBloco = page.locator('[data-bloco-resultado-economico]').count()
    conf(temBloco == 1, "Resultados > Operacional > Pecuaria mostra o bloco", str(temBloco))
    for w in (1280, 390):
        page.set_viewport_size({"width": w, "height": 900}); page.wait_for_timeout(200)
        larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(larg <= 0, f"sem rolar de lado em {w} px", f"passa {larg} px")
    conf(page.evaluate("() => TABELAS_COPIA.some(t => t[0]==='rebanho_inventario')"), "fotos entram na copia de seguranca")
    page.close()

    # ===================== AE PECUARIA =====================
    print("\n  AE PECUARIA: peso de referencia do lote")
    DB_PEC = {k: [] for k in ["fazendas", "animais", "abates", "dietas", "ingredientes", "movimentos", "producoes_racao",
              "saidas_racao", "leituras_cocho", "pasto", "manejos", "reproducao_custos", "diagnosticos_gestacionais",
              "partos", "desmamas", "custos_fixos", "precos_arroba", "titulos", "alertas", "pesagens", "pesagens_animais",
              "protocolos_inseminacao", "lancamentos_financeiros", "centros_custo"]}
    DB_PEC["lotes"] = [dict(l) for l in LOTES]
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, avisos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: avisos.append(m.text) if m.text.startswith("[aviso]") else None)
    page.on("dialog", lambda d: d.accept())
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB_PEC, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEpecuaria.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico", timeout=15000)
    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    def editar(lote_id):
        page.evaluate(f"""() => {{ const lote = state.lotes.find(l=>l.id==={lote_id});
            editDraft = {{...lote, dataFim: lote.dataFim||'', _editId: lote.id}}; state.modal = {{type:'lote'}}; render(); }}""")
        page.wait_for_timeout(150)
    def salvar():
        page.locator('[data-save="lote"]').click(); page.wait_for_timeout(500)
    def lote_db(i): return page.evaluate(f"() => window.__DB__.lotes.find(l=>l.id==={i})")

    editar(2)
    campo = page.locator("#f-pesoreferencia")
    conf(campo.count() == 1 and campo.input_value() == "420", "editar o lote mostra o peso de referencia gravado (420)")
    campo.fill("430"); salvar()
    conf(lote_db(2)["peso_referencia_kg"] == 430, "salvar grava o peso novo (430)", str(lote_db(2)))
    editar(2); page.locator("#f-pesoreferencia").fill(""); salvar()
    conf(lote_db(2)["peso_referencia_kg"] is None, "apagar o campo limpa o peso de referencia (manda nulo)", str(lote_db(2)))
    # lote sem peso: salvar sem mexer nao manda a coluna (funciona antes do SQL)
    page.evaluate("() => { window.__updates = []; const orig = db.from.bind(db); window.__origFrom = orig; db.from = (t) => { const q = orig(t);"
                  " if (t==='lotes') { const u = q.update.bind(q); q.update = (row) => { window.__updates.push(row); return u(row); }; } return q; }; }")
    editar(1); salvar()
    upd = page.evaluate("() => window.__updates")
    conf(len(upd) == 1 and "peso_referencia_kg" not in upd[0], "lote sem peso de referencia: salvar nao manda a coluna", str(upd))
    editar(3); page.locator("#f-pesoreferencia").fill("5"); salvar()
    conf(any("fora do normal" in a for a in avisos) and lote_db(3)["peso_referencia_kg"] is None,
         "peso fora de 20 a 1000 kg e barrado com aviso", str(avisos[-2:]))
    page.evaluate("() => { state.modal = null; render(); }")
    # lote novo com referencia
    page.evaluate("() => { openNewModal('lote'); render(); }"); page.wait_for_timeout(200)
    page.locator("#f-nome").fill("Vacas Novas"); page.locator("#f-numanimais").fill("30")
    page.locator("#f-pesoreferencia").fill("400"); salvar()
    novo = page.evaluate("() => window.__DB__.lotes.find(l=>l.nome==='Vacas Novas')")
    conf(novo is not None and novo.get("peso_referencia_kg") == 400, "lote novo grava o peso de referencia", str(novo))
    page.set_viewport_size({"width": 390, "height": 844}); editar(2)
    larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(larg <= 0, "janela do lote sem rolar de lado em 390 px", f"passa {larg} px")
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
