# Bundle de 38 commits — 27/08/2026

O push daqui continua bloqueado pelo proxy (`EduardoSaquy/AEagropecuaria is
not in this session's authorized repository set`). O `git fetch` funciona,
então **este bundle já está em cima do `origin/main` atual** — inclusive do
módulo de Financiamentos que o Code mergeou no PR #168.

## O que fazer

```bash
cd AEagropecuaria
git fetch origin && git checkout main && git pull

git bundle verify AEagropecuaria_38_commits.bundle   # confere antes
git pull AEagropecuaria_38_commits.bundle main       # deve ser fast-forward
git push origin main
```

Se o `git pull` pedir merge em vez de fast-forward, é porque o `origin/main`
andou depois de 27/08 23:30. Nesse caso pare e me avise antes de resolver na
mão — o conflito conhecido em `AEMatriz.html` entre Financiamentos e Contas
a Pagar já foi resolvido aqui dentro, e resolver de novo por cima é onde se
perde código.

## O que vem no bundle

**Merge com o módulo de Financiamentos.** Cinco conflitos em `AEMatriz.html`.
Quatro eram aditivos (mais uma tela no menu, mais um ramo no salvar, mais
duas consultas no `loadAll`). O quinto pedia decisão: o `origin` tinha
trocado o select de lotes por `id, nome`. Ficou o de cá — a venda de animais
precisa de `numero_animais`, `destino` e `data_fim` para saber quantas
cabeças o lote tem e se já foi encerrado. A guarda `vePecuniaOuFinanciamentos`
do `origin` ficou como estava.

Suíte depois do merge: matriz 22, contas 83, venda 28, unidade 31, paginação
ok, mais um teste de fumaça das cinco telas do Matriz com os dois módulos
ligados ao mesmo tempo.

**Plano de contas.** `centros_05_dois_niveis.sql` (já rodado no banco real),
`centros_06_quem_ficou_de_fora.sql` e `centros_07_de_para.sql`.
O `centros_04_nivel_classe.sql` fica obsoleto — partia de premissa errada.

**Conag.** Os 9.400 lançamentos consolidados, a atividade e a fazenda de cada
um, e as etapas 1 e 2 da importação.
