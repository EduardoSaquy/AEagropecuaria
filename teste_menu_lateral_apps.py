"""
Menu lateral nos outros quatro apps (pedido do Eduardo, 07/11/2026, depois de aprovar o do AE Matriz): AE Pecuaria, AE Cana e AE
Cereais ganham a coluna a esquerda a partir de 1280 px (menu principal grande, usuario, "← Painel", Trocar senha e Sair no
rodape); de 760 a 1279 px a barra de cima fica, com o menu maior; no celular nada muda. O AE Combustivel ja tinha barra lateral
(azul): ficou com o menu maior e o usuario embaixo, como os outros. Prova:
  - em 1280 e 1440 px a barra e uma coluna a esquerda de ~232 px (Combustivel 244), o conteudo ao lado, o menu grande;
  - usuario, "← Painel" (aponta para o AE Matriz), Trocar senha e Sair aparecem inteiros na tela, nos tres apps de grade e no
    Combustivel, e os botoes continuam com os mesmos atributos (data-logout, data-trocar-senha-abrir);
  - a marca (que era verde escuro sobre verde escuro) aparece em cor clara;
  - em 1180 px a barra de cima fica, com o menu maior (letra de 15 px ou mais);
  - no celular (390 px) a barra de cima segue como era.
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
DB_VAZIO = {"profiles": [ADMIN]}
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, arq, db, w, h, toque):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / arq))
    page.wait_for_function("() => document.querySelector('.nav-item') !== null", timeout=30000)
    page.wait_for_timeout(600)
    return page


MEDE = """() => {
  const r = s => { const e = document.querySelector(s); if(!e) return null; const b = e.getBoundingClientRect(); const cs = getComputedStyle(e);
    return {x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height), bottom: Math.round(b.bottom), fonte: parseFloat(cs.fontSize)}; };
  const marca = [...document.querySelectorAll('.brand-mark [stroke], .brand-mark [fill]')].map(e => getComputedStyle(e).stroke + '|' + getComputedStyle(e).fill).join(' ');
  return {tabs: r('.tabsrow'), sidebar: r('.sidebar'), main: r('.main'), nav: r('.nav-item'), sair: r('[data-logout]'), senha: r('[data-trocar-senha-abrir]'),
          painel: r('a.btn-sair'), painelHref: (document.querySelector('a.btn-sair') || {}).getAttribute ? document.querySelector('a.btn-sair').getAttribute('href') : null,
          topbar: r('.topbar'), marca, alturaJanela: window.innerHeight, nNav: document.querySelectorAll('.nav-item').length};
}"""
CLARO = ("rgb(223, 246, 232)", "rgb(116, 198, 157)")

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arq, db in (("AEpecuaria.html", DB_PEC), ("AECana.html", DB_VAZIO), ("AECereais.html", DB_VAZIO)):
        for rotulo, w, h, toque in (("1280x800 toque", 1280, 800, True), ("1440x860 mouse", 1440, 860, False)):
            print(f"== {arq} {rotulo}")
            page = abre(browser, arq, db, w, h, toque)
            m = page.evaluate(MEDE)
            conf(m["tabs"]["x"] == 0 and 220 <= m["tabs"]["w"] <= 250 and m["tabs"]["y"] > 50 - 1, "a barra do menu e uma coluna a esquerda", str(m["tabs"]))
            conf(m["main"]["x"] >= 228 and m["main"]["y"] == 0, "o conteudo fica ao lado, desde o topo", str(m["main"]))
            conf(m["nav"]["fonte"] >= 15 and m["nav"]["h"] >= 46, "o menu e grande (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
            conf(all(m[k] and m[k]["bottom"] <= m["alturaJanela"] for k in ("sair", "senha", "painel")),
                 "Sair, Trocar senha e ← Painel aparecem inteiros na tela", str({k: m[k] for k in ("sair", "senha", "painel")}))
            conf(m["painelHref"] == "./AEMatriz.html", "← Painel aponta para o AE Matriz", str(m["painelHref"]))
            conf(any(c in m["marca"] for c in CLARO), "a marca aparece em cor clara na barra escura", m["marca"][:160])
            page.context.close()
        print(f"== {arq} 1180x820 (tablet menor): barra de cima com o menu maior")
        page = abre(browser, arq, db, 1180, 820, True)
        m = page.evaluate(MEDE)
        conf(m["tabs"]["y"] >= 55 and m["tabs"]["w"] >= 1100, "a barra do menu continua em cima", str(m["tabs"]))
        conf(m["nav"]["fonte"] >= 14.5 and m["nav"]["h"] >= 44, "menu maior (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
        page.context.close()
        print(f"== {arq} 390x800 (celular): como era")
        page = abre(browser, arq, db, 390, 800, True)
        m = page.evaluate(MEDE)
        conf(m["topbar"]["y"] == 0 and m["topbar"]["w"] >= 388, "a barra de cima segue em cima, na largura toda", str(m["topbar"]))
        page.context.close()

    print("== AECombustivel.html (barra lateral azul ja existente, agora com o menu maior)")
    for rotulo, w, h, toque in (("1280x800 toque", 1280, 800, True), ("1440x860 mouse", 1440, 860, False)):
        page = abre(browser, "AECombustivel.html", DB_VAZIO, w, h, toque)
        m = page.evaluate(MEDE)
        conf(m["sidebar"]["x"] == 0 and 240 <= m["sidebar"]["w"] <= 250 and m["sidebar"]["h"] == m["alturaJanela"], f"{rotulo}: a barra e uma coluna a esquerda, na altura da tela", str(m["sidebar"]))
        conf(m["nav"]["fonte"] >= 15 and m["nav"]["h"] >= 46, f"{rotulo}: o menu e grande (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
        conf(all(m[k] and m[k]["bottom"] <= m["alturaJanela"] for k in ("sair", "senha", "painel")), f"{rotulo}: Sair, Trocar senha e ← Painel aparecem inteiros", str({k: m[k] for k in ("sair", "senha", "painel")}))
        conf(m["sair"]["y"] > m["nav"]["y"], f"{rotulo}: o usuario fica embaixo do menu")
        page.context.close()
    page = abre(browser, "AECombustivel.html", DB_VAZIO, 390, 800, True)
    m = page.evaluate(MEDE)
    conf(m["sidebar"]["w"] >= 388, "no celular a barra segue em cima, na largura toda", str(m["sidebar"]))
    page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
