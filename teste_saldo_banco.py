"""
Financiamentos: saldo devedor segundo o banco (pedido do Eduardo, 24/10/2026: "o saldo
devedor que vc colocou e um e no contrato e outro"). O extrato do banco soma ao principal o
juros, a correcao e os seguros que ainda nao foram pagos; o app conta so o principal. O
campo (opcional, com data) mostra o numero do banco ao lado do contrato, sem entrar em conta
nenhuma.

O que este teste prova (hoje = 24/10/2026, contratos inventados):
  - lista: "No banco: R$ ... em dd/mm/aaaa" embaixo do saldo devedor; contrato sem o campo,
    quitado, ou com saldo velho se comportam como devem; os cards do topo seguem pelo principal;
  - tela do contrato: principal, saldo do banco e a diferenca (juros, correcao e seguros ainda
    nao pagos); parcela paga DEPOIS da data do extrato deixa o saldo "desatualizado" e some a diferenca;
  - NADA muda na divida, nos vencimentos, no historico nem no fluxo da aba Empresa com ou sem o campo;
  - editar (contrato importado e contrato a mao): abre preenchido, grava valor e data juntos,
    recusa valor sem data, apagar o valor limpa as duas colunas;
  - tolerancia: contrato salvo sem o campo nao manda as colunas novas (o banco ainda pode nao ter);
  - contrato novo com e sem o campo; lancar do ERP nao mostra o campo;
  - lista e tela do contrato sem rolar de lado de 1280 a 320 px.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

RELOGIO = """(() => {
  const R = Date, FIXO = new R(2026, 9, 24, 12, 0, 0).getTime();
  class D extends R {
    constructor(...a){ if(a.length === 0) super(FIXO); else super(...a); }
    static now(){ return FIXO; }
  }
  window.Date = D;
})();"""

def fin(i, banco, principal, data, taxa, n, status="ativo", obs=None, atividade="graos", finalidade="custeio",
        sistema="sac", saldo=None, saldo_em=None):
    r = {"id": i, "banco": banco, "finalidade": finalidade, "valor_principal": principal, "valor_iof": 0, "valor_seguro": 0,
         "data_contratacao": data, "taxa_juros_aa": taxa, "sistema_amortizacao": sistema, "numero_parcelas": n,
         "carencia_meses": 0, "periodicidade_meses": 12, "primeiro_vencimento": None, "continuacao": False,
         "atividade": atividade, "fazenda_id": None, "garantia": None, "status": status,
         "financiamento_origem_id": None, "observacao": obs}
    if saldo is not None:       # contrato sem o campo = linha sem as colunas, como o banco antes do SQL novo
        r["saldo_banco"] = saldo
        r["saldo_banco_em"] = saldo_em
    return r

def parc(i, fid, n, venc, amort, juros, saldo, status="pendente", pago=None):
    return {"id": i, "financiamento_id": fid, "numero": n, "data_vencimento": venc, "valor_parcela": amort + juros,
            "valor_amortizacao": amort, "valor_juros": juros, "saldo_devedor_apos": saldo, "status": status,
            "data_pagamento": pago, "valor_pago": (amort + juros) if pago else None, "lancamentos_financeiro_ids": []}

OBS_ERP = "Importado do ERP (contrato C09): cronograma real, uma parcela por linha do ERP; juros das parcelas a vencer estimado pela taxa informada."

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
        # 1: importado do ERP, 1 parcela paga, saldo do banco da mesma data do extrato
        fin(1, "Banco Alfa", 300000, "2024-11-15", 9, 3, obs=OBS_ERP, atividade="cana", finalidade="investimento",
            saldo=340000.50, saldo_em="2026-10-16"),
        # 2: custeio de parcela unica, a mao, nada pago
        fin(2, "Banco Beta", 500000, "2026-10-20", 9, 1, sistema="parcela_unica", finalidade="capital_giro", atividade=None,
            saldo=500420.35, saldo_em="2026-10-23"),
        # 3: a mao, sem o campo (a linha nem tem as colunas)
        fin(3, "Banco Gama", 90000, "2026-08-10", 10, 3),
        # 4: saldo velho: parcela paga em 10/03/2026, extrato de 10/01/2026
        fin(4, "Banco Delta", 200000, "2025-11-10", 10, 2, saldo=250000.00, saldo_em="2026-01-10"),
        # 5: quitado com saldo gravado: nao mostra
        fin(5, "Banco Epsilon", 50000, "2025-01-10", 10, 1, status="quitado", sistema="parcela_unica", saldo=100.00, saldo_em="2026-05-01"),
    ],
    "parcelas_financiamento": [
        parc(1, 1, 1, "2025-11-17", 100000, 0, 200000, status="paga", pago="2025-11-17"),
        parc(2, 1, 2, "2026-11-16", 100000, 60000, 100000),
        parc(3, 1, 3, "2027-11-16", 100000, 70000, 0),
        parc(4, 2, 1, "2027-10-15", 500000, 44000, 0),
        parc(5, 3, 1, "2026-11-10", 30000, 1000, 60000),
        parc(6, 3, 2, "2026-12-10", 30000, 1000, 30000),
        parc(7, 3, 3, "2027-01-10", 30000, 1000, 0),
        parc(8, 4, 1, "2026-03-10", 100000, 5000, 100000, status="paga", pago="2026-03-10"),
        parc(9, 4, 2, "2027-03-10", 100000, 4000, 0),
        parc(10, 5, 1, "2026-05-01", 50000, 2000, 0, status="paga", pago="2026-05-01"),
    ],
    "movimentos_financiamento": [],
    "profiles": [{"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}],
}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def perto(a, b, tol=0.005):
    return a is not None and abs(float(a) - b) < tol

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, dialogos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: (dialogos.append(d.message), d.accept()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(2500)

    def lista():
        page.evaluate("() => { state.page = 'financiamentos'; state.financiamentoDetalheId = null; state.modal = null; editDraft = null; render(); }")
        page.wait_for_timeout(250)

    def abrir(fid):
        page.evaluate("(id) => { state.page = 'financiamentos'; state.financiamentoDetalheId = id; state.modal = null; editDraft = null; render(); }", fid)
        page.wait_for_timeout(250)

    def db(tabela):
        return page.evaluate("(t) => window.__DB__[t]", tabela)

    def contrato(fid):
        return next(f for f in db("financiamentos") if f["id"] == fid)

    def texto(sel="body"):
        return page.evaluate("(s) => document.querySelector(s).innerText", sel)

    def celula_saldo(banco):
        return page.evaluate("""(b) => { const tr = [...document.querySelectorAll('tbody tr')].find(t => t.innerText.includes(b));
                                         return tr ? tr.children[3].innerText : null; }""", banco)

    print("\n  FINANCIAMENTOS > SALDO DEVEDOR SEGUNDO O BANCO")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- 1. a lista ----
    lista()
    alfa, beta, gama, delta, epsilon = (celula_saldo(b) for b in ("Banco Alfa", "Banco Beta", "Banco Gama", "Banco Delta", "Banco Epsilon"))
    conf(alfa and "R$ 200.000,00" in alfa and "No banco: R$ 340.000,50 em 16/10/2026" in alfa,
         "lista: contrato importado mostra o principal (R$ 200.000,00) e embaixo 'No banco: R$ 340.000,50 em 16/10/2026'", str(alfa))
    conf(beta and "R$ 500.000,00" in beta and "No banco: R$ 500.420,35 em 23/10/2026" in beta,
         "lista: parcela unica mostra R$ 500.000,00 e 'No banco: R$ 500.420,35 em 23/10/2026'", str(beta))
    conf(gama and "No banco" not in gama and "R$ 90.000,00" in gama, "contrato sem o campo: so o principal, nada de 'No banco'", str(gama))
    conf(delta and "R$ 100.000,00" in delta and "No banco: R$ 250.000,00 em 10/01/2026 (desatualizado)" in delta,
         "saldo de antes de uma parcela paga aparece como (desatualizado)", str(delta))
    conf(epsilon and "No banco" not in epsilon, "contrato quitado nao mostra o saldo do banco", str(epsilon))
    topo = texto(".stat-row")
    conf("R$ 1.090.000,00" in topo and "R$ 890.000,00" in topo,
         "cards do topo seguem pelo principal: contratado R$ 1.090.000,00 e saldo devedor R$ 890.000,00 (os 4 ativos), sem somar o banco", topo.replace("\n", " | "))
    cab = page.evaluate("() => [...document.querySelectorAll('thead th')].map(t => t.textContent.trim())")
    conf(cab[:6] == ["Banco", "Contratado", "Data do contrato", "Saldo devedor", "Próxima parcela", "Status"],
         "cabecalho da lista bate com as colunas (antes 'Finalidade' ficava em cima do valor contratado)", str(cab))

    # ---- 2. a tela do contrato ----
    abrir(1)
    t = texto("body")
    cards = page.evaluate("() => [...document.querySelectorAll('.stat-card')].map(c => c.innerText.replace(/\\n/g, ' | '))")
    conf(len(cards) == 3, "tela do contrato: 3 cards (principal, saldo do banco, a diferenca)", str(cards))
    conf(cards and "PRINCIPAL QUE FALTA PAGAR" in cards[0].upper() and "R$ 200.000,00" in cards[0], "card 1: principal que falta pagar R$ 200.000,00", str(cards[:1]))
    conf(len(cards) > 1 and "SEGUNDO O BANCO EM 16/10/2026" in cards[1].upper() and "R$ 340.000,50" in cards[1],
         "card 2: saldo devedor segundo o banco em 16/10/2026, R$ 340.000,50", str(cards[1:2]))
    conf(len(cards) > 2 and "JUROS, CORREÇÃO E SEGUROS AINDA NÃO PAGOS" in cards[2].upper() and "R$ 140.000,50" in cards[2],
         "card 3: juros, correcao e seguros ainda nao pagos R$ 140.000,50 (= 340.000,50 - 200.000,00)", str(cards[2:3]))
    conf("desatualizado" not in t.lower(), "saldo da mesma data do extrato: sem aviso de desatualizado")
    conf("lança o juros como despesa quando a parcela é paga" in t, "explica por que o app conta so o principal")
    abrir(2)
    cards = page.evaluate("() => [...document.querySelectorAll('.stat-card')].map(c => c.innerText.replace(/\\n/g, ' | '))")
    conf(len(cards) == 3 and "R$ 500.000,00" in cards[0] and "R$ 500.420,35" in cards[1] and "R$ 420,35" in cards[2],
         "parcela unica: R$ 500.000,00 / R$ 500.420,35 / R$ 420,35 de juros ate agora", str(cards))
    abrir(4)
    cards = page.evaluate("() => [...document.querySelectorAll('.stat-card')].map(c => c.innerText.replace(/\\n/g, ' | '))")
    t = texto("body")
    conf(len(cards) == 2 and "R$ 100.000,00" in cards[0] and "R$ 250.000,00" in cards[1], "saldo velho: so principal e saldo do banco, sem a diferenca (que seria falsa)", str(cards))
    conf("Este saldo do banco está desatualizado" in t and "Informe o saldo novo em Editar" in t, "e avisa que esta desatualizado e o que fazer")
    abrir(3)
    conf(page.evaluate("() => document.querySelectorAll('.stat-card').length") == 0, "contrato sem o campo: a tela fica como era (sem os cards)")
    abrir(5)
    conf(page.evaluate("() => document.querySelectorAll('.stat-card').length") == 0, "contrato quitado: sem os cards")

    # ---- 3. nada muda nas contas da empresa ----
    MEDIDAS = """() => JSON.stringify({d: dividaEmpresa(), r: resumoFinanciamentos(), v: vencimentosDaDivida(), h: historicoEmpresa(),
        f25: fluxoEmpresa({tipo:'ano', ano:2025}), f26: fluxoEmpresa({tipo:'ano', ano:2026}), f27: fluxoEmpresa({tipo:'ano', ano:2027}),
        t: taxaMediaContratos()})"""
    com = page.evaluate(MEDIDAS)
    page.evaluate("() => state.financiamentos.forEach(f => { f.saldoBanco = null; f.saldoBancoEm = ''; })")
    sem = page.evaluate(MEDIDAS)
    conf(com == sem and len(com) > 500, "divida, vencimentos, historico, fluxo (2025 a 2027) e taxa media iguais com e sem o saldo do banco",
         f"{len(com)} x {len(sem)} caracteres")
    page.reload(); page.wait_for_timeout(2500)

    # ---- 4. editar o contrato importado (cronograma travado) ----
    abrir(1)
    page.click('.toolbar [data-editar-financiamento]')
    page.wait_for_timeout(250)
    campos = page.evaluate("() => ({v: document.getElementById('f-saldobancofin').value, d: document.getElementById('f-saldobancoemfin').value})")
    conf(perto(campos["v"], 340000.50) and campos["d"] == "2026-10-16", "Editar abre com o saldo e a data gravados", str(campos))
    page.fill("#f-saldobancofin", "345000,25")
    page.fill("#f-saldobancoemfin", "2026-10-20")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(700)
    c1 = contrato(1)
    conf(perto(c1["saldo_banco"], 345000.25) and c1["saldo_banco_em"] == "2026-10-20", "salvar grava valor e data: R$ 345.000,25 em 20/10/2026", str({k: c1.get(k) for k in ("saldo_banco", "saldo_banco_em")}))
    abrir(1)
    cards = page.evaluate("() => [...document.querySelectorAll('.stat-card')].map(c => c.innerText.replace(/\\n/g, ' | '))")
    conf(len(cards) == 3 and "R$ 345.000,25" in cards[1] and "R$ 145.000,25" in cards[2], "a tela passa a mostrar o numero novo e a diferenca R$ 145.000,25", str(cards))
    conf(c1["status"] == "ativo" and len(db("parcelas_financiamento")) == 10, "o cronograma e o resto do contrato nao mudam (10 parcelas no total)")

    page.click('.toolbar [data-editar-financiamento]')
    page.wait_for_timeout(250)
    page.fill("#f-saldobancoemfin", "")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(500)
    erro = page.evaluate("() => (document.querySelector('.login-error') || {}).innerText || ''")
    conf("data do saldo do banco" in erro and perto(contrato(1)["saldo_banco"], 345000.25), "valor sem data: recusa ('Preencha: data do saldo do banco') e nada muda", erro)
    page.fill("#f-saldobancofin", "")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(700)
    c1 = contrato(1)
    conf(c1["saldo_banco"] is None and c1["saldo_banco_em"] is None, "apagar o valor limpa valor e data", str({k: c1.get(k) for k in ("saldo_banco", "saldo_banco_em")}))
    abrir(1)
    sem_cards = page.evaluate("() => document.querySelectorAll('.stat-card').length") == 0
    lista()
    conf(sem_cards and "No banco" not in celula_saldo("Banco Alfa"), "e a tela e a lista voltam ao normal (sem os cards, sem 'No banco')")

    # ---- 5. editar contrato a mao: o campo vai junto; sem o campo nada extra vai ----
    abrir(3)
    page.click('.toolbar [data-editar-financiamento]')
    page.wait_for_timeout(250)
    page.fill("#f-garantiafin", "Penhor da safra")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(900)
    c3 = contrato(3)
    conf(c3["garantia"] == "Penhor da safra" and "saldo_banco" not in c3 and "saldo_banco_em" not in c3,
         "contrato sem o campo, salvo sem preencher: as colunas novas nem vao no pedido (o banco ainda pode nao ter)", str({k: v for k, v in c3.items() if "saldo" in k}))
    abrir(3)
    page.click('.toolbar [data-editar-financiamento]')
    page.wait_for_timeout(250)
    page.fill("#f-saldobancofin", "91234,56")
    page.fill("#f-saldobancoemfin", "2026-10-22")
    page.click('[data-save="financiamento"]')
    page.wait_for_timeout(900)
    c3 = contrato(3)
    conf(perto(c3.get("saldo_banco"), 91234.56) and c3.get("saldo_banco_em") == "2026-10-22", "preenchendo, grava: R$ 91.234,56 em 22/10/2026", str({k: v for k, v in c3.items() if "saldo" in k}))
    conf(len([p for p in db("parcelas_financiamento") if p["financiamento_id"] == 3]) == 3, "o cronograma do contrato a mao foi refeito (3 parcelas), como sempre")
    abrir(3)
    cards = page.evaluate("() => [...document.querySelectorAll('.stat-card')].map(c => c.innerText.replace(/\\n/g, ' | '))")
    conf(len(cards) == 3 and "R$ 90.000,00" in cards[0] and "R$ 91.234,56" in cards[1] and "R$ 1.234,56" in cards[2], "e a tela mostra R$ 90.000,00 / R$ 91.234,56 / R$ 1.234,56", str(cards))

    # ---- 6. contrato novo ----
    def preenche_novo(banco, saldo=None, em=None):
        lista()
        page.locator('[data-novo-financiamento]').click()
        page.wait_for_timeout(250)
        page.fill('#f-bancofin', banco)
        page.select_option('#f-atividadefin', 'cana')
        page.fill('#f-principalfin', '100000')
        page.fill('#f-datafin', '2026-10-01')
        page.fill('#f-taxafin', '9')
        page.fill('#f-numparcelasfin', '2')
        page.fill('#f-vencfin', '2027-10-01')
        if saldo is not None:
            page.fill('#f-saldobancofin', saldo)
        if em is not None:
            page.fill('#f-saldobancoemfin', em)
        page.locator('[data-save="financiamento"]').click()
        page.wait_for_timeout(900)
    preenche_novo("Banco Novo Um")
    n1 = next((f for f in db("financiamentos") if f["banco"] == "Banco Novo Um"), None)
    conf(n1 is not None and "saldo_banco" not in n1 and "saldo_banco_em" not in n1, "contrato novo sem o campo: salva sem as colunas novas", str(n1))
    preenche_novo("Banco Novo Dois", "100450,10", "2026-10-23")
    n2 = next((f for f in db("financiamentos") if f["banco"] == "Banco Novo Dois"), None)
    conf(n2 is not None and perto(n2.get("saldo_banco"), 100450.10) and n2.get("saldo_banco_em") == "2026-10-23",
         "contrato novo com o campo: grava R$ 100.450,10 em 23/10/2026", str(n2))
    antes = len(db("financiamentos"))
    preenche_novo("Banco Novo Tres", "100450,10", None)
    erro = page.evaluate("() => (document.querySelector('.login-error') || {}).innerText || ''")
    conf(len(db("financiamentos")) == antes and "data do saldo do banco" in erro, "contrato novo com valor e sem data: nao salva e diz o que falta", erro)
    page.keyboard.press("Escape")
    page.evaluate("() => { state.modal = null; editDraft = null; render(); }")

    # ---- 7. lancar do ERP nao mostra o campo ----
    page.evaluate("""() => { state.page = 'financiamentos'; state.financiamentoDetalheId = null;
        editDraft = {banco:'Banco do Teste', finalidade:'investimento', atividade:'', valorPrincipal:1000, dataContratacao:'2025-01-01', taxaJurosAa:'',
                     sistemaAmortizacao:'sac', numeroParcelas:1, carenciaMeses:0, valorIof:0, valorSeguro:0, fazendaId:'', garantia:'', observacao:'',
                     _erpChave:'X', _erpResumo:{contrato:'C99', pagas:0, totalPago:0, aVencer:1, totalAVencer:1000, primeira:'2027-01-01', ultima:'2027-01-01'}};
        state.modal = {type:'financiamento'}; render(); }""")
    page.wait_for_timeout(250)
    conf(page.evaluate("() => !document.getElementById('f-saldobancofin') && !document.getElementById('f-saldobancoemfin')"),
         "'Lancar contrato do ERP' nao tem o campo (ali nao ha extrato do banco)")
    page.evaluate("() => { state.modal = null; editDraft = null; render(); }")

    # ---- 8. sem rolar de lado ----
    MEDE = """() => { const out=[]; const d=document.documentElement;
      if(d.scrollWidth>d.clientWidth+1) out.push('pagina +'+(d.scrollWidth-d.clientWidth)+'px');
      document.querySelectorAll('*').forEach(el=>{ const cs=getComputedStyle(el);
        if((cs.overflowX==='auto'||cs.overflowX==='scroll') && el.clientWidth>0 && el.scrollWidth>el.clientWidth+1)
          out.push((el.className||el.tagName)+' +'+(el.scrollWidth-el.clientWidth)+'px'); });
      document.querySelectorAll('.stat-card').forEach(el=>{ if(el.scrollWidth>el.clientWidth+1) out.push('stat-card +'+(el.scrollWidth-el.clientWidth)+'px'); });
      return out; }"""
    # banco de volta com os campos (a tela acima apagou o do contrato 1)
    page.evaluate("""() => { const f = state.financiamentos.find(x => x.id === 1); f.saldoBanco = 340000.50; f.saldoBancoEm = '2026-10-16'; }""")
    for w in (1920, 1280, 1100, 1061, 1024, 800, 390, 376, 320):
        page.set_viewport_size({"width": w, "height": 900})
        lista()
        rolou_lista = page.evaluate(MEDE)
        abrir(1)
        rolou_det = page.evaluate(MEDE)
        conf(not rolou_lista and not rolou_det, f"{w} px: lista e tela do contrato sem rolar de lado", f"lista {rolou_lista} | contrato {rolou_det}")
        if w <= 800:
            lista()
            rotulos = page.evaluate("""() => { const tr = [...document.querySelectorAll('tbody tr')].find(t => t.innerText.includes('Banco Alfa'));
                return [...tr.children].map(td => getComputedStyle(td, '::before').content); }""")
            conf(rotulos[1:6] == ['"Contratado"', '"Data do contrato"', '"Saldo devedor"', '"Próxima parcela"', '"Status"'],
                 f"{w} px: cada linha vira um bloco com o nome de cada coluna", str(rotulos))

    conf(not [e for e in erros if not any(r in e for r in ruido)], "nenhum erro de JavaScript do comeco ao fim", " | ".join(erros[:3]))
    browser.close()

print(f"\n{passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
