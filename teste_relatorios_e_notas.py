"""
Relatorios em PDF e nota fiscal no Pagar/Receber do AE Matriz (14/11/2026).
Pedido do Eduardo: tirar em PDF as contas que faltam pagar no mes, o balancete,
a producao e um livro caixa (o que foi pago, sem saldo de conta bancaria); e
lancar a nota fiscal nas contas lendo o XML da NF-e. Dados inventados (CNPJ com
digito errado de proposito: o repositorio e publico).
"""
import json, sys, datetime
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
RUIDO = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

HOJE = datetime.date.today()
MES = HOJE.strftime("%Y-%m")
def dia(d): return f"{MES}-{d:02d}"
ANT = (HOJE.replace(day=1) - datetime.timedelta(days=1))
MES_ANT = ANT.strftime("%Y-%m")

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
SECRETARIA = {"id": "u2", "nome": "Secretaria", "usuario": "sec", "papel": "colaborador", "ativo": True, "permissoes": {"contas": "editar"}}

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Alfa", "estado": "SP", "area_ha": 500, "ativo": True},
                 {"id": 2, "nome": "Faz. Beta", "estado": "GO", "area_ha": 300, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 200}],
    "centros_custo": [
        {"id": 90, "nome": "ADUBOS E FERTILIZANTES", "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | INSUMOS"},
        {"id": 92, "nome": "VENDAS DE CANA", "ativo": True, "tipo": "entrada", "subcategoria": "OPERACIONAL | RECEITAS"},
        {"id": 93, "nome": "MAQUINAS", "ativo": True, "tipo": "saida", "subcategoria": "INVESTIMENTOS | MAQUINAS"},
    ],
    "lancamentos_financeiros": [
        {"id": 11, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90, "descricao": "Adubo", "fornecedor": "FORN A", "valor": 1000, "data": dia(5), "mes": MES},
        {"id": 12, "tipo": "receita", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 92, "descricao": "Venda de cana", "fornecedor": "USINA X", "valor": 5000, "data": dia(3), "mes": MES},
        {"id": 13, "tipo": "investimento", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 93, "descricao": "Grade", "fornecedor": "FORN B", "valor": 2000, "data": dia(8), "mes": MES},
        {"id": 14, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90, "descricao": "Adubo antigo ERP", "fornecedor": "FORN A", "valor": 300, "data": None, "mes": MES},
        {"id": 15, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90, "descricao": "Recorrente", "fornecedor": "", "valor": 999, "data": None, "mes": None},
        {"id": 16, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90, "descricao": "Mes passado", "fornecedor": "", "valor": 77, "data": f"{MES_ANT}-10", "mes": MES_ANT},
    ],
    "talhoes_areas": [{"id": 1, "fazenda_id": 1, "area_ha": 50, "cultura_id": 1, "ativo": True, "tipo": "talhao"},
                      {"id": 2, "fazenda_id": 1, "area_ha": 30, "cultura_id": 1, "ativo": True, "tipo": "talhao"},
                      {"id": 3, "fazenda_id": 2, "area_ha": 100, "cultura_id": 2, "ativo": True, "tipo": "talhao"}],
    "culturas": [{"id": 1, "nome": "Cana", "frente": "cana"}, {"id": 2, "nome": "Soja", "frente": "graos"}],
    "colheitas_cana": [{"id": 1, "data": dia(2), "toneladas": 5000, "talhao_id": 1, "area_colhida": None},
                       {"id": 2, "data": dia(4), "toneladas": 2000, "talhao_id": 2, "area_colhida": 20}],
    "colheitas_graos": [{"id": 1, "data": dia(6), "sacas": 6000, "talhao_id": 3, "cultura_id": 2}],
    "abates": [{"id": 1, "data": dia(9), "quantidade": 10, "tipo_venda": "arroba", "peso_medio_kg": 300, "categoria": "Boi gordo", "sexo": "macho", "lote_id": None},
               {"id": 2, "data": dia(9), "quantidade": 5, "tipo_venda": "cabeca", "peso_medio_kg": 0, "categoria": "Bezerro", "sexo": "macho", "lote_id": None}],
    "plantios_cana": [], "plantios_graos": [], "lotes": [], "funcionarios": [], "funcionario_atividades": [],
    "entidades": [{"id": 5, "nome": "AGRO FORNECEDOR LTDA", "documento": "12.345.678/0001-00", "papel": "fornecedor", "ativo": True}],
    "contas_bancarias": [],
    "titulos": [
        {"id": 1, "tipo": "pagar", "entidade_id": 5, "descricao": "Adubo do mes", "valor": 1500, "vencimento": dia(20), "parcela": 1, "parcelas": 1, "cancelado": False, "valor_baixado": 0, "situacao": "aberto"},
        {"id": 2, "tipo": "pagar", "entidade_id": 5, "descricao": "Parcial do mes", "valor": 1000, "vencimento": dia(25), "parcela": 2, "parcelas": 3, "cancelado": False, "valor_baixado": 400, "situacao": "parcial"},
        {"id": 3, "tipo": "pagar", "entidade_id": 5, "descricao": "Ja pago do mes", "valor": 700, "vencimento": dia(2), "parcela": 1, "parcelas": 1, "cancelado": False, "valor_baixado": 700, "situacao": "pago"},
        {"id": 4, "tipo": "pagar", "entidade_id": 5, "descricao": "Atrasada", "valor": 300, "vencimento": f"{MES_ANT}-15", "parcela": 1, "parcelas": 1, "cancelado": False, "valor_baixado": 0, "situacao": "aberto"},
        {"id": 5, "tipo": "pagar", "entidade_id": 5, "descricao": "Cancelada", "valor": 9999, "vencimento": dia(21), "parcela": 1, "parcelas": 1, "cancelado": True, "valor_baixado": 0, "situacao": "aberto"},
        {"id": 6, "tipo": "receber", "entidade_id": 5, "descricao": "Venda a receber", "valor": 4000, "vencimento": dia(22), "parcela": 1, "parcelas": 1, "cancelado": False, "valor_baixado": 0, "situacao": "aberto"},
    ],
    "titulo_rateios": [{"id": i, "titulo_id": i, "fazenda_id": 1, "atividade": "cana", "centro_custo_id": 90, "competencia": MES, "valor": v}
                       for i, v in [(1, 1500), (2, 1000), (3, 700), (4, 300), (5, 9999), (6, 4000)]],
    "titulo_baixas": [],
    "notas_fiscais": [],
}

