"""
Planilha de manejo (07/11/2026): no curral nao ha sinal, entao o funcionario preenche a Planilha_de_Manejo.xlsx e, com internet,
importa no AE Pecuaria (Manejo > Importar planilha). Prova (a planilha de verdade, preenchida por codigo, e o app servido por
http, como em producao):
  - a planilha modelo tem os rotulos que o app procura; a tela de Manejo tem o cartao, o link do modelo e o modelo existe no site;
  - planilha certa: previa mostra cada animal, nada e gravado ate tocar em Importar; ao importar cria UM manejo finalizado, uma
    pesagem com a media, o peso por animal, as inseminacoes (qual = 1a), cadastra o animal novo (raca, sexo do lote) e usa o
    cadastro 057 quando a planilha diz 57 (zero a esquerda nao conta); peso com virgula decimal;
  - erros (lote que nao existe, numero com texto, animal novo sem raca, peso zero, raca do touro faltando, diagnostico
    invalido): a previa mostra linha a linha, o botao fica desligado e NADA e gravado;
  - desmama acha o bezerro sem desmama pela mae e recusa mae sem bezerro, bezerro ja desmamado e mae repetida;
  - mudanca de lote move o animal e acerta o total dos dois lotes; lote misto exige o sexo do animal novo;
  - 4a inseminacao e numero repetido viram AVISO (nao impedem);
  - a mesma planilha importada duas vezes avisa e pede confirmacao; recusar nao grava nada;
  - sem internet ao importar: avisa e nao grava; rede que cai no meio: para, diz a linha, e "Continuar" termina sem duplicar;
  - arquivo que nao e a planilha modelo da aviso claro; nada rola de lado em 1280 e 390 px; nenhum erro de JavaScript.
"""
import json
import sys
import tempfile
import threading
from datetime import date, timedelta
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import urlopen

from openpyxl import Workbook, load_workbook
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
TMP = Path(tempfile.mkdtemp(prefix="manejo_planilha_"))
HOJE = date.today()
dia = lambda n: (HOJE - timedelta(days=n)).isoformat()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}


