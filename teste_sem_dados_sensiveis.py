"""
O repositorio e PUBLICO. Nenhum arquivo versionado pode ter CPF/CNPJ, numero de
conta bancaria, numero de contrato/cedula ou numero de documento/nota
(pedido do Eduardo, 15/10/2026: "qualquer referencia a numero de documento ou
conta bancaria, pode apagar ou trocar o nome").

Varre tudo que o git rastreia (git ls-files) e falha se achar:
  - CPF ou CNPJ de verdade (digitos verificadores conferem), formatado ou so
    com numeros;
  - o texto "(doc" seguido de numero na descricao (numero de documento do ERP);
  - nome de banco seguido de numero de conta (banco + 5 algarismos);
  - numero de contrato de credito rural no formato do Banco do Brasil
    (dois algarismos, barra, cinco algarismos, hifen e digito; ou 765. mais dois grupos de tres);
  - arquivo de dump de dados que deveria ficar so no computador.
Teste, script e documentacao novos usam numero inventado (ou apelido), nunca o real.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


def cpf_valido(d):
    if len(d) != 11 or len(set(d)) == 1: return False
    n = [int(c) for c in d]
    d1 = (sum(n[i] * (10 - i) for i in range(9)) * 10 % 11) % 10
    d2 = (sum(n[i] * (11 - i) for i in range(10)) * 10 % 11) % 10
    return n[9] == d1 and n[10] == d2

def cnpj_valido(d):
    if len(d) != 14 or len(set(d)) == 1: return False
    n = [int(c) for c in d]
    def dv(base, pesos):
        r = sum(a * b for a, b in zip(base, pesos)) % 11
        return 0 if r < 2 else 11 - r
    p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    return n[12] == dv(n[:12], p1) and n[13] == dv(n[:13], [6] + p1)

RE_FORMATADO = re.compile(r"(?<!\d)(\d{3}\.\d{3}\.\d{3}-\d{2}|\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2})(?!\d)")
RE_SO_DIGITOS = re.compile(r"(?<![\d.,/-])(\d{11}|\d{14})(?!\d)")
RE_DOC = re.compile(r"\(doc[ .:]+\d", re.I)
RE_CONTA = re.compile(r"\b(SICOOB|BANCO DO BRASIL|BANCO DA AMAZONIA|BASA|BRADESCO|ITAU|SICREDI|SANTANDER|CAIXA ECONOMICA)\s*[-:]?\s*\d{4,7}\b", re.I)
RE_AGENCIA = re.compile(r"\bag[eê]ncia\s*[:=]?\s*\d{3,5}\b", re.I)
RE_CONTRATO = re.compile(r"(?<![\d/])\d{2}/\d{5}-[\dX]\b|(?<![\d.])765\.\d{3}\.\d{3}\b")

def achados_no_texto(texto):
    """[(tipo, linha)] com o que parece dado sensivel neste texto."""
    saida = []
    for i, linha in enumerate(texto.split("\n"), 1):
        for m in RE_FORMATADO.finditer(linha):
            d = re.sub(r"\D", "", m.group(1))
            if cpf_valido(d) or cnpj_valido(d): saida.append(("CPF/CNPJ formatado", i))
        for m in RE_SO_DIGITOS.finditer(linha):
            if cpf_valido(m.group(1)) or cnpj_valido(m.group(1)): saida.append(("CPF/CNPJ so com numeros", i))
        if RE_DOC.search(linha): saida.append(("numero de documento '(doc N'", i))
        if RE_CONTA.search(linha) or RE_AGENCIA.search(linha): saida.append(("banco + numero de conta/agencia", i))
        if RE_CONTRATO.search(linha): saida.append(("numero de contrato de credito", i))
    return saida

# ---- 0. o detector funciona (senao o teste passaria sem enxergar nada) ----
def digito_cpf(base):
    n = [int(c) for c in base]
    d1 = (sum(n[i] * (10 - i) for i in range(9)) * 10 % 11) % 10
    n.append(d1)
    d2 = (sum(n[i] * (11 - i) for i in range(10)) * 10 % 11) % 10
    return "".join(map(str, n)) + str(d2)

def digito_cnpj(base):
    n = [int(c) for c in base]
    def dv(b, p):
        r = sum(x * y for x, y in zip(b, p)) % 11
        return 0 if r < 2 else 11 - r
    p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    n.append(dv(n, p1)); n.append(dv(n, [6] + p1))
    return "".join(map(str, n))

print("\n  REPOSITORIO PUBLICO: SEM CPF/CNPJ, CONTA BANCARIA OU NUMERO DE DOCUMENTO")
cpf = digito_cpf("123456789")                  # inventado, valido so na conta
cnpj = digito_cnpj("112223330001")             # inventado
fmt_cpf = f"{cpf[:3]}.{cpf[3:6]}.{cpf[6:9]}-{cpf[9:]}"
fmt_cnpj = f"{cnpj[:2]}.{cnpj[2:5]}.{cnpj[5:8]}/{cnpj[8:12]}-{cnpj[12:]}"
amostras = {
    "CPF so com numeros": f"x '{cpf}' y",
    "CNPJ so com numeros": f"x '{cnpj}' y",
    "CPF formatado": f"cliente {fmt_cpf}",
    "CNPJ formatado": f"cliente {fmt_cnpj}",
    "numero de documento": "Adubo (do" + "c 8977, pago em 20/04/2026)",
    "conta bancaria": "-- SICOOB " + "99999 - conta",
    "agencia": "ag" + "encia: 1234",
    "contrato BB": "AMORTIZACAO (Contrato: 40/" + "99999-9)",
    "contrato BB (rural)": "contrato 765." + "999.999",
}
for nome, linha in amostras.items():
    conf(len(achados_no_texto(linha)) >= 1, f"o detector enxerga: {nome}", linha)
inofensivos = ["valor 12345678901.50", "document.getElementById('x')", "(documento)", "simples 11111111111", "ano 2026-10-15 id 1700000000000",
               "agencia text,", "SICOOB COCRED", "contrato C01", "BANCO DO BRASIL"]
conf(all(not achados_no_texto(l) for l in inofensivos), "e nao reclama de valor, id, codigo, nome de banco sem numero nem apelido de contrato", str(inofensivos))

# ---- 1. o que o git rastreia ----
rastreados = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True, text=True, encoding="utf-8").stdout.split("\n")
rastreados = [a for a in rastreados if a]
conf(len(rastreados) > 50, f"o git rastreia {len(rastreados)} arquivos (a varredura enxerga o projeto)")
BINARIOS = (".png", ".jpg", ".jpeg", ".gif", ".ico", ".exe", ".zip", ".pdf", ".woff", ".woff2", ".webp", ".bundle")
violacoes = []
for a in rastreados:
    if a.lower().endswith(BINARIOS): continue
    try: texto = (REPO / a).read_text(encoding="utf-8", errors="ignore")
    except OSError: continue
    for tipo, linha in achados_no_texto(texto):
        violacoes.append(f"{a}:{linha} ({tipo})")
conf(not violacoes, "nenhum arquivo versionado tem CPF/CNPJ, '(doc N', conta bancaria ou numero de contrato", "\n            ".join(violacoes[:12]))

# ---- 2. dumps de dados nao podem voltar ao git ----
PROIBIDOS = (re.compile(r"^erp/.*\.(csv|json)$"), re.compile(r"^erp/pdf_faz/"),
             re.compile(r"^cana_despesas_2026_(carga|recategoriza)\.sql$"), re.compile(r"^cana_receita_2026_carga\.sql$"),
             re.compile(r"^erp_receita_01_importar\.sql$"))
dumps = [a for a in rastreados if any(p.search(a) for p in PROIBIDOS)]
conf(not dumps, "nenhum dump de dados do ERP nem carga com CPF/CNPJ/(doc N) esta versionado", str(dumps[:8]))
ignorado = (REPO / ".gitignore").read_text(encoding="utf-8")
conf(all(s in ignorado for s in ("erp/*.csv", "erp/pdf_faz/", "erp_receita_01_importar.sql")),
     ".gitignore bloqueia esses arquivos (continuam so no computador)")

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
