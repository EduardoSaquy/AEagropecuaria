# Importar o Conag — instruções para o Code

O Eduardo está no tablet e não consegue operar o dashboard do Supabase até o
fim. Faça você, pelo `psql`.

## Ordem

**1. Aplique o bundle primeiro.** O CSV que a importação usa
(`conag/lancamentos_para_importar.csv`) **não está no GitHub** — ele só existe
nos commits que não subiram. Sem o bundle, o passo 2 quebra no `\copy`.

```
git bundle verify AEagro_XX_commits.bundle
git pull AEagro_XX_commits.bundle main
```

Se der conflito, **pare e mostre o conflito ao Eduardo** — ele e eu mexemos
nos mesmos arquivos e o merge é decisão dele, não limpeza automática.

**2. Rode a importação**, da raiz do repositório:

```
psql "<STRING DE CONEXAO>" -v ON_ERROR_STOP=1 -f conag_tudo.sql
```

A string está em **Supabase → Project Settings → Database → Connection string
→ URI**, modo **Session** (porta 5432). Peça a senha ao Eduardo. **Rode de
dentro da pasta do repositório**: o `\copy` procura o CSV por caminho relativo.

Se faltar o cliente: `sudo apt install postgresql-client`.

## Estado atual do banco

O Eduardo já rodou pelo dashboard, e deram certo:

- `centros_05_dois_niveis.sql` → 7 / 1.375 / 2
- `conag_10_estrutura.sql` → mesa criada
- carga do CSV em `conag_staging` → 9.400 linhas
- a primeira parte do `conag_12` → contas de nível 4, `lancamento_rateios`, view

A importação em si **não rodou** — bateu na trava `mes_bate_com_data` e o
Postgres desfez tudo. Já está corrigido no arquivo (veja abaixo).

`conag_tudo.sql` é seguro rodar por cima disso: ele recria `conag_staging`,
recarrega o CSV e usa `on conflict do nothing` no `conag_id`. Rodar duas vezes
dá o mesmo resultado.

## O que mudou desde a versão anterior

`data` agora fica **nula** nos lançamentos do Conag e o vencimento vai para uma
coluna própria (`lancamentos_financeiros.vencimento`, criada pelo script).

Motivo: a trava `mes_bate_com_data` exige `data is null or mes =
to_char(data,'YYYY-MM')`, e em 4.836 dos 9.400 títulos (51,4%, R$ 23,6 milhões)
o vencimento cai em mês diferente da competência — compra em dezembro, boleto
em janeiro. `data` significa *quando o custo aconteceu*, e o Conag só informa o
mês. **Não relaxe essa trava**: ela nasceu de um bug real que inflou
R$ 43.928,73 para R$ 1.230.390,69.

## O que ele faz

Seis etapas, 9.400 títulos, R$ 62.609.569,50: mesa de pouso → carga do CSV →
85 contas de nível 4 + `lancamento_rateios` + view `lancamentos_rateados` →
importa os 9.400 → rateia os 791 do geral de fazenda e os 2.657 do
administrativo → confere.

## O resultado esperado

14 linhas. As quatro que decidem:

| linha | tem que dizer |
|---|---|
| 3 — A view devolve o mesmo dinheiro? | `SIM - bate com a linha 2` |
| 4 — Título cujo rateio não fecha | `nenhum - todos fecham` |
| 12 — Lancamentos NOSSOS, anteriores | `2760` (ou `2761`, se o teste id 3234 ainda existir) |
| 13 — Valor NOSSO, anterior | `10447812.29` (ou `10453612.29`) |

Se qualquer uma sair diferente, **pare e mande a saída inteira** em vez de
tentar consertar.

## Testar antes, sem tocar no Supabase

`./ensaio_conag.sh` sobe um Postgres local, monta o banco a partir de
`schema_real.txt` — já com a trava `mes_bate_com_data` — e roda tudo com o CSV
de verdade. É o ensaio que validou este arquivo.
