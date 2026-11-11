"""
Animal vendido sai do cadastro ativo (Eduardo, 11/11/2026, revisao geral).

A venda baixava so a contagem do lote; o cadastro individual ficava "ativo"
(202 bois dos Currais 1 e 2, lotes ja vendidos e encerrados). O banco passou a
marcar 'vendido' com a data (gatilho trg_lote_baixa_animais,
pecuaria_animal_vendido_01.sql, ensaiado a parte num Postgres). Aqui, o lado
do app:
- o lote mostra "Vendido em dd/mm/aaaa" e separa cabecas de numerados;
- lancar o numero de um animal vendido NAO o traz de volta para um lote ativo
  (o numero e unico por sexo e o historico de pesagem e pelo numero): avisa;
- "Nao foi vendido" volta o animal a ativo e abre o Editar para escolher o lote;
- Editar de um vendido nao muda o lote sem desfazer a venda antes;
- a planilha de manejo recusa na previa o numero de um vendido;
- antes do SQL (sem data_saida, sem 'vendido') nada muda.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

DB = {
    "fazendas": [{"id": 1, "nome": "Faz Teste"}],
    "lotes": [
        {"id": 31, "nome": "Curral 2", "destino": "confinamento", "sexo": "macho",
         "numero_animais": 0, "data_inicio": "2026-07-21", "data_fim": "2026-10-27", "dieta_id": None},
        {"id": 36, "nome": "Engorda Nova", "destino": "confinamento", "sexo": "macho",
         "numero_animais": 50, "data_inicio": "2026-10-30", "data_fim": None, "dieta_id": None},
    ],
    "animais": [
        {"id": 901, "numero": "512", "lote_id": 31, "sexo": "macho", "raca": "nelore", "criado_por": "x",
         "status": "vendido", "data_morte": None, "data_saida": "2026-10-27", "nome": None},
        {"id": 902, "numero": "513", "lote_id": 31, "sexo": "macho", "raca": "nelore", "criado_por": "x",
         "status": "vendido", "data_morte": None, "data_saida": "2026-10-27", "nome": None},
        {"id": 903, "numero": "700", "lote_id": 36, "sexo": "macho", "raca": "nelore", "criado_por": "x",
         "status": "ativo", "data_morte": None, "data_saida": None, "nome": None},
    ],
    "abates": [{"id": 1, "lote_id": 31, "data": "2026-10-27", "quantidade": 2, "tipo_venda": "arroba",
                "peso_medio_kg": 290, "valor_arroba": 300, "categoria": "boi", "sexo": "macho"}],
    "dietas": [], "ingredientes": [], "movimentos": [], "producoes_racao": [],
    "saidas_racao": [], "leituras_cocho": [], "pasto": [],
    "manejos": [], "reproducao_custos": [], "diagnosticos_gestacionais": [],
    "partos": [], "desmamas": [], "custos_fixos": [], "precos_arroba": [],
    "titulos": [], "alertas": [], "pesagens": [], "pesagens_animais": [],
    "protocolos_inseminacao": [], "lancamentos_financeiros": [], "centros_custo": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}
RUIDO = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def abrir(pw, db):
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, avisos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: avisos.append(m.text) if m.text.startswith("[aviso]") else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(db, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico", timeout=15000)
    return browser, page, erros, avisos

def ver_lote(page, lote_id):
    page.evaluate(f"() => {{ state.page='loteDetalhe'; state.loteDetalheId={lote_id}; render(); }}")
    page.wait_for_timeout(150)

with sync_playwright() as pw:
    print("\n  ANIMAL VENDIDO")
    browser, page, erros, avisos = abrir(pw, DB)
    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    ver_lote(page, 31)
    pills = page.locator("[data-animal-vendido]")
    conf(pills.count() == 2 and "Vendido em 27/10/2026" in pills.first.inner_text(),
         "lote vendido mostra 'Vendido em 27/10/2026' nos dois animais", str(pills.count()))
    resumo = page.locator("[data-resumo-lote-animais]").inner_text()
    conf("0 cabeça(s) no lote" in resumo and "0 com número cadastrado" in resumo and "2 vendido(s)" in resumo,
         "cabeçalho separa cabeças, numerados e vendidos", resumo)
    conf(page.locator("[data-registrar-morte]").count() == 0 and page.locator("[data-reverter-venda-animal]").count() == 2,
         "vendido tem 'Não foi vendido' no lugar de 'Registrar morte'")

    ver_lote(page, 36)
    resumo = page.locator("[data-resumo-lote-animais]").inner_text()
    conf("50 cabeça(s) no lote" in resumo and "1 com número cadastrado" in resumo and "vendido" not in resumo,
         "lote ativo: 50 cabeças, 1 com número, sem 'vendido'", resumo)

    # numero de um vendido lancado de novo (pesagem, manejo, entrada...): nao move
    r = page.evaluate("""async () => { const x = await upsertAnimal('512', 36, {sexo:'macho', raca:'nelore'});
        return {erro: x.error ? x.error.message : null, lote: window.__DB__.animais.find(a=>a.id===901).lote_id,
                status: window.__DB__.animais.find(a=>a.id===901).status,
                total: window.__DB__.animais.filter(a=>a.numero==='512').length}; }""")
    conf(r["erro"] is not None and "vendido em 27/10/2026" in r["erro"] and "Curral 2" in r["erro"],
         "lançar o 512 (vendido) avisa que é de um animal vendido, com data e lote", str(r["erro"]))
    conf(r["lote"] == 31 and r["status"] == "vendido" and r["total"] == 1,
         "o 512 vendido continua no Curral 2, vendido, e não foi criado outro", json.dumps(r))
    r = page.evaluate("""async () => { const x = await upsertAnimal('700', 36, {sexo:'macho'}); return x.error ? x.error.message : null; }""")
    conf(r is None, "animal ativo continua sendo atualizado normalmente", str(r))

    # planilha de manejo: a previa recusa o numero do vendido
    msg = page.evaluate("() => mensagemAnimalVendido(state.animais.find(a=>a.id===901))")
    conf("512099" in msg and "Não foi vendido" in msg, "a mensagem sugere outro número (512099) e o 'Não foi vendido'", msg)

    # Editar de um vendido mudando o lote: barrado
    ver_lote(page, 31)
    page.locator('[data-edit-animal="901"]').click()
    page.select_option("#f-loteanimal", "36")
    page.locator('[data-save="animal"]').click()
    page.wait_for_timeout(300)
    lote = page.evaluate("() => window.__DB__.animais.find(a=>a.id===901).lote_id")
    conf(lote == 31 and any("marcado como vendido" in a for a in avisos),
         "Editar não move um vendido para lote ativo sem desfazer a venda", f"lote={lote} avisos={avisos[-1:]}")
    page.evaluate("() => { state.modal=null; editDraft=null; render(); }")

    # Nao foi vendido: volta a ativo e abre o Editar
    ver_lote(page, 31)
    page.locator('[data-reverter-venda-animal="902"]').click()
    page.wait_for_selector("#f-loteanimal", timeout=5000)
    a = page.evaluate("() => window.__DB__.animais.find(x=>x.id===902)")
    conf(a["status"] == "ativo" and a["data_saida"] is None, "'Não foi vendido' volta o 513 a ativo, sem data de saída", json.dumps(a))
    conf(page.locator("#f-loteanimal").count() == 1, "e abre o Editar para escolher o lote")
    page.select_option("#f-loteanimal", "36")
    page.locator('[data-save="animal"]').click()
    page.wait_for_timeout(400)
    conf(page.evaluate("() => window.__DB__.animais.find(x=>x.id===902).lote_id") == 36, "depois de desfeito, o Editar move o 513 para o lote ativo")

    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))
    browser.close()

    print("\n  ANTES DO SQL (banco sem data_saida e sem 'vendido')")
    db_antigo = json.loads(json.dumps(DB))
    for a in db_antigo["animais"]:
        a.pop("data_saida"); a["status"] = "ativo"
    browser, page, erros, avisos = abrir(pw, db_antigo)
    ver_lote(page, 31)
    conf(page.locator("[data-animal-vendido]").count() == 0 and page.locator("[data-registrar-morte]").count() == 2,
         "sem o SQL, os animais aparecem como antes (Ativo, Registrar morte)")
    r = page.evaluate("""async () => { const x = await upsertAnimal('512', 31, {sexo:'macho'}); return x.error ? x.error.message : null; }""")
    conf(r is None, "sem o SQL, o upsert funciona como antes", str(r))
    conf(not [e for e in erros if not any(r in e for r in RUIDO)], "sem erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
