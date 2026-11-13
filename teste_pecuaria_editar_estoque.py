"""
Editar saida de racao, saida de recria (tabela pasto) e producao de racao troca a baixa de estoque (movimentos) numa
transacao so, pela funcao do banco editar_consumo_com_estoque (pecuaria_editar_com_estoque_01.sql, 13/11/2026). Sem a
funcao, o caminho antigo agora e na ordem segura nos tres: muda o lancamento, grava a baixa nova e so entao apaga a
antiga (antes a recria e a producao apagavam primeiro e, se a gravacao nova falhasse, o consumo sumia do estoque).
Falha no codigo anterior. Dados inventados.
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

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
def base():
    db = {k: [] for k in ["fazendas", "animais", "abates", "leituras_cocho", "manejos", "reproducao_custos",
          "diagnosticos_gestacionais", "partos", "desmamas", "custos_fixos", "precos_arroba", "titulos", "alertas",
          "pesagens", "pesagens_animais", "protocolos_inseminacao", "lancamentos_financeiros", "centros_custo"]}
    db["lotes"] = [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "sexo": "macho", "numero_animais": 50,
                    "data_inicio": "2026-07-01", "data_fim": None, "dieta_id": 1},
                   {"id": 2, "nome": "Novilhas", "destino": "pasto", "sexo": "femea", "numero_animais": 40,
                    "data_inicio": "2026-07-01", "data_fim": None, "dieta_id": 2}]
    db["ingredientes"] = [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1}, {"id": 2, "nome": "Farelo", "unidade": "kg", "preco_kg": 2}]
    itens = [{"ingredienteId": 1, "pct": 60}, {"ingredienteId": 2, "pct": 40}]
    db["dietas"] = [{"id": 1, "nome": "Engorda", "tipo": "confinamento", "itens": itens, "consumo_direto": True},
                    {"id": 2, "nome": "Proteinado", "tipo": "pasto", "itens": itens, "consumo_direto": True},
                    {"id": 3, "nome": "Racao pronta", "tipo": "cria", "itens": itens, "consumo_direto": False}]
    db["saidas_racao"] = [{"id": 10, "data": "2026-11-10", "dieta_id": 1, "lote_id": 1, "quantidade_kg": 1000}]
    db["pasto"] = [{"id": 20, "data": "2026-11-10", "dieta_id": 2, "lote_id": 2, "quantidade": 500}]
    db["producoes_racao"] = [{"id": 30, "data": "2026-11-10", "dieta_id": 3, "quantidade_kg": 2000}]
    db["movimentos"] = [
        {"id": 1, "data": "2026-11-10", "ingrediente_id": 1, "tipo": "saida", "quantidade": 600, "saida_racao_id": 10},
        {"id": 2, "data": "2026-11-10", "ingrediente_id": 2, "tipo": "saida", "quantidade": 400, "saida_racao_id": 10},
        {"id": 3, "data": "2026-11-10", "ingrediente_id": 1, "tipo": "saida", "quantidade": 300, "pasto_id": 20},
        {"id": 4, "data": "2026-11-10", "ingrediente_id": 2, "tipo": "saida", "quantidade": 200, "pasto_id": 20},
        {"id": 5, "data": "2026-11-10", "ingrediente_id": 1, "tipo": "saida", "quantidade": 1200, "producao_racao_id": 30},
        {"id": 6, "data": "2026-11-10", "ingrediente_id": 2, "tipo": "saida", "quantidade": 800, "producao_racao_id": 30},
    ]
    return db

def abrir(pw, rpc):
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, avisos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: avisos.append(m.text) if m.text.startswith("[aviso]") else None)
    page.on("dialog", lambda d: d.accept())
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(base(), profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
                         "window.__CHAMADAS_RPC__ = [];")
    if rpc:
        page.add_init_script("window.__RPC__ = {editar_consumo_com_estoque: (a) => ({data: (a.p_movimentos||[]).length, error: null})};")
    page.goto((REPO / "AEpecuaria.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico", timeout=15000)
    return browser, page, erros, avisos

def editar(page, tipo, lista, id_, qtd_campo, qtd):
    page.evaluate(f"""() => {{ const s = state.{lista}.find(x=>x.id==={id_}); editDraft = {{...s, _editId: s.id}};
        state.modal = {{type: '{tipo}'}}; render(); }}""")
    page.wait_for_timeout(150)
    page.locator(f"#{qtd_campo}").fill(str(qtd))
    page.locator(f'[data-save="{tipo}"]').click(); page.wait_for_timeout(600)

def movs(page, fk, id_):
    return page.evaluate(f"() => window.__DB__.movimentos.filter(m=>m.{fk}==={id_}).map(m=>m.ingrediente_id+':'+Number(m.quantidade)).sort()")

with sync_playwright() as pw:
    print("\n  COM A FUNCAO DO BANCO (tudo ou nada)")
    browser, page, erros, avisos = abrir(pw, rpc=True)
    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(erros[:3]))
    page.evaluate("() => { window.__ESCRITAS__.length = 0; }")
    editar(page, "saidaRacao", "saidasRacao", 10, "f-qtdracao", 1500)
    ch = page.evaluate("() => window.__CHAMADAS_RPC__.filter(c=>c.nome==='editar_consumo_com_estoque').map(c=>c.args)")
    conf(len(ch) == 1 and ch[0]["p_tabela"] == "saidas_racao" and ch[0]["p_id"] == 10, "saida de racao: uma chamada so da funcao", json.dumps(ch)[:200])
    if ch:
        conf(ch[0]["p_campos"]["quantidade_kg"] == 1500 and ch[0]["p_campos"]["lote_id"] == 1 and ch[0]["p_campos"]["dieta_id"] == 1,
             "manda o lancamento novo (1500 kg)", json.dumps(ch[0]["p_campos"]))
        conf(sorted((m["ingrediente_id"], m["quantidade"]) for m in ch[0]["p_movimentos"]) == [(1, 900), (2, 600)],
             "manda a baixa nova pela dieta: 60% milho = 900, 40% farelo = 600", json.dumps(ch[0]["p_movimentos"]))
    esc = page.evaluate("() => window.__ESCRITAS__.filter(e => e.tabela==='saidas_racao' || e.tabela==='movimentos')")
    conf(esc == [], "nada gravado direto nas tabelas (so pela funcao)", json.dumps(esc)[:200])
    conf(page.locator("[data-save]").count() == 0, "janela fecha depois de salvar")

    page.evaluate("() => { window.__CHAMADAS_RPC__.length = 0; }")
    editar(page, "pasto", "pasto", 20, "f-qtdpasto", 800)
    ch = page.evaluate("() => window.__CHAMADAS_RPC__.filter(c=>c.nome==='editar_consumo_com_estoque').map(c=>c.args)")
    conf(len(ch) == 1 and ch[0]["p_tabela"] == "pasto" and ch[0]["p_campos"]["quantidade"] == 800
         and sorted((m["ingrediente_id"], m["quantidade"]) for m in ch[0]["p_movimentos"]) == [(1, 480), (2, 320)],
         "recria: funcao com 800 kg e baixa 480/320", json.dumps(ch)[:200])
    page.evaluate("() => { window.__CHAMADAS_RPC__.length = 0; }")
    editar(page, "producaoRacao", "producoesRacao", 30, "f-qtdproduzida", 3000)
    ch = page.evaluate("() => window.__CHAMADAS_RPC__.filter(c=>c.nome==='editar_consumo_com_estoque').map(c=>c.args)")
    conf(len(ch) == 1 and ch[0]["p_tabela"] == "producoes_racao"
         and sorted((m["ingrediente_id"], m["quantidade"]) for m in ch[0]["p_movimentos"]) == [(1, 1800), (2, 1200)],
         "producao: funcao com a baixa 1800/1200 (producao sempre baixa os ingredientes)", json.dumps(ch)[:200])
    # dieta pronta (sem consumo direto) na saida: baixa vazia
    page.evaluate("() => { window.__CHAMADAS_RPC__.length = 0; }")
    page.evaluate("""() => { const s = state.saidasRacao.find(x=>x.id===10); editDraft = {...s, dietaId: 3, _editId: s.id};
        state.modal = {type:'saidaRacao'}; render(); }""")
    page.wait_for_timeout(150)
    page.locator('[data-save="saidaRacao"]').click(); page.wait_for_timeout(600)
    ch = page.evaluate("() => window.__CHAMADAS_RPC__.filter(c=>c.nome==='editar_consumo_com_estoque').map(c=>c.args)")
    conf(len(ch) == 1 and ch[0]["p_movimentos"] == [] and ch[0]["p_campos"]["dieta_id"] == 3,
         "trocar para dieta pronta: funcao com baixa vazia (a antiga sai)", json.dumps(ch)[:200])
    # recusa do banco aparece e a janela fica
    page.evaluate("() => { window.__RPC__.editar_consumo_com_estoque = () => ({data:null, error:{code:'P0002', message:'Lancamento 20 nao encontrado ou sem permissao para editar.'}}); }")
    avisos.clear()
    editar(page, "pasto", "pasto", 20, "f-qtdpasto", 900)
    conf(any("sem permissao" in a for a in avisos) and page.locator('[data-save="pasto"]').count() == 1,
         "recusa do banco aparece na tela e a janela continua aberta", str(avisos[-2:]))
    browser.close()

    print("\n  SEM A FUNCAO (antes do SQL): caminho antigo na ordem segura")
    browser, page, erros, avisos = abrir(pw, rpc=False)
    editar(page, "saidaRacao", "saidasRacao", 10, "f-qtdracao", 1500)
    conf(movs(page, "saida_racao_id", 10) == ["1:900", "2:600"], "saida: baixa antiga trocada pela nova, sem dobrar", str(movs(page, "saida_racao_id", 10)))
    conf(page.evaluate("() => window.__DB__.saidas_racao[0].quantidade_kg") == 1500, "saida gravada com 1500 kg")
    editar(page, "pasto", "pasto", 20, "f-qtdpasto", 800)
    conf(movs(page, "pasto_id", 20) == ["1:480", "2:320"], "recria: baixa trocada", str(movs(page, "pasto_id", 20)))
    editar(page, "producaoRacao", "producoesRacao", 30, "f-qtdproduzida", 3000)
    conf(movs(page, "producao_racao_id", 30) == ["1:1800", "2:1200"], "producao: baixa trocada", str(movs(page, "producao_racao_id", 30)))
    # gravacao da baixa nova falha: a antiga fica (antes, na recria e na producao, ela sumia)
    page.evaluate("""() => { const orig = db.from.bind(db); db.from = (t) => { const q = orig(t);
        if (t==='movimentos') { q.insert = () => ({ select: () => Promise.resolve({data:null, error:{message:'Failed to fetch'}}) ,
            then: (r) => r({data:null, error:{message:'Failed to fetch'}}) }); } return q; }; }""")
    for tipo, lista, id_, campo, fk, antes in (("pasto", "pasto", 20, "f-qtdpasto", "pasto_id", ["1:480", "2:320"]),
                                               ("producaoRacao", "producoesRacao", 30, "f-qtdproduzida", "producao_racao_id", ["1:1800", "2:1200"]),
                                               ("saidaRacao", "saidasRacao", 10, "f-qtdracao", "saida_racao_id", ["1:900", "2:600"])):
        editar(page, tipo, lista, id_, campo, 2222)
        conf(movs(page, fk, id_) == antes, f"{tipo}: baixa nova falhou e a antiga continua no estoque (nao some)", str(movs(page, fk, id_)))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
