"""
Financiamentos > "Divida do Conag ainda sem contrato" > "Lancar contrato".

Pedido do Eduardo em 15/10/2026: ao lancar os contratos antigos no modulo, as
linhas do Conag desse contrato nao podem continuar contando (divida e
amortizacao apareceriam duas vezes) e ele nao quer apagar nada a mao.

O que este teste prova, com contas conhecidas (hoje = 14/10/2026):
  - a lista mostra so contratos do Conag com parcelas a vencer (quitado nao
    aparece), agrupados por credor + numero do contrato; linhas sem numero se
    separam pelo valor da parcela;
  - lancar o contrato cria o financiamento com o cronograma REAL do Conag (uma
    parcela por linha, datas e valores do banco): as ja pagas entram como pagas
    e SEM juros lancado; as a vencer ficam pendentes com juros estimado;
  - as linhas do Conag ficam ligadas ao contrato (financiamento_id) e saem das
    contas: a divida e a amortizacao nao contam duas vezes;
  - nenhum lancamento financeiro e criado (o juros do passado ja esta la);
  - o contrato importado nao conta como emprestimo recebido, nao tem "Editar"
    (regerar apagaria o cronograma real) e, se for cancelado, as linhas voltam;
  - lancar contrato digitado a mao enquanto ha divida do Conag avisa na tela.
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

def mov(i, data, valor, credor, contrato):
    return {"id": i, "data": data, "tipo": "amortizacao", "valor": valor, "credor": credor, "contrato": contrato,
            "descricao": "", "origem": "conag", "conag_id": 1000 + i, "financiamento_id": None}

DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "centros_custo": [
        {"id": 1, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS"},
    ],
    "lancamentos_financeiros": [],
    "financiamentos": [], "parcelas_financiamento": [],
    "movimentos_financiamento": [
        # A) BB C01: anuais e crescentes (o gerador SAC/Price nao reproduz); 2 pagas + 3 a vencer
        mov(1, "2024-11-15", 100000.00, "BANCO DO BRASIL", "C01"),
        mov(2, "2025-11-15", 120000.00, "BANCO DO BRASIL", "C01"),
        mov(3, "2026-11-16", 150000.00, "BANCO DO BRASIL", "C01"),
        mov(4, "2027-11-15", 160000.00, "BANCO DO BRASIL", "C01"),
        mov(5, "2028-11-15", 170000.00, "BANCO DO BRASIL", "C01"),
        # B) BB sem numero, parcela de 456.737,72: 1 paga + 2 a vencer (o Conag nem sempre traz o numero)
        mov(6, "2026-08-19", 456737.72, "BANCO DO BRASIL", ""),
        mov(7, "2027-08-15", 456737.72, "BANCO DO BRASIL", ""),
        mov(8, "2028-08-15", 456737.72, "BANCO DO BRASIL", ""),
        # outra parcela sem numero, de valor diferente: NAO entra no contrato B; e ja paga, entao nem aparece
        mov(9, "2023-06-15", 2030.00, "BANCO DO BRASIL", ""),
        # C) contrato quitado (so linhas passadas): nao precisa virar contrato
        mov(10, "2023-05-11", 3672989.65, "BANCO DA AMAZONIA BASA", ""),
        # D) so a vencer, sem nenhuma paga
        mov(11, "2027-03-10", 80000.00, "SICOOB COCRED", "C02"),
    ],
    "profiles": [{"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}],
}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def perto(a, b, tol=0.01):
    return a is not None and abs(a - b) < tol

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page()
    erros, dialogos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: (dialogos.append(d.message), d.dismiss()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(2500)

    print("\n  FINANCIAMENTOS > LANCAR CONTRATO DO CONAG")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- 1. a lista: so contrato com parcela a vencer ----
    grupos = page.evaluate("""() => gruposConagParaLancar().map(g => ({chave: g.chave, contrato: g.contrato, credor: g.credor,
        linhas: g.linhas.length, pagas: g.pagas.length, aVencer: g.aVencer.length,
        totalPago: g.totalPago, totalAVencer: g.totalAVencer, total: g.total}))""")
    por_contrato = {(g["contrato"] or "sem numero"): g for g in grupos}
    conf(len(grupos) == 3, "3 contratos com parcela a vencer na lista (o quitado e a parcela solta de 2023 nao aparecem)", str(grupos))
    a = por_contrato.get("C01", {})
    conf(a.get("linhas") == 5 and a.get("pagas") == 2 and a.get("aVencer") == 3
         and perto(a.get("totalPago"), 220000) and perto(a.get("totalAVencer"), 480000) and perto(a.get("total"), 700000),
         "contrato C01: 5 parcelas (2 pagas R$ 220.000, 3 a vencer R$ 480.000), total R$ 700.000", str(a))
    b = por_contrato.get("sem numero", {})
    conf(b.get("linhas") == 3 and b.get("pagas") == 1 and b.get("aVencer") == 2 and perto(b.get("totalAVencer"), 913475.44),
         "sem numero: so as 3 linhas de R$ 456.737,72 formam o contrato (a parcela de R$ 2.030 de 2023 fica de fora)", str(b))
    conf([g["contrato"] for g in grupos] == ["C01", "C02", ""],
         "lista ordenada pela proxima parcela a vencer (16/11/2026, 10/03/2027, 15/08/2027)", str([(g["contrato"], g["credor"]) for g in grupos]))
    d0 = page.evaluate("() => dividaEmpresa()")
    conf(d0["origem"] == "conag" and perto(d0["valor"], 480000 + 913475.44 + 80000),
         "antes de lancar nada, a divida da aba Empresa e a do Conag: R$ 1.473.475,44", str(d0))

    # ---- 2. a tela de Financiamentos ----
    page.evaluate("() => { state.page = 'financiamentos'; render(); }")
    page.wait_for_timeout(300)
    texto = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("dívida do conag ainda sem contrato" in texto and "lançar contrato" in texto,
         "Financiamentos mostra a lista 'Divida do Conag ainda sem contrato' com o botao 'Lancar contrato'")
    conf("contrato c01" in texto and "banco do brasil" in texto and "sicoob cocred" in texto,
         "a lista mostra credor e numero do contrato")
    conf("basa" not in texto.split("dívida do conag ainda sem contrato")[1], "o contrato quitado (BASA) nao aparece na lista")

    # ---- 3. abrir o contrato A ----
    page.click('[data-lancar-conag="BANCO DO BRASIL|C01"]')
    page.wait_for_timeout(300)
    modal = page.evaluate("""() => ({
        titulo: document.querySelector('.modal-head h3').innerText,
        banco: document.getElementById('f-bancofin').value, bancoSoLeitura: document.getElementById('f-bancofin').readOnly,
        principal: document.getElementById('f-principalfin').value, principalSoLeitura: document.getElementById('f-principalfin').readOnly,
        data: document.getElementById('f-datafin').value,
        temSistema: !!document.getElementById('f-sistemafin'), temParcelas: !!document.getElementById('f-numparcelasfin'),
        temCarencia: !!document.getElementById('f-carenciafin'), temIof: !!document.getElementById('f-ioffin'),
        texto: document.querySelector('.modal-body').innerText.toLowerCase()})""")
    conf(modal["titulo"] == "Lançar contrato do Conag" and modal["banco"] == "Banco do Brasil" and modal["bancoSoLeitura"],
         "o modal abre como 'Lancar contrato do Conag' com o banco preenchido (so leitura)", str(modal))
    # O Conag so tem vencimentos: a data do contrato e estimada recuando da 1a
    # parcela o intervalo tipico (mediana dos intervalos: 365,5 -> 366 dias)
    conf(float(modal["principal"]) == 700000 and modal["principalSoLeitura"] and modal["data"] == "2023-11-15",
         "principal = soma das parcelas do Conag (R$ 700.000, so leitura); data estimada = 1a parcela menos o intervalo tipico (15/11/2023)", str(modal))
    conf(not (modal["temSistema"] or modal["temParcelas"] or modal["temCarencia"] or modal["temIof"]),
         "o cronograma vem do Conag: sem sistema de amortizacao, numero de parcelas, carencia, IOF nem seguro")
    conf("5 parcelas" in modal["texto"] and "2 já paga(s), r$ 220.000,00" in modal["texto"] and "3 a vencer, r$ 480.000,00" in modal["texto"],
         "o modal explica: 5 parcelas, 2 ja pagas (R$ 220.000), 3 a vencer (R$ 480.000)", modal["texto"][:300])

    # ---- 4. campos obrigatorios ----
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(300)
    erro = page.evaluate("() => (document.querySelector('.login-error') || {}).innerText || ''")
    conf("atividade" in erro.lower() and "taxa de juros" in erro.lower(),
         "salvar sem atividade e sem taxa pede os dois, sem criar nada", erro)
    conf(len(page.evaluate("() => window.__DB__.financiamentos")) == 0, "nada foi gravado ainda")

    # ---- 5. salvar ----
    page.select_option("#f-finalidadefin", "custeio")
    page.select_option("#f-atividadefin", "graos")
    page.fill("#f-taxafin", "10")
    antes_lanc = len(page.evaluate("() => window.__DB__.lancamentos_financeiros"))
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(1200)
    fin = page.evaluate("() => window.__DB__.financiamentos")
    parc = page.evaluate("() => window.__DB__.parcelas_financiamento.sort((x, y) => x.numero - y.numero)")
    conf(len(fin) == 1 and fin[0]["banco"] == "Banco do Brasil" and perto(fin[0]["valor_principal"], 700000)
         and fin[0]["numero_parcelas"] == 5 and fin[0]["status"] == "ativo" and fin[0]["finalidade"] == "custeio" and fin[0]["atividade"] == "graos",
         "criou 1 financiamento ativo: Banco do Brasil, principal R$ 700.000, 5 parcelas, custeio de graos", str(fin))
    conf(fin and fin[0]["observacao"].startswith("Importado do Conag (contrato C01)"),
         "a observacao marca o contrato como importado do Conag (o app usa isso para esconder 'Editar')", str(fin[:1]))
    conf([p["data_vencimento"] for p in parc] == ["2024-11-15", "2025-11-15", "2026-11-16", "2027-11-15", "2028-11-15"],
         "as 5 parcelas tem as datas REAIS do Conag (anuais), nao as mensais do gerador", str([p["data_vencimento"] for p in parc]))
    conf([round(p["valor_amortizacao"]) for p in parc] == [100000, 120000, 150000, 160000, 170000],
         "e as amortizacoes REAIS e crescentes do Conag", str([p["valor_amortizacao"] for p in parc]))
    conf([round(p["saldo_devedor_apos"]) for p in parc] == [600000, 480000, 330000, 170000, 0],
         "saldo devedor depois de cada parcela: 600.000, 480.000, 330.000, 170.000, 0", str([p["saldo_devedor_apos"] for p in parc]))
    conf([p["status"] for p in parc] == ["paga", "paga", "pendente", "pendente", "pendente"]
         and parc[0]["data_pagamento"] == "2024-11-15" and parc[1]["data_pagamento"] == "2025-11-15",
         "as 2 ja pagas entram como pagas na data do Conag; as 3 a vencer ficam pendentes", str([(p["status"], p.get("data_pagamento")) for p in parc]))
    conf(all(p["valor_juros"] == 0 for p in parc[:2]) and all(p["valor_juros"] > 0 for p in parc[2:]),
         "juros: zero nas ja pagas (ja estao no Financeiro) e estimado nas a vencer", str([p["valor_juros"] for p in parc]))
    # 1a a vencer: saldo 480.000 por 366 dias (2025-11-15 -> 2026-11-16) a 10% a.a.
    esperado = 480000 * ((1.10) ** (366 / 365) - 1)
    conf(perto(parc[2]["valor_juros"], esperado, 1.0),
         f"juros estimado da 1a parcela a vencer = 480.000 x ((1,10)^(366/365) - 1) = {esperado:,.2f}", str(parc[2]["valor_juros"]))
    conf(len(page.evaluate("() => window.__DB__.lancamentos_financeiros")) == antes_lanc,
         "nenhum lancamento financeiro foi criado (o juros do passado ja esta no Financeiro, vindo do Conag)")
    movs = {m["id"]: m for m in page.evaluate("() => window.__DB__.movimentos_financiamento")}
    fid = fin[0]["id"] if fin else None
    conf(all(movs[i]["financiamento_id"] == fid for i in (1, 2, 3, 4, 5)),
         "as 5 linhas do contrato ficaram ligadas a ele (financiamento_id), pagas e a vencer", str({i: movs[i]["financiamento_id"] for i in range(1, 6)}))
    conf(all(movs[i]["financiamento_id"] is None for i in (6, 7, 8, 9, 10, 11)),
         "as linhas dos outros contratos nao foram tocadas")
    conf(any("5 parcelas" in m and "2 já pagas" in m for m in dialogos),
         "o app avisa o que fez: 5 parcelas, 2 ja pagas, 3 a vencer", str(dialogos))

    # ---- 6. efeito nas contas ----
    d1 = page.evaluate("() => dividaEmpresa()")
    conf(d1["origem"] == "ambos" and perto(d1["saldoModulo"], 480000) and perto(d1["aVencerConag"], 913475.44 + 80000)
         and perto(d1["valor"], 480000 + 913475.44 + 80000),
         "divida = R$ 480.000 do contrato lancado + R$ 993.475,44 ainda so no Conag: o mesmo total de antes, sem contar a dívida do contrato duas vezes", str(d1))
    f24 = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2024})")["financiamento"]
    f25 = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2025})")["financiamento"]
    conf(perto(f24["amortizacao"], 100000) and perto(f25["amortizacao"], 120000),
         "amortizacao paga entra UMA vez: R$ 100.000 em 2024 e R$ 120.000 em 2025 (pela parcela; a linha do Conag nao soma de novo)", f"{f24} {f25}")
    conf(perto(f24["emprestimosRecebidos"], 0) and perto(f25["emprestimosRecebidos"], 0),
         "contrato importado do Conag nao conta como emprestimo recebido (o Conag nao traz o dinheiro que entrou)")
    gr = page.evaluate("() => gruposConagParaLancar().map(g => g.contrato || 'sem numero')")
    conf("C01" not in gr and len(gr) == 2, "o contrato lancado sai da lista; sobram os outros 2", str(gr))

    # ---- 7. a tela depois ----
    page.click("[data-abrir-financiamento]")
    page.wait_for_timeout(300)
    detalhe = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("importado do conag (contrato c01)" in detalhe and "juros já no financeiro (conag)" in detalhe,
         "o detalhe diz que veio do Conag e que o juros das parcelas pagas ja esta no Financeiro")
    conf(page.evaluate("() => document.querySelectorAll('[data-pagar-parcela]').length") == 3,
         "as 3 parcelas a vencer tem 'Marcar como paga'; as 2 do passado nao")
    page.evaluate("() => { state.financiamentoDetalheId = null; render(); }")

    # ---- 7b. contrato so com parcelas a vencer: nada pago, mas tambem sem 'Editar' ----
    # (sem nenhuma parcela paga o botao Editar apareceria; regerar o cronograma
    # apagaria as parcelas reais do Conag)
    page.click('[data-lancar-conag="SICOOB COCRED|C02"]')
    page.wait_for_timeout(300)
    page.select_option("#f-finalidadefin", "capital_giro")
    page.fill("#f-taxafin", "12")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(1200)
    fin2 = page.evaluate("() => window.__DB__.financiamentos")
    parc2 = page.evaluate("() => window.__DB__.parcelas_financiamento.filter(p => p.financiamento_id === %d)" % (fin2[1]["id"] if len(fin2) > 1 else -1))
    conf(len(fin2) == 2 and fin2[1]["banco"] == "Sicoob Cocred" and fin2[1]["atividade"] is None
         and len(parc2) == 1 and parc2[0]["status"] == "pendente" and perto(parc2[0]["valor_amortizacao"], 80000),
         "contrato D (so a vencer, capital de giro): 1 parcela pendente de R$ 80.000, sem atividade (capital de giro e rateado)", str(fin2[1:]))
    tem_editar = page.evaluate("() => !!document.querySelector('[data-editar-financiamento]')")
    conf(not tem_editar,
         "contrato importado do Conag nao tem 'Editar', mesmo sem parcela paga (regerar apagaria o cronograma real)")

    # ---- 8. cancelar o contrato devolve as linhas ----
    page.evaluate("() => { state.financiamentos = state.financiamentos.map(f => ({...f, status: 'cancelado'})); render(); }")
    conf(page.evaluate("() => gruposConagParaLancar().length") == 3,
         "contratos cancelados: as linhas voltam ao Conag e os 3 contratos voltam para a lista")
    d2 = page.evaluate("() => dividaEmpresa()")
    conf(d2["origem"] == "conag" and perto(d2["valor"], 480000 + 913475.44 + 80000),
         "e a divida continua R$ 1.473.475,44 (nada se perdeu)", str(d2))
    page.evaluate("() => { state.financiamentos = state.financiamentos.map(f => ({...f, status: 'ativo'})); render(); }")

    # ---- 9. tentar lancar de novo / contrato digitado a mao ----
    page.evaluate("() => { state.page = 'financiamentos'; render(); }")
    page.wait_for_timeout(200)
    page.click('[data-lancar-conag="BANCO DO BRASIL|SEM NUMERO 456737.72"]')
    page.wait_for_timeout(200)
    page.evaluate("() => { state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => [6, 7, 8].includes(m.id) ? {...m, financiamentoId: 999} : m); }")
    page.select_option("#f-atividadefin", "pecuaria")
    page.fill("#f-taxafin", "8")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(400)
    erro2 = page.evaluate("() => (document.querySelector('.login-error') || {}).innerText || ''")
    conf("já foi lançado" in erro2.lower() and len(page.evaluate("() => window.__DB__.financiamentos")) == 2,
         "se as linhas ja foram assumidas por outro contrato, nao cria um segundo contrato", erro2)
    page.evaluate("() => { state.modal = null; editDraft = null; state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => [6, 7, 8].includes(m.id) ? {...m, financiamentoId: null} : m); render(); }")
    page.click("[data-novo-financiamento]")
    page.wait_for_timeout(300)
    aviso = page.evaluate("() => document.querySelector('.modal-body').innerText.toLowerCase()")
    conf("ainda tem 1 contrato(s)" in aviso and "lançar contrato" in aviso,
         "ao digitar um contrato a mao, o modal avisa que o Conag ainda tem divida sem contrato", aviso[:250])

    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))
    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
sys.exit(1 if falhas else 0)
