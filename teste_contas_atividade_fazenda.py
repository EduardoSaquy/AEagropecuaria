"""
Pagar/Receber com a coluna "Atividade / Fazenda" (pedido do Eduardo, 09/11/2026: "uma coluna mostrando a atividade relacionada
a conta e a fazenda").

Prova, com o app de verdade e o Supabase simulado:
  - a coluna existe em A Pagar e em A Receber, entre Descricao e Onde pesa;
  - conta de uma parte: a atividade (nome curto: "Cana") e a fazenda da parte ("Geral" quando a parte nao tem fazenda); "Onde pesa" fica so com o
    centro e a competencia (o valor e o da propria conta);
  - conta dividida: cada atividade/fazenda uma vez so (duas partes da mesma atividade e fazenda em centros diferentes
    aparecem uma vez) e "Onde pesa" segue com cada parte, sua atividade, fazenda e valor;
  - conta sem rateio: "—" na coluna e o aviso "sem rateio" continua em Onde pesa;
  - a busca acha pela atividade ("pecuaria");
  - a linha de total continua embaixo de Valor e Saldo;
  - nada rola de lado de 1920 a 320 px; no modo bloco (tablet e celular) a coluna aparece com o nome dela;
  - de 1280 px para cima e no tablet em pe (1100) nenhuma palavra da tabela (titulo ou celula) e cortada no meio
    ("VENCIMENT O" cortava antes; no iPad deitado, 1160 a 1279, "FORNECEDOR" ainda quebra com hifen, como ja quebrava);
  - nenhum erro de JavaScript.
Falha no codigo anterior (nao havia a coluna).
"""
import json
import datetime
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
HOJE = datetime.date.today()
D = lambda n: (HOJE + datetime.timedelta(days=n)).isoformat()
MES = HOJE.isoformat()[:7]


def tit(i, tipo, ent, desc, valor, venc):
    return {"id": i, "tipo": tipo, "entidade_id": ent, "descricao": desc, "valor": valor, "vencimento": venc, "parcela": 1,
            "parcelas": 1, "previsao": False, "cancelado": False, "valor_baixado": 0, "situacao": "aberto", "conta_bancaria_id": None}


def rat(i, t, ativ, faz, centro, valor):
    return {"id": i, "titulo_id": t, "fazenda_id": faz, "atividade": ativ, "centro_custo_id": centro, "competencia": MES, "valor": valor}


