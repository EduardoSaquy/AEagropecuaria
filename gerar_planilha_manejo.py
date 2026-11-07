"""
Gera Planilha_de_Manejo.xlsx: o modelo que se preenche no curral, sem internet (Excel ou Google Planilhas no celular), e que depois
se importa no AE Pecuaria (Manejo > Importar planilha). Pedido do Eduardo em 07/11/2026.

A importacao do app le a planilha pelos TEXTOS dos rotulos (coluna A do bloco de cima e cabecalhos da tabela), nao pela posicao
das celulas: pode inserir linha ou mudar a largura, mas nao renomeie os rotulos. Se mudar um rotulo aqui, mude no app
(PLANILHA_MANEJO_ROTULOS em AEpecuaria.html) e no teste_manejo_planilha.py.

Uso:  python gerar_planilha_manejo.py
"""
from pathlib import Path

from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

SAIDA = Path(__file__).resolve().parent / "Planilha_de_Manejo.xlsx"
LINHA_CABECALHO = 16
PRIMEIRA = LINHA_CABECALHO + 1
ULTIMA = PRIMEIRA + 199          # 200 animais por planilha

VERDE = "1F5C3A"
verde_claro = PatternFill("solid", fgColor="E3F1E8")
cinza = PatternFill("solid", fgColor="E7E7E7")
amarelo = PatternFill("solid", fgColor="FFF6D6")
fina = Side(style="thin", color="B9C4BC")
borda = Border(left=fina, right=fina, top=fina, bottom=fina)

wb = Workbook()
ws = wb.active
ws.title = "Manejo"

ws["A1"] = "Planilha de Manejo — AE Pecuária"
ws["A1"].font = Font(size=16, bold=True, color=VERDE)
ws["A2"] = ("Preencha no curral, mesmo sem internet. Depois, com internet, abra o AE Pecuária > Manejo > Importar planilha. "
            "Uma planilha = um lote e uma data.")
ws["A2"].alignment = Alignment(wrap_text=True, vertical="top")
ws.merge_cells("A2:J2")
ws.row_dimensions[2].height = 32

bloco = [
    ("Data do manejo", "dd/mm/aaaa", None),
    ("Lote (nome como está no app)", "ex.: Vacas 07/08", None),
    ("Muda de lote? Lote de destino", "em branco = não muda", None),
    ("Pesagem?", "Sim ou Não", "simnao"),
    ("Inseminação (IATF)?", "Sim ou Não", "simnao"),
    ("Diagnóstico de gestação?", "Sim ou Não", "simnao"),
    ("Protocolo de inseminação?", "Sim ou Não", "simnao"),
    ("Desmama?", "Sim ou Não", "simnao"),
    ("Vacinação?", "Sim ou Não", "simnao"),
    ("Vermifugação?", "Sim ou Não", "simnao"),
]
dv_simnao = DataValidation(type="list", formula1='"Sim,Não"', allow_blank=True, showErrorMessage=True,
                           errorTitle="Escolha Sim ou Não", error="Escolha Sim ou Não na lista.")
ws.add_data_validation(dv_simnao)
for i, (rotulo, dica, tipo) in enumerate(bloco):
    r = 4 + i
    ws.cell(r, 1, rotulo).font = Font(bold=True)
    ws.cell(r, 1).fill = verde_claro
    ws.cell(r, 1).border = borda
    c = ws.cell(r, 2)
    c.fill = amarelo
    c.border = borda
    ws.cell(r, 3, dica).font = Font(italic=True, color="777777")
    if tipo == "simnao":
        c.value = "Não"
        dv_simnao.add(c)
ws["B4"].number_format = "DD/MM/YYYY"

cabecalhos = [
    "Número do animal",
    "Sexo (só animal novo)",
    "Raça (só animal novo)",
    "Peso (kg)",
    "Raça do touro (inseminação)",
    "Diagnóstico (prenha ou vazia)",
    "Desmama: número da mãe",
    "Desmama: peso (kg)",
    "Desmama: raça do bezerro",
    "Observação (não é importada)",
]
ws.cell(LINHA_CABECALHO - 1, 1, "Um animal por linha. Só preencha as colunas das ações marcadas Sim lá em cima (as outras ficam cinza).").font = Font(italic=True, color="555555")
for j, h in enumerate(cabecalhos, start=1):
    c = ws.cell(LINHA_CABECALHO, j, h)
    c.font = Font(bold=True, color="FFFFFF")
    c.fill = PatternFill("solid", fgColor=VERDE)
    c.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
    c.border = borda
