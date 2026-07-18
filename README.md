# AEpecuária

Sistema web de gestão nutricional e de estoque para confinamento e semiconfinamento de bovinos de corte, desenvolvido para uso interno da **AE Agropecuária**.

O app permite cadastrar ingredientes com sua composição nutricional, controlar entradas e saídas de estoque com alerta automático de nível baixo, e formular dietas calculando automaticamente matéria seca, proteína bruta, NDT e custo por animal.

## Funcionalidades

- **Ingredientes** — cadastro de insumos com categoria, fornecedor, composição nutricional (MS, PB, NDT) e preço por kg. CRUD completo (criar, editar, excluir).
- **Estoque** — saldo calculado automaticamente a partir das movimentações (entradas e saídas), alerta visual de estoque abaixo do mínimo, valor total em estoque. CRUD completo de movimentações.
- **Formulação de Dietas** — composição de dietas por percentual de ingrediente, com cálculo automático de MS%, PB%, NDT%, custo por kg e custo por animal/dia. Cada dieta é marcada como **Confinamento** ou **Pasto**, para não misturar as duas na hora de lançar. CRUD completo.
- **Lotes** — cadastro dos lotes/currais de animais, com número de cabeças e datas de início e encerramento.
- **Saída de Ração** — lançamento da ração feita e distribuída a um lote a partir de uma dieta de **Confinamento**; o estoque de cada ingrediente é descontado automaticamente na proporção da composição da dieta. CRUD completo.
- **Leitura de Cocho** — registro diário da avaliação de sobra no cocho de cada curral, com nota de 1 (limpo) a 4 (muito excesso) e observação opcional. CRUD completo.
- **Pasto** — registro da reposição de uma dieta/mistura de **Pasto** (ex: suplemento mineral) no cocho de lotes que estão soltos; desconta o estoque de cada ingrediente da mistura automaticamente. CRUD completo.
- **Cria** — cadastro dos lotes de fêmeas em reprodução (lotes com "reprodução" no nome), lançamento da ração feita a partir de uma dieta (desconta o estoque automaticamente, igual em Confinamento) e registro dos lançamentos de sêmen e outros insumos usados na inseminação, por lote/data/custo. CRUD completo.
- **Financeiro** — custo de ração, pasto e cria do dia e do mês, custo por animal (variável e total com custo fixo diluído), custo diário e mensal detalhado por lote, cadastro de custos fixos mensais da operação (mão de obra, energia, etc.), com o total mensal (variável + fixo). Mostra também um **banner com o preço médio da arroba no Tocantins** (atualizado manualmente, referência Datagro). Também permite registrar **investimentos** (compra de animais, máquinas, etc.), mantidos separados do custo operacional. Não mostra receita nem resultado — isso fica na aba Resultados. CRUD completo de custos fixos e investimentos.
- **Resultados** — módulo de acesso separado do Financeiro, para controlar quem vê receita e resultado da operação. Cadastro de **receitas** (venda de animais e outras receitas, por data e lote), valor total em estoque dos insumos, definição de uma **meta de margem** para comparar com a margem real do mês, um **demonstrativo de Despesa vs Receita do mês e do ano** (com o resultado — lucro ou prejuízo), o **resultado financeiro por hectare** (receita, despesa e resultado do mês divididos pela área da fazenda) e um **painel de resultados** com dois gráficos de rosca interativos: um comparando o custo total por área (Confinamento, Pasto, Cria, já com a fatia do custo fixo diluída) e outro mostrando os centros de custo fixo (Pessoal, Manutenção, etc.). CRUD completo de receitas.
- **Fazenda** — visível só para Administrador e Proprietário. Cadastro da área total da fazenda em hectares, usada para calcular o resultado financeiro por hectare mostrado em Resultados.
- **Login e Administração** — acesso ao app exige login (usuário + senha, sem necessidade de e-mail). Um administrador cadastra as contas da equipe pela própria tela de Administração e controla, por pessoa, o nível de acesso a cada módulo (Nenhum, Visualizar ou Editar) — o menu e as ações de cada tela se ajustam automaticamente ao que a pessoa pode ver ou alterar.

## Status do projeto

Protótipo funcional (MVP). Os dados são persistidos em um banco Postgres no Supabase (plano gratuito) — o app funciona em qualquer dispositivo (computador ou celular) e os dados ficam salvos entre sessões. Acesso protegido por login, com permissão por módulo controlada por um administrador.

## Como usar

Acesse pelo navegador (computador ou celular), sem instalação:
**https://eduardosaquy.github.io/AEagropecuaria/AEpecuaria.html**

Também é possível baixar o arquivo `AEpecuaria.html` e abrir localmente, mas nesse caso ele ainda depende de conexão com internet para acessar o banco de dados.

## Tecnologia

HTML, CSS e JavaScript puro no frontend (sem frameworks ou build). Persistência via [Supabase](https://supabase.com) (Postgres + API REST), consumido diretamente do navegador com a biblioteca `@supabase/supabase-js`.

## Autor

EduardoSaquy

## Licença

Uso proprietário e interno da AE Agropecuária. Reprodução, distribuição ou uso fora da empresa não autorizados sem permissão prévia.
