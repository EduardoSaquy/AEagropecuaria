"""
O nome do ERP de origem nao aparece em lugar nenhum do repositorio.

O Eduardo pediu (16/10/2026: "o nome ... aparece em tudo, nao e para
aparecer"): nem na tela, nem no banco, nem nos arquivos, nem no nome dos
arquivos. Em texto corrido, no codigo e nos nomes de coluna e tabela o
sistema se chama simplesmente "ERP".

Este teste varre todo arquivo versionado (o nome do arquivo e o conteudo) e
falha se o nome voltar. O nome e montado por pedacos aqui dentro para este
arquivo nao ser um dos que a varredura acha.

Fornecedor que tem esse nome no cadastro e fornecedor de verdade, mas o nome
dele mora so no banco; nenhum arquivo versionado precisa citar.
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
NOME = "con" + "ag"

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

def tem_o_nome(texto):
    return NOME in texto.lower()

print("\n  NOME DO ERP: NAO APARECE EM ARQUIVO NENHUM")

# 1. o detector enxerga (senao o teste passaria sempre)
for amostra in (NOME.capitalize() + " 123", NOME.upper() + " CONSULTORIA", f"{NOME}_id", f"gruposLinhas{NOME.capitalize()}"):
    conf(tem_o_nome(amostra), f"o detector enxerga: {amostra[:3]}...{amostra[-6:]}")
conf(not tem_o_nome("ERP, agronegocio, congelar, Dívida do ERP ainda sem contrato"), "e nao reclama de ERP nem de palavras parecidas")

# 2. a varredura
saida = subprocess.run(["git", "ls-files", "-z"], cwd=REPO, capture_output=True, check=True).stdout
arquivos = [p for p in saida.decode("utf-8").split("\0") if p]
conf(len(arquivos) > 150, f"o git rastreia {len(arquivos)} arquivos (a varredura enxerga o projeto)")

no_nome = [p for p in arquivos if tem_o_nome(p)]
conf(not no_nome, "nenhum arquivo ou pasta versionado tem o nome no nome", str(no_nome[:8]))

no_conteudo = []
for p in arquivos:
    caminho = REPO / p
    try:
        txt = caminho.read_bytes().decode("utf-8")
    except (UnicodeDecodeError, OSError):
        continue   # binario (imagem, icone)
    if tem_o_nome(txt):
        linha = next((i for i, l in enumerate(txt.splitlines(), 1) if tem_o_nome(l)), 0)
        no_conteudo.append(f"{p}:{linha}")
conf(not no_conteudo, "nenhum arquivo versionado cita o nome no conteudo", str(no_conteudo[:8]))

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
