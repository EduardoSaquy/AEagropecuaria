"""
Avisos na pagina no lugar do alert() do AE Pecuaria (revisao geral de 05/11/2026, achado 7: 137 alert() travavam a tela do campo).
Prova:
  - alert() nao abre mais a janela do navegador: vira um aviso na tela e o codigo seguinte roda na hora (nao trava);
  - o aviso vai para window.__AVISOS__ e para o console ("[aviso] ...") (por onde os testes leem);
  - o aviso comum some sozinho; o de erro ("Nao foi possivel...", "Erro...", "Falha...") fica ate fechar;
  - o texto entra como TEXTO (HTML digitado aparece escrito, nao executa) e a quebra de linha e mantida;
  - botao de fechar e a tecla Esc fecham; no maximo 4 avisos de uma vez;
  - o aviso nao some quando a tela e redesenhada (fica fora do #root), aparece no topo e acima de uma janela aberta;
  - no toque o botao de fechar tem 44 px; confirm() continua sendo a janela do navegador (pergunta que precisa de resposta);
  - um aviso de verdade do app (campo obrigatorio vazio) aparece como aviso na tela.
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
HOJE = date.today()
dia = lambda n: (HOJE - timedelta(days=n)).isoformat()
DB = {
    "lotes": [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 60, "data_inicio": dia(80), "data_fim": None, "dieta_id": 1, "sexo": "macho"}],
    "dietas": [{"id": 1, "nome": "Terminacao", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": False}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.2, "estoque_kg": 5000}],
    "animais": [], "pesagens": [], "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "reproducao_custos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [], "producoes_racao": [], "abates": [], "precos_arroba": [], "movimentos": [], "manejos": [], "fazendas": [],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [], "config_financeiro": [], "funcionarios": [], "pesagens_animais": [],
    "protocolos_inseminacao": [], "profiles": [ADMIN],
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


def abre(browser, w=1280, h=800, toque=False):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.nativos = []
    page.consoles = []
    page.on("dialog", lambda d: (page.nativos.append((d.type, d.message)), d.accept()))
    page.on("console", lambda m: page.consoles.append(m.text) if m.text.startswith("[aviso] ") else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lotes && state.lotes.length > 0", timeout=30000)
    page.wait_for_timeout(500)
    return page


def avisos_na_tela(page):
    return page.evaluate("() => [...document.querySelectorAll('#avisos .aviso')].map(e => ({classe: e.className, papel: e.getAttribute('role'), texto: e.querySelector('.aviso-texto').textContent}))")


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = abre(browser)

    print("== alert() virou aviso na tela")
    r = page.evaluate("() => { alert('Salvo com sucesso.'); window.__depois = 'rodou'; return window.__depois; }")
    conf(r == "rodou", "o codigo depois do alert() roda na hora (nao trava)")
    conf(page.nativos == [], "nenhuma janela nativa abriu", str(page.nativos))
    av = avisos_na_tela(page)
    conf(len(av) == 1 and av[0]["texto"] == "Salvo com sucesso." and "aviso-info" in av[0]["classe"], "o aviso aparece na tela, como informacao", str(av))
    conf(av[0]["papel"] == "status", "informacao anunciada como status (leitor de tela)", str(av))
    conf(page.evaluate("() => window.__AVISOS__.length") == 1 and "[aviso] Salvo com sucesso." in page.consoles, "vai para window.__AVISOS__ e para o console")
    caixa = page.evaluate("() => { const b = document.getElementById('avisos').getBoundingClientRect(); return {topo: Math.round(b.top), z: getComputedStyle(document.getElementById('avisos')).zIndex}; }")
    conf(caixa["topo"] <= 20 and int(caixa["z"]) > 1000, "aparece no topo, acima de tudo", str(caixa))

    print("== some sozinho, menos o de erro")
    page.evaluate("() => { TEMPO_AVISO_MS = 200; document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); alert('Aviso comum.'); alert('Não foi possível salvar: sem rede.'); }")
    page.wait_for_timeout(1500)
    av = avisos_na_tela(page)
    conf(len(av) == 1 and "aviso-erro" in av[0]["classe"] and av[0]["papel"] == "alert", "o aviso comum sumiu sozinho e o de erro ficou (role=alert)", str(av))
    for texto, erro in (("Erro ao gravar", True), ("Falha na conexão", True), ("Ocorreu um erro ao abrir esta janela", True), ("Os dados não carregaram (x)", True),
                        ("Preencha o campo \"Lote\" antes de salvar.", False), ("Selecione o lote.", False)):
        page.evaluate("(t) => alert(t)", texto)
        cls = page.evaluate("() => document.querySelector('#avisos .aviso:last-child').className")
        conf(("aviso-erro" in cls) == erro, f"\"{texto[:34]}\" e tratado como {'erro' if erro else 'aviso comum'}")

    print("== texto seguro e quebra de linha")
    page.evaluate("() => document.querySelectorAll('#avisos .aviso').forEach(e => e.remove())")
    page.evaluate("() => { window.__x = 0; alert('<img src=x onerror=\"window.__x=1\">\\n\\nSegunda linha'); }")
    page.wait_for_timeout(300)
    conf(page.evaluate("() => window.__x") == 0 and page.evaluate("() => document.querySelectorAll('#avisos img').length") == 0, "HTML digitado nao executa nem vira elemento")
    av = avisos_na_tela(page)
    conf("<img src=x" in av[0]["texto"] and "Segunda linha" in av[0]["texto"], "aparece escrito, como texto", str(av))
    conf(page.evaluate("() => getComputedStyle(document.querySelector('#avisos .aviso-texto')).whiteSpace") == "pre-line", "a quebra de linha da mensagem e mantida")

    print("== fechar")
    page.evaluate("() => { document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); alert('Não foi possível um'); alert('Não foi possível dois'); }")
    page.locator("#avisos .aviso-fechar").first.click()
    conf(len(avisos_na_tela(page)) == 1, "o botao × fecha o aviso")
    page.keyboard.press("Escape")
    conf(len(avisos_na_tela(page)) == 0, "Esc fecha o ultimo aviso")
    page.evaluate("() => { for (let i = 1; i <= 7; i++) alert('Não foi possível ' + i); }")
    conf(len(avisos_na_tela(page)) == 4 and avisos_na_tela(page)[-1]["texto"].endswith("7"), "no maximo 4 avisos ao mesmo tempo (os mais novos ficam)")
    page.evaluate("() => document.querySelectorAll('#avisos .aviso').forEach(e => e.remove())")

    print("== convive com a tela")
    page.evaluate("() => alert('Não foi possível guardar')")
    page.evaluate("() => { state.page = 'lotes'; render(); }")
    page.wait_for_timeout(200)
    conf(len(avisos_na_tela(page)) == 1, "redesenhar a tela nao apaga o aviso (fica fora do #root)")
    page.evaluate("() => { state.modal = {type:'lote'}; editDraft = {}; render(); }")
    page.wait_for_timeout(250)
    topo = page.evaluate("""() => { const a = document.querySelector('#avisos .aviso'); const b = a.getBoundingClientRect();
        const el = document.elementFromPoint(b.left + 20, b.top + 10); return !!el && !!el.closest('#avisos'); }""")
    conf(topo, "com uma janela aberta o aviso continua por cima dela")
    page.evaluate("() => { state.modal = null; render(); document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); }")

    print("== confirm() continua nativo")
    page.evaluate("() => { window.__c = confirm('Excluir mesmo?'); }")
    conf(page.nativos and page.nativos[-1] == ("confirm", "Excluir mesmo?"), "confirm() abre a janela do navegador e espera a resposta", str(page.nativos))

    print("== um aviso de verdade do app")
    page.nativos.clear()
    page.evaluate("() => { document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); state.carregouDados = false; openNewModal('saidaRacaoCria'); }")
    page.wait_for_timeout(300)
    av = avisos_na_tela(page)
    conf(page.nativos == [] and len(av) == 1 and "carregando" in av[0]["texto"],
         "lancar enquanto os dados carregam: o app avisa na tela, sem janela nativa", str(av) + str(page.nativos))
    page.context.close()

    print("== toque")
    page = abre(browser, 820, 1180, True)
    page.evaluate("() => alert('Não foi possível testar o toque')")
    h = page.evaluate("() => { const b = document.querySelector('.aviso-fechar').getBoundingClientRect(); return [Math.round(b.height), Math.round(b.width)]; }")
    conf(h[0] >= 44 and h[1] >= 44, "o botao de fechar tem pelo menos 44 px no toque", str(h))
    lateral = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(lateral <= 1, "o aviso nao faz a pagina rolar de lado (%d px)" % lateral)
    page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
