"""
Pagamento de parcela de financiamento: data e safra do juros (09/11/2026).

O caso real: o custeio da soja 25/26 venceu e foi pago em 10/07/2026, mas foi marcado
como pago em 09/11/2026 (a janela abria com a data de hoje; o botao rapido usava hoje
sem mostrar). O juros caiu em novembro (custo dos Graos por hectare 10 vezes maior no
mes) e, sem safra, na safra 26/27. Pedido do Eduardo: o app evitar isso.

Prova (hoje = 09/11/2026):
  - parcela ja vencida abre "Registrar pagamento" com a data do VENCIMENTO; a vencer, com hoje;
  - juros de CUSTEIO vem com a safra que o dinheiro financiou (soja 25/26 -> 2025;
    pre-custeio 26/27 -> 2026) e o lancamento grava ano_safra; investimento vem sem safra
    (conta pelo mes); a safra escolhida na tela e a que vale;
  - capital de giro: os 3 lancamentos levam a safra escolhida;
  - data a mais de 30 dias do vencimento mostra aviso na hora; depois do vencimento pede
    confirmacao (cancelar nao grava nada; confirmar grava);
  - "Marcar como paga" numa parcela vencida usa a data do vencimento e a safra do custeio,
    e a pergunta mostra a data e diz que o juros e estimado; a vencer, usa hoje;
  - nenhum erro de JavaScript.
Falha no codigo anterior (data de hoje, sem safra, sem aviso).
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

RELOGIO = """(() => {
  const R = Date, FIXO = new R(2026, 10, 9, 12, 0, 0).getTime();
  class D extends R {
    constructor(...a){ if(a.length === 0) super(FIXO); else super(...a); }
    static now(){ return FIXO; }
  }
  window.Date = D;
})();"""


def fin(i, banco, principal, data, finalidade, atividade):
    return {"id": i, "banco": banco, "finalidade": finalidade, "valor_principal": principal, "valor_iof": 0, "valor_seguro": 0,
            "data_contratacao": data, "taxa_juros_aa": 9.3, "sistema_amortizacao": "parcela_unica", "numero_parcelas": 1,
            "carencia_meses": 0, "atividade": atividade, "fazenda_id": None, "garantia": None, "status": "ativo",
            "financiamento_origem_id": None, "observacao": None}


def parc(i, fid, venc, amort, juros):
    return {"id": i, "financiamento_id": fid, "numero": 1, "data_vencimento": venc, "valor_parcela": amort + juros,
            "valor_amortizacao": amort, "valor_juros": juros, "saldo_devedor_apos": 0, "status": "pendente",
            "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []}


DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "centros_custo": [{"id": 1, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento", "frente": None, "ativo": True,
                       "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS"}],
    "lancamentos_financeiros": [], "movimentos_financiamento": [],
    "financiamentos": [
        fin(1, "Banco Soja", 300000, "2025-08-28", "custeio", "graos"),        # custeio 25/26, ja vencido
        fin(2, "Banco Pre", 100000, "2026-02-19", "custeio", "graos"),         # pre-custeio 26/27, a vencer
        fin(3, "Banco Matrizes", 150000, "2025-10-29", "investimento", "pecuaria"),
        fin(4, "Banco Giro", 90000, "2026-01-15", "capital_giro", None),
        fin(5, "Banco Rapido", 200000, "2025-08-28", "custeio", "graos"),      # botao rapido, ja vencido
        fin(6, "Banco Futuro", 50000, "2026-03-01", "investimento", "pecuaria"),  # botao rapido, a vencer
    ],
    "parcelas_financiamento": [
        parc(11, 1, "2026-07-10", 300000, 23567.26),
        parc(21, 2, "2027-06-10", 100000, 16295.74),
        parc(31, 3, "2026-10-20", 150000, 12000),
        parc(41, 4, "2026-11-05", 90000, 3000),
        parc(51, 5, "2026-07-10", 200000, 18000),
        parc(61, 6, "2027-03-01", 50000, 4000),
    ],
    "profiles": [{"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}],
}

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, dialogos = [], []
    responder = {"aceitar": True}
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: (dialogos.append(d.message), d.accept() if responder["aceitar"] else d.dismiss()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.parcelasFinanciamento && state.parcelasFinanciamento.length === 6",
                           timeout=20000)

    def abrir(fid):
        page.evaluate("(id) => { state.page = 'financiamentos'; state.financiamentoDetalheId = id; state.modal = null; editDraft = null; render(); }", fid)
        page.wait_for_timeout(200)

    def db(t):
        return page.evaluate("(t) => window.__DB__[t]", t)

    def parcela(pid):
        return next(p for p in db("parcelas_financiamento") if p["id"] == pid)

    def lancs_do(banco):
        return [l for l in db("lancamentos_financeiros") if banco in (l.get("descricao") or "")]

    def janela(pid):
        abrir(next(p for p in DB["parcelas_financiamento"] if p["id"] == pid)["financiamento_id"])
        page.click(f'[data-pagamento-parcela="{pid}"]')
        page.wait_for_timeout(200)
        return page.evaluate("""() => ({data: document.getElementById('f-pagdata').value,
            safra: document.getElementById('f-pagsafra') ? document.getElementById('f-pagsafra').value : null,
            aviso: (document.getElementById('f-pag-aviso') || {}).textContent || ''})""")

    print("\n  PAGAMENTO DE PARCELA: DATA E SAFRA DO JUROS")

    # 1. custeio 25/26 ja vencido: abre com o vencimento e a safra 2025
    j = janela(11)
    conf(j["data"] == "2026-07-10", "parcela vencida abre com a data do vencimento (10/07/2026), nao hoje", str(j))
    conf(j["safra"] == "2025", "custeio da soja 25/26 vem com a safra 2025/26", str(j))
    conf(j["aviso"].strip() == "", "na data do vencimento nao ha aviso", j["aviso"])
    # trocar para hoje: aviso na hora
    page.fill("#f-pagdata", "2026-11-09")
    page.dispatch_event("#f-pagdata", "input")
    aviso = page.evaluate("() => document.getElementById('f-pag-aviso').textContent")
    conf("122 dias depois do vencimento" in aviso and "11/2026" in aviso, "data de hoje: aviso de 122 dias depois do vencimento, juros em 11/2026", aviso)
    # salvar com hoje e CANCELAR a confirmacao: nada gravado
    responder["aceitar"] = False
    n = len(dialogos)
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(400)
    conf(len(dialogos) == n + 1 and "122 dias depois do vencimento" in dialogos[-1], "salvar 122 dias depois pede confirmacao", str(dialogos[n:]))
    conf(parcela(11)["status"] == "pendente" and lancs_do("Banco Soja") == [], "cancelar a confirmacao nao grava nada")
    conf(page.locator("#f-pagdata").count() == 1, "a janela continua aberta para corrigir")
    # volta para o vencimento e grava
    responder["aceitar"] = True
    page.fill("#f-pagdata", "2026-07-10")
    page.fill("#f-pagjuros", "23000.00")
    n = len(dialogos)
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    p11 = parcela(11)
    ls = lancs_do("Banco Soja")
    conf(len(dialogos) == n, "na data do vencimento salva sem perguntar", str(dialogos[n:]))
    conf(p11["status"] == "paga" and p11["data_pagamento"] == "2026-07-10", "parcela paga em 10/07/2026", str(p11))
    conf(len(ls) == 1 and ls[0]["data"] == "2026-07-10" and ls[0]["mes"] == "2026-07" and ls[0].get("ano_safra") == 2025
         and abs(ls[0]["valor"] - 23000) < 0.01,
         "o juros vira despesa em 10/07/2026, mes 2026-07, safra 2025, com o valor do extrato", str(ls))

    # 2. pre-custeio 26/27 a vencer: hoje e safra 2026, sem aviso grande? (vence em 2027: e antes do vencimento)
    j = janela(21)
    conf(j["data"] == "2026-11-09", "parcela a vencer abre com a data de hoje", str(j))
    conf(j["safra"] == "2026", "pre-custeio 26/27 (cedula 02/2026, vence 06/2027) vem com a safra 2026/27", str(j))
    conf("dias antes do vencimento" in j["aviso"], "pagar 7 meses antes do vencimento mostra o aviso", j["aviso"])
    page.select_option("#f-pagsafra", "2024")
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    ls = lancs_do("Banco Pre")
    conf(len(ls) == 1 and ls[0].get("ano_safra") == 2024, "a safra escolhida na tela e a que vale (2024)", str(ls))

    # 3. investimento: sem safra, nao manda ano_safra
    j = janela(31)
    conf(j["data"] == "2026-10-20" and j["safra"] == "", "investimento: data do vencimento (ja vencido) e safra em branco", str(j))
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    ls = lancs_do("Banco Matrizes")
    conf(len(ls) == 1 and ls[0].get("ano_safra") is None and ls[0]["data"] == "2026-10-20", "investimento: o juros conta pelo mes (ano_safra vazio)", str(ls))

    # 4. capital de giro: 3 lancamentos com a safra escolhida
    j = janela(41)
    conf(j["data"] == "2026-11-05" and j["safra"] == "", "capital de giro: data do vencimento e safra em branco", str(j))
    page.select_option("#f-pagsafra", "2026")
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    ls = lancs_do("Banco Giro")
    conf(len(ls) == 3 and all(l.get("ano_safra") == 2026 and l["data"] == "2026-11-05" for l in ls),
         "capital de giro: os 3 lancamentos levam a safra escolhida", str(ls))

    # 5. botao rapido numa parcela vencida: data do vencimento, safra do custeio, pergunta clara
    abrir(5)
    n = len(dialogos)
    page.click('[data-pagar-parcela="51"]')
    page.wait_for_timeout(600)
    msg = dialogos[n] if len(dialogos) > n else ""
    conf("10/07/2026" in msg and "estimado" in msg and "Registrar pagamento" in msg,
         "a pergunta do botao rapido mostra a data, diz que o juros e estimado e aponta Registrar pagamento", msg)
    p51 = parcela(51)
    ls = lancs_do("Banco Rapido")
    conf(p51["data_pagamento"] == "2026-07-10" and len(ls) == 1 and ls[0]["data"] == "2026-07-10" and ls[0].get("ano_safra") == 2025,
         "botao rapido em parcela vencida: paga no vencimento, juros em 07/2026 na safra 2025", str((p51, ls)))

    # 6. botao rapido numa parcela a vencer: hoje, sem safra
    abrir(6)
    page.click('[data-pagar-parcela="61"]')
    page.wait_for_timeout(600)
    p61 = parcela(61)
    ls = lancs_do("Banco Futuro")
    conf(p61["data_pagamento"] == "2026-11-09" and len(ls) == 1 and ls[0]["data"] == "2026-11-09" and ls[0].get("ano_safra") is None,
         "botao rapido em parcela a vencer: hoje, sem safra (investimento)", str((p61, ls)))

    # 7. a janela cabe no celular
    page.set_viewport_size({"width": 390, "height": 844})
    janela(21) if parcela(21)["status"] == "pendente" else None
    abrir(2)
    conf(not page.evaluate("() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1"),
         "nada rola de lado no celular")

    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
sys.exit(1 if falhas else 0)
