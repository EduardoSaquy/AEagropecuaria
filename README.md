# AEpecuária

Sistema web de gestão nutricional e de estoque para confinamento e semiconfinamento de bovinos de corte, desenvolvido para uso interno da **AE Agropecuária**.

O app permite cadastrar ingredientes com sua composição nutricional, controlar entradas e saídas de estoque com alerta automático de nível baixo, e formular dietas calculando automaticamente matéria seca, proteína bruta, NDT e custo por animal.

## Funcionalidades

- **Ingredientes** — cadastro de insumos com categoria, fornecedor, composição nutricional (MS, PB, NDT) e preço por kg. O preço por kg só é visível (na lista e no formulário) para Administrador e Proprietário — segue sendo usado normalmente nos cálculos de custo, só não aparece pra quem não tem esse acesso. CRUD completo (criar, editar, excluir).
- **Estoque** — saldo calculado automaticamente a partir das movimentações (entradas e saídas), alerta visual de estoque abaixo do mínimo. O valor total em estoque e o valor de cada item também ficam visíveis só para Administrador e Proprietário. CRUD completo de movimentações.
- **Formulação de Dietas** — composição de dietas por percentual de ingrediente, com cálculo automático de MS%, PB%, NDT%, custo por kg e custo por animal/dia. Cada dieta é marcada como **Confinamento** ou **Pasto**, para não misturar as duas na hora de lançar. CRUD completo.
- **Lotes** — cadastro dos lotes/currais de animais, com número de cabeças e datas de início e encerramento.
- **Saída de Ração** — lançamento da ração feita e distribuída a um lote a partir de uma dieta de **Confinamento**; o estoque de cada ingrediente é descontado automaticamente na proporção da composição da dieta. CRUD completo.
- **Leitura de Cocho** — registro diário da avaliação de sobra no cocho de cada curral, com nota de 1 (limpo) a 4 (muito excesso) e observação opcional. CRUD completo.
- **Pasto** — registro da reposição de uma dieta/mistura de **Pasto** (ex: suplemento mineral) no cocho de lotes que estão soltos; desconta o estoque de cada ingrediente da mistura automaticamente. CRUD completo.
- **Cria** — cadastro dos lotes de fêmeas em reprodução (lotes com destino Cria, cadastrados na aba Lotes), lançamento da ração feita a partir de uma dieta (desconta o estoque automaticamente, igual em Confinamento), registro dos lançamentos de sêmen e outros insumos usados na inseminação, por lote/data/custo, e registro dos **partos**, com lote, data, número da mãe e sexo do bezerro. CRUD completo.
- **Pesagem** — dentro de Confinamento, Pasto e Cria, registro do peso médio por animal de um lote, com data e observação opcional. A partir do histórico de pesagens de cada lote, mostra um gráfico de evolução do peso, o ganho no período, o **GMD** (ganho médio diário, kg/dia) entre pesagens e a quantidade de **arrobas (@) produzidas** (ganho de peso ÷ 30 kg × nº de animais). CRUD completo.
- **Financeiro** — custo de ração, pasto e cria do dia e do mês, custo por animal (variável e total com despesa geral diluída), custo diário e mensal detalhado por lote (incluindo arrobas produzidas e custo por @ de cada lote, quando há pesagem cadastrada no mês), e o cadastro de **Despesas** da operação (mão de obra, energia, nutrição, etc.), com o total mensal (variável + despesas) e o **custo por @ produzida da fazenda inteira**. Cada despesa tem um centro de custo e pode opcionalmente ter uma **data específica** (o gasto real daquele mês, ex: importado de um relatório) — sem data, funciona como valor **recorrente** (padrão pra qualquer mês sem lançamento próprio). Cada despesa também pode ter uma **área direta** (Confinamento, Pasto ou Cria) — nesse caso o valor vai inteiro pra aquela área, sem rateio, seguindo a prática de custo direto x indireto da pecuária (custo que já nasce ligado a uma fase vai 100% pra ela; custo compartilhado, como mão de obra geral, é rateado por número de animais). Uma despesa sem área (geral) pode ainda ser marcada para não ser diluída — conta só no total geral, sem entrar em Por Lote nem no gráfico por área; usado pra um custo histórico (ex: nutrição sem área definida) que já é ou vai ser coberto pelos lançamentos diários de ração/cocho/pasto, evitando contar o mesmo gasto duas vezes. Mostra também um **banner com o preço médio da arroba no Tocantins** (atualizado manualmente, referência Datagro). Não mostra receita, investimentos nem resultado — isso fica na aba Resultados. CRUD completo de despesas.
- **Resultados** — módulo de acesso separado do Financeiro, para controlar quem vê receita e resultado da operação. Cadastro de **receitas** (venda de animais e outras receitas, por data e lote) e de **investimentos** (compra de animais, máquinas, etc., mantidos separados do custo operacional), valor total em estoque dos insumos, definição de uma **meta de margem** para comparar com a margem real do mês, um **demonstrativo de Despesa vs Receita do mês e do ano** (com o resultado — lucro ou prejuízo), o **resultado financeiro por hectare** (receita, despesa e resultado do mês divididos pela área da fazenda) e um **painel de resultados** com quatro gráficos de rosca interativos (mês e ano): custo total por área (Confinamento, Pasto, Cria, já com a fatia do custo fixo diluída) e custo total por centro de custo (custos fixos — Pessoal, Manutenção, Nutrição, etc. — somados aos lançamentos diários de ração/pasto/cria, pra mostrar o custo real completo, não só o fixo). CRUD completo de receitas e investimentos.
- **Fazenda** — visível só para Administrador e Proprietário. Cadastro da área total da fazenda em hectares, usada para calcular o resultado financeiro por hectare mostrado em Resultados.
- **Login e Administração** — acesso ao app exige login (usuário + senha, sem necessidade de e-mail). Um administrador cadastra as contas da equipe pela própria tela de Administração e controla, por pessoa, o nível de acesso a cada módulo (Nenhum, Visualizar ou Editar) — o menu e as ações de cada tela se ajustam automaticamente ao que a pessoa pode ver ou alterar. Qualquer pessoa logada pode trocar a própria senha a qualquer momento (botão "Trocar senha" na barra lateral), informando a senha atual e a nova senha.
- **Funciona sem sinal (fila offline)** — lançamentos de campo (Saída de Ração, Leitura de Cocho, reposição de Pasto, Inseminação, Partos e Pesagem) não se perdem quando não há internet no curral/pasto: se o salvamento falhar por falta de conexão, o lançamento fica guardado neste aparelho e é enviado automaticamente assim que o sinal voltar (checagem a cada 30s e também ao detectar que a conexão voltou). Enquanto há pendências, aparece um aviso na barra lateral ("⏳ N pendente(s) de sincronização"), onde dá pra ver o que está esperando ser enviado ou tentar sincronizar na hora.

