"""
Avisos na pagina no lugar do alert() nos apps Matriz, Cana, Cereais e Combustivel (07/11/2026; a Pecuaria ja tinha, ver
teste_avisos_pecuaria.py). O alert() do navegador travava a tela ate a pessoa tocar em OK e tinha a cara do navegador.
Prova, em cada um dos quatro apps:
  - alert() nao abre mais a janela do navegador: vira um aviso na tela e o codigo seguinte roda na hora (nao trava);
  - o aviso vai para window.__AVISOS__ e para o console ("[aviso] ...") (por onde os testes leem);
  - aparece no topo, acima de tudo; o aviso comum some sozinho; o de erro ("Nao foi possivel...", "Erro...") fica ate fechar;
  - o texto entra como TEXTO (HTML digitado aparece escrito, nao executa) e a quebra de linha e mantida;
  - o botao × e a tecla Esc fecham; no maximo 4 avisos de uma vez;
  - redesenhar a tela nao apaga o aviso; confirm() continua sendo a janela do navegador;
  - no toque o botao de fechar tem 44 px e o aviso nao faz a pagina rolar de lado.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}

DB_MATRIZ = {
    "fazendas": [{"id": 1, "nome": "Fazenda A", "estado": "GO", "area_ha": 300, "ativo": True}],
    "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [{"id": 9, "fazenda_id": None, "nome": "Manutencao", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "DESPESAS | Manutencao"}],
    "equipamentos": [], "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [], "entidades": [], "contas_bancarias": [],
    "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
}
DB_LAVOURA = {
    "fazendas": [{"id": 1, "nome": "Faz A", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 100}, {"id": 2, "fazenda_id": 1, "atividade": "graos", "area_ha": 100}],
    "culturas": [{"id": 10, "nome": "Cana", "frente": "cana", "ativo": True}, {"id": 11, "nome": "Soja", "frente": "graos", "ativo": True}],
    "safras": [], "talhoes_areas": [], "plantios_cana": [], "plantios_graos": [], "colheitas_cana": [], "colheitas_graos": [],
    "insumos_cana": [], "insumos_graos": [], "entradas_insumo_cana": [], "entradas_insumo_graos": [], "aplicacoes_cana": [], "aplicacoes_graos": [],
    "profiles": [ADMIN],
}
DB_COMB = {
    "fazendas": [{"id": 1, "nome": "Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}],
    "tanques": [{"id": 1, "fazenda_id": 1, "nome": "Tanque 1", "produto_id": 1, "capacidade_litros": 10000, "tipo": "fixo", "ativo": True}],
    "entradas_estoque": [], "equipamentos": [], "abastecimentos": [], "manutencoes": [], "lancamentos_financeiros": [],
    "produtos": [{"id": 1, "nome": "Diesel S10", "unidade": "L", "ativo": True}], "fornecedores": [{"id": 1, "nome": "Posto", "ativo": True}],
    "operadores": [], "profiles": [ADMIN],
}
APPS = (("AEMatriz.html", DB_MATRIZ), ("AECana.html", DB_LAVOURA), ("AECereais.html", DB_LAVOURA), ("AECombustivel.html", DB_COMB))

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, arquivo, db, w=1280, h=800, toque=False):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.nativos = []
    page.consoles = []
    page.erros = []
    page.on("dialog", lambda d: (page.nativos.append((d.type, d.message)), d.accept()))
    page.on("console", lambda m: page.consoles.append(m.text) if m.text.startswith("[aviso] ") else None)
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil", timeout=30000)
    page.wait_for_timeout(900)
    return page


def avisos_na_tela(page):
    return page.evaluate("() => [...document.querySelectorAll('#avisos .aviso')].map(e => ({classe: e.className, papel: e.getAttribute('role'), texto: e.querySelector('.aviso-texto').textContent}))")


def limpa(page):
    page.evaluate("() => document.querySelectorAll('#avisos .aviso').forEach(e => e.remove())")


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arquivo, db in APPS:
        print(f"\n== {arquivo}")
        page = abre(browser, arquivo, db)
        conf(not page.erros, "abre sem erro de JavaScript", " | ".join(page.erros[:3]))

        r = page.evaluate("() => { alert('Salvo com sucesso.'); window.__depois = 'rodou'; return window.__depois; }")
        conf(r == "rodou", "o codigo depois do alert() roda na hora (nao trava)")
        conf(page.nativos == [], "nenhuma janela nativa abriu", str(page.nativos))
        av = avisos_na_tela(page)
        conf(len(av) == 1 and av[0]["texto"] == "Salvo com sucesso." and "aviso-info" in av[0]["classe"] and av[0]["papel"] == "status",
             "o aviso aparece na tela, como informacao (role=status)", str(av))
        conf(page.evaluate("() => window.__AVISOS__.length") == 1 and "[aviso] Salvo com sucesso." in page.consoles, "vai para window.__AVISOS__ e para o console")
        caixa = page.evaluate("() => { const b = document.getElementById('avisos').getBoundingClientRect(); return {topo: Math.round(b.top), z: getComputedStyle(document.getElementById('avisos')).zIndex}; }")
        conf(caixa["topo"] <= 20 and int(caixa["z"]) > 1000, "aparece no topo, acima de tudo", str(caixa))

        page.evaluate("() => { TEMPO_AVISO_MS = 200; document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); alert('Aviso comum.'); alert('Não foi possível salvar: sem rede.'); }")
        page.wait_for_timeout(1500)
        av = avisos_na_tela(page)
        conf(len(av) == 1 and "aviso-erro" in av[0]["classe"] and av[0]["papel"] == "alert", "o aviso comum some sozinho e o de erro fica (role=alert)", str(av))
        for texto, erro in (("Erro ao gravar", True), ("Falha na conexão", True), ("Preencha o campo \"Valor\" antes de salvar.", False)):
            page.evaluate("(t) => alert(t)", texto)
            cls = page.evaluate("() => document.querySelector('#avisos .aviso:last-child').className")
            conf(("aviso-erro" in cls) == erro, f"\"{texto[:34]}\" e tratado como {'erro' if erro else 'aviso comum'}")
        limpa(page)

        page.evaluate("() => { window.__x = 0; alert('<img src=x onerror=\"window.__x=1\">\\n\\nSegunda linha'); }")
        page.wait_for_timeout(300)
        conf(page.evaluate("() => window.__x") == 0 and page.evaluate("() => document.querySelectorAll('#avisos img').length") == 0, "HTML digitado nao executa nem vira elemento")
        conf("<img src=x" in avisos_na_tela(page)[0]["texto"], "aparece escrito, como texto")
        conf(page.evaluate("() => getComputedStyle(document.querySelector('#avisos .aviso-texto')).whiteSpace") == "pre-line", "a quebra de linha da mensagem e mantida")

        page.evaluate("() => { document.querySelectorAll('#avisos .aviso').forEach(e => e.remove()); alert('Não foi possível um'); alert('Não foi possível dois'); }")
        page.locator("#avisos .aviso-fechar").first.click()
        conf(len(avisos_na_tela(page)) == 1, "o botao × fecha o aviso")
        page.keyboard.press("Escape")
        conf(len(avisos_na_tela(page)) == 0, "Esc fecha o ultimo aviso")
        page.evaluate("() => { for (let i = 1; i <= 7; i++) alert('Não foi possível ' + i); }")
        conf(len(avisos_na_tela(page)) == 4 and avisos_na_tela(page)[-1]["texto"].endswith("7"), "no maximo 4 avisos ao mesmo tempo (os mais novos ficam)")
        limpa(page)

        page.evaluate("() => alert('Não foi possível guardar')")
        page.evaluate("() => { render(); }")
        page.wait_for_timeout(250)
        conf(len(avisos_na_tela(page)) == 1, "redesenhar a tela nao apaga o aviso (fica fora do #root)")
        limpa(page)

        page.evaluate("() => { window.__c = confirm('Excluir mesmo?'); }")
        conf(page.nativos and page.nativos[-1] == ("confirm", "Excluir mesmo?"), "confirm() continua sendo a janela do navegador", str(page.nativos))
        conf(not page.erros, "nenhum erro de JavaScript no caminho todo", " | ".join(page.erros[:3]))
        page.context.close()

        page = abre(browser, arquivo, db, 820, 1180, True)
        page.evaluate("() => alert('Não foi possível testar o toque')")
        h = page.evaluate("() => { const b = document.querySelector('.aviso-fechar').getBoundingClientRect(); return [Math.round(b.height), Math.round(b.width)]; }")
        conf(h[0] >= 44 and h[1] >= 44, "no toque o botao de fechar tem pelo menos 44 px", str(h))
        lateral = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(lateral <= 1, "o aviso nao faz a pagina rolar de lado (%d px)" % lateral)
        page.context.close()

        page = abre(browser, arquivo, db, 360, 740, True)
        page.evaluate("() => { alert('Não foi possível salvar: sem conexão com a internet.\\nO lançamento não foi gravado.'); }")
        caixa = page.evaluate("() => { const b = document.querySelector('#avisos .aviso').getBoundingClientRect(); return [Math.round(b.left), Math.round(b.right), window.innerWidth]; }")
        conf(caixa[0] >= 0 and caixa[1] <= caixa[2], "no celular de 360 px o aviso cabe inteiro na largura da tela", str(caixa))
        page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
