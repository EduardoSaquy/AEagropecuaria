"""
AE Pecuaria: "Qual animal e?" (pedido do Eduardo em 02/11/2026).
Numero do animal continua unico (numero + sexo), mas numeros PARECIDOS podem
ser animais diferentes: 11 x 11099 ("11 ES") e 57 x 057. Ao salvar
inseminacao, diagnostico, parto, pesagem e Manejo, se o numero puder ser de
mais de um animal -- ou nao existir mas existir um parecido -- o app pergunta
qual e antes de gravar. Numero sem parecido nao pergunta; editar sem mexer
no numero nao pergunta; "Voltar e corrigir" nao grava nada.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
FOTO = sys.argv[1] if len(sys.argv) > 1 else None

def animal(**k):
    base = {"lote_id": 6, "status": "ativo", "raca": "nelore", "sexo": "femea", "nome": None}
    base.update(k); return base

DB = {
    "lotes": [
        {"id": 6, "nome": "Vacas 07/08", "destino": "cria", "numero_animais": 80, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
        {"id": 7, "nome": "Vacas Vazias Santa Alice", "destino": "cria", "numero_animais": 80, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
        {"id": 9, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 0, "data_inicio": "2026-01-01", "data_fim": "2026-10-30", "dieta_id": 1, "sexo": "macho"},
        {"id": 8, "nome": "Curral 2", "destino": "confinamento", "numero_animais": 60, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1, "sexo": "macho"},
    ],
    "dietas": [{"id": 1, "nome": "Dieta Cria", "tipo": "cria", "itens": [], "consumo_direto": True}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
    "animais": [
        animal(id=1, numero="11"),
        animal(id=2, numero="11099", nome="ES", lote_id=7),
        animal(id=3, numero="057"),
        animal(id=4, numero="200"),
        animal(id=6, numero="300"),
        animal(id=7, numero="1", sexo="macho", lote_id=8, nome="Alice"),
        animal(id=8, numero="001", sexo="macho", lote_id=9),   # boi de lote encerrado: outro animal
        animal(id=5, numero="11", sexo="macho", lote_id=8),   # macho 11: nao e opcao numa vaca
    ],
    "partos": [
        {"id": 1, "data": "2025-08-01", "lote_id": 6, "numero_mae": "300", "sexo_bezerro": "macho", "tipo": "nascimento"},
        {"id": 2, "data": "2026-07-01", "lote_id": 6, "numero_mae": "300", "sexo_bezerro": "femea", "tipo": "nascimento"},
    ],
    "desmamas": [], "diagnosticos_gestacionais": [],
    "reproducao_custos": [{"id": 900, "data": "2026-10-19", "lote_id": 6, "numero_vaca": "11", "raca_touro": "nelore",
                           "qual_inseminacao": "1", "custo": 46.30, "criado_por": "x", "manejo_id": None, "item": None}]
        + [{"id": 900+i, "data": d, "lote_id": 6, "numero_vaca": "300", "raca_touro": "nelore", "qual_inseminacao": q,
            "custo": 46.30, "criado_por": "x", "manejo_id": None, "item": None}
           for i, (d, q) in enumerate([("2026-06-01", "1"), ("2026-08-01", "1"), ("2026-09-01", "2"), ("2026-10-01", "3")], start=1)],
    "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "pesagens": [], "manejos": [], "movimentos": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
    "producoes_racao": [], "abates": [], "precos_arroba": [], "config_financeiro": [],
    "funcionarios": [], "pesagens_animais": [], "protocolos_inseminacao": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def nova_insem(page, numero):
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('reproducaoCusto'); render(); }")
    page.wait_for_timeout(100)
    page.select_option('#f-lote', '6')
    page.fill('#f-data', '2026-10-19')
    page.fill('#f-numvaca', numero)
    page.locator('#f-numvaca').dispatch_event('change')
    page.wait_for_timeout(100)
    page.select_option('#f-racatouro', 'nelore')
    if page.locator('#f-racavaca').input_value() == '':
        page.select_option('#f-racavaca', 'nelore')
    page.fill('#f-custoreproducao', '46.30')

def insems(page):
    return page.evaluate("() => window.__DB__.reproducao_custos.filter(r=>r.id<900 || r.id>904).map(r=>r.numero_vaca)")

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros = []; avisos = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.recusar = False
    page.on("dialog", lambda d: (avisos.append(d.message), d.dismiss() if (d.type == "confirm" and page.recusar) else d.accept()))
    page.on("console", lambda m: avisos.append(m.text[len("[aviso] "):]) if m.text.startswith("[aviso] ") else None)  # o alert() virou aviso na pagina (07/11/2026)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEpecuaria.html").as_uri())
    page.wait_for_timeout(1200)
    print("\n  AE PECUARIA: QUAL ANIMAL E?")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # 11 -> pergunta entre 11 e 11099 (ES); o macho 11 nao aparece numa vaca
    nova_insem(page, "11")
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(300)
    opcoes = page.locator('[data-escolha-numero]').evaluate_all("els => els.map(e=>e.dataset.escolhaNumero)")
    conf(sorted(opcoes) == ["11", "11099"], "11: pergunta entre a 11 e a 11099 (ES), sem o macho 11", str(opcoes))
    conf("ES" in page.locator('[data-escolher-animal]').inner_text(), "a escolha mostra o nome (ES)")
    conf(insems(page) == [], "nada gravado enquanto a pergunta esta aberta")
    if FOTO: page.screenshot(path=FOTO + "_desktop.png")
    page.locator('[data-escolha-numero="11099"]').click(); page.wait_for_timeout(500)
    conf(insems(page) == ["11099"], "escolheu a 11099: a inseminacao vai para a 11099", str(insems(page)))

    # Voltar e corrigir: nao grava
    nova_insem(page, "11")
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(300)
    page.locator('[data-escolha-voltar]').click(); page.wait_for_timeout(300)
    conf(insems(page) == ["11099"] and page.locator('[data-escolher-animal]').count() == 0,
         "Voltar e corrigir: fecha a pergunta e nao grava", str(insems(page)))
    conf(page.locator('#f-numvaca').count() == 1, "a janela da inseminacao continua aberta para corrigir")

    # 57 = 057 (zero a esquerda nao conta): NAO pergunta, grava na 057 do cadastro
    nova_insem(page, "57")
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(500)
    conf(page.locator('[data-escolher-animal]').count() == 0, "57 com a 057 cadastrada: nao pergunta (zero a esquerda nao conta)")
    conf(insems(page)[-1] == "057", "grava na 057 do cadastro, sem criar a 57", str(insems(page)))
    conf(page.evaluate("() => !state.animais.some(a=>a.numero==='57')"), "nao cadastrou uma vaca 57")

    # digitar 057 vira 57 no campo
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('reproducaoCusto'); render(); }")
    page.wait_for_timeout(100)
    page.locator('#f-numvaca').type("0057")
    conf(page.locator('#f-numvaca').input_value() == "57", "digitar 0057 vira 57 no campo", page.locator('#f-numvaca').input_value())

    # 200: sem parecido -> nao pergunta
    nova_insem(page, "200")
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(500)
    conf(page.locator('[data-escolher-animal]').count() == 0 and insems(page)[-1] == "200",
         "200 (sem numero parecido): grava direto, sem perguntar", str(insems(page)))

    # editar sem mexer no numero: nao pergunta
    page.evaluate("() => { state.modal=null; editDraft=null; render(); }")
    page.evaluate("""() => { const r = state.reproducao.find(x=>x.id===900);
        state.modal={type:'reproducaoCusto'}; editDraft={...r, _editId:900, custo:String(r.custo)}; render(); }""")
    page.wait_for_timeout(150)
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(500)
    conf(page.locator('[data-escolher-animal]').count() == 0, "editar a inseminacao da 11 sem mexer no numero: nao pergunta")

    # diagnostico e parto tambem perguntam
    for tipo, campo in (("diagnosticoGestacional", "#f-numvaca"), ("parto", "#f-numeromae")):
        page.evaluate(f"() => {{ state.modal=null; editDraft=null; openNewModal('{tipo}'); render(); }}")
        page.wait_for_timeout(100)
        page.select_option('#f-lote', '6'); page.fill('#f-data', '2026-10-19')
        page.fill(campo, "11")
        page.locator(f'[data-save="{tipo}"]').click(); page.wait_for_timeout(300)
        conf(page.locator('[data-escolher-animal]').count() == 1, f"{tipo}: o numero 11 tambem pergunta qual animal e")
        page.locator('[data-escolha-voltar]').click(); page.wait_for_timeout(150)

    # boi 001 de lote encerrado nao entra na escolha do bezerro 1 (Alice)
    conf(page.evaluate("() => precisaEscolherAnimal('1', 'macho')") is False,
         "macho 1 (Alice) x boi 001 de lote encerrado: nao pergunta, o boi encerrado fica fora")

    # ===== regra das 3 IATF (contagem zera no parto) =====
    c = page.evaluate("() => cicloReprodutivoVaca('300', '2026-10-19')")
    conf(c["crias"] == 2 and c["ultimoParto"]["data"] == "2026-07-01" and len(c["inseminacoesDesdeParto"]) == 3 and c["proxima"] == 4,
         "vaca 300: 2 crias, ultimo parto 01/07/2026, 3 IA depois dele (a de junho, antes do parto, nao conta) -> proxima e a 4a", str(c))
    c2 = page.evaluate("() => cicloReprodutivoVaca('300', '2026-08-15')")
    conf(c2["proxima"] == 2, "na data de 15/08/2026 a proxima seria a 2a", str(c2["proxima"]))
    c3 = page.evaluate("() => cicloReprodutivoVaca('11', '2026-10-25')")
    conf(c3["crias"] == 0 and c3["ultimoParto"] is None, "vaca sem parto: 0 crias, conta todas as IA")

    nova_insem(page, "300")
    conf(page.locator('#f-qualinsem').input_value() == "4", "numero 300: o app preenche '4a (fora da regra)'", page.locator('#f-qualinsem').input_value())
    texto = page.locator('[data-ciclo-vaca]').inner_text()
    conf("2 crias" in texto and "descarte" in texto, "a janela mostra crias, IA desde o parto e o aviso de descarte", texto)
    antes = len(insems(page))
    avisos.clear(); page.recusar = True
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(400)
    conf(any("descarte" in a for a in avisos) and len(insems(page)) == antes,
         "4a inseminacao: o app avisa; respondendo Cancelar nao grava", str(avisos)[:200])
    page.recusar = False; avisos.clear()
    page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(500)
    conf(len(insems(page)) == antes + 1 and page.evaluate("() => window.__DB__.reproducao_custos.at(-1).qual_inseminacao") == "4",
         "respondendo OK grava a 4a (so avisa, nao bloqueia)")

    nova_insem(page, "200")
    conf(page.locator('#f-qualinsem').input_value() == "2", "vaca 200 (ja tem 1 IA hoje, sem parto): o app preenche 2a",
         page.locator('#f-qualinsem').input_value())
    page.evaluate("() => { state.modal=null; editDraft=null; render(); }")

    if FOTO:
        page.set_viewport_size({"width": 390, "height": 844})
        nova_insem(page, "11")
        page.locator('[data-save="reproducaoCusto"]').click(); page.wait_for_timeout(300)
        page.screenshot(path=FOTO + "_celular.png")
        page.locator('[data-escolha-voltar]').click()

    conf(not erros, "nenhum erro de JavaScript no caminho", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
