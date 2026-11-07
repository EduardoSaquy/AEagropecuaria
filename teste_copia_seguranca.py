"""
Copia de seguranca dos dados no AE Matriz (07/11/2026). O plano gratuito do Supabase nao guarda copia automatica; em Usuarios o
administrador baixa um arquivo com todas as tabelas e uma planilha dos lancamentos para o contador. Prova:
  - o cartao aparece para o administrador (e nao existe para outro perfil), com "Nenhuma copia baixada" ate a primeira;
  - "Baixar copia dos dados": baixa AE_copia_AAAA-MM-DD.json com TODAS as linhas (inclusive mais de 1000 por tabela, paginadas),
    uma chave por tabela, o resumo com a contagem, quem gerou e quando;
  - tabela que a permissao nao deixa ler fica de fora, aparece no resumo e no aviso, e nao derruba o resto;
  - depois da copia a tela mostra a data da ultima copia;
  - "Baixar lancamentos em planilha": CSV com BOM, ponto e virgula, virgula decimal, data dd/mm/aaaa, mes recorrente marcado,
    aspas e quebra de linha dentro do texto preservadas, texto que o Excel leria como formula neutralizado;
  - nada disso viola a politica de seguranca de conteudo da pagina e nao ha erro de JavaScript.
"""
import csv
import io
import json
import re
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}

lanc = [
    {"id": 1, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 1, "descricao": "=HYPERLINK(\"http://x\")", "valor": 1234.5,
     "data": "2026-03-05", "mes": "2026-03", "fornecedor": "Fornecedor A", "observacao": "", "ano_safra": 2025},
    {"id": 2, "tipo": "receita", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 2, "descricao": 'Venda "boa"; com ponto e virgula\nsegunda linha', "valor": 99.99,
     "data": "2026-04-10", "mes": "2026-04", "fornecedor": "", "observacao": "obs", "ano_safra": None},
    {"id": 3, "tipo": "despesa", "atividade": "graos", "fazenda_id": 1, "centro_custo_id": 1, "descricao": "Conta recorrente", "valor": 500,
     "data": None, "mes": None, "fornecedor": "", "observacao": "", "ano_safra": None},
]
# mais de 1000 linhas: a copia tem de paginar
lanc += [{"id": 100 + i, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 1, "descricao": f"Lancamento {i}", "valor": 10 + i,
          "data": "2026-05-01", "mes": "2026-05", "fornecedor": "", "observacao": "", "ano_safra": None} for i in range(2302)]
