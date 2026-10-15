"""
Financiamentos: ajustar um contrato depois de lancar (pedido do Eduardo,
15/10/2026: "se tiver algum que ja foi amortizado eu apago ou edito").

O que este teste prova, com contas conhecidas (hoje = 14/10/2026):
  - Registrar pagamento: data e juros reais; o juros so vira despesa (na data do
    pagamento, nao hoje) se marcar; desmarcado, a parcela fica paga sem lancamento;
  - Editar parcela: vencimento e juros sempre; amortizacao so no contrato importado
    do Conag, e ai o saldo devedor de cada parcela e o principal se refazem;
  - Quitar: todas as parcelas em aberto viram pagas na data informada, sem juros,
    o contrato fica quitado e a amortizacao entra no fluxo de caixa dessa data;
  - Editar contrato com cronograma travado (importado ou com parcela paga) nao regera
    as parcelas; no importado, mudar a taxa refaz o juros estimado das em aberto;
  - Cancelar ("apagar") nao apaga historico: so muda o status; as linhas do Conag
    que o contrato tinha assumido voltam; contrato com juros ja lancado nao cancela;
  - a tela do contrato nao rola de lado no celular.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

RELOGIO = """(() => {
  const R = Date, FIXO = new R(2026, 9, 14, 12, 0, 0).getTime();
  class D extends R {
    constructor(...a){ if(a.length === 0) super(FIXO); else super(...a); }
    static now(){ return FIXO; }
  }
  window.Date = D;
})();"""

def fin(i, banco, principal, data, taxa, n, status="ativo", obs=None, atividade="graos", finalidade="custeio", sistema="sac"):
    return {"id": i, "banco": banco, "finalidade": finalidade, "valor_principal": principal, "valor_iof": 0, "valor_seguro": 0,
            "data_contratacao": data, "taxa_juros_aa": taxa, "sistema_amortizacao": sistema, "numero_parcelas": n,
            "carencia_meses": 0, "atividade": atividade, "fazenda_id": None, "garantia": None, "status": status,
            "financiamento_origem_id": None, "observacao": obs}

def parc(i, fid, n, venc, amort, juros, saldo, status="pendente", pago=None, ids=None):
    return {"id": i, "financiamento_id": fid, "numero": n, "data_vencimento": venc, "valor_parcela": amort + juros,
            "valor_amortizacao": amort, "valor_juros": juros, "saldo_devedor_apos": saldo, "status": status,
            "data_pagamento": pago, "valor_pago": (amort + juros) if pago else None,
            "lancamentos_financeiro_ids": ids or []}

def mov(i, data, valor, fid=None):
    return {"id": i, "data": data, "tipo": "amortizacao", "valor": valor, "credor": "BANCO DO BRASIL", "contrato": "[contrato]",
            "descricao": "", "origem": "conag", "conag_id": 1000 + i, "financiamento_id": fid}

OBS_CONAG = ("Importado do Conag (contrato [contrato]): cronograma real, uma parcela por linha do Conag; "
             "juros das parcelas a vencer estimado pela taxa informada.")

DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "centros_custo": [
        {"id": 1, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS"},
    ],
    "lancamentos_financeiros": [],
    "financiamentos": [
        fin(1, "Banco A", 90000, "2026-08-10", 10, 3),                                   # a mao, nada pago
        fin(2, "Banco B", 60000, "2026-03-10", 10, 2),                                   # a mao, juros ja lancado
        fin(3, "Banco do Brasil", 400000, "2024-11-15", 10, 4, obs=OBS_CONAG, atividade="graos", finalidade="custeio"),  # importado
        fin(4, "Banco D", 90000, "2026-09-01", 10, 3),                                   # a mao, para quitar
        fin(5, "Banco E", 50000, "2026-09-01", 10, 1, sistema="parcela_unica"),          # a mao, para cancelar
    ],
    "parcelas_financiamento": [
        parc(1, 1, 1, "2026-11-10", 30000, 1000, 60000),
        parc(2, 1, 2, "2026-12-10", 30000, 1000, 30000),
        parc(3, 1, 3, "2027-01-10", 30000, 1000, 0),
        parc(4, 2, 1, "2026-06-10", 30000, 2000, 30000, status="paga", pago="2026-06-10", ids=[901]),
        parc(5, 2, 2, "2026-12-10", 30000, 1000, 0),
        parc(6, 3, 1, "2025-11-15", 100000, 0, 300000, status="paga", pago="2025-11-15"),
        parc(7, 3, 2, "2026-05-15", 100000, 0, 200000, status="paga", pago="2026-05-15"),
        parc(8, 3, 3, "2026-11-16", 100000, 9999.99, 100000),
        parc(9, 3, 4, "2027-11-15", 100000, 9999.99, 0),
        parc(10, 4, 1, "2026-10-20", 30000, 500, 60000),
        parc(11, 4, 2, "2026-11-20", 30000, 500, 30000),
        parc(12, 4, 3, "2026-12-20", 30000, 500, 0),
        parc(13, 5, 1, "2027-09-01", 50000, 5000, 0),
    ],
    "movimentos_financiamento": [
        mov(1, "2025-11-15", 100000, 3), mov(2, "2026-05-15", 100000, 3),
        mov(3, "2026-11-16", 100000, 3), mov(4, "2027-11-15", 100000, 3),
    ],
    "profiles": [{"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}],
}
DB["lancamentos_financeiros"].append(
    {"id": 901, "tipo": "despesa", "atividade": "graos", "fazenda_id": None, "centro_custo_id": 1,
     "descricao": "Juros - Banco B (parcela 1/2)", "valor": 2000, "data": "2026-06-10", "mes": "2026-06", "areas": []})

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def perto(a, b, tol=0.01):
    return a is not None and abs(a - b) < tol

def juros_est(saldo, taxa, d0, d1):
    from datetime import date
    dias = max(1, (date.fromisoformat(d1) - date.fromisoformat(d0)).days)
    return saldo * ((1 + taxa / 100) ** (dias / 365) - 1)

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page()
    erros, dialogos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: (dialogos.append(d.message), d.accept()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(2500)

    def abrir(fid):
        page.evaluate("(id) => { state.page = 'financiamentos'; state.financiamentoDetalheId = id; state.modal = null; editDraft = null; render(); }", fid)
        page.wait_for_timeout(250)

    def db(tabela):
        return page.evaluate("(t) => window.__DB__[t]", tabela)

    def parcela(pid):
        return next(p for p in db("parcelas_financiamento") if p["id"] == pid)

    def contrato(fid):
        return next(f for f in db("financiamentos") if f["id"] == fid)

    print("\n  FINANCIAMENTOS > AJUSTAR UM CONTRATO")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- 1. a tela do contrato ----
    abrir(1)
    botoes = page.evaluate("""() => ({
        editar: !!document.querySelector('.toolbar [data-editar-financiamento]'), quitar: !!document.querySelector('.toolbar [data-quitar-financiamento]'),
        renegociar: !!document.querySelector('.toolbar [data-renegociar-financiamento]'), cancelar: !!document.querySelector('.toolbar [data-cancelar-financiamento]'),
        porParcela: [...document.querySelectorAll('tbody tr')].map(tr => ['pagar-parcela', 'pagamento-parcela', 'editar-parcela'].filter(a => tr.querySelector('[data-' + a + ']')).length)})""")
    conf(botoes["editar"] and botoes["quitar"] and botoes["renegociar"] and botoes["cancelar"],
         "o contrato mostra Editar, Quitar, Renegociar e Cancelar contrato", str(botoes))
    conf(botoes["porParcela"] == [3, 3, 3], "cada parcela em aberto tem: Marcar como paga, Registrar pagamento e Editar", str(botoes["porParcela"]))

    # ---- 2. registrar pagamento com a data e o juros reais, lancando o juros ----
    page.click('[data-pagamento-parcela="1"]')
    page.wait_for_timeout(250)
    padrao = page.evaluate("""() => ({data: document.getElementById('f-pagdata').value, juros: document.getElementById('f-pagjuros').value,
        lancar: document.getElementById('f-paglancar').checked, titulo: document.querySelector('.modal-head h3').innerText})""")
    conf(padrao["data"] == "2026-10-14" and float(padrao["juros"]) == 1000 and padrao["lancar"] and "parcela 1" in padrao["titulo"],
         "o modal abre com a data de hoje, o juros estimado (R$ 1.000) e 'lancar o juros' marcado", str(padrao))
    page.fill("#f-pagdata", "2026-10-05")
    page.fill("#f-pagjuros", "1234.56")
    antes = len(db("lancamentos_financeiros"))
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    p1 = parcela(1)
    lancs = db("lancamentos_financeiros")
    novo = lancs[-1] if len(lancs) > antes else {}
    conf(p1["status"] == "paga" and p1["data_pagamento"] == "2026-10-05" and perto(p1["valor_juros"], 1234.56) and perto(p1["valor_pago"], 31234.56),
         "parcela 1 paga em 05/10/2026 com o juros real: juros R$ 1.234,56, total pago R$ 31.234,56", str(p1))
    conf(len(lancs) == antes + 1 and novo.get("tipo") == "despesa" and perto(novo.get("valor"), 1234.56) and novo.get("data") == "2026-10-05"
         and novo.get("mes") == "2026-10" and novo.get("centro_custo_id") == 1 and novo.get("atividade") == "graos",
         "o juros virou UMA despesa de R$ 1.234,56 na data do pagamento (05/10), no centro 'Juros e Encargos de Financiamento', atividade graos", str(novo))
    conf(p1["lancamentos_financeiro_ids"] == [novo.get("id")], "a parcela guarda o id do lancamento", str(p1["lancamentos_financeiro_ids"]))
    conf(contrato(1)["status"] == "ativo", "o contrato segue ativo (ainda ha parcelas em aberto)")

    # ---- 3. registrar pagamento SEM lancar o juros ----
    page.click('[data-pagamento-parcela="2"]')
    page.wait_for_timeout(250)
    page.uncheck("#f-paglancar")
    antes = len(db("lancamentos_financeiros"))
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    p2 = parcela(2)
    conf(p2["status"] == "paga" and p2["data_pagamento"] == "2026-10-14" and p2["lancamentos_financeiro_ids"] == []
         and len(db("lancamentos_financeiros")) == antes,
         "desmarcando 'lancar o juros': parcela 2 fica paga (hoje) e nenhum lancamento e criado", str(p2))
    abrir(1)
    texto = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("sem juros lançado pelo app" in texto, "a tela avisa que essa parcela paga ficou sem juros lancado pelo app")

    # ---- 4. editar parcela (contrato a mao: so vencimento e juros) ----
    page.click('[data-editar-parcela="3"]')
    page.wait_for_timeout(250)
    ro = page.evaluate("() => ({amort: document.getElementById('f-parcamort').readOnly, data: document.getElementById('f-parcdata').value, juros: document.getElementById('f-parcjuros').value})")
    conf(ro["amort"] and ro["data"] == "2027-01-10" and float(ro["juros"]) == 1000,
         "contrato lancado a mao: a amortizacao da parcela e so leitura; vencimento e juros editaveis", str(ro))
    page.fill("#f-parcdata", "2027-02-10")
    page.fill("#f-parcjuros", "900")
    page.click('[data-save="parcelaFin"]')
    page.wait_for_timeout(600)
    p3 = parcela(3)
    conf(p3["data_vencimento"] == "2027-02-10" and perto(p3["valor_juros"], 900) and perto(p3["valor_parcela"], 30900) and perto(p3["valor_amortizacao"], 30000),
         "parcela 3: vencimento 10/02/2027, juros R$ 900 e valor da parcela R$ 30.900 (amortizacao intacta)", str(p3))

    # ---- 5. quitar o que ja foi amortizado ----
    abrir(4)
    page.click('[data-quitar-financiamento="4"]')
    page.wait_for_timeout(250)
    texto_q = page.evaluate("() => document.querySelector('.modal-body').innerText.toLowerCase()")
    conf("3 parcela(s) em aberto" in texto_q and "r$ 90.000,00" in texto_q and "nenhum juros é lançado" in texto_q,
         "Quitar explica: 3 parcelas em aberto, R$ 90.000 de principal, nenhum juros lancado", texto_q[:240])
    page.fill("#f-quitdata", "2026-09-30")
    antes = len(db("lancamentos_financeiros"))
    page.click('[data-save="quitarFin"]')
    page.wait_for_timeout(800)
    ps = [parcela(i) for i in (10, 11, 12)]
    conf(all(p["status"] == "paga" and p["data_pagamento"] == "2026-09-30" for p in ps) and contrato(4)["status"] == "quitado",
         "Quitar em 30/09/2026: as 3 parcelas ficam pagas nessa data e o contrato quitado", str([(p["status"], p["data_pagamento"]) for p in ps]))
    conf(len(db("lancamentos_financeiros")) == antes, "e nenhum juros foi lancado no Financeiro")
    set_flux = page.evaluate("() => fluxoEmpresa({tipo:'mes', mes:'2026-09', ano:2026, safra:2026})")
    conf(perto(set_flux["financiamento"]["amortizacao"], 90000),
         "a amortizacao de R$ 90.000 entra no fluxo de caixa de setembro/2026 (a data da quitacao)", str(set_flux["financiamento"]))

    # ---- 6. cancelar ("apagar") ----
    abrir(2)
    n_dialogos = len(dialogos)
    page.click('[data-cancelar-financiamento="2"]')
    page.wait_for_timeout(500)
    conf(contrato(2)["status"] == "ativo" and any("já tem juros lançado" in m for m in dialogos[n_dialogos:]),
         "contrato com juros ja lancado no Financeiro nao cancela: o app explica e nada muda", str(dialogos[n_dialogos:]))
    abrir(5)
    page.click('[data-cancelar-financiamento="5"]')
    page.wait_for_timeout(600)
    conf(contrato(5)["status"] == "cancelado" and len(db("parcelas_financiamento")) == 13,
         "contrato sem juros lancado: Cancelar so muda o status para 'cancelado' (parcelas e historico ficam)", str(contrato(5)["status"]))
    d_apos = page.evaluate("() => dividaEmpresa()")
    conf(perto(d_apos["saldoModulo"], 30000 + 30000 + 200000),
         "a divida dos contratos ativos nao inclui o cancelado nem o quitado: 30.000 (A) + 30.000 (B) + 200.000 (importado) = R$ 260.000", str(d_apos))

    # ---- 7. contrato com parcela paga: edicao reduzida ----
    abrir(2)
    page.click('[data-editar-financiamento="2"]')
    page.wait_for_timeout(300)
    modal2 = page.evaluate("""() => ({campos: [...document.querySelectorAll('.modal-body .field label')].map(l => l.innerText),
        taxaSoLeitura: document.getElementById('f-taxafin').readOnly, dataSoLeitura: document.getElementById('f-datafin').readOnly,
        temSistema: !!document.getElementById('f-sistemafin'), texto: document.querySelector('.modal-body').innerText.toLowerCase()})""")
    conf(not modal2["temSistema"] and modal2["taxaSoLeitura"] and modal2["dataSoLeitura"] and "parcelas já pagas" in modal2["texto"],
         "contrato com parcela paga: a edicao nao mexe no cronograma (sem sistema/parcelas; taxa e data so leitura)", str(modal2["campos"]))
    page.fill("#f-garantiafin", "Safra 26/27")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(600)
    c2 = contrato(2)
    conf(c2["garantia"] == "Safra 26/27" and len(db("parcelas_financiamento")) == 13 and parcela(5)["data_vencimento"] == "2026-12-10",
         "salvar muda a garantia e deixa as parcelas como estavam", str((c2["garantia"], parcela(5)["data_vencimento"])))

    # ---- 8. contrato importado do Conag: editar, ajustar parcela, pagar, quitar ----
    abrir(3)
    page.click('.toolbar [data-editar-financiamento="3"]')
    page.wait_for_timeout(300)
    modal3 = page.evaluate("""() => ({temSistema: !!document.getElementById('f-sistemafin'), principal: document.getElementById('f-principalfin').value,
        principalSoLeitura: document.getElementById('f-principalfin').readOnly, taxaSoLeitura: document.getElementById('f-taxafin').readOnly,
        obs: document.getElementById('f-obsfin').value, texto: document.querySelector('.modal-body').innerText.toLowerCase()})""")
    conf(not modal3["temSistema"] and float(modal3["principal"]) == 400000 and modal3["principalSoLeitura"] and not modal3["taxaSoLeitura"]
         and "importado do conag" in modal3["texto"] and modal3["obs"] == "",
         "contrato importado: edita taxa e dados, principal so leitura, sem cronograma; a observacao mostra so o texto do usuario", str(modal3))
    page.fill("#f-taxafin", "12")
    page.fill("#f-obsfin", "cedula 2024")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(800)
    c3 = contrato(3)
    e3 = juros_est(200000, 12, "2026-05-15", "2026-11-16")
    e4 = juros_est(100000, 12, "2026-11-16", "2027-11-15")
    conf(perto(c3["taxa_juros_aa"], 12) and c3["observacao"].startswith("Importado do Conag (contrato [contrato])") and c3["observacao"].endswith("cedula 2024"),
         "taxa 12% salva; a observacao mantem a marca do Conag e acrescenta o texto do usuario", str(c3["observacao"]))
    conf(perto(parcela(8)["valor_juros"], e3, 0.02) and perto(parcela(9)["valor_juros"], e4, 0.02),
         f"mudar a taxa refaz o juros estimado das parcelas em aberto: R$ {e3:,.2f} e R$ {e4:,.2f}", str((parcela(8)["valor_juros"], parcela(9)["valor_juros"])))
    conf(parcela(6)["valor_juros"] == 0 and parcela(7)["valor_juros"] == 0 and parcela(6)["status"] == "paga",
         "as parcelas ja pagas nao mudam (juros zero, pagas)")
    page.click('[data-editar-parcela="8"]')
    page.wait_for_timeout(250)
    ro3 = page.evaluate("() => document.getElementById('f-parcamort').readOnly")
    conf(not ro3, "no contrato importado a amortizacao da parcela e editavel (o cronograma espelha o do banco)")
    page.fill("#f-parcamort", "110000")
    page.fill("#f-parcjuros", "15000")
    page.fill("#f-parcdata", "2026-11-17")
    page.click('[data-save="parcelaFin"]')
    page.wait_for_timeout(800)
    saldos3 = [round(parcela(i)["saldo_devedor_apos"]) for i in (6, 7, 8, 9)]
    conf(perto(contrato(3)["valor_principal"], 410000) and saldos3 == [310000, 210000, 100000, 0],
         "amortizacao 100.000 -> 110.000: o principal vira R$ 410.000 (soma das parcelas) e o saldo devedor de cada parcela se refaz",
         str((contrato(3)["valor_principal"], saldos3)))
    conf(parcela(8)["data_vencimento"] == "2026-11-17" and perto(parcela(8)["valor_parcela"], 125000),
         "vencimento 17/11/2026 e valor da parcela = 110.000 + 15.000 = R$ 125.000", str(parcela(8)))
    # a parcela 8 foi paga fora do app e o juros dela ja esta no Financeiro: registra sem lancar
    page.click('[data-pagamento-parcela="8"]')
    page.wait_for_timeout(250)
    page.fill("#f-pagdata", "2026-10-13")
    page.uncheck("#f-paglancar")
    antes = len(db("lancamentos_financeiros"))
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(600)
    conf(parcela(8)["status"] == "paga" and parcela(8)["data_pagamento"] == "2026-10-13" and len(db("lancamentos_financeiros")) == antes,
         "parcela 8 registrada como paga em 13/10/2026 sem lancar juros (ja estava no Financeiro)")
    page.click('[data-quitar-financiamento="3"]')
    page.wait_for_timeout(250)
    page.fill("#f-quitdata", "2026-10-14")
    page.click('[data-save="quitarFin"]')
    page.wait_for_timeout(800)
    conf(contrato(3)["status"] == "quitado" and parcela(9)["status"] == "paga" and parcela(9)["data_pagamento"] == "2026-10-14",
         "Quitar o que sobrou: parcela 9 paga em 14/10/2026 e o contrato fica quitado", str((contrato(3)["status"], parcela(9)["status"])))
    d3 = page.evaluate("() => dividaEmpresa()")
    fl = page.evaluate("() => fluxoEmpresa({tipo:'mes', mes:'2026-10', ano:2026, safra:2026})")["financiamento"]
    conf(perto(fl["amortizacao"], 30000 + 30000 + 110000 + 100000),
         "outubro/2026: amortizacao = 30.000 + 30.000 (contrato A) + 110.000 (dia 13) + 100.000 (dia 14) = R$ 270.000, uma vez so (as linhas do Conag nao somam de novo)", str(fl))
    conf(perto(d3["saldoModulo"], 30000 + 30000) and perto(d3["aVencerConag"], 0),
         "depois de quitar, a divida e so a dos contratos A e B (R$ 60.000): o importado zerou e nada sobrou no Conag", str(d3))

    # ---- 9. cancelar o importado devolve as linhas do Conag ----
    sem_cancelar = page.evaluate("() => gruposConagParaLancar().length")
    abrir(3)
    n_dialogos = len(dialogos)
    page.click('[data-cancelar-financiamento="3"]')
    page.wait_for_timeout(600)
    conf(contrato(3)["status"] == "cancelado" and any("linhas do Conag voltam" in m for m in dialogos[n_dialogos:]),
         "cancelar o contrato importado avisa que as linhas do Conag voltam e muda o status para cancelado", str(dialogos[n_dialogos:]))
    grupos = page.evaluate("() => gruposConagParaLancar().map(g => [g.contrato, g.pagas.length, g.aVencer.length])")
    conf(sem_cancelar == 0 and grupos == [["[contrato]", 2, 2]],
         "as 4 linhas voltam para 'Divida do Conag ainda sem contrato' (2 pagas, 2 a vencer) e o contrato pode ser lancado de novo", str(grupos))
    fl2 = page.evaluate("() => fluxoEmpresa({tipo:'mes', mes:'2026-10', ano:2026, safra:2026})")["financiamento"]
    conf(perto(fl2["amortizacao"], 60000),
         "contrato cancelado: as parcelas dele (110.000 + 100.000) saem do fluxo e ficam so os 60.000 do contrato A (nao ha linha do Conag em outubro)", str(fl2))

    # ---- 10. a tela do contrato nao rola de lado no celular ----
    medir = """() => {
        const raiz = document.documentElement;
        const main = document.querySelector('.main');
        const limite = main.getBoundingClientRect().right - parseFloat(getComputedStyle(main).paddingRight) + 0.5;
        const sobram = [...main.children].filter(e => e.getBoundingClientRect().right > limite).map(e => String(e.className));
        const cards = [...document.querySelectorAll('.card')].map(c => c.scrollWidth - c.clientWidth);
        return {pagina: raiz.scrollWidth - raiz.clientWidth, maiorCard: Math.max(0, ...cards), sobram};
    }"""
    abrir(1)
    for largura, altura in [(1280, 800), (390, 844), (376, 800), (320, 640)]:
        page.set_viewport_size({"width": largura, "height": altura})
        page.wait_for_timeout(250)
        m = page.evaluate(medir)
        conf(m["pagina"] <= 0 and m["maiorCard"] <= 1 and not m["sobram"],
             f"{largura} px: a tela do contrato nao rola de lado (pagina={m['pagina']}, maior card={m['maiorCard']}, sobram={m['sobram']})", str(m))
    page.set_viewport_size({"width": 1280, "height": 720})

    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))
    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
sys.exit(1 if falhas else 0)