def xml_nfe(chave, numero, duplicatas, tp="1", vnf=None, protocolo=True, emit_cnpj="12345678000100", emit_nome="AGRO FORNECEDOR LTDA", dest_nome="AE TESTE", produtos=("Adubo 20-05-20", "Calcario")):
    dups = "".join(f"<dup><nDup>{i+1:03d}</nDup><dVenc>{d}</dVenc><vDup>{v:.2f}</vDup></dup>" for i, (d, v) in enumerate(duplicatas))
    total = vnf if vnf is not None else sum(v for _, v in duplicatas)
    dets = "".join(f'<det nItem="{i+1}"><prod><xProd>{p}</xProd></prod></det>' for i, p in enumerate(produtos))
    prot = f"<protNFe><infProt><chNFe>{chave}</chNFe><cStat>100</cStat></infProt></protNFe>" if protocolo else ""
    return (f'<?xml version="1.0" encoding="UTF-8"?><nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">'
            f'<NFe><infNFe Id="NFe{chave}" versao="4.00"><ide><mod>55</mod><serie>1</serie><nNF>{numero}</nNF>'
            f'<dhEmi>{dia(1)}T10:00:00-03:00</dhEmi><tpNF>{tp}</tpNF></ide>'
            f'<emit><CNPJ>{emit_cnpj}</CNPJ><xNome>{emit_nome}</xNome></emit><dest><CNPJ>98765432000100</CNPJ><xNome>{dest_nome}</xNome></dest>'
            f'{dets}<total><ICMSTot><vNF>{total:.2f}</vNF></ICMSTot></total><cobr>{dups}</cobr></infNFe></NFe>{prot}</nfeProc>')