DB = {
    "fazendas": [{"id": 1, "nome": "Fazenda Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [],
    "lotes": [{"id": 1, "nome": "Curral 1"}], "animais": [{"id": 1, "numero": "10"}, {"id": 2, "numero": "11"}],
    "pesagens": [{"id": 1, "data": "2026-05-01", "lote_id": 1, "peso_medio_kg": 400}],
    "centros_custo": [{"id": 1, "nome": "Nutricao animal", "tipo": "saida", "subcategoria": "INSUMOS | Nutricao animal"},
                      {"id": 2, "nome": "Vendas", "tipo": "entrada", "subcategoria": "RECEITAS | Vendas"}],
    "lancamentos_financeiros": lanc, "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
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
    ctx = browser.new_context(viewport={"width": 1280, "height": 900}, accept_downloads=True)
    page = ctx.new_page()
    erros, csp = [], []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("console", lambda m: csp.append(m.text) if "Content Security Policy" in m.text else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.lancamentos.length > 2000", timeout=30000)
    page.wait_for_timeout(500)
    page.evaluate("() => { state.page = 'usuarios'; render(); }")
    page.wait_for_timeout(300)

    print("== o cartao")
    corpo = page.inner_text("body")
    conf("Cópia de segurança dos dados" in corpo and page.locator("[data-baixar-copia]").count() == 1, "o administrador ve o cartao da copia")
    conf("Nenhuma cópia foi baixada neste aparelho ainda" in corpo, "antes da primeira copia diz que nenhuma foi baixada")
    conf("O plano gratuito do banco de dados não guarda cópia automática" in corpo, "explica por que baixar")
    nao_admin = page.evaluate("() => { const p = state.perfil; state.perfil = {...p, papel: 'proprietario'}; const h = PageUsuarios(); state.perfil = p; return h; }")
    conf("data-baixar-copia" not in nao_admin and "data-baixar-csv" not in nao_admin, "quem nao e administrador nao tem os botoes")

    print("== copia dos dados")
    # uma tabela que a permissao nao deixa ler
    page.evaluate("""() => {
      const orig = db.from.bind(db);
      db.from = (t) => {
        if (t === 'pesagens') {
          const q = { select(){return q;}, order(){return q;}, range(){ return Promise.resolve({data: null, error: {code: '42501', message: 'permission denied for table pesagens'}}); } };
          return q;
        }
        return orig(t);
      };
    }""")
    with page.expect_download(timeout=60000) as dl:
        page.click("[data-baixar-copia]")
    d = dl.value
    conf(re.fullmatch(r"AE_copia_\d{4}-\d{2}-\d{2}\.json", d.suggested_filename) is not None, "o arquivo se chama AE_copia_AAAA-MM-DD.json", d.suggested_filename)
    dados = json.loads(Path(d.path()).read_text(encoding="utf-8"))
    conf(dados["app"] == "AE Agropecuária" and dados["geradoPor"] == "Eduardo Saquy" and dados["geradoEm"].startswith("20"), "traz quem gerou e quando")
    tab = dados["tabelas"]
    conf(len(tab["lancamentos_financeiros"]) == 2305, "os 2.305 lancamentos estao la (paginado de 1000 em 1000)", str(len(tab["lancamentos_financeiros"])))
    ids = [r["id"] for r in tab["lancamentos_financeiros"]]
    conf(len(set(ids)) == 2305, "sem linha repetida entre as paginas")
    conf(len(tab["centros_custo"]) == 2 and len(tab["fazendas"]) == 1 and len(tab["animais"]) == 2 and len(tab["lotes"]) == 1, "as outras tabelas tambem")
    conf(len(tab["lancamentos_rateados"]) == 2305, "a visao do rateio vai junto (o rateio em si e fechado a quem esta logado)")
    conf("pesagens" not in tab and "permission denied" in dados["resumo"]["pesagens"]["erro"], "tabela sem permissao fica de fora e aparece no resumo")
    conf(dados["resumo"]["lancamentos_financeiros"] == {"linhas": 2305}, "o resumo tem a contagem de cada tabela")
    conf("lancamento_rateios" not in tab and "contas_bancarias" not in tab and "log_alteracoes" not in tab, "conta bancaria, rateios brutos e registro de alteracoes nao entram")
    status = page.inner_text("[data-copia-status]")
    conf("Cópia pronta" in status and "Não baixou: pesagens" in status, "o aviso diz o que ficou de fora", status)
    page.evaluate("() => render()")
    page.wait_for_timeout(200)
    conf("Última cópia baixada neste aparelho" in page.inner_text("body"), "depois da copia a tela mostra a data da ultima")
    conf(page.locator("[data-baixar-copia]").is_enabled(), "o botao volta a ficar disponivel")

    print("== planilha para o contador")
    with page.expect_download(timeout=30000) as dl2:
        page.click("[data-baixar-csv]")
    d2 = dl2.value
    conf(re.fullmatch(r"AE_lancamentos_\d{4}-\d{2}-\d{2}\.csv", d2.suggested_filename) is not None, "o arquivo se chama AE_lancamentos_AAAA-MM-DD.csv", d2.suggested_filename)
    bruto = Path(d2.path()).read_bytes()
    conf(bruto.startswith(b"\xef\xbb\xbf"), "comeca com BOM (o Excel abre os acentos certos)")
    linhas = list(csv.reader(io.StringIO(bruto.decode("utf-8-sig")), delimiter=";"))
    conf(linhas[0][:3] == ["Data", "Mês", "Tipo"] and len(linhas) == 2306, "cabecalho e uma linha por lancamento", str(len(linhas)))
    por_id = {r[12]: r for r in linhas[1:]}
    a = por_id["1"]
    conf(a[0] == "05/03/2026" and a[1] == "03/2026" and a[9] == "1234,50", "data dd/mm/aaaa, mes mm/aaaa e valor com virgula decimal", str(a))
    conf(a[4] == "Fazenda Mata Verde" and a[5] == "Nutricao animal" and a[6] != "", "fazenda, centro de custo e grupo por nome", str(a))
    conf(a[7].startswith("'="), "texto que o Excel leria como formula vem neutralizado", a[7])
    conf(por_id["2"][7] == 'Venda "boa"; com ponto e virgula\nsegunda linha', "aspas, ponto e virgula e quebra de linha dentro do texto ficam inteiros", repr(por_id["2"][7]))
    conf(por_id["3"][0] == "" and por_id["3"][1] == "Recorrente", "lancamento recorrente aparece como Recorrente", str(por_id["3"]))
    conf(por_id["1"][11] == "2025" and por_id["2"][11] == "", "ano da safra so quando existe")

    print("== seguranca da pagina")
    conf(not csp, "nenhuma violacao da politica de seguranca de conteudo", str(csp[:2]))
    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