## Status do projeto

Protótipo funcional (MVP). Os dados são persistidos em um banco Postgres no Supabase (plano gratuito) — o app funciona em qualquer dispositivo (computador ou celular) e os dados ficam salvos entre sessões. Acesso protegido por login, com permissão por módulo controlada por um administrador.

## Como usar

Acesse pelo navegador (computador ou celular), sem instalação:
**https://eduardosaquy.github.io/AEagropecuaria/AEpecuaria.html**

Também é possível baixar o arquivo `AEpecuaria.html` e abrir localmente, mas nesse caso ele ainda depende de conexão com internet para acessar o banco de dados.

## Tecnologia

HTML, CSS e JavaScript puro no frontend (sem frameworks ou build). Persistência via [Supabase](https://supabase.com) (Postgres + API REST), consumido diretamente do navegador com a biblioteca `@supabase/supabase-js`.

## AE Combustível

App novo e independente (`AECombustivel.html`), para controle de combustível (diesel S10/S500, Arla 32, gasolina) das frentes de cana-de-açúcar, grãos e pecuária. Mesma tecnologia do AEpecuária (HTML/CSS/JS puro + Supabase + PWA instalável), mas com **banco de dados próprio e separado** — não interfere no app da pecuária.

Os cadastros centrais (fazenda, cultura/safra, talhão/lote, centro de custo) nascem pensados para as três frentes desde o início, para que o rateio de combustível caia no lugar certo à medida que os módulos de cana e grãos forem criados.

- **Status**: Fases 1 (Fundação + Cadastros base), 2 (Estoque) e 3 (Abastecimentos) prontas.
  - Fase 1 — login com controle de acesso por papel (Administrador/Gestor/Encarregado/Operador) e CRUD de Fazendas, Produtos, Culturas, Operações, Fornecedores, Safras, Centros de Custo, Talhões/Áreas, Equipamentos, Operadores e Tanques.
  - Fase 2 — Entradas de estoque por nota fiscal, Medições Físicas (régua/sensor) e Ajustes de Estoque (sempre com justificativa), com uma aba de Resumo que mostra o saldo teórico por tanque, a conciliação com a última medição física, o valor aproximado em estoque e alertas de estoque baixo (configurável por tanque).
  - Fase 3 — Abastecimentos (núcleo do sistema): registro por tanque fixo ou comboio, com operador, volume, leitura de horímetro/hodômetro (a leitura não pode retroceder — checado no banco) e rateio por talhão/área ou centro de custo. **Funciona offline**: um cache local dos cadastros deixa o app utilizável mesmo sem sinal, e cada abastecimento registrado offline entra numa fila local (IndexedDB) que sincroniza sozinha assim que a conexão volta, sem duplicar registros. Um alerta (não bloqueante) avisa quando o volume abastecido excede a capacidade do tanque do equipamento.
- **Próximas fases**: rateio e indicadores de consumo (L/h, L/ha, L/km, L/t), detecção de anomalias e alertas configuráveis, dashboards e relatórios.
- **Colocar no ar**: crie um projeto novo no [Supabase](https://supabase.com) e rode `combustivel_schema.sql` do começo ao fim (o arquivo tem as migrações das Fases 1, 2 e 3 em sequência, com passo a passo comentado). Publique a Edge Function `criar-usuario-combustivel` e preencha a URL/chave do projeto no topo de `AECombustivel.html`.

## Autor

EduardoSaquy

## Licença

Uso proprietário e interno da AE Agropecuária. Reprodução, distribuição ou uso fora da empresa não autorizados sem permissão prévia.
