# Importar o Conag — instruções para o Code

O Eduardo está no tablet e não consegue colar SQL no dashboard do Supabase.
Faça você, pelo `psql`.

## O que rodar

Da raiz do repositório:

```
psql "<STRING DE CONEXAO>" -v ON_ERROR_STOP=1 -f conag_tudo.sql
```

A string de conexão está em **Supabase → Project Settings → Database →
Connection string → URI**, modo **Session** (porta 5432). O Eduardo tem a
senha; peça a ele. **Rode de dentro da pasta do repositório** — o `\copy`
procura `conag/lancamentos_para_importar.csv` por caminho relativo.

Se `psql` não estiver instalado: `sudo apt install postgresql-client`.

## O que ele faz

Um arquivo só, seis etapas, 9.400 títulos e R$ 62.609.569,50:

1. cria `conag_staging` e as colunas `conag_id`, `cnpj_nota`, `contrato`
2. carrega o CSV
3. cria as 85 contas de nível 4, a tabela `lancamento_rateios` e a view
   `lancamentos_rateados`
4. importa os 9.400
5. rateia os 791 do geral de fazenda e os 2.657 do administrativo
6. imprime a conferência

Pode rodar mais de uma vez — o índice único em `conag_id` não deixa duplicar.
Confirmado: duas rodadas seguidas dão resultado idêntico.

## Pré-requisitos

`centros_05_dois_niveis.sql` e `centros_07_de_para.sql` já foram rodados pelo
Eduardo no dashboard (deram 7 / 1.375 / 2). O `conag_tudo.sql` para na
primeira linha se algum faltar, e diz qual.

## O resultado esperado

13 linhas. As duas que decidem:

| linha | tem que dizer |
|---|---|
| 3 — A view devolve o mesmo dinheiro? | `SIM - bate com a linha 2` |
| 4 — Título cujo rateio não fecha | `nenhum - todos fecham` |

E as linhas 12 e 13 (`Lancamentos NOSSOS, anteriores`) **não podem ter
mudado**: eram 2.760 e R$ 10.447.812,29 — ou 2.761 e R$ 10.453.612,29 se o
lançamento de teste id 3234 ainda estiver lá.

Se qualquer uma dessas quatro sair diferente, **pare e mande a saída inteira**
em vez de tentar consertar.

## Como testar antes, sem tocar no Supabase

`./ensaio_conag.sh` sobe um Postgres local, monta o banco a partir de
`schema_real.txt` e roda tudo com o CSV de verdade. É o ensaio que já validou
este arquivo.