ws.row_dimensions[LINHA_CABECALHO].height = 44
for r in range(PRIMEIRA, ULTIMA + 1):
    for j in range(1, len(cabecalhos) + 1):
        ws.cell(r, j).border = borda
    ws.cell(r, 1).number_format = "@"          # número do animal como texto: 057 não vira 57 sem querer
    ws.cell(r, 7).number_format = "@"

largura = [18, 16, 16, 12, 18, 18, 16, 14, 18, 28]
for j, w in enumerate(largura, start=1):
    ws.column_dimensions[chr(64 + j)].width = w
ws.column_dimensions["A"].width = 34
ws.freeze_panes = ws.cell(PRIMEIRA, 1)

intervalo = lambda col: f"{col}{PRIMEIRA}:{col}{ULTIMA}"
listas = [("B", '"Macho,Fêmea"'), ("C", '"Angus,Nelore,Outro"'), ("E", '"Angus,Nelore,Outro"'),
          ("F", '"Prenha,Vazia"'), ("I", '"Angus,Nelore,Outro"')]
for col, formula in listas:
    dv = DataValidation(type="list", formula1=formula, allow_blank=True, showErrorMessage=True, errorTitle="Escolha da lista", error="Escolha uma opção da lista.")
    ws.add_data_validation(dv)
    dv.add(intervalo(col))
for col in ("D", "H"):
    dv = DataValidation(type="decimal", operator="greaterThan", formula1="0", allow_blank=True, showErrorMessage=True,
                        errorTitle="Peso", error="Digite o peso em kg, maior que zero.")
    ws.add_data_validation(dv)
    dv.add(intervalo(col))

# colunas das ações que estão em Não ficam cinza (só orientação visual; o app decide pelo que está marcado)
def cinza_se_nao(coluna, celula_acao):
    ws.conditional_formatting.add(intervalo(coluna), FormulaRule(formula=[f'${celula_acao[0]}${celula_acao[1:]}<>"Sim"'], fill=cinza))
cinza_se_nao("D", "B7")
cinza_se_nao("E", "B8")
cinza_se_nao("F", "B9")
for col in ("G", "H", "I"):
    cinza_se_nao(col, "B11")

ins = wb.create_sheet("Instruções")
linhas = [
    ("Como usar", True),
    ("1. Preencha o alto da planilha: data, lote (o nome igual ao do app) e marque Sim nas ações que vai fazer. Se os animais vão mudar de lote, escreva o lote de destino.", False),
    ("2. Uma linha por animal. Digite só os algarismos do número (57, não 057 nem 'vaca 57'). Zero à esquerda não conta.", False),
    ("3. Animal que ainda não está cadastrado: preencha Raça (e Sexo, se o lote for misto). Animal já cadastrado: deixe Sexo e Raça em branco.", False),
    ("4. Pesagem = Sim: o peso é obrigatório em todas as linhas. Inseminação = Sim: raça do touro e número obrigatórios. Diagnóstico = Sim: prenha ou vazia e número obrigatórios.", False),
    ("5. Desmama = Sim: número da mãe (a vaca que pariu o bezerro), peso da desmama e raça do bezerro. O número do bezerro é opcional.", False),
    ("6. Salve e, quando tiver internet, no AE Pecuária: Manejo > Importar planilha > escolha o arquivo. O app mostra uma prévia (o que entra e o que tem erro) ANTES de gravar.", False),
    ("7. Importou? Não importe a mesma planilha duas vezes: o app avisa se já importou esta.", False),
    ("", False),
    ("Não renomeie os títulos da coluna A (alto) nem da linha de cabeçalho da tabela: é por eles que o app encontra cada dado.", True),
]
for i, (txt, negrito) in enumerate(linhas, start=1):
    c = ins.cell(i, 1, txt)
    c.font = Font(bold=negrito, size=12 if negrito else 11)
    c.alignment = Alignment(wrap_text=True, vertical="top")
ins.column_dimensions["A"].width = 120

wb.save(SAIDA)
print("ok", SAIDA)
