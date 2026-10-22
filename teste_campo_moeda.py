"""
Campos de dinheiro do AE Matriz com ponto de milhar e virgula enquanto digita
(pedido do Eduardo em 22/10/2026: "nos campos financeiro coloque o
preenchimento financeiro ja colocando pontos e virgulas").

O campo (data-moeda) mostra 1.234.567,89, mas el.value devolve "1234567.89",
como o campo numerico devolvia: o resto do app le e grava igual. Prova:
  - digitar 560000 mostra 560.000; ao sair do campo vira 560.000,00;
  - virgula e ponto digitados viram os centavos (teclado do celular);
  - apagar no meio reagrupa os pontos;
  - valor que ja vem gravado aparece formatado (560.000,00);
  - so 2 casas depois da virgula;
  - salvar grava o numero certo (financiamento e lancamento).
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [{"id": 9, "fazenda_id": None, "nome": "Energia", "ativo": True, "tipo": "saida",
                       "subcategoria": "DESPESAS OPERACIONAIS | Energia"}],
    "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [],
    "profiles": [ADMIN],
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


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    print("\n  CAMPOS DE DINHEIRO (ponto e virgula ao digitar)")
    tela = lambda sel: page.eval_on_selector(sel, "e => Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').get.call(e)")
    valor = lambda sel: page.eval_on_selector(sel, "e => e.value")

    page.evaluate("() => { state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    campo = '#f-principalfin'

    page.click(campo)
    page.keyboard.type("560000")
    conf(tela(campo) == "560.000", "digitar 560000 mostra 560.000", tela(campo))
    conf(valor(campo) == "560000", "e o valor lido pelo app e 560000", valor(campo))
    page.click('#f-bancofin')
    conf(tela(campo) == "560.000,00", "ao sair do campo completa os centavos: 560.000,00", tela(campo))

    page.fill(campo, "")
    page.click(campo)
    page.keyboard.type("1234567,8")
    conf(tela(campo) == "1.234.567,8", "virgula digitada: 1.234.567,8", tela(campo))
    conf(valor(campo) == "1234567.8", "valor lido 1234567.8", valor(campo))
    page.keyboard.type("95")
    conf(tela(campo) == "1.234.567,89", "so 2 casas depois da virgula", tela(campo))

    page.fill(campo, "")
    page.click(campo)
    page.keyboard.type("2500.5")
    conf(tela(campo) == "2.500,5", "ponto digitado (teclado do celular) vira a virgula dos centavos", tela(campo))
    conf(valor(campo) == "2500.5", "valor lido 2500.5", valor(campo))

    page.fill(campo, "")
    page.click(campo)
    page.keyboard.type("560000")
    page.keyboard.press("ArrowLeft")
    page.keyboard.press("ArrowLeft")
    page.keyboard.press("ArrowLeft")
    page.keyboard.press("Backspace")
    conf(tela(campo) == "56.000", "apagar no meio reagrupa: 560.000 -> 56.000", tela(campo))
    page.keyboard.type("9")
    conf(tela(campo) == "569.000", "e digitar no meio continua no lugar certo: 569.000", tela(campo))

    page.fill(campo, "100000.5")
    conf(tela(campo) == "100.000,5" and valor(campo) == "100000.5", "valor colado com ponto decimal (100000.5)", tela(campo))

    # salvar grava o numero
    page.fill(campo, "")
    page.click(campo)
    page.keyboard.type("240000")
    page.fill('#f-bancofin', 'Banco Moeda')
    page.select_option('#f-atividadefin', 'graos')
    page.fill('#f-datafin', '2025-11-15')
    page.fill('#f-taxafin', '9')
    page.fill('#f-numparcelasfin', '3')
    page.fill('#f-vencfin', '2026-11-15')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)
    row = page.evaluate("() => window.__DB__.financiamentos.find(f=>f.banco==='Banco Moeda')")
    conf(row and row["valor_principal"] == 240000, "financiamento grava valor_principal = 240000", str(row and row["valor_principal"]))

    # valor que ja vem gravado aparece formatado
    page.locator(f'[data-editar-financiamento="{row["id"]}"]').click()
    page.wait_for_timeout(300)
    conf(tela(campo) == "240.000,00", "ao editar, o valor gravado aparece 240.000,00", tela(campo))
    page.locator('[data-close="1"]').first.click()
    page.wait_for_timeout(200)

    # lancamento: digitado com ponto e virgula, grava numero
    page.evaluate("""() => {
      state.page='financeiro'; state.abaFinanceiro='despesa'; state.erroLancamento='';
      editDraft = {tipo:'despesa', atividade:'cana', fazendaId:'', centroCustoId:9, descricao:'Conta de luz',
                   valor:'', data:'2026-10-20', areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""")
    page.wait_for_timeout(300)
    page.click('#f-valorlanc')
    page.keyboard.type("12345,67")
    conf(tela('#f-valorlanc') == "12.345,67", "lancamento mostra 12.345,67", tela('#f-valorlanc'))
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    lanc = page.evaluate("() => window.__DB__.lancamentos_financeiros.find(l=>l.descricao==='Conta de luz')")
    conf(lanc and abs(float(lanc["valor"]) - 12345.67) < 0.001, "lancamento grava valor = 12345.67", str(lanc and lanc["valor"]))

    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
