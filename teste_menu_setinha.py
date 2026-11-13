"""
Setinha com as sub-abas de cada item do menu (pedido do Eduardo, 08/11/2026: "uma setinha para ter a opcao de clicar nas sub abas
direto"), nos cinco apps (o HTML vem do ItemDoMenu(), em core.js). Prova:
  - cada item do menu que tem 2 ou mais sub-abas ganha uma setinha; item de uma pagina so fica sem;
  - ao abrir o app, a lista do item da tela atual ja esta aberta; a dos outros esta fechada;
  - a setinha de OUTRO item abre a lista dele e fecha a que estava aberta (um por vez), sem trocar de tela;
  - clicar numa sub-aba vai direto para ela (no Matriz: a tela E a aba de dentro dela: Resultados, Financeiro, Pagar/Receber);
  - a setinha do item aberto fecha a lista; o que ficou aberto vale ate fechar o app (nao fica guardado);
  - onde o menu e a barra de cima (tablet em pe) e na barra rolavel dos outros apps no celular a setinha e a lista ficam escondidas
    e a barra se desenha como antes; no celular do Matriz (painel que abre) a setinha funciona e escolher uma sub-aba fecha o painel.
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
HOJE = date.today()
dia = lambda n: (HOJE - timedelta(days=n)).isoformat()
DB_PEC = {
    "lotes": [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 60, "data_inicio": dia(80), "data_fim": None, "dieta_id": 1, "sexo": "macho"}],
    "dietas": [{"id": 1, "nome": "Terminacao", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": False}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.2, "estoque_kg": 5000}],
    "animais": [], "pesagens": [], "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "reproducao_custos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [], "producoes_racao": [], "abates": [], "precos_arroba": [], "movimentos": [], "manejos": [], "fazendas": [],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [], "config_financeiro": [], "funcionarios": [], "pesagens_animais": [],
    "protocolos_inseminacao": [], "profiles": [ADMIN],
}
DB_MATRIZ = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [], "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
}
DB_VAZIO = {"profiles": [ADMIN]}
APPS = (("AEMatriz.html", DB_MATRIZ), ("AEpecuaria.html", DB_PEC), ("AECana.html", DB_VAZIO), ("AECereais.html", DB_VAZIO), ("AECombustivel.html", DB_VAZIO))
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def toque_largo(w):
    return w >= 1160


def abre(browser, arq, db, w, h, toque):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / arq))
    page.wait_for_function("() => document.querySelector('.nav-item') !== null && typeof state !== 'undefined' && state.perfil", timeout=30000)
    page.wait_for_timeout(600)
    return page


GRUPOS = """() => [...document.querySelectorAll('.nav-grupo')].map(g => {
  const seta = g.querySelector('.nav-seta'), sub = g.querySelector('.nav-sub');
  const visivel = e => !!e && getComputedStyle(e).display !== 'none' && e.getBoundingClientRect().height > 0;
  return {chave: seta ? seta.getAttribute('data-nav-seta') : null, aberto: g.classList.contains('aberto'), ativo: g.classList.contains('ativo'),
          expandido: seta ? seta.getAttribute('aria-expanded') : null, setaVisivel: visivel(seta), subVisivel: visivel(sub),
          subs: [...g.querySelectorAll('[data-menu-sub]')].map(b => b.getAttribute('data-menu-sub')), subAtiva: (g.querySelector('.nav-sub-item.active') || {getAttribute: () => null}).getAttribute('data-menu-sub')};
})"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    # Pedido do Eduardo (13/11/2026): ao abrir o Matriz no Painel, a lista de Resultados vinha aberta (ficava guardada no aparelho).
    print("\n== AEMatriz.html: abrir o app no Painel com uma lista guardada de antes")
    ctx0 = browser.new_context(viewport={"width": 1180, "height": 820}, has_touch=True, is_mobile=True)
    p0 = ctx0.new_page()
    p0.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    p0.add_init_script(STUB)
    p0.add_init_script(f"localStorage.setItem('ae_menu_aberto_v1_AE Matriz','resultados'); localStorage.setItem('ae_menu_aberto_v1_AEMatriz','resultados'); window.__DB__ = {json.dumps(DB_MATRIZ)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    p0.goto("file://" + str(REPO / "AEMatriz.html"))
    p0.wait_for_function("() => document.querySelector('.nav-item') !== null && typeof state !== 'undefined' && state.perfil", timeout=30000)
    p0.wait_for_timeout(600)
    g0 = p0.evaluate(GRUPOS)
    conf(p0.evaluate("() => state.page") == "painel", "abre no Painel", p0.evaluate("() => state.page"))
    conf(len(g0) > 0 and not any(g["aberto"] for g in g0), "no Painel nenhuma lista de sub-abas vem aberta", str([g["chave"] for g in g0 if g["aberto"]]))
    conf(p0.evaluate("() => Object.keys(localStorage).filter(k => k.indexOf('ae_menu_aberto_v1_') === 0).length") == 0, "a lista guardada de antes foi apagada do aparelho")
    ctx0.close()
    for arq, db in APPS:
        for rotulo, w, h, toque in (("iPad 1180x820 (toque)", 1180, 820, True), ("desktop 1440x860 (mouse)", 1440, 860, False)):
            print(f"== {arq} {rotulo}")
            page = abre(browser, arq, db, w, h, toque)
            g = page.evaluate(GRUPOS)
            conf(len(g) >= 2 and all(len(x["subs"]) >= 2 for x in g), "ha itens com setinha e todos eles tem 2 ou mais sub-abas (%d itens)" % len(g), str(g))
            conf(all(x["setaVisivel"] for x in g), "a setinha aparece em todos eles")
            abertos = [x for x in g if x["aberto"]]
            conf(len(abertos) <= 1 and all(x["subVisivel"] == x["aberto"] for x in g), "no maximo um item aberto, e so o aberto mostra a lista", str(g))
            ativo = next((x for x in g if x["ativo"]), None)
            if ativo:
                conf(ativo["aberto"] and ativo["subVisivel"], "o item da tela atual abre sozinho com a lista a mostra")
            if toque_largo(w):
                cortados = page.evaluate("""() => [...document.querySelectorAll('.nav-linha .nav-item, .nav-grupo > .nav-item')].filter(b => b.scrollWidth > b.clientWidth + 1).map(b => b.textContent.trim())""")
                menores = page.evaluate("""() => [...document.querySelectorAll('.nav-seta, .nav-sub-item')].filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && (r.width < 44 || r.height < 44); }).map(e => e.className)""")
                conf(not cortados, "nenhum nome de item fica cortado pela setinha (%s)" % ", ".join(cortados), str(cortados))
                conf(not menores and (page.evaluate("() => matchMedia('(pointer: coarse)').matches") or True), "a setinha e as sub-abas tem pelo menos 44 px de lado", str(menores))
            # setinha de outro item: abre a lista dele, fecha a outra, nao troca de tela
            outro = next(x for x in g if not x["ativo"])
            pagina_antes = page.evaluate("() => state.page")
            page.locator(f"[data-nav-seta='{outro['chave']}']").click()
            page.wait_for_timeout(200)
            g2 = page.evaluate(GRUPOS)
            o2 = next(x for x in g2 if x["chave"] == outro["chave"])
            conf(o2["aberto"] and o2["subVisivel"] and o2["expandido"] == "true", "a setinha de outro item abre a lista dele", str(o2))
            conf(sum(1 for x in g2 if x["aberto"]) == 1, "so um item fica aberto por vez (a lista que estava aberta fecha)")
            conf(page.evaluate("() => state.page") == pagina_antes, "so abrir a lista nao troca de tela")
            guardado = page.evaluate("() => menuAbertoMemoria")
            conf(guardado == outro["chave"], "o que ficou aberto vale enquanto o app esta aberto", str(guardado))
            # clicar numa sub-aba vai direto
            alvo = o2["subs"][-1]
            page.locator(f"[data-menu-sub='{alvo}']").click()
            page.wait_for_timeout(300)
            pagina_alvo = alvo.split("|")[0]
            conf(page.evaluate("() => state.page") == pagina_alvo, f"clicar na sub-aba '{alvo}' vai direto para a tela dela", str(page.evaluate("() => state.page")))
            g3 = page.evaluate(GRUPOS)
            o3 = next(x for x in g3 if x["chave"] == outro["chave"])
            conf(o3["ativo"] and o3["subAtiva"] == alvo, "o item vira o da tela atual e a sub-aba fica marcada", str(o3))
            if arq == "AEMatriz.html":
                for valor, verifica in (("resultados|empresa", "state.page === 'resultados' && state.subAbaResultados === 'empresa'"),
                                        ("financeiro|investimento", "state.page === 'financeiro' && state.abaFinanceiro === 'investimento'"),
                                        ("contas|receber", "state.page === 'contas' && state.abaContas === 'receber'")):
                    chave = valor.split("|")[0]
                    if page.locator(f"[data-menu-sub='{valor}']:visible").count() == 0:
                        page.locator(f"[data-nav-seta='{chave}']").click()
                        page.wait_for_timeout(150)
                    page.locator(f"[data-menu-sub='{valor}']").click()
                    page.wait_for_timeout(300)
                    conf(page.evaluate(f"() => {verifica}"), f"Matriz: '{valor}' escolhe a tela E a aba de dentro dela")
                    conf(page.locator(f"[data-menu-sub='{valor}'].active").count() == 1, f"Matriz: a sub-aba '{valor}' fica marcada no menu")
            # a setinha do item aberto fecha a lista
            aberto = next(x for x in page.evaluate(GRUPOS) if x["aberto"])
            page.locator(f"[data-nav-seta='{aberto['chave']}']").click()
            page.wait_for_timeout(200)
            g4 = page.evaluate(GRUPOS)
            conf(not any(x["aberto"] for x in g4), "a setinha do item aberto fecha a lista (nenhum aberto)")
            conf(page.evaluate("() => menuAbertoMemoria") == "", "e o 'tudo fechado' tambem fica guardado")
            # clicar no nome de um item sem lista: continua funcionando e fecha as listas
            page.context.close()

    for arq, db in APPS:
        print(f"== {arq} 1100x800 (barra de cima): setinha e lista escondidas, a barra como antes")
        page = abre(browser, arq, db, 1100, 800, True) if arq == "AECombustivel.html" else abre(browser, arq, db, 1100, 800, True)
        g = page.evaluate(GRUPOS)
        if arq == "AECombustivel.html":
            conf(any(x["setaVisivel"] for x in g), "Combustivel: a barra lateral azul segue de 761 px para cima, entao a setinha aparece")
        else:
            conf(not any(x["setaVisivel"] or x["subVisivel"] for x in g), "a setinha e as listas ficam escondidas")
            caixa = page.evaluate("() => { const t = document.querySelector('.tabsrow'); const b = t.getBoundingClientRect(); return {y: Math.round(b.y), h: Math.round(b.height), w: Math.round(b.width)}; }")
            conf(caixa["y"] >= 55 and caixa["h"] < 140 and caixa["w"] >= 1040, "a barra segue em cima, na largura toda, sem crescer", str(caixa))
            disp = page.evaluate("() => [...new Set([...document.querySelectorAll('.nav-grupo, .nav-linha')].map(e => getComputedStyle(e).display))]")
            conf(disp == ["contents"], "os envoltorios nao criam caixa (display:contents)", str(disp))
        page.context.close()

    for arq, db in APPS[1:4]:
        print(f"== {arq} 390x800 (celular): barra rolavel de lado, sem setinha")
        page = abre(browser, arq, db, 390, 800, True)
        g = page.evaluate(GRUPOS)
        conf(not any(x["setaVisivel"] or x["subVisivel"] for x in g), "a setinha e as listas ficam escondidas")
        conf(page.evaluate("() => document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "a pagina nao rola de lado")
        page.context.close()

    print("== AEMatriz.html 390x800 (celular): painel do menu com a setinha")
    page = abre(browser, "AEMatriz.html", DB_MATRIZ, 390, 800, True)
    page.locator("[data-mobile-nav-toggle]").click()
    page.wait_for_timeout(250)
    g = page.evaluate(GRUPOS)
    conf(len(g) >= 2 and all(x["setaVisivel"] for x in g), "o painel do menu mostra a setinha dos itens com sub-abas", str(g))
    page.locator("[data-nav-seta='resultados']").click()
    page.wait_for_timeout(200)
    r = next(x for x in page.evaluate(GRUPOS) if x["chave"] == "resultados")
    conf(r["aberto"] and r["subVisivel"], "a setinha abre a lista de Resultados no painel")
    page.locator("[data-menu-sub='resultados|relatorios']").click()
    page.wait_for_timeout(300)
    conf(page.evaluate("() => state.page === 'resultados' && state.subAbaResultados === 'relatorios' && state.mobileNavAberto === false"), "escolher a sub-aba vai para ela e fecha o painel do menu")
    conf(page.evaluate("() => document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "a pagina nao rola de lado")
    page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