def monta_db():
    return {
        "lotes": [
            {"id": 1, "nome": "Vacas 07/08", "destino": "cria", "numero_animais": 40, "data_inicio": dia(300), "data_fim": None, "dieta_id": None, "sexo": "femea"},
            {"id": 2, "nome": "Vacas Prenhes", "destino": "cria", "numero_animais": 10, "data_inicio": dia(300), "data_fim": None, "dieta_id": None, "sexo": "femea"},
            {"id": 3, "nome": "Lote Misto", "destino": "pasto", "numero_animais": 20, "data_inicio": dia(300), "data_fim": None, "dieta_id": None, "sexo": ""},
            {"id": 4, "nome": "Curral Velho", "destino": "confinamento", "numero_animais": 0, "data_inicio": dia(400), "data_fim": dia(10), "dieta_id": None, "sexo": "macho"},
        ],
        "dietas": [], "ingredientes": [],
        "animais": [
            {"id": 1, "numero": "100", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 2, "numero": "101", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 3, "numero": "057", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 4, "numero": "102", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 5, "numero": "103", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 6, "numero": "11", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 7, "numero": "11099", "lote_id": 1, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 8, "numero": "500", "lote_id": 3, "sexo": "macho", "raca": "angus", "status": "ativo"},
        ],
        "partos": [
            {"id": 1, "data": dia(120), "lote_id": 1, "numero_mae": "100", "sexo_bezerro": "macho", "raca_bezerro": "nelore", "tipo": "nascimento"},
            {"id": 2, "data": dia(150), "lote_id": 1, "numero_mae": "101", "sexo_bezerro": "femea", "raca_bezerro": "nelore", "tipo": "nascimento"},
            {"id": 3, "data": dia(170), "lote_id": 1, "numero_mae": "102", "sexo_bezerro": "macho", "raca_bezerro": "nelore", "tipo": "nascimento"},
            {"id": 4, "data": dia(200), "lote_id": 1, "numero_mae": "103", "sexo_bezerro": "macho", "raca_bezerro": "nelore", "tipo": "nascimento"},
        ],
        "desmamas": [{"id": 1, "parto_id": 3, "data": dia(20), "raca": "nelore", "peso_kg": 180}],
        "reproducao_custos": [{"id": i, "data": dia(150 - 20 * i), "lote_id": 1, "numero_vaca": "103", "item": "IATF", "custo": 0, "qual_inseminacao": str(i)} for i in (1, 2, 3)],
        "pesagens": [], "pesagens_animais": [], "diagnosticos_gestacionais": [], "protocolos_inseminacao": [], "manejos": [], "movimentos": [], "saidas_racao": [],
        "leituras_cocho": [], "pasto": [], "producoes_racao": [], "abates": [], "precos_arroba": [], "fazendas": [], "fazenda_atividades": [],
        "centros_custo": [], "lancamentos_financeiros": [], "config_financeiro": [], "funcionarios": [], "profiles": [ADMIN],
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


contador = [0]


def planilha(bloco, linhas):
    """Preenche a planilha modelo de verdade. bloco: {'B4': ..., 'B5': ...}; linhas: tuplas (numero, sexo, raca, peso, touro, diag, mae, pesoDesm, racaDesm)."""
    wb = load_workbook(REPO / "Planilha_de_Manejo.xlsx")
    ws = wb["Manejo"]
    for celula, v in bloco.items():
        ws[celula] = v
    for i, l in enumerate(linhas):
        for col, v in zip("ABCDEFGHI", l):
            if v is not None:
                ws[f"{col}{17 + i}"] = v
    contador[0] += 1
    caminho = TMP / f"plan{contador[0]}.xlsx"
    wb.save(caminho)
    return str(caminho)


def base(**mudar):
    b = {"B4": HOJE, "B5": "Vacas 07/08", "B6": None, "B7": "Não", "B8": "Não", "B9": "Não", "B10": "Não", "B11": "Não", "B12": "Não", "B13": "Não"}
    b.update(mudar)
    return b


def importa(page, caminho):
    page.evaluate("() => { state.importManejo = null; render(); }")
    page.set_input_files("[data-arquivo-planilha-manejo]", caminho)
    page.wait_for_function("() => state.importManejo && !state.importManejo.lendo && (state.importManejo.plano || state.importManejo.erro)", timeout=30000)
    page.wait_for_timeout(200)


def previa(page):
    return page.evaluate("""() => [...document.querySelectorAll('[data-linha-previa]')].map(tr => ({
        linha: Number(tr.dataset.linhaPrevia), situacao: tr.dataset.situacao, animal: tr.children[1].innerText.trim(),
        o_que: tr.children[2].innerText.trim(), texto: tr.children[3].innerText.trim() }))""")


def botao_importar(page):
    b = page.locator("[data-importar-planilha-manejo]")
    return {"existe": b.count() == 1, "ligado": b.count() == 1 and b.is_enabled(), "texto": b.inner_text().strip() if b.count() else ""}


def abre_manejo(ctx, url, db=None):
    page = ctx.new_page()
    page.avisos, page.erros, page.confirmacoes = [], [], []
    page.on("console", lambda m: page.avisos.append(m.text[len("[aviso] "):]) if m.text.startswith("[aviso] ") else None)
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: (page.confirmacoes.append(d.message), d.accept() if page.aceita else d.dismiss()))
    page.aceita = True
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db or monta_db())}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto(url + "/AEpecuaria.html")
    page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico && state.lotes.length > 0", timeout=30000)
    page.evaluate("() => { state.modal = null; editDraft = null; state.page = 'manejoInicio'; render(); }")
    page.wait_for_timeout(300)
    return page


def tabela(page, nome):
    return page.evaluate("(n) => window.__DB__[n] || []", nome)


handler = partial(SimpleHTTPRequestHandler, directory=str(REPO))
handler.log_message = lambda *a, **k: None
class Quieto(SimpleHTTPRequestHandler):
    def log_message(self, *a, **k):
        pass
