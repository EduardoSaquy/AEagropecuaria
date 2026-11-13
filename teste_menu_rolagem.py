"""
O menu lateral nao volta para o topo ao trocar de tela (pedido do Eduardo, 13/11/2026: "no app de pecuaria toda vez que clica em uma
aba na lateral a barra de rolagem vai pra cima sozinha"). Cada app redesenha a tela inteira e o menu novo nascia com a rolagem 0.
Prova, nos cinco apps, numa tela baixa (o menu nao cabe e rola por dentro), com toque e com mouse:
  - rolar o menu ate o fim e tocar num item de baixo: a tela troca e o menu continua rolado onde estava;
  - tocar numa sub-aba (setinha aberta) tambem nao devolve o menu ao topo;
  - quem nao rolou o menu continua com ele no topo.
"""
import json
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
APPS = (("AEpecuaria.html", DB_PEC), ("AEMatriz.html", DB_MATRIZ), ("AECana.html", DB_VAZIO), ("AECereais.html", DB_VAZIO), ("AECombustivel.html", DB_VAZIO))
MENU = "document.querySelector('.tabsrow, .sidebar nav')"
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
    page.wait_for_function("() => document.querySelector('.nav-item') !== null && typeof state !== 'undefined' && state.perfil", timeout=30000)
    page.wait_for_timeout(600)
    return page


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arq, db in APPS:
        for rotulo, w, h, toque in (("iPad deitado 1180x560 (toque)", 1180, 560, True), ("desktop 1440x520 (mouse)", 1440, 520, False)):
            print(f"\n== {arq} {rotulo}")
            page = abre(browser, arq, db, w, h, toque)
            rola = page.evaluate(f"() => {{ const m = {MENU}; return m ? m.scrollHeight - m.clientHeight : -1; }}")
            if rola < 40:
                conf(True, f"menu cabe na tela (sobra {rola} px): nada a provar nesta altura")
                page.context.close()
                continue
            conf(page.evaluate(f"() => {MENU}.scrollTop") == 0, "ao abrir, o menu esta no topo")
            page.evaluate(f"() => {{ const m = {MENU}; m.scrollTop = m.scrollHeight; }}")
            page.wait_for_timeout(200)
            antes = page.evaluate(f"() => {MENU}.scrollTop")
            conf(antes > 0, "o menu foi rolado ate o fim", str(antes))
            pagina_antes = page.evaluate("() => state.page")
            # um item de baixo, visivel, que nao e o da tela atual
            alvo = page.evaluate(f"""() => {{
              const m = {MENU}, r = m.getBoundingClientRect();
              const itens = [...m.querySelectorAll('.nav-item')].filter(b => !b.classList.contains('active'))
                .filter(b => {{ const q = b.getBoundingClientRect(); return q.height > 0 && q.top >= r.top && q.bottom <= r.bottom; }});
              const b = itens[itens.length - 1]; if(!b) return null;
              b.setAttribute('data-alvo-teste', '1'); return b.textContent.trim();
            }}""")
            conf(alvo is not None, "ha um item de baixo visivel para tocar", str(alvo))
            if alvo:
                if toque:
                    page.locator("[data-alvo-teste='1']").tap()
                else:
                    page.locator("[data-alvo-teste='1']").click()
                page.wait_for_timeout(500)
                conf(True, f"tocou em '{alvo}'")
                depois, maximo = page.evaluate(f"() => [{MENU}.scrollTop, {MENU}.scrollHeight - {MENU}.clientHeight]")
                esperado = min(antes, maximo)   # se o menu ficou mais curto (a lista de sub-abas fechou), para no fim dele
                conf(abs(depois - esperado) <= 2, "depois de trocar de tela o menu continua rolado onde estava (nao volta ao topo)", f"antes {antes}, depois {depois}, maximo agora {maximo}")
                # sub-aba aberta pela setinha: tocar nela tambem nao devolve ao topo
                sub = page.evaluate(f"""() => {{
                  const m = {MENU}, r = m.getBoundingClientRect();
                  const b = [...m.querySelectorAll('[data-menu-sub]')].find(x => {{ const q = x.getBoundingClientRect(); return q.height > 0 && q.top >= r.top && q.bottom <= r.bottom && !x.classList.contains('active'); }});
                  if(!b) return null; b.setAttribute('data-sub-teste','1'); return b.getAttribute('data-menu-sub');
                }}""")
                if sub:
                    antes2 = page.evaluate(f"() => {MENU}.scrollTop")
                    page.locator("[data-sub-teste='1']").click()
                    page.wait_for_timeout(500)
                    depois2 = page.evaluate(f"() => {MENU}.scrollTop")
                    conf(abs(depois2 - antes2) <= 2, f"tocar na sub-aba '{sub}' tambem nao devolve o menu ao topo", f"antes {antes2}, depois {depois2}")
                # rolar de volta ao topo e trocar de tela: continua no topo
                page.evaluate(f"() => {{ {MENU}.scrollTop = 0; }}")
                page.wait_for_timeout(200)
                page.locator(".nav-item:not(.active)").first.click()
                page.wait_for_timeout(500)
                conf(page.evaluate(f"() => {MENU}.scrollTop") == 0, "quem voltou o menu ao topo continua com ele no topo depois de trocar de tela")
            page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falharam")
raise SystemExit(1 if falhas else 0)