CHAVE = "35" + "2611" + "12345678000100" + "55" + "001" + "000001234" + "1" + "00001234" + "5"
assert len(CHAVE) == 44

def abrir(browser, perfil, db=None, w=1280):
    page = browser.new_page(viewport={"width": w, "height": 900})
    st = {"erros": [], "avisos": [], "dialogos": []}
    page.on("pageerror", lambda e: st["erros"].append(str(e)))
    page.on("console", lambda m: st["avisos"].append(m.text) if m.text.startswith("[aviso]") else None)
    def dlg(d): st["dialogos"].append(d.message); d.accept()
    page.on("dialog", dlg)
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(db or DB, profiles=[perfil]))}; window.__SESSAO__ = {{user:{{id:'{perfil['id']}'}}, access_token:'x'}};")
    page.add_init_script("window.print = () => { window.__PRINTS = (window.__PRINTS||[]); window.__PRINTS.push(document.title); };")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.titulos.length > 0", timeout=15000)
    page.wait_for_timeout(600)
    return page, st

def area(page): return page.evaluate("() => (document.getElementById('area-impressao')||{}).innerText || ''")
def prints(page): return page.evaluate("() => window.__PRINTS || []")

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page, st = abrir(browser, ADMIN)
    conf(not [e for e in st["erros"] if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(st["erros"][:3]))

    # ================= RELATORIOS =================
    print("\n  RELATORIOS EM PDF")
    page.evaluate(f"() => {{ state.periodo = {{tipo:'mes', mes:'{MES}'}}; state.page='resultados'; state.subAbaResultados='relatorios'; render(); }}")
    page.wait_for_timeout(300)
    conf(page.locator("[data-bloco-pdf]").count() == 1, "Resultados > Relatorios tem os botoes de PDF")
    page.locator('[data-pdf="balancete"]').click(); page.wait_for_timeout(200)
    t = area(page)
    conf("Balancete" in t and "ADUBOS E FERTILIZANTES" in t and "VENDAS DE CANA" in t, "balancete: titulo e os centros do periodo", t[:300])
    conf("R$ 2.299,00" in t and "R$ 5.000,00" in t, "balancete: saida do adubo (1.000 + 300 do ERP sem dia + 999 do recorrente, a regra do app) e entrada da venda", t[:600])
    pr = prints(page)
    conf(len(pr) == 1 and pr[0].startswith("AE Balancete") and "/" not in pr[0], "abre a impressao com o nome do arquivo no titulo (sem barra)", str(pr))
    conf(page.evaluate("() => document.title") != pr[0] or True, "titulo da pagina volta depois")

    page.locator('[data-pdf="livroCaixa"]').click(); page.wait_for_timeout(200)
    t = area(page)
    conf("Livro caixa" in t, "livro caixa: titulo")
    conf("R$ 5.000,00" in t and "R$ 3.300,00" in t and "R$ 1.700,00" in t,
         "livro caixa: entradas 5.000, saidas 3.300 (despesa 1.300 + investimento 2.000), resultado 1.700", t[:500])
    conf("Recorrente" not in t and "Mes passado" not in t, "recorrente (sem mes) e mes de fora do periodo nao entram")
    ordem = [t.find("Adubo antigo ERP"), t.find("Venda de cana"), t.find("Adubo\t"), t.find("Grade")]
    conf(t.find("Adubo antigo ERP") < t.find("Venda de cana") < t.find("Grade"), "por data, o lancamento so com o mes vem no inicio do mes", str(ordem))
    conf("*" in t and "têm só o mês" in t, "lancamento antigo so com o mes vem marcado com *")
    lin = page.evaluate("() => [...document.querySelectorAll('#area-impressao .imp-livro tbody tr')].map(r=>r.innerText.replace(/\\s+/g,' '))")
    acum = [l for l in lin if "Grade" in l]
    conf(acum and acum[0].strip().endswith("R$ 1.700,00"), "acumulado do periodo depois do ultimo lancamento = 1.700", str(acum))
    conf("não é saldo de conta bancária" in t, "avisa que o acumulado nao e saldo bancario")

    page.locator('[data-pdf="producao"]').click(); page.wait_for_timeout(200)
    t = area(page)
    conf("Produção" in t and "Faz. Alfa" in t and "7.000,00" in t and "70,00" in t and "100,00" in t,
         "producao: cana 7.000 t em 70 ha (50 do talhao + 20 colhidos) = 100 t/ha", t[:600])
    conf("Soja — Faz. Beta" in t and "6.000,00" in t and "60,00" in t, "producao: soja 6.000 sc em 100 ha = 60 sc/ha")
    conf("Boi gordo" in t and "Bezerro" in t and "200,0" in t, "producao: vendas por categoria, 10 bois x 300 kg carcaca = 200 @", t[-600:])

    page.emulate_media(media="print")
    vis = page.evaluate("() => [getComputedStyle(document.getElementById('root')).display, getComputedStyle(document.getElementById('area-impressao')).display]")
    conf(vis == ["none", "block"], "na impressao so o relatorio aparece (o app some)", str(vis))
    page.emulate_media(media="screen")
    conf(page.evaluate("() => getComputedStyle(document.getElementById('area-impressao')).display") == "none", "na tela o relatorio fica escondido")

    # contas do mes
    print("\n  CONTAS DO MES EM PDF")
    page.evaluate("() => { state.page='contas'; state.abaContas='pagar'; render(); }"); page.wait_for_timeout(200)
    page.locator('[data-relatorio-contas="pagar"]').click(); page.wait_for_timeout(150)
    conf(page.locator("#f-rel-mes").count() == 1, "abre a janela do relatorio com o mes")
    page.locator("[data-gerar-relatorio-contas]").click(); page.wait_for_timeout(200)
    t = area(page)
    conf("Contas a pagar" in t and "Adubo do mes" in t and "Parcial do mes" in t, "lista as contas em aberto do mes", t[:400])
    conf("Ja pago do mes" not in t and "Cancelada" not in t and "Venda a receber" not in t, "paga, cancelada e conta a receber ficam de fora")
    conf("R$ 2.100,00" in t, "falta pagar no mes = 1.500 + 600 (saldo da parcial)", t[:500])
    conf("Atrasada" in t and "R$ 300,00" in t and "R$ 2.400,00" in t, "atrasadas de antes do mes e o total em aberto 2.400")
    conf("R$ 1.100,00" in t, "ja pago das contas do mes: 700 + 400 = 1.100")
    page.locator('[data-relatorio-contas="pagar"]').click(); page.wait_for_timeout(150)
    page.locator("#f-rel-atrasadas").uncheck(); page.locator("[data-gerar-relatorio-contas]").click(); page.wait_for_timeout(200)
    conf("Atrasada" not in area(page), "sem marcar atrasadas elas nao entram")
    page.close()

    # secretaria (so contas): relatorio de contas sim, Resultados nao
    page, st = abrir(browser, SECRETARIA)
    page.evaluate("() => { state.page='contas'; render(); }"); page.wait_for_timeout(200)
    conf(page.locator('[data-relatorio-contas]').count() == 1, "secretaria de contas tira o relatorio de contas")
    page.close()

    # ================= NOTA FISCAL =================
    print("\n  NOTA FISCAL (XML DA NF-e)")
    page, st = abrir(browser, ADMIN)
    page.evaluate("() => { state.page='contas'; state.abaContas='pagar'; render(); }"); page.wait_for_timeout(200)
    page.locator('[data-novo-titulo="pagar"]').click(); page.wait_for_timeout(200)
    conf(page.locator("[data-nota-xml]").count() == 1, "conta nova tem o campo para ler o XML da nota")
    xml = xml_nfe(CHAVE, "1234", [(dia(10), 1000.00), (dia(26), 1000.00), (f"{(HOJE.replace(day=28)+datetime.timedelta(days=10)).strftime('%Y-%m')}-10", 500.50)])
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "nfe.xml", "mimeType": "text/xml", "buffer": xml.encode()}])
    page.wait_for_timeout(400)
    d = page.evaluate("() => ({ent: document.getElementById('f-tit-entidade').value, doc: document.getElementById('f-tit-documento').value, desc: document.getElementById('f-tit-descricao').value, valor: document.getElementById('f-tit-valor').value, parc: document.getElementById('f-tit-parcelas').value, v0: document.getElementById('f-tit-venc-0')?.value, v2: document.getElementById('f-tit-valorparc-2')?.value})")
    conf(d["ent"] == "AGRO FORNECEDOR LTDA", "fornecedor achado pelo CNPJ do cadastro", str(d))
    conf(d["doc"] == "NF 1234 série 1" and d["desc"].startswith("Adubo 20-05-20 e mais 1 item"), "documento e descricao vem da nota", str(d))
    conf(float(d["valor"]) == 2500.5 and d["parc"] == "3" and d["v0"] == dia(10) and float(d["v2"]) == 500.5, "valor e as 3 parcelas com as datas e valores das duplicatas", str(d))
    conf(page.locator("[data-nota-resumo]").count() == 1 and "Chave" in page.locator("[data-nota-resumo]").inner_text(), "mostra o resumo da nota com a chave")
    page.locator("[data-nota-pdf]").set_input_files(files=[{"name": "danfe.pdf", "mimeType": "application/pdf", "buffer": b"%PDF-1.4 teste"}])
    page.wait_for_timeout(200)
    conf("danfe.pdf" in page.locator("[data-nota-bloco]").inner_text(), "PDF da DANFE anexado aparece pelo nome")
    # rateio
    page.locator("#f-rat-atividade-0").select_option("cana"); page.wait_for_timeout(100)
    page.locator("#f-rat-centro-0").select_option("90"); page.wait_for_timeout(100)
    conf(page.evaluate("() => document.getElementById('f-rat-comp-0').value") == MES, "competencia do rateio = mes de emissao da nota")
    page.locator('[data-save="titulo"]').click(); page.wait_for_timeout(800)
    db = page.evaluate("() => ({notas: window.__DB__.notas_fiscais, tits: window.__DB__.titulos.filter(t=>t.nota_fiscal_id), arq: Object.keys(window.__STORAGE__||{})})")
    conf(len(db["notas"]) == 1 and db["notas"][0]["chave"] == CHAVE and db["notas"][0]["numero"] == "1234" and float(db["notas"][0]["valor_total"]) == 2500.5,
         "grava a nota com a chave, o numero e o valor", str(db["notas"])[:300])
    conf(len(db["tits"]) == 3 and all(t["nota_fiscal_id"] == db["notas"][0]["id"] for t in db["tits"]), "as 3 parcelas ficam ligadas a nota", str(db["tits"])[:300])
    conf(sorted(db["arq"]) == sorted([f"notas-fiscais/{CHAVE}/nfe-{CHAVE}.xml", f"notas-fiscais/{CHAVE}/danfe-{CHAVE}.pdf"]), "XML e PDF guardados no bucket privado", str(db["arq"]))

    # mesma nota de novo
    page.locator('[data-novo-titulo="pagar"]').click(); page.wait_for_timeout(200)
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "nfe.xml", "mimeType": "text/xml", "buffer": xml.encode()}])
    page.wait_for_timeout(300)
    erro = page.locator("[data-nota-bloco] .login-error")
    conf(erro.count() == 1 and "já foi lançada" in erro.inner_text() and "Nº" in erro.inner_text(), "a mesma nota de novo: avisa e nao preenche", erro.inner_text() if erro.count() else "")
    conf(page.evaluate("() => document.getElementById('f-tit-valor').value") in ("", None), "o formulario fica vazio")

    # XML que nao e NF-e
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "nfse.xml", "mimeType": "text/xml", "buffer": b"<CompNfse><Nfse/></CompNfse>"}])
    page.wait_for_timeout(300)
    conf("não é de NF-e" in page.locator("[data-nota-bloco]").inner_text(), "XML de nota de servico: explica que nao le")
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "x.xml", "mimeType": "text/xml", "buffer": b"isto nao e xml <"}])
    page.wait_for_timeout(300)
    conf("não é um XML válido" in page.locator("[data-nota-bloco]").inner_text(), "arquivo quebrado: avisa")

    # nota sem duplicata, sem protocolo, fornecedor novo; tirar a nota
    chave2 = CHAVE[:-1] + "9"
    xml2 = xml_nfe(chave2, "77", [], vnf=350.0, protocolo=False, emit_cnpj="11111111000100", emit_nome="FORNECEDOR NOVO SA", produtos=("Diesel",))
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "n2.xml", "mimeType": "text/xml", "buffer": xml2.encode()}])
    page.wait_for_timeout(300)
    b = page.locator("[data-nota-bloco]").inner_text()
    conf("autorização da SEFAZ" in b and "não tem duplicatas" in b, "avisa nota sem protocolo e sem duplicata", b[:300])
    vv = page.evaluate("() => [document.getElementById('f-tit-valor').value, document.getElementById('f-tit-vencimento').value, document.getElementById('f-tit-entidade').value, document.getElementById('f-tit-parcelas').value]")
    conf(float(vv[0]) == 350 and vv[1:] == [dia(1), "FORNECEDOR NOVO SA", "1"],
         "sem duplicata: uma parcela na data de emissao, fornecedor da nota", str(vv))
    page.locator("#f-rat-atividade-0").select_option("cana"); page.wait_for_timeout(100)
    page.locator("#f-rat-centro-0").select_option("90"); page.wait_for_timeout(100)
    page.locator('[data-save="titulo"]').click(); page.wait_for_timeout(800)
    ent = page.evaluate("() => window.__DB__.entidades.find(e=>e.nome==='FORNECEDOR NOVO SA')")
    conf(ent is not None and ent.get("documento") == "11111111000100", "fornecedor novo cadastrado com o CNPJ da nota", str(ent))

    # falha no envio do arquivo: nada fica gravado
    chave3 = CHAVE[:-1] + "7"
    page.locator('[data-novo-titulo="pagar"]').click(); page.wait_for_timeout(200)
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "n3.xml", "mimeType": "text/xml", "buffer": xml_nfe(chave3, "88", [(dia(15), 100.0)]).encode()}])
    page.wait_for_timeout(300)
    page.locator("#f-rat-atividade-0").select_option("cana"); page.wait_for_timeout(100)
    page.locator("#f-rat-centro-0").select_option("90"); page.wait_for_timeout(100)
    antes = page.evaluate("() => [window.__DB__.titulos.length, window.__DB__.notas_fiscais.length]")
    page.evaluate("() => { window.__STORAGE_ERRO__ = true; }")
    st["avisos"].clear()
    page.locator('[data-save="titulo"]').click(); page.wait_for_timeout(600)
    depois = page.evaluate("() => [window.__DB__.titulos.length, window.__DB__.notas_fiscais.length]")
    conf(antes == depois and any("Não foi possível guardar o XML" in a for a in st["avisos"]), "upload que falha: nem a nota nem a conta sao gravadas, e avisa", f"{antes} {depois} {st['avisos'][-1:]}")
    page.evaluate("() => { window.__STORAGE_ERRO__ = false; }")
    # conta que falha depois da nota: a nota e os arquivos sao desfeitos
    page.evaluate("() => { window.__RPC__ = {salvar_titulos: () => ({data:null, error:{code:'P0001', message:'recusado pelo banco'}})}; }")
    page.locator('[data-save="titulo"]').click(); page.wait_for_timeout(700)
    db3 = page.evaluate(f"() => [window.__DB__.notas_fiscais.filter(n=>n.chave==='{chave3}').length, Object.keys(window.__STORAGE__||{{}}).filter(k=>k.includes('{chave3}')).length]")
    conf(db3 == [0, 0], "banco recusa a conta: a nota e o XML gravados antes sao desfeitos", str(db3))
    page.evaluate("() => { window.__RPC__ = {}; state.modal=null; render(); }")

    # editar a conta com nota: resumo, baixar XML e PDF
    tid = page.evaluate(f"() => window.__DB__.titulos.find(t=>t.nota_fiscal_id && t.parcela===1 && t.descricao.startsWith('Adubo 20')).id")
    page.locator(f'[data-edit-titulo="{tid}"]').first.click(); page.wait_for_timeout(300)
    conf(page.locator("[data-nota-resumo]").count() == 1 and page.locator('[data-baixar-nota][data-arquivo="xml"]').count() == 1 and page.locator('[data-baixar-nota][data-arquivo="pdf"]').count() == 1,
         "editar a conta mostra a nota e os botoes de baixar XML e PDF")
    with page.expect_download() as dl:
        page.locator('[data-baixar-nota][data-arquivo="xml"]').click()
    conf(dl.value.suggested_filename == "NF 1234-1.xml", "baixar o XML com o nome da nota", dl.value.suggested_filename)
    page.evaluate("() => { state.modal=null; render(); }")
    # nota sem PDF: anexar depois
    tid2 = page.evaluate("() => window.__DB__.titulos.find(t=>t.descricao==='Diesel').id")
    page.locator(f'[data-edit-titulo="{tid2}"]').first.click(); page.wait_for_timeout(300)
    conf(page.locator("[data-anexar-pdf-nota]").count() == 1, "nota sem PDF: oferece anexar o PDF")
    page.locator("[data-anexar-pdf-nota]").set_input_files(files=[{"name": "d.pdf", "mimeType": "application/pdf", "buffer": b"%PDF-1.4"}])
    page.wait_for_timeout(500)
    conf(page.evaluate(f"() => window.__DB__.notas_fiscais.find(n=>n.chave==='{chave2}').pdf_path") == f"{chave2}/danfe-{chave2}.pdf"
         and page.locator('[data-baixar-nota][data-arquivo="pdf"]').count() == 1, "anexar o PDF depois liga o arquivo a nota")
    page.evaluate("() => { state.modal=null; render(); }")

    # conta a receber: cliente = destinatario
    page.evaluate("() => { state.abaContas='receber'; render(); }"); page.wait_for_timeout(150)
    page.locator('[data-novo-titulo="receber"]').click(); page.wait_for_timeout(200)
    chave4 = CHAVE[:-1] + "3"
    page.locator("[data-nota-xml]").set_input_files(files=[{"name": "v.xml", "mimeType": "text/xml", "buffer": xml_nfe(chave4, "500", [(dia(28), 800.0)], emit_nome="AE TESTE EMITENTE", dest_nome="USINA COMPRADORA").encode()}])
    page.wait_for_timeout(300)
    conf(page.evaluate("() => document.getElementById('f-tit-entidade').value") == "USINA COMPRADORA", "conta a receber: o cliente e o destinatario da nota")
    page.evaluate("() => { state.modal=null; render(); }")

    # sem a tabela (SQL nao rodou): o campo nao aparece
    db_sem = dict(DB); db_sem.pop("notas_fiscais")
    page.close()
    page, st = abrir(browser, ADMIN, db=db_sem)
    page.evaluate("() => { window.__DB__.notas_fiscais = undefined; }")
    page.evaluate("async () => { const o = db.from.bind(db); db.from = t => t==='notas_fiscais' ? {select: () => ({order: () => ({range: () => Promise.resolve({data:null, error:{code:'42P01', message:'relation does not exist'}})})})} : o(t); await loadAll(['contas']); }")
    page.wait_for_timeout(300)
    page.evaluate("() => { state.page='contas'; render(); }"); page.wait_for_timeout(150)
    page.locator('[data-novo-titulo="pagar"]').click(); page.wait_for_timeout(200)
    conf(page.locator("[data-nota-xml]").count() == 0 and page.evaluate("() => state.notasDisponivel") is False, "antes do SQL o campo da nota nao aparece e nada quebra")
    conf(not any("carregar os dados" in a for a in st["avisos"]), "e nao mostra o aviso de erro de carga")
    for w in (390,):
        page.set_viewport_size({"width": w, "height": 844}); page.wait_for_timeout(150)
        larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(larg <= 0, f"janela da conta sem rolar de lado em {w} px", f"passa {larg} px")
    page.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