servidor = ThreadingHTTPServer(("127.0.0.1", 0), partial(Quieto, directory=str(REPO)))
threading.Thread(target=servidor.serve_forever, daemon=True).start()
URL = f"http://127.0.0.1:{servidor.server_address[1]}"

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    ctx = browser.new_context(viewport={"width": 1280, "height": 900}, service_workers="block")

    # ------------------------------------------------------------------ modelo e tela
    print("== a planilha modelo e o cartao na tela")
    wb = load_workbook(REPO / "Planilha_de_Manejo.xlsx")
    ws = wb["Manejo"]
    rotulos = [str(ws.cell(r, 1).value or "") for r in range(1, 16)]
    conf(any(x.startswith("Data do manejo") for x in rotulos) and any(x.startswith("Lote (") for x in rotulos) and any(x.startswith("Desmama?") for x in rotulos),
         "o modelo tem os rotulos do alto que o app procura")
    conf(str(ws["A16"].value).startswith("Número do animal") and ws["I16"].value.startswith("Desmama: raça"), "e os titulos da tabela")
    conf(len(ws.data_validations.dataValidation) >= 7, "e as listas de escolha (Sim/Nao, raca, diagnostico)")
    conf(urlopen(URL + "/Planilha_de_Manejo.xlsx").status == 200, "o modelo esta no site (link de baixar)")
    conf(urlopen(URL + "/vendor/xlsx.full.min.js").status == 200, "o leitor de planilhas esta no site")
    page = abre_manejo(ctx, URL)
    conf(page.locator("[data-importar-manejo]").count() == 1 and page.locator('a[href="./Planilha_de_Manejo.xlsx"]').count() == 1, "a tela de Manejo tem o cartao de importar e o link do modelo")

    # ------------------------------------------------------------------ planilha certa
    print("== planilha certa: previa e importacao")
    p1 = planilha(base(B7="Sim", B8="Sim", B12="Sim"), [
        (100, None, None, 450.5, "Nelore"),
        ("57", None, None, 420, "Angus"),
        ("300", None, "Nelore", 400, "Angus"),
        (101, None, None, "389,5", "Outro"),
    ])
    importa(page, p1)
    pv = previa(page)
    conf(len(pv) == 4 and all(r["situacao"] == "ok" for r in pv), "4 animais, todos ok na previa", str(pv))
    conf(pv[1]["animal"] == "057", "'57' usa o cadastro 057 (zero a esquerda nao conta)", str(pv[1]))
    conf("animal novo (nelore, fêmea)" in pv[2]["o_que"] and "400 kg" in pv[2]["o_que"] and "IATF (touro angus)" in pv[2]["o_que"], "o animal novo mostra raca e sexo do lote", pv[2]["o_que"])
    conf("389,5 kg" in pv[3]["o_que"], "peso com virgula decimal", pv[3]["o_que"])
    corpo = page.inner_text("[data-previa-manejo]")
    conf("Vacas 07/08" in corpo and "Pesagem" in corpo and "Inseminação" in corpo and "Vacinação" in corpo, "a previa resume lote, data e acoes")
    b = botao_importar(page)
    conf(b["ligado"] and b["texto"] == "Importar 4 animal(is)", "o botao importa 4 animais", str(b))
    conf(not tabela(page, "manejos") and not tabela(page, "pesagens_animais"), "ate tocar em Importar nada foi gravado")
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_function("() => state.importManejo && state.importManejo.concluido", timeout=30000)
    page.wait_for_timeout(300)
    manejos = tabela(page, "manejos")
    conf(len(manejos) == 1 and manejos[0]["status"] == "finalizado" and manejos[0]["total_animais"] == 4 and manejos[0]["lote_id"] == 1 and manejos[0]["vacinacao"] is True,
         "UM manejo, finalizado, 4 animais, com a vacinacao", str(manejos))
    pes = tabela(page, "pesagens")
    conf(len(pes) == 1 and abs(pes[0]["peso_medio_kg"] - 415.0) < 0.01 and pes[0]["manejo_id"] == manejos[0]["id"], "uma pesagem com a media (415 kg) ligada ao manejo", str(pes))
    pa = tabela(page, "pesagens_animais")
    conf([r["numero_animal"] for r in pa] == ["100", "057", "300", "101"] and [r["peso_kg"] for r in pa] == [450.5, 420, 400, 389.5], "peso de cada animal", str(pa))
    ia = tabela(page, "reproducao_custos")
    novos = [r for r in ia if r["id"] > 3]
    conf(len(novos) == 4 and all(r["manejo_id"] == manejos[0]["id"] and r["qual_inseminacao"] == "1" for r in novos) and [r["raca_touro"] for r in novos] == ["nelore", "angus", "angus", "outro"],
         "4 inseminacoes (1a), com a raca do touro, ligadas ao manejo", str(novos))
    an = [a for a in tabela(page, "animais") if a["numero"] == "300"]
    conf(len(an) == 1 and an[0]["lote_id"] == 1 and an[0]["sexo"] == "femea" and an[0]["raca"] == "nelore", "o animal novo 300 foi cadastrado no lote, com a raca e o sexo do lote", str(an))
    conf("Planilha importada" in page.inner_text("[data-importacao-concluida]") and "4 animal" in page.inner_text("[data-importacao-concluida]"), "a tela mostra a conclusao")
    conf(page.evaluate("() => state.manejos.length") == 1, "o historico de manejos ja mostra o novo")

    # ------------------------------------------------------------------ mesma planilha de novo
    print("== a mesma planilha de novo")
    n_antes = len(tabela(page, "pesagens_animais"))
    page.aceita = False
    importa(page, p1)
    conf(page.locator("[data-ja-importada]").count() == 1, "avisa que esta planilha ja foi importada neste aparelho")
    conf(botao_importar(page)["texto"] == "Importar mesmo assim", "o botao vira 'Importar mesmo assim'")
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_timeout(500)
    conf(any("já foi importada" in c for c in page.confirmacoes) and len(tabela(page, "pesagens_animais")) == n_antes, "pede confirmacao e, recusando, nada e gravado")
    page.aceita = True
    page.click("[data-cancelar-importacao-manejo]")
    conf(page.locator("[data-previa-manejo]").count() == 0, "Cancelar limpa a previa")
    page.close()

    # ------------------------------------------------------------------ erros: nada gravado
    print("== erros: a previa mostra linha a linha e nada e gravado")
    page = abre_manejo(ctx, URL)
    p2 = planilha(base(B5="Lote que nao existe", B7="Sim", B8="Sim"), [(100, None, None, 450, "Nelore")])
    importa(page, p2)
    conf("Não achei o lote" in page.inner_text("[data-previa-manejo]") and not botao_importar(page)["ligado"], "lote inexistente: erro no alto e botao desligado")
    p3 = planilha(base(B7="Sim", B8="Sim"), [
        ("abc", None, None, 400, "Nelore"),           # 17: numero com texto
        ("400", None, None, 400, "Nelore"),           # 18: animal novo sem raca
        (101, None, None, 0, "Nelore"),               # 19: peso zero
        (100, None, None, 450, None),                 # 20: sem raca do touro
        (None, None, None, 300, "Nelore"),            # 21: sem numero (precisa p/ inseminacao)
    ])
    importa(page, p3)
    pv = previa(page)
    por_linha = {r["linha"]: r for r in pv}
    conf(len(pv) == 5 and all(r["situacao"] == "erro" for r in pv), "as 5 linhas com problema aparecem como erro", str([(r["linha"], r["situacao"]) for r in pv]))
    conf("algarismos" in por_linha[17]["texto"].lower() or "número" in por_linha[17]["texto"].lower(), "numero com texto", por_linha[17]["texto"])
    conf("ainda não está cadastrado" in por_linha[18]["texto"], "animal novo sem raca", por_linha[18]["texto"])
    conf("peso maior que zero" in por_linha[19]["texto"], "peso zero", por_linha[19]["texto"])
    conf("raça do touro" in por_linha[20]["texto"], "falta a raca do touro", por_linha[20]["texto"])
    conf("Informe o número do animal" in por_linha[21]["texto"], "inseminacao sem numero", por_linha[21]["texto"])
    conf(not botao_importar(page)["ligado"] and "5 com erro" in page.inner_text("[data-previa-manejo]"), "botao desligado e a contagem de erros")
    conf(not tabela(page, "manejos") and not tabela(page, "pesagens"), "nada foi gravado")
    p3b = planilha(base(B9="Sim"), [(100, None, None, None, None, "talvez")])
    importa(page, p3b)
    conf("Prenha ou Vazia" in previa(page)[0]["texto"], "diagnostico invalido")
    p3c = planilha(base(B7="Não", B8="Não", B9="Não", B10="Não", B11="Não"), [(100,)])
    importa(page, p3c)
    conf("Marque Sim em ao menos uma ação" in page.inner_text("[data-previa-manejo]"), "sem nenhuma acao marcada")
    p3d = planilha(base(B5="Curral Velho", B7="Sim"), [(100, None, None, 300)])
    importa(page, p3d)
    conf("encerrado" in page.inner_text("[data-previa-manejo]"), "lote encerrado nao recebe manejo")

    # ------------------------------------------------------------------ avisos que nao impedem
    print("== avisos que nao impedem")
    p4 = planilha(base(B8="Sim"), [(103, None, None, None, "Nelore"), (100, None, None, None, "Nelore"), (100, None, None, None, "Nelore"), (11, None, None, None, "Nelore")])
    importa(page, p4)
    pv = previa(page)
    por_linha = {r["linha"]: r for r in pv}
    conf(por_linha[17]["situacao"] == "aviso" and "4ª" in por_linha[17]["texto"], "a 4a inseminacao da vaca 103 e so aviso", por_linha[17]["texto"])
    conf(por_linha[19]["situacao"] == "aviso" and "aparece também na linha 18" in por_linha[19]["texto"], "numero repetido na planilha e so aviso", por_linha[19]["texto"])
    conf(por_linha[20]["situacao"] == "aviso" and "11099" in por_linha[20]["texto"], "brinco parecido (11 e 11099) avisa qual foi usado", por_linha[20]["texto"])
    conf(botao_importar(page)["ligado"], "e o botao continua ligado")

    # ------------------------------------------------------------------ desmama
    print("== desmama")
    p5 = planilha(base(B11="Sim"), [(None, None, None, None, None, None, 101, 180, "Nelore")])
    importa(page, p5)
    conf(previa(page)[0]["situacao"] == "ok" and "desmama (mãe 101" in previa(page)[0]["o_que"], "desmama acha o bezerro da mae 101", str(previa(page)))
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_function("() => state.importManejo && state.importManejo.concluido", timeout=30000)
    des = [d for d in tabela(page, "desmamas") if d["id"] != 1]
    conf(len(des) == 1 and des[0]["parto_id"] == 2 and des[0]["peso_kg"] == 180 and des[0]["raca"] == "nelore", "a desmama foi gravada no parto certo", str(des))
    p5b = planilha(base(B11="Sim"), [(None, None, None, None, None, None, 999, 180, "Nelore"), (None, None, None, None, None, None, 102, 180, "Nelore"),
                                     (None, None, None, None, None, None, 100, 150, "Nelore"), (None, None, None, None, None, None, 100, 150, "Nelore"),
                                     (None, None, None, None, None, None, 101, 150, "Nelore")])
    importa(page, p5b)
    pv = previa(page)
    por_linha = {r["linha"]: r for r in pv}
    conf("não achei um bezerro sem desmama da mãe 999" in por_linha[17]["texto"], "mae sem bezerro", por_linha[17]["texto"])
    conf("não achei um bezerro sem desmama da mãe 102" in por_linha[18]["texto"], "bezerro ja desmamado", por_linha[18]["texto"])
    conf(por_linha[19]["situacao"] == "ok" and "já aparece na linha 19" in por_linha[20]["texto"], "mae repetida na planilha", por_linha[20]["texto"])
    conf("não achei um bezerro sem desmama da mãe 101" in por_linha[21]["texto"], "bezerro desmamado na importacao anterior nao aparece de novo", por_linha[21]["texto"])
    page.close()

    # ------------------------------------------------------------------ mudanca de lote e lote misto
    print("== mudanca de lote e lote misto")
    page = abre_manejo(ctx, URL)
    p6 = planilha(base(B6="vacas prenhes", B9="Sim"), [(100, None, None, None, None, "Prenha"), (101, None, None, None, None, "Vazia")])
    importa(page, p6)
    conf(all(r["situacao"] == "ok" for r in previa(page)) and "→ Vacas Prenhes" in page.inner_text("[data-previa-manejo]"), "previa mostra o lote de destino")
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_function("() => state.importManejo && state.importManejo.concluido", timeout=30000)
    lotes = {l["id"]: l["numero_animais"] for l in tabela(page, "lotes")}
    animais = {a["numero"]: a["lote_id"] for a in tabela(page, "animais")}
    conf(animais["100"] == 2 and animais["101"] == 2, "os 2 animais foram para o lote de destino", str(animais))
    conf(lotes[1] == 38 and lotes[2] == 12, "o total dos dois lotes foi acertado (40->38 e 10->12)", str(lotes))
    dg = tabela(page, "diagnosticos_gestacionais")
    conf([d["resultado"] for d in dg] == ["prenha", "vazia"], "diagnosticos gravados", str(dg))
    p7 = planilha(base(B5="Lote Misto", B7="Sim"), [("600", None, "Angus", 350), ("601", "Fêmea", "Angus", 330), (500, None, None, 400)])
    importa(page, p7)
    pv = previa(page)
    conf(pv[0]["situacao"] == "erro" and "sexo" in pv[0]["texto"].lower(), "lote misto: animal novo sem sexo e erro", pv[0]["texto"])
    conf(pv[1]["situacao"] == "ok" and "fêmea" in pv[1]["o_que"], "com o sexo preenchido passa", str(pv[1]))
    conf(pv[2]["situacao"] == "ok", "animal ja cadastrado nao pede nada", str(pv[2]))
    page.close()

    # ------------------------------------------------------------------ sem internet e rede que cai
    print("== sem internet e rede que cai no meio")
    page = abre_manejo(ctx, URL)
    p8 = planilha(base(B7="Sim"), [(100, None, None, 400), (101, None, None, 410), (102, None, None, 420)])
    importa(page, p8)
    page.evaluate("() => { window.__SEM_REDE__ = true; }")
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_timeout(800)
    conf(any("Sem internet: nada foi gravado" in a for a in page.avisos) and not tabela(page, "manejos"), "sem internet ao importar: avisa e nao grava nada", str(page.avisos))
    conf(botao_importar(page)["ligado"], "e da para tentar de novo")
    page.evaluate("""() => { window.__SEM_REDE__ = false; window.__CHAMADAS__ = 0; const o = gravarAnimalDoManejo;
        gravarAnimalDoManejo = function (...a) { window.__CHAMADAS__++; if (window.__CHAMADAS__ === 2) window.__SEM_REDE__ = true; return o.apply(this, a); }; }""")
    page.click("[data-importar-planilha-manejo]")
    page.wait_for_function("() => state.importManejo && state.importManejo.parou", timeout=30000)
    txt = page.inner_text("[data-importacao-parou]")
    conf("parou na linha 18" in txt and "1 animal(is) já foram gravados" in txt, "a rede caiu no 2o animal: para e diz a linha e quantos entraram", txt)
    conf(len(tabela(page, "pesagens_animais")) == 1 and tabela(page, "manejos")[0]["status"] == "aberto", "so o 1o foi gravado e o manejo segue aberto")
    page.evaluate("() => { window.__SEM_REDE__ = false; }")
    page.click("[data-continuar-importacao-manejo]")
    page.wait_for_function("() => state.importManejo && state.importManejo.concluido", timeout=30000)
    pa = tabela(page, "pesagens_animais")
    conf([r["numero_animal"] for r in pa] == ["100", "101", "102"], "Continuar termina sem repetir o 1o", str([r["numero_animal"] for r in pa]))
    m = tabela(page, "manejos")
    conf(len(m) == 1 and m[0]["status"] == "finalizado" and m[0]["total_animais"] == 3, "um manejo so, finalizado com 3 animais", str(m))
    conf(abs(tabela(page, "pesagens")[0]["peso_medio_kg"] - 410) < 0.01, "a media de peso conta os 3 (410 kg)")

    # ------------------------------------------------------------------ arquivo errado e tela
    print("== arquivo errado e a tela")
    wb = Workbook()
    wb.active["A1"] = "isto nao e a planilha de manejo"
    errada = TMP / "errada.xlsx"
    wb.save(errada)
    page.evaluate("() => { state.importManejo = null; render(); }")
    importa(page, str(errada))
    conf("Não achei a linha de títulos" in page.inner_text("[data-importar-manejo]"), "arquivo que nao e o modelo da um aviso claro")
    for w in (1280, 390):
        page.set_viewport_size({"width": w, "height": 900})
        page.evaluate("() => { state.importManejo = null; render(); }")
        importa(page, p3)
        lat = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(lat <= 1, f"{w} px: a previa nao faz a pagina rolar de lado ({lat} px)")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    ctx.close()
    browser.close()

servidor.shutdown()
print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
