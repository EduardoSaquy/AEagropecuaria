# Estrutura do Conag — lida em 27/08/2026

Fonte: as telas do proprio ERP, nao documentacao. Cada bloco foi lido da
tela indicada.

## Unidade de Negocio (3)  — tela unidade-de-negocio
    3  AE AGROPECUARIA
    2  TOCANTINS
    1  SAO PAULO
Agrupa fazendas. NAO EXISTE no nosso app.

## Fazendas (7)  — filtro do painel-resultado
    0  SEM VINCULO E SEM RATEIO
    1  FAZENDA PALHADAO
    2  FAZENDA PALMITO
    3  FAZENDA MATA VERDE
    4  FAZENDA SANTA ALICE
    5  FAZENDA INVERNADA
    6  FAZENDA REUNIDAS
    7  FAZENDA DAS TRES MARIAS

## Atividade de Negocio (9)  — tela atividade-de-negocio
    0  SEM VINCULO E SEM RATEIO
    1  PECUARIA          CRIACAO
    2  CANA              PLANTACAO / POR AREA
    3  SOJA              PLANTACAO / POR AREA
    4  ABACATE           PLANTACAO / POR AREA
    5  SORGO             PLANTACAO / POR AREA
    6  MILHO             PLANTACAO / POR AREA
    7  MILHETO           PLANTACAO / POR AREA
    8  FENO              PLANTACAO / POR AREA
    9  FEIJAOMUNGO VERDE PLANTACAO / POR AREA
Todas com safra de maio (05) a abril (04) - igual a janela do nosso app.

NO CONAG, ATIVIDADE E A CULTURA. Nosso app tem 4 atividades e a cultura
como campo separado. A traducao:
    PECUARIA -> atividade='pecuaria'
    CANA     -> atividade='cana'
    demais   -> atividade='graos'   + cultura_id
    ABACATE  -> atividade='geral'   + cultura_id  (decisao nossa)

## Ano Agricola (9 abertos)  — tela controle-de-safras
    2021/2022 ate 2029/2030. Global, nao por fazenda.
    Nosso safras e por fazenda+cultura: um ano do Conag vira varios nossos.

## Contas bancarias (9)  — filtro do balancete
    1 CAIXA INTERNO CAIXA        6 SICOOB 36381
    2 SICOOB 15283               7 SICOOB 22666
    3 BANCO DO BRASIL 12156      8 BANCO DO BRASIL 13921
    4 BANCO DO BRASIL 19725      9 BANCO DA AMAZONIA 036184
    5 BANCO DO BRASIL 6993

## Plano de contas — QUATRO niveis
    1  Centro Gerencial     ENTRADAS / SAIDAS            (2 registros)
    2  SubCategoria         OPERACIONAL | INSUMOS AGROPECUARIOS
    3  (sem nome na tela)   INSUMOS AGRICOLAS            <-- FALTA no nosso
    4  Centro de Custo      ADUBOS E FERTILIZANTES       (57 registros)

Nosso centros_custo: tipo + subcategoria + nome = tres niveis. O nivel 3
separa INSUMOS AGRICOLAS de INSUMOS PECUARIOS dentro do mesmo grupo, e se
perdeu na migracao.

## Campos que o Conag tem e nos nao
    Unidade de Negocio        agrupa fazendas
    CPF/CNPJ da nota          por qual PJ o titulo foi pago (3 diferentes)
    Situacao IR               dedutivel com nota / sem nota / nao dedutivel
    Direto / Indireto         custo de producao x administrativo
    Planejamento              orcado x realizado
    Departamento              nao usado (todos vazios)
    Variavel de Controle      nao usado
    Contrato, Ano Safra no titulo

## Contas a Receber: 0 registros
Nunca foi usada. Nao ha nada para importar.
