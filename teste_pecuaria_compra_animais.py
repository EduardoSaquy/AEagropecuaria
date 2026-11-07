"""
A compra de animais aparece no resultado da Pecuaria (achado da revisao geral de 05/11/2026: o
resultado ignorava `investimento`, e a Pecuaria de 2025/26 mostrava lucro de +R$ 1,0 mi quando, em
caixa, foi -R$ 1,1 mi). O resultado de receita - despesa NAO muda; a compra aparece a parte:
  - Resultados > Operacional > Pecuaria: bloco "Investimentos da Pecuaria" com giro, matriz, a
    classificar e outros (a classe vem do centro de custo), total e RESULTADO DE CAIXA = resultado - total;
  - Resultados > Geral: aviso com o total investido e o resultado de caixa;
  - so a Pecuaria: Cana e Cereais nao ganham o bloco, e investimento de Cana nao entra na conta da Pecuaria;
  - filtro por mes/ano/safra respeitado; periodo sem investimento = sem bloco e sem aviso;
  - o resultado (receita - despesa) continua exatamente o de antes.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}


def centro(i, nome, tipo):
    return {"id": i, "fazenda_id": None, "nome": nome, "frente": None, "ativo": True, "tipo": tipo, "subcategoria": nome}


def lanc(i, tipo, ativ, centro_id, valor, data, desc, **extra):
    return {"id": i, "tipo": tipo, "atividade": ativ, "fazenda_id": None, "centro_custo_id": centro_id, "descricao": desc,
            "valor": valor, "data": data, "mes": data[:7], "fornecedor": "", "areas": [], **extra}


CENTROS = [
    centro(1, "VENDAS DE GADO", "entrada"), centro(2, "ENERGIA", "saida"),
    centro(3, "COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE", "saida"),
    centro(4, "COMPRA DE MATRIZES PARA REPRODUÇÃO", "saida"),
    centro(5, "INVESTIMENTO EM ANIMAIS", "saida"),
    centro(6, "COMPRA DE EQUINOS", "saida"), centro(7, "MAQUINAS E IMPLEMENTOS", "saida"),
]
L = [
    lanc(1, "receita", "pecuaria", 1, 500000, "2025-06-10", "Venda de gado"),
    lanc(2, "despesa", "pecuaria", 2, 100000, "2025-06-12", "Energia"),
    lanc(3, "investimento", "pecuaria", 3, 200000, "2025-03-15", "Compra de bezerros"),       # giro
    lanc(4, "investimento", "pecuaria", 3, 50000, "2025-07-01", "Compra de bezerros 2"),     # giro
    lanc(5, "investimento", "pecuaria", 4, 120000, "2025-06-20", "Compra de matrizes"),      # matriz
    lanc(6, "investimento", "pecuaria", 5, 30000, "2025-06-25", "Compra de animais a mao"),  # a classificar
    lanc(7, "investimento", "pecuaria", 6, 13000, "2025-06-28", "Cavalo"),                   # outro
    lanc(8, "investimento", "cana", 7, 999000, "2025-06-05", "Trator da cana"),              # NAO e da Pecuaria
    lanc(9, "receita", "cana", 1, 70000, "2025-06-06", "Venda de cana"),
    lanc(10, "investimento", "pecuaria", 3, 77000, "2024-02-01", "Compra de 2024"),          # outro ano
]
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": CENTROS, "lancamentos_financeiros": L,
    "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
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


def txt(page, seletor):
    return page.evaluate("(s) => { const e = document.querySelector(s); return e ? e.innerText.replace(/\\s+/g, ' ').trim() : null; }", seletor)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lancamentos && state.lancamentos.length > 0", timeout=30000)
    page.wait_for_function("() => state.resultados.pecuaria && !state.resultados.pecuaria.loading && state.resultados.pecuaria.mensal", timeout=30000)
    page.wait_for_timeout(500)

    def ir(periodo, aba):
        page.evaluate("([p, a]) => { state.periodo = p; state.page = 'resultados'; state.subAbaResultados = a; render(); }", [periodo, aba])
        page.wait_for_timeout(200)

    print("== Operacional, ano 2025")
    ir({"tipo": "ano", "ano": 2025, "mes": "2025-06", "safra": 2025}, "operacional")
    bloco = txt(page, "[data-bloco-investimentos-pecuaria]")
    conf(bloco is not None, "a Pecuaria ganha o bloco de investimentos")
    # 2025: giro 200.000 + 50.000, matriz 120.000, a classificar 30.000, outros 13.000 = 413.000 (o da cana e o de 2024 ficam fora)
    conf(bloco and "R$ 250.000,00" in bloco and "Compra de animais de giro" in bloco, "giro de 2025 = R$ 250.000,00", bloco)
    conf(bloco and "Compra de matrizes R$ 120.000,00" in bloco, "matriz = R$ 120.000,00", bloco)
    conf(bloco and "falta dizer se é matriz ou giro R$ 30.000,00" in bloco, "a classificar = R$ 30.000,00", bloco)
    conf(bloco and "Outros investimentos (equinos, consórcio...) R$ 13.000,00" in bloco, "outros = R$ 13.000,00", bloco)
    conf(txt(page, "[data-total-investido-pecuaria]") == "R$ 413.000,00", "total investido = R$ 413.000,00 (sem o trator da cana nem a compra de 2024)",
         str(txt(page, "[data-total-investido-pecuaria]")))
    # resultado = 500.000 - 100.000 = 400.000 ; caixa = 400.000 - 413.000 = -13.000
    conf(txt(page, "[data-resultado-caixa-pecuaria]") == "R$ -13.000,00" or txt(page, "[data-resultado-caixa-pecuaria]") == "-R$ 13.000,00",
         "resultado de caixa = resultado (R$ 400.000,00) - investimentos = -13.000,00", str(txt(page, "[data-resultado-caixa-pecuaria]")))
    conf(page.evaluate("() => document.querySelector('[data-resultado-caixa-pecuaria]').className.includes('alerta')"), "caixa negativo fica em alerta")
    # resultado com o custo dos animais de giro = 400.000 - 250.000 = 150.000
    conf(txt(page, "[data-resultado-custo-animais-pecuaria]") == "R$ 150.000,00", "resultado com o custo dos animais de giro = R$ 150.000,00",
         str(txt(page, "[data-resultado-custo-animais-pecuaria]")))
    conf(page.evaluate("() => document.querySelector('[data-resultado-custo-animais-pecuaria]').className.includes('bom')"), "e fica em bom (positivo)")
    r = page.evaluate("() => { const x = resultadoOperacaoNoPeriodo('pecuaria'); return {receita: x.receita, despesa: x.despesa, resultado: x.resultado}; }")
    conf(r["receita"] == 500000 and r["despesa"] == 100000 and r["resultado"] == 400000, "o resultado (receita - despesa) continua o de antes", str(r))
    conf(page.evaluate("() => document.querySelectorAll('[data-bloco-investimentos-pecuaria]').length") == 1, "so um bloco (Cana e Cereais nao ganham)")

    print("== Geral, ano 2025")
    ir({"tipo": "ano", "ano": 2025, "mes": "2025-06", "safra": 2025}, "geral")
    aviso = txt(page, "[data-aviso-investimento-pecuaria]")
    conf(aviso is not None and "R$ 413.000,00" in aviso, "aviso com o total investido", str(aviso))
    conf(aviso is not None and ("R$ -13.000,00" in aviso or "-R$ 13.000,00" in aviso), "aviso com o resultado de caixa da Pecuaria", str(aviso))
    conf(aviso is not None and "R$ 150.000,00" in aviso and "custo dos animais de giro" in aviso, "aviso com o resultado com o custo dos animais de giro", str(aviso))

    print("== outros periodos")
    ir({"tipo": "mes", "ano": 2025, "mes": "2025-06", "safra": 2025}, "operacional")
    # junho/2025: matriz 120.000 + a classificar 30.000 + outro 13.000 = 163.000 ; resultado 400.000 -> caixa 237.000
    conf(txt(page, "[data-total-investido-pecuaria]") == "R$ 163.000,00", "mes 2025-06: total R$ 163.000,00", str(txt(page, "[data-total-investido-pecuaria]")))
    conf(txt(page, "[data-resultado-caixa-pecuaria]") == "R$ 237.000,00", "mes 2025-06: caixa R$ 237.000,00", str(txt(page, "[data-resultado-caixa-pecuaria]")))
    conf(page.evaluate("() => document.querySelector('[data-resultado-caixa-pecuaria]').className.includes('bom')"), "caixa positivo fica em bom")
    conf(txt(page, "[data-resultado-custo-animais-pecuaria]") is None, "mes sem compra de giro: sem o cartao do custo dos animais")
    ir({"tipo": "mes", "ano": 2025, "mes": "2025-01", "safra": 2024}, "operacional")
    conf(txt(page, "[data-bloco-investimentos-pecuaria]") is None, "mes sem investimento: sem bloco")
    ir({"tipo": "mes", "ano": 2025, "mes": "2025-01", "safra": 2024}, "geral")
    conf(txt(page, "[data-aviso-investimento-pecuaria]") is None, "mes sem investimento: sem aviso")
    # safra 2024/25 = maio/2024 a abril/2025: so a compra de bezerros de 15/03/2025 (200.000)
    ir({"tipo": "safra", "ano": 2025, "mes": "2025-06", "safra": 2024}, "operacional")
    conf(txt(page, "[data-total-investido-pecuaria]") == "R$ 200.000,00", "safra 2024/25: total R$ 200.000,00", str(txt(page, "[data-total-investido-pecuaria]")))

    print("== o dado novo nao quebra nada")
    conf(not erros, "sem erro de JS", "; ".join(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
