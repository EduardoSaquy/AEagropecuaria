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
- **Financeiro** — custo de ração e pasto do dia e do mês, custo por animal (variável e total com custo fixo diluído), custo diário e mensal detalhado por curral, valor total em estoque dos insumos, e cadastro de custos fixos mensais da operação (mão de obra, energia, etc.), com o total mensal (variável + fixo). Também permite registrar **investimentos** (compra de animais, máquinas, etc.), mantidos separados do custo operacional. CRUD completo dos custos fixos e investimentos.

## Status do projeto

Protótipo funcional (MVP). Os dados são persistidos em um banco Postgres no Supabase (plano gratuito) — o app funciona em qualquer dispositivo (computador ou celular) e os dados ficam salvos entre sessões. Ainda não há autenticação/login: qualquer pessoa com a URL do app tem acesso de leitura e escrita.

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