DB = {
    "fazendas": [{"id": 4, "nome": "Faz. Invernada", "estado": "TO", "area_ha": 1694, "ativo": True},
                 {"id": 5, "nome": "Fazenda Santa Alice", "estado": "TO", "area_ha": 898, "ativo": True}],
    "fazenda_atividades": [], "lotes": [], "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "MANUTENCAO DA FROTA", "frente": None, "ativo": True, "tipo": "saida",
                       "subcategoria": "OPERACIONAL | MANUTENCAO"},
                      {"id": 91, "fazenda_id": None, "nome": "PECAS", "frente": None, "ativo": True, "tipo": "saida",
                       "subcategoria": "OPERACIONAL | MANUTENCAO"},
                      {"id": 95, "fazenda_id": None, "nome": "VENDA DE GRAOS", "frente": None, "ativo": True, "tipo": "entrada",
                       "subcategoria": "OPERACIONAL | RECEITAS"}],
    "entidades": [{"id": 5, "nome": "AUTO ELETRICA", "documento": "", "papel": "fornecedor", "ativo": True},
                  {"id": 6, "nome": "COOPERATIVA", "documento": "", "papel": "cliente", "ativo": True}],
    "contas_bancarias": [],
    "titulos": [
        tit(107, "pagar", 5, "BATERIA PARA O TRATOR", 1100.00, D(3)),     # uma parte, sem fazenda
        tit(108, "pagar", 5, "CAMARA DE AR", 429.20, D(5)),               # uma parte, com fazenda
        tit(109, "pagar", 5, "FILTROS E OLEO", 900.00, D(8)),             # dividida: graos/Invernada + pecuaria/Santa Alice
        tit(110, "pagar", 5, "PNEU", 600.00, D(9)),                      # duas partes, mesma atividade e fazenda
        tit(111, "pagar", 5, "SEM RATEIO", 50.00, D(10)),
        tit(201, "receber", 6, "VENDA DE SOJA", 5000.00, D(12)),
    ],
    "titulo_rateios": [
        rat(1, 107, "cana", None, 90, 1100.00),
        rat(2, 108, "graos", 4, 90, 429.20),
        rat(3, 109, "graos", 4, 90, 600.00), rat(4, 109, "pecuaria", 5, 91, 300.00),
        rat(5, 110, "cana", 5, 90, 400.00), rat(6, 110, "cana", 5, 91, 200.00),
        rat(7, 201, "graos", 4, 95, 5000.00),
    ],
    "titulo_baixas": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1340, "height": 900})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.titulos && state.titulos.length === 6", timeout=20000)
    ev = page.evaluate

    def contas(aba="pagar", busca=""):
        ev("(a) => { state.modal=null; editDraft=null; state.page='contas'; state.abaContas=a.aba; state.filtroContas='todos';"
           " state.searchContas=a.busca; state.contasSelecionadas=[]; render(); }", {"aba": aba, "busca": busca})
        page.wait_for_timeout(150)

    def celula(id_, rotulo):
        return ev("(a) => { const tr = document.querySelector(`[data-num-id=\"${a.id}\"]`).closest('tr');"
                  " const td = tr.querySelector(`td[data-rotulo=\"${a.r}\"]`); return td ? td.innerText.trim() : null; }",
                  {"id": str(id_), "r": rotulo})

    def itens(id_):
        return ev("(id) => [...document.querySelector(`[data-num-id=\"${id}\"]`).closest('tr')"
                  ".querySelectorAll('[data-atividade-fazenda] .ativ-faz')].map(e => e.innerText.replace(/\\s+/g, ' ').trim())", str(id_))

    MEDE_CORTES = """() => {
      const t = document.querySelector('.tabela-contas'); const cortes = [];
      const cells = [...t.querySelectorAll('thead th, tbody td')].filter(c => !c.classList.contains('acoes'));
      for (const c of cells) {
        const cs = getComputedStyle(c); const util = c.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
        const walker = document.createTreeWalker(c, NodeFilter.SHOW_TEXT); let n;
        while ((n = walker.nextNode())) {
          const es = getComputedStyle(n.parentElement); const span = document.createElement('span');
          span.style.cssText = `position:absolute;visibility:hidden;white-space:nowrap;font:${es.font};letter-spacing:${es.letterSpacing};text-transform:${es.textTransform}`;
          document.body.appendChild(span);
          for (const w of n.textContent.split(/\\s+/).filter(Boolean)) { span.textContent = w; if (span.getBoundingClientRect().width > util + 0.5) cortes.push(w); }
          span.remove();
        }
      }
      return [...new Set(cortes)];
    }"""

    def rola_de_lado():
        return ev("() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1"
                  " || [...document.querySelectorAll('#root .card')].some(c => c.scrollWidth > c.clientWidth + 1)")

    print("\n  PAGAR/RECEBER: COLUNA ATIVIDADE / FAZENDA")
    contas()
    cab = ev("() => [...document.querySelectorAll('.tabela-contas thead th')].map(t => t.innerText.trim().toUpperCase())")
    conf("ATIVIDADE / FAZENDA" in cab, "a coluna existe em A Pagar", str(cab))
    if "ATIVIDADE / FAZENDA" in cab:
        i = cab.index("ATIVIDADE / FAZENDA")
        conf(cab[i - 1] == "DESCRIÇÃO" and cab[i + 1] == "ONDE PESA", "fica entre Descricao e Onde pesa", str(cab))
    conf(itens(107) == ["Cana Geral"], "uma parte sem fazenda: atividade e 'Geral'", str(itens(107)))
    conf(itens(108) == ["Grãos Faz. Invernada"], "uma parte com fazenda: atividade e fazenda", str(itens(108)))
    onde = celula(108, "Onde pesa")
    conf(onde == f"MANUTENCAO DA FROTA · {MES}", "uma parte: Onde pesa fica so com o centro e a competencia", onde)
    conf(itens(109) == ["Grãos Faz. Invernada", "Pecuária Fazenda Santa Alice"], "conta dividida: cada atividade/fazenda", str(itens(109)))
    onde = celula(109, "Onde pesa") or ""
    conf("Grãos · Faz. Invernada" in onde and "R$ 600,00" in onde and "Pecuária · Fazenda Santa Alice" in onde and "R$ 300,00" in onde,
         "conta dividida: Onde pesa segue com cada parte e o valor dela", onde)
    conf(itens(110) == ["Cana Fazenda Santa Alice"], "duas partes da mesma atividade e fazenda aparecem uma vez", str(itens(110)))
    conf(itens(111) == [] and celula(111, "Atividade / Fazenda") == "—" and "sem rateio" in (celula(111, "Onde pesa") or ""),
         "sem rateio: '—' na coluna e o aviso continua em Onde pesa")
    alinh = ev("""() => { const th = [...document.querySelectorAll('.tabela-contas thead th')]; const tot = document.querySelector('.tabela-contas tr.linha-total');
        const v = th.find(t => t.innerText.trim().toUpperCase() === 'VALOR').getBoundingClientRect();
        const tv = tot.querySelector('td[data-rotulo="Valor"]').getBoundingClientRect(); return Math.abs(v.left - tv.left); }""")
    conf(alinh < 2, "a linha de total continua embaixo de Valor", str(alinh))

    contas(busca="pecuária")
    nums = ev("() => [...document.querySelectorAll('.tabela-contas [data-num-id]')].map(e => e.dataset.numId)")
    conf(nums == ["109"], "busca pela atividade acha a conta", str(nums))
    contas(aba="receber")
    conf(itens(201) == ["Grãos Faz. Invernada"], "A Receber tambem tem a coluna", str(itens(201)))

    print("\n  -- larguras --")
    for w in (1920, 1340, 1280, 1180, 1100, 1060, 820, 390, 320):
        page.set_viewport_size({"width": w, "height": 900})
        contas()
        conf(not rola_de_lado(), f"nada rola de lado em {w} px")
        if w in (1920, 1340, 1280, 1100):
            cortes = ev(MEDE_CORTES)
            conf(not cortes, f"nenhuma palavra cortada no meio em {w} px", str(cortes))
    page.set_viewport_size({"width": 390, "height": 844})
    contas()
    rot = ev("() => getComputedStyle(document.querySelector('[data-atividade-fazenda]'), '::before').content")
    conf("Atividade / Fazenda" in (rot or ""), "no celular a coluna aparece com o nome dela", str(rot))
    conf(page.locator("[data-atividade-fazenda]").first.is_visible(), "e aparece na tela")

    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
