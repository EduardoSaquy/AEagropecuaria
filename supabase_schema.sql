-- Schema do AEpecuária (rodar no SQL Editor do Supabase)

create table ingredientes (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  fornecedor text,
  unidade text default 'kg',
  ms numeric default 0,
  pb numeric default 0,
  ndt numeric default 0,
  preco_kg numeric default 0,
  estoque_min numeric default 0,
  obs text default ''
);

create table movimentos (
  id bigint generated always as identity primary key,
  data date not null,
  ingrediente_id bigint references ingredientes(id) on delete cascade,
  tipo text not null, -- 'entrada' ou 'saida'
  quantidade numeric default 0
);

create table dietas (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria_animal text,
  kg_animal_dia numeric default 0,
  itens jsonb default '[]' -- [{ingredienteId, pct}]
);

-- dados de exemplo (os mesmos que já existem no app hoje)
insert into ingredientes (nome, categoria, fornecedor, unidade, ms, pb, ndt, preco_kg, estoque_min, obs) values
  ('Milho moído', 'Energético', 'Cooperativa Vale Verde', 'kg', 88, 9.0, 88, 0.98, 5000, ''),
  ('Farelo de soja', 'Proteico', 'Agroindustrial Sul', 'kg', 89, 45.0, 82, 2.35, 2000, ''),
  ('Bagaço de cana', 'Volumoso', 'Usina Santa Fé', 'kg', 50, 2.0, 48, 0.22, 8000, ''),
  ('Núcleo mineral', 'Mineral', 'NutriMax', 'kg', 98, 0, 0, 6.80, 300, '');

insert into movimentos (data, ingrediente_id, tipo, quantidade) values
  ('2026-06-15', 1, 'entrada', 12000),
  ('2026-06-15', 2, 'entrada', 5000),
  ('2026-06-15', 3, 'entrada', 20000),
  ('2026-06-15', 4, 'entrada', 600),
  ('2026-06-28', 1, 'saida', 5200),
  ('2026-06-28', 2, 'saida', 2100),
  ('2026-06-28', 3, 'saida', 9600),
  ('2026-06-28', 4, 'saida', 180);

insert into dietas (nome, categoria_animal, kg_animal_dia, itens) values
  ('Dieta Terminação Alto Grão', 'Boi terminação', 9.5,
   '[{"ingredienteId":1,"pct":68},{"ingredienteId":2,"pct":12},{"ingredienteId":3,"pct":18},{"ingredienteId":4,"pct":2}]');

-- Row Level Security: como é um app interno de teste sem login,
-- liberamos leitura/escrita pública (protegido só por quem tem a URL).
alter table ingredientes enable row level security;
alter table movimentos enable row level security;
alter table dietas enable row level security;

create policy "public full access" on ingredientes for all using (true) with check (true);
create policy "public full access" on movimentos for all using (true) with check (true);
create policy "public full access" on dietas for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Lotes e Saída de Ração
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- acima (ingredientes, movimentos, dietas) já existirem no seu projeto.
-- ===================================================================

create table lotes (
  id bigint generated always as identity primary key,
  nome text not null,
  numero_animais numeric default 0,
  data_inicio date,
  data_fim date
);

create table saidas_racao (
  id bigint generated always as identity primary key,
  data date not null,
  dieta_id bigint references dietas(id) on delete set null,
  lote_id bigint references lotes(id) on delete set null,
  quantidade_kg numeric default 0
);

-- vincula as movimentações de estoque geradas por uma saída de ração,
-- para que excluir a saída também desfaça o desconto no estoque
alter table movimentos add column saida_racao_id bigint references saidas_racao(id) on delete cascade;

alter table lotes enable row level security;
alter table saidas_racao enable row level security;

create policy "public full access" on lotes for all using (true) with check (true);
create policy "public full access" on saidas_racao for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Leitura de Cocho
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- lotes e saidas_racao (migração acima) já existirem no seu projeto.
-- ===================================================================

create table leituras_cocho (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete cascade,
  nota smallint not null check (nota between 1 and 4), -- 1 limpo · 2 bom · 3 pouco excesso · 4 muito excesso
  observacao text default ''
);

alter table leituras_cocho enable row level security;

create policy "public full access" on leituras_cocho for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Pasto e Financeiro
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
-- ===================================================================

create table pasto (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  ingrediente_id bigint references ingredientes(id) on delete set null,
  quantidade numeric default 0
);

-- vincula as movimentações de estoque geradas por uma reposição de pasto,
-- para que excluir o registro também desfaça o desconto no estoque
alter table movimentos add column pasto_id bigint references pasto(id) on delete cascade;

create table custos_fixos (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  valor_mensal numeric default 0
);

alter table pasto enable row level security;
alter table custos_fixos enable row level security;

create policy "public full access" on pasto for all using (true) with check (true);
create policy "public full access" on custos_fixos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Dietas de Confinamento x Pasto
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- O Pasto passa a usar uma dieta formulada (do tipo "pasto") em vez de
-- um ingrediente único, igual já funciona em Saída de Ração. A coluna
-- pasto.ingrediente_id não é mais usada pelo app, mas fica no banco
-- (não é apagada) para não perder o histórico de lançamentos antigos.
-- ===================================================================

alter table dietas add column tipo text default 'confinamento' check (tipo in ('confinamento','pasto'));
alter table pasto add column dieta_id bigint references dietas(id) on delete set null;

-- ===================================================================
-- MIGRAÇÃO: Investimentos
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro de compras de animais, máquinas e outros bens — separado
-- dos Custos Fixos porque não é uma despesa operacional recorrente,
-- e não entra nos cálculos de custo diário/mensal do Financeiro.
-- ===================================================================

create table investimentos (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  valor numeric default 0,
  data date
);

alter table investimentos enable row level security;

create policy "public full access" on investimentos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Reprodução (lançamentos de sêmen e outros insumos)
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro por data/lote do custo com sêmen e outros insumos usados na
-- inseminação — só aparece vinculado a lotes com "reprodução" no nome
-- (aba Reprodução). Entra no Financeiro como custo variável, igual
-- Saída de Ração e Pasto.
-- ===================================================================

create table reproducao_custos (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete cascade,
  item text not null,
  custo numeric default 0
);

alter table reproducao_custos enable row level security;

create policy "public full access" on reproducao_custos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Receitas
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro de venda de animais e outras receitas da operação, por
-- data e (opcionalmente) lote. Usado no Financeiro para o
-- demonstrativo de Despesa vs Receita do mês.
-- ===================================================================

create table receitas (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  descricao text not null,
  arrobas numeric,
  valor numeric default 0
);

alter table receitas enable row level security;

create policy "public full access" on receitas for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Preço da arroba e meta de margem
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- precos_arroba: histórico do valor médio da arroba (atualizado
-- manualmente, ex: consultando o app Indicador do Boi Datagro), usado
-- no banner do topo do Resumo do Financeiro.
-- config_financeiro: linha única (id=1) com a meta de margem (%),
-- usada para comparar com a margem real do mês.
-- ===================================================================

create table precos_arroba (
  id bigint generated always as identity primary key,
  data date not null,
  valor numeric default 0
);

alter table precos_arroba enable row level security;

create policy "public full access" on precos_arroba for all using (true) with check (true);

create table config_financeiro (
  id bigint primary key,
  meta_margem_pct numeric
);

alter table config_financeiro enable row level security;

create policy "public full access" on config_financeiro for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Login e permissões por módulo
--
-- ATENÇÃO — ORDEM DE EXECUÇÃO, LEIA ANTES DE RODAR:
-- Esta migração troca as políticas de acesso público ("public full
-- access") por políticas que exigem login e permissão por módulo.
-- A partir do momento em que você rodar este bloco, o app SÓ funciona
-- para quem tiver uma conta com perfil em `profiles` — incluindo você.
--
-- Passo a passo obrigatório, NESTA ORDEM:
-- 1. Espere o app publicado já ter a tela de login (peça confirmação
--    antes de rodar esta migração).
-- 2. No painel do Supabase: Authentication > Users > Add user. Crie
--    sua própria conta (email pode ser fake, ex: eduardo@aeagropecuaria.local,
--    já marcando "Auto Confirm User"). Anote o UUID gerado.
-- 3. Rode o bloco abaixo (cria as tabelas/políticas nova).
-- 4. Rode o insert manual no final deste bloco, trocando o UUID e o
--    nome, pra virar o primeiro administrador.
-- 5. Só depois disso faça login no app com esse usuário/senha.
-- ===================================================================

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  usuario text not null unique, -- nome de usuário do login (sem @dominio)
  papel text not null default 'funcionario' check (papel in ('admin','funcionario')),
  permissoes jsonb not null default '{}'::jsonb, -- {"insumos":"editar","dietas":"visualizar",...}
  ativo boolean not null default true,
  created_at timestamptz default now()
);

alter table profiles enable row level security;

-- funções auxiliares (security definer + search_path fixo, para não
-- herdar permissão de quem chama nem sofrer sequestro de search_path)
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles where id = auth.uid() and papel = 'admin' and ativo = true
  );
$$;

create or replace function tem_permissao(modulo text, nivel text) returns boolean
language sql security definer set search_path = public stable as $$
  select case
    when is_admin() then true
    when nivel = 'visualizar' then (
      select permissoes->>modulo in ('visualizar','editar')
      from profiles where id = auth.uid() and ativo = true
    )
    else (
      select permissoes->>modulo = 'editar'
      from profiles where id = auth.uid() and ativo = true
    )
  end;
$$;

create policy "ver proprio perfil ou admin ve todos" on profiles for select
  using (auth.uid() = id or is_admin());
create policy "admin cria perfis" on profiles for insert with check (is_admin());
create policy "admin atualiza perfis" on profiles for update using (is_admin()) with check (is_admin());
create policy "admin exclui perfis" on profiles for delete using (is_admin());

-- troca as políticas públicas por políticas com permissão por módulo.
-- lotes e saidas_racao são usados tanto por Confinamento quanto por
-- Cria (e lotes também por Pasto), então aceitam qualquer um dos módulos.
-- (cada operação de escrita vira 3 políticas separadas — insert/update/delete —
-- porque o Postgres não aceita "for insert, update, delete" numa política só)
drop policy if exists "public full access" on ingredientes;
drop policy if exists "public full access" on movimentos;
create policy "select insumos" on ingredientes for select using (tem_permissao('insumos','visualizar'));
create policy "inserir insumos" on ingredientes for insert with check (tem_permissao('insumos','editar'));
create policy "atualizar insumos" on ingredientes for update using (tem_permissao('insumos','editar')) with check (tem_permissao('insumos','editar'));
create policy "excluir insumos" on ingredientes for delete using (tem_permissao('insumos','editar'));
create policy "select movimentos" on movimentos for select using (tem_permissao('insumos','visualizar'));
create policy "inserir movimentos" on movimentos for insert with check (tem_permissao('insumos','editar'));
create policy "atualizar movimentos" on movimentos for update using (tem_permissao('insumos','editar')) with check (tem_permissao('insumos','editar'));
create policy "excluir movimentos" on movimentos for delete using (tem_permissao('insumos','editar'));

drop policy if exists "public full access" on dietas;
create policy "select dietas" on dietas for select using (tem_permissao('dietas','visualizar'));
create policy "inserir dietas" on dietas for insert with check (tem_permissao('dietas','editar'));
create policy "atualizar dietas" on dietas for update using (tem_permissao('dietas','editar')) with check (tem_permissao('dietas','editar'));
create policy "excluir dietas" on dietas for delete using (tem_permissao('dietas','editar'));

drop policy if exists "public full access" on lotes;
create policy "select lotes" on lotes for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
);
create policy "inserir lotes" on lotes for insert with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);
create policy "atualizar lotes" on lotes for update using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);
create policy "excluir lotes" on lotes for delete using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);

drop policy if exists "public full access" on saidas_racao;
create policy "select saidas_racao" on saidas_racao for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('cria','visualizar')
);
create policy "inserir saidas_racao" on saidas_racao for insert with check (
  tem_permissao('confinamento','editar') or tem_permissao('cria','editar')
);
create policy "atualizar saidas_racao" on saidas_racao for update using (
  tem_permissao('confinamento','editar') or tem_permissao('cria','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('cria','editar')
);
create policy "excluir saidas_racao" on saidas_racao for delete using (
  tem_permissao('confinamento','editar') or tem_permissao('cria','editar')
);

drop policy if exists "public full access" on leituras_cocho;
create policy "select leituras_cocho" on leituras_cocho for select using (tem_permissao('confinamento','visualizar'));
create policy "inserir leituras_cocho" on leituras_cocho for insert with check (tem_permissao('confinamento','editar'));
create policy "atualizar leituras_cocho" on leituras_cocho for update using (tem_permissao('confinamento','editar')) with check (tem_permissao('confinamento','editar'));
create policy "excluir leituras_cocho" on leituras_cocho for delete using (tem_permissao('confinamento','editar'));

drop policy if exists "public full access" on pasto;
create policy "select pasto" on pasto for select using (tem_permissao('pasto','visualizar'));
create policy "inserir pasto" on pasto for insert with check (tem_permissao('pasto','editar'));
create policy "atualizar pasto" on pasto for update using (tem_permissao('pasto','editar')) with check (tem_permissao('pasto','editar'));
create policy "excluir pasto" on pasto for delete using (tem_permissao('pasto','editar'));

drop policy if exists "public full access" on reproducao_custos;
create policy "select reproducao_custos" on reproducao_custos for select using (tem_permissao('cria','visualizar'));
create policy "inserir reproducao_custos" on reproducao_custos for insert with check (tem_permissao('cria','editar'));
create policy "atualizar reproducao_custos" on reproducao_custos for update using (tem_permissao('cria','editar')) with check (tem_permissao('cria','editar'));
create policy "excluir reproducao_custos" on reproducao_custos for delete using (tem_permissao('cria','editar'));

drop policy if exists "public full access" on custos_fixos;
drop policy if exists "public full access" on investimentos;
drop policy if exists "public full access" on receitas;
drop policy if exists "public full access" on precos_arroba;
drop policy if exists "public full access" on config_financeiro;
create policy "select custos_fixos" on custos_fixos for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir custos_fixos" on custos_fixos for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar custos_fixos" on custos_fixos for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir custos_fixos" on custos_fixos for delete using (tem_permissao('financeiro','editar'));
create policy "select investimentos" on investimentos for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir investimentos" on investimentos for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar investimentos" on investimentos for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir investimentos" on investimentos for delete using (tem_permissao('financeiro','editar'));
create policy "select receitas" on receitas for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir receitas" on receitas for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar receitas" on receitas for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir receitas" on receitas for delete using (tem_permissao('financeiro','editar'));
create policy "select precos_arroba" on precos_arroba for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir precos_arroba" on precos_arroba for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar precos_arroba" on precos_arroba for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir precos_arroba" on precos_arroba for delete using (tem_permissao('financeiro','editar'));
create policy "select config_financeiro" on config_financeiro for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir config_financeiro" on config_financeiro for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar config_financeiro" on config_financeiro for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir config_financeiro" on config_financeiro for delete using (tem_permissao('financeiro','editar'));

-- PASSO 4 (rode por último, depois de criar seu usuário no painel):
-- troque '<SEU-UUID-AQUI>' pelo UUID do usuário criado no painel, e
-- 'Eduardo' pelo seu nome. 'usuario' é o que você vai digitar pra
-- entrar no app (sem @dominio) — use o mesmo que está antes do @ no
-- email fake que você criou no painel (ex: email "eduardo@aeagropecuaria.local"
-- → usuario 'eduardo').
--
-- insert into profiles (id, nome, usuario, papel, permissoes, ativo) values
--   ('<SEU-UUID-AQUI>', 'Eduardo', 'eduardo', 'admin', '{}'::jsonb, true);

-- ===================================================================
-- MIGRAÇÃO: Cargos Proprietário e Consultor, renomeia Funcionário -> Colaborador
-- Pode rodar a qualquer momento (não precisa de ordem especial como a
-- migração de login). Some acesso não muda para quem já é 'funcionario':
-- essas contas viram 'colaborador' automaticamente, com as mesmas
-- permissões de antes.
-- ===================================================================
alter table profiles drop constraint if exists profiles_papel_check;
update profiles set papel = 'colaborador' where papel = 'funcionario';
alter table profiles alter column papel set default 'colaborador';
alter table profiles add constraint profiles_papel_check
  check (papel in ('admin','proprietario','colaborador','consultor'));

-- Proprietário passa a ter acesso total, igual Administrador.
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles where id = auth.uid() and papel in ('admin','proprietario') and ativo = true
  );
$$;

-- ===================================================================
-- MIGRAÇÃO: Campo destino explícito em lotes (Confinamento/Pasto/Cria)
-- Antes o destino do lote era adivinhado pelo nome (se tinha
-- "confinamento" ou "reprodução" no nome). Agora é um campo explícito,
-- escolhido na hora de cadastrar o lote na aba Lotes. Esta migração
-- preenche o destino dos lotes já cadastrados usando a mesma regra
-- antiga, então nada muda de lugar para quem já estava cadastrado.
-- Pode rodar a qualquer momento.
-- ===================================================================
alter table lotes add column if not exists destino text;
update lotes set destino = case
  when nome ~* 'reprodu' then 'cria'
  when nome ~* 'confinamento' then 'confinamento'
  else 'pasto'
end
where destino is null;
alter table lotes alter column destino set default 'pasto';
alter table lotes alter column destino set not null;
alter table lotes drop constraint if exists lotes_destino_check;
alter table lotes add constraint lotes_destino_check
  check (destino in ('confinamento','pasto','cria'));

-- ===================================================================
-- MIGRAÇÃO: Módulo "Resultados" separado do Financeiro
-- Receitas e a meta de margem (config_financeiro) passam a ser
-- controladas pelo módulo "resultados" em vez de "financeiro" — assim
-- dá pra liberar o Financeiro (só custos) para alguém sem dar acesso
-- às receitas e aos demonstrativos de resultado.
-- Pode rodar a qualquer momento.
-- ===================================================================
drop policy if exists "select receitas" on receitas;
drop policy if exists "inserir receitas" on receitas;
drop policy if exists "atualizar receitas" on receitas;
drop policy if exists "excluir receitas" on receitas;
create policy "select receitas" on receitas for select using (tem_permissao('resultados','visualizar'));
create policy "inserir receitas" on receitas for insert with check (tem_permissao('resultados','editar'));
create policy "atualizar receitas" on receitas for update using (tem_permissao('resultados','editar')) with check (tem_permissao('resultados','editar'));
create policy "excluir receitas" on receitas for delete using (tem_permissao('resultados','editar'));

drop policy if exists "select config_financeiro" on config_financeiro;
drop policy if exists "inserir config_financeiro" on config_financeiro;
drop policy if exists "atualizar config_financeiro" on config_financeiro;
drop policy if exists "excluir config_financeiro" on config_financeiro;
create policy "select config_financeiro" on config_financeiro for select using (tem_permissao('resultados','visualizar'));
create policy "inserir config_financeiro" on config_financeiro for insert with check (tem_permissao('resultados','editar'));
create policy "atualizar config_financeiro" on config_financeiro for update using (tem_permissao('resultados','editar')) with check (tem_permissao('resultados','editar'));
create policy "excluir config_financeiro" on config_financeiro for delete using (tem_permissao('resultados','editar'));

-- ===================================================================
-- MIGRAÇÃO: Fazenda (área em hectares) e resultado por hectare
-- Cadastro da área é restrito a Administrador/Proprietário (mesma
-- lógica de is_admin(), que já cobre os dois cargos), mas o valor
-- calculado (resultado por hectare) fica visível pra quem já tem
-- acesso de visualização a Resultados.
-- Pode rodar a qualquer momento.
-- ===================================================================
create table config_fazenda (
  id bigint primary key,
  hectares numeric
);

alter table config_fazenda enable row level security;

create policy "select config_fazenda" on config_fazenda for select using (tem_permissao('resultados','visualizar'));
create policy "inserir config_fazenda" on config_fazenda for insert with check (is_admin());
create policy "atualizar config_fazenda" on config_fazenda for update using (is_admin()) with check (is_admin());
create policy "excluir config_fazenda" on config_fazenda for delete using (is_admin());

-- ===================================================================
-- MIGRAÇÃO: Investimentos passa de Financeiro para Resultados
-- Pode rodar a qualquer momento. Depois de rodar, revise em
-- Administração > Editar acesso quem deve enxergar Investimentos —
-- quem só tinha acesso a Financeiro não ganha "resultados" sozinho.
-- ===================================================================
drop policy if exists "select investimentos" on investimentos;
drop policy if exists "inserir investimentos" on investimentos;
drop policy if exists "atualizar investimentos" on investimentos;
drop policy if exists "excluir investimentos" on investimentos;
create policy "select investimentos" on investimentos for select using (tem_permissao('resultados','visualizar'));
create policy "inserir investimentos" on investimentos for insert with check (tem_permissao('resultados','editar'));
create policy "atualizar investimentos" on investimentos for update using (tem_permissao('resultados','editar')) with check (tem_permissao('resultados','editar'));
create policy "excluir investimentos" on investimentos for delete using (tem_permissao('resultados','editar'));

-- ===================================================================
-- MIGRAÇÃO: Partos (Cria)
-- Registro de partos por lote, com o número da mãe e o sexo do
-- bezerro. Mesmo módulo de permissão ("cria") já usado para os
-- outros lançamentos de Cria (ração e reprodução).
-- Pode rodar a qualquer momento.
-- ===================================================================
create table partos (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  numero_mae text,
  sexo_bezerro text check (sexo_bezerro in ('macho','femea'))
);

alter table partos enable row level security;

create policy "select partos" on partos for select using (tem_permissao('cria','visualizar'));
create policy "inserir partos" on partos for insert with check (tem_permissao('cria','editar'));
create policy "atualizar partos" on partos for update using (tem_permissao('cria','editar')) with check (tem_permissao('cria','editar'));
create policy "excluir partos" on partos for delete using (tem_permissao('cria','editar'));

-- ===================================================================
-- MIGRAÇÃO: Histórico mensal real de Custos Fixos
-- Antes, custo fixo era um valor único que valia igual pra todo mês
-- (passado ou futuro), o que fazia o comparativo mensal do Financeiro
-- parecer irreal (mesmo valor todo mês). Agora cada custo fixo pode
-- opcionalmente ser amarrado a um mês específico ('YYYY-MM'). Um mês
-- sem custo fixo próprio cadastrado continua caindo no valor
-- "recorrente" (mes = null), que serve de padrão/projeção.
-- Pode rodar a qualquer momento — os custos fixos já cadastrados
-- continuam funcionando normalmente como "recorrentes" (mes = null).
-- ===================================================================
alter table custos_fixos add column if not exists mes text;

-- ===================================================================
-- MIGRAÇÃO: Diluição opcional por lote/área do custo fixo
-- Todo custo fixo sempre entra no total geral (Financeiro/Resultados).
-- Até aqui, ele também era sempre rateado por lote/área/dia na proporção
-- do número de animais (aba Por Lote e gráfico "por área"). Agora dá pra
-- desmarcar essa diluição num custo fixo específico — útil para um custo
-- que já é (ou vai ser) coberto pelos lançamentos diários de ração, cocho
-- ou pasto (ex: nutrição), pra não contar esse valor duas vezes por lote.
-- Pode rodar a qualquer momento — todo custo fixo existente continua
-- diluído normalmente (diluir_por_lote = true por padrão).
-- ===================================================================
alter table custos_fixos add column if not exists diluir_por_lote boolean not null default true;

-- ===================================================================
-- MIGRAÇÃO: Área direta (Confinamento/Pasto/Cria) e data da despesa
-- Até aqui, um custo fixo só podia contar no total geral ou ser rateado
-- por cabeça entre as áreas (diluir_por_lote). Isso é o correto pra custo
-- indireto (ex: mão de obra, energia), mas um custo que já nasce ligado a
-- uma área (ex: insumo de reprodução, que é só da Cria) deveria ir inteiro
-- pra ela, sem rateio — é assim que apuração de custo em pecuária separa
-- custo direto (vai 100% pra área de origem) de indireto (rateado).
-- Também adiciona uma data específica da despesa (opcional), além do mês —
-- pra registrar uma conta como um lançamento real (ex: nota fiscal de um
-- dia específico), não só um valor recorrente ou mensal.
-- Pode rodar a qualquer momento — toda despesa existente continua com
-- área em branco (geral/indireta, comportamento igual a antes).
-- ===================================================================
alter table custos_fixos add column if not exists area text check (area in ('confinamento','pasto','cria'));
alter table custos_fixos add column if not exists data date;

-- ===================================================================
-- MIGRAÇÃO: Pesagem (Confinamento, Pasto e Cria)
-- Nova aba "Pesagem", dentro de Confinamento, Pasto e Cria, pra registrar
-- o peso médio por animal de um lote, com data e observação. A partir do
-- histórico de pesagens dá pra calcular o ganho de peso (GMD) e a arroba
-- produzida de cada lote — usados no Financeiro pra mostrar o custo por
-- arroba produzida (@), por lote e da fazenda inteira.
-- Pode rodar a qualquer momento, sem ordem especial.
-- ===================================================================
create table pesagens (
  id bigint generated always as identity primary key,
  lote_id bigint references lotes(id) on delete cascade,
  data date not null,
  peso_medio_kg numeric not null,
  observacao text
);
alter table pesagens enable row level security;
create policy "select pesagens" on pesagens for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
);
create policy "inserir pesagens" on pesagens for insert with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);
create policy "atualizar pesagens" on pesagens for update using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);
create policy "excluir pesagens" on pesagens for delete using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
);

-- ===================================================================
-- MIGRAÇÃO: Observação em Despesas e Receitas
-- Cocho e Pesagem já tinham um campo de observação opcional; Despesas
-- (custos_fixos) e Receitas não tinham como anotar um detalhe do
-- lançamento (ex: número da nota fiscal, comprador, motivo do valor).
-- Pode rodar a qualquer momento — todo lançamento existente continua
-- com observação em branco.
-- ===================================================================
alter table custos_fixos add column if not exists observacao text;
alter table receitas add column if not exists observacao text;

-- ===================================================================
-- MIGRAÇÃO: Área direta combinada "Pasto + Cria"
-- Além da área direta única (Confinamento/Pasto/Cria) e do rateio geral
-- (entre as três), uma despesa pode ser direta de "Pasto + Cria" — vai só
-- pra essas duas, rateada por nº de animais entre elas, sem pesar no
-- Confinamento (ex: insumo agrícola de manejo de pasto/forragem, usado
-- tanto por quem tá solto quanto pela Cria, mas não pelo confinado).
-- Pode rodar a qualquer momento — nenhuma despesa existente usa esse
-- valor ainda, então nada muda até alguém escolher essa área.
-- ===================================================================
alter table custos_fixos drop constraint if exists custos_fixos_area_check;
alter table custos_fixos add constraint custos_fixos_area_check check (area in ('confinamento','pasto','cria','pasto_cria'));

-- ===================================================================
-- MIGRAÇÃO: Quem lançou (autor do lançamento)
-- Cada lançamento de campo (Saída de Ração, Leitura de Cocho, Pasto,
-- Reprodução, Partos e Pesagem) passa a guardar o nome de quem estava
-- logado ao criar o registro — mostrado como coluna "Lançado por" nas
-- respectivas listas. Só grava no momento de criar (insert); editar um
-- lançamento existente não troca o autor original.
-- Pode rodar a qualquer momento — nenhum lançamento existente é afetado
-- (fica com "Lançado por" em branco, já que não tem como recuperar quem
-- fez os lançamentos antigos).
-- ===================================================================
alter table saidas_racao add column if not exists criado_por text;
alter table leituras_cocho add column if not exists criado_por text;
alter table pasto add column if not exists criado_por text;
alter table reproducao_custos add column if not exists criado_por text;
alter table partos add column if not exists criado_por text;
alter table pesagens add column if not exists criado_por text;

-- ===================================================================
-- MIGRAÇÃO: Preço da entrada e média ponderada de custo
-- Uma "Entrada" de estoque passa a poder informar o preço pago (R$/kg)
-- daquela compra. Se informado, o preço/kg do ingrediente é recalculado
-- automaticamente pela média ponderada entre o estoque que já existia
-- (antes dessa entrada) e a quantidade que está entrando — refletindo
-- reajustes de preço sem precisar editar o ingrediente manualmente.
-- Só acontece ao registrar uma entrada nova (não ao editar uma já
-- existente) e só quando o preço é informado (campo opcional).
-- Pode rodar a qualquer momento — todo movimento existente fica com
-- preco_kg em branco, sem efeito nenhum sobre o preço já cadastrado.
-- ===================================================================
alter table movimentos add column if not exists preco_kg numeric;

-- ===================================================================
-- MIGRAÇÃO: Horário do lançamento e bloqueio de edição da data (Saída de Ração)
-- Toda Saída de Ração passa a guardar o momento exato (data + hora) em
-- que foi lançada, mostrado como "Lançado em" na lista e no modal de
-- edição. Além disso, a Data do lançamento (a data operacional escolhida
-- por quem lança, diferente do "Lançado em" automático) só pode ser
-- alterada por Administrador ou Proprietário — outros papéis veem o
-- campo desabilitado ao editar um lançamento já existente (continuam
-- podendo editar dieta, lote e quantidade normalmente). Só vale pra
-- edição; lançar um registro novo continua liberado pra quem tem acesso.
-- Pode rodar a qualquer momento — todo lançamento existente fica com
-- "Lançado em" em branco (sem como recuperar o horário de lançamentos
-- antigos).
-- ===================================================================
alter table saidas_racao add column if not exists criado_em timestamptz;

-- ===================================================================
-- MIGRAÇÃO: Múltiplas atividades por despesa (rateio automático generalizado)
-- Substitui a área única (area: confinamento/pasto/cria/pasto_cria/geral)
-- e a diluição opcional (diluir_por_lote) por uma lista de atividades
-- (areas: subconjunto de confinamento/pasto/cria, de 0 a 3 itens):
--   - 0 marcadas (Geral): valor sempre rateado por nº de animais entre as
--     três atividades (não existe mais opção de "Geral, não diluído").
--   - 1 marcada: valor inteiro vai pra aquela atividade, sem rateio.
--   - 2 ou 3 marcadas: valor rateado por nº de animais só entre as
--     marcadas (generaliza o antigo "Pasto + Cria" pra qualquer par, e
--     3 marcadas dá no mesmo resultado que Geral).
-- O backfill abaixo converte o dado antigo (coluna area + diluir_por_lote)
-- pro novo formato, preservando o comportamento de cada despesa já
-- cadastrada. As colunas antigas ficam pra trás (não usadas pelo app),
-- sem dropar nada.
-- Pode rodar a qualquer momento.
-- ===================================================================
alter table custos_fixos add column if not exists areas text[] not null default '{}';
update custos_fixos set areas = case
  when area = 'confinamento' then array['confinamento']
  when area = 'pasto' then array['pasto']
  when area = 'cria' then array['cria']
  when area = 'pasto_cria' then array['pasto','cria']
  else '{}'
end
where areas = '{}';

-- ===================================================================
-- MIGRAÇÃO: Dieta de Cria
-- Até aqui uma dieta só podia ser "Confinamento" ou "Pasto" — a Saída de
-- Ração da Cria reaproveitava as dietas de Confinamento, sem opção
-- própria. Agora existe um terceiro tipo, "Cria", e cada tela de Saída
-- de Ração (Confinamento/Cria) só lista as dietas do seu próprio tipo.
-- Dietas já cadastradas como "confinamento" continuam nesse tipo — se
-- alguma foi criada pra uso da Cria, edite-a e troque o Tipo pra "Cria"
-- pra ela aparecer na Saída de Ração da Cria.
-- Pode rodar a qualquer momento.
-- ===================================================================
alter table dietas drop constraint if exists dietas_tipo_check;
alter table dietas add constraint dietas_tipo_check check (tipo in ('confinamento','cria','pasto'));

-- ===================================================================
-- MIGRAÇÃO: Estoque de Ração Pronta (produto já misturado)
-- Até aqui, lançar uma Saída de Ração ou uma reposição de Pasto descontava
-- direto o estoque de cada INGREDIENTE CRU (milho, farelo, etc.) na
-- proporção da composição da dieta. Agora existe um estágio intermediário,
-- a "ração pronta" (o produto já misturado): um novo lançamento, "Produção
-- de Ração" (tabela producoes_racao), registra que X kg de uma dieta foram
-- misturados — isso desconta os ingredientes crus (mesma lógica de antes,
-- só que agora só acontece na produção) e soma X kg no estoque de ração
-- pronta daquela dieta. A Saída de Ração e a reposição de Pasto passam a
-- só descontar desse estoque de ração pronta (não descontam mais o
-- ingrediente cru diretamente) — o app calcula esse saldo (produzido menos
-- consumido) sem precisar de uma coluna de saldo por dieta.
-- Cada dieta também ganha um "estoque mínimo de ração pronta (kg)", pra
-- mostrar um alerta na nova aba Estoque de Ração quando o saldo cair
-- abaixo disso — mesmo princípio do estoque mínimo dos ingredientes.
-- Pode rodar a qualquer momento — nenhuma dieta ou lançamento existente
-- muda de comportamento sozinho (estoque mínimo começa em 0 = sem
-- alerta; o estoque de ração pronta começa em 0 até a primeira produção
-- ser registrada).
-- ===================================================================
alter table dietas add column if not exists estoque_min_pronta numeric not null default 0;

create table if not exists producoes_racao (
  id bigint generated always as identity primary key,
  data date not null,
  dieta_id bigint references dietas(id) on delete set null,
  quantidade_kg numeric not null,
  criado_por text,
  criado_em timestamptz default now()
);
alter table movimentos add column if not exists producao_racao_id bigint references producoes_racao(id) on delete cascade;

alter table producoes_racao enable row level security;
create policy "select producoes_racao" on producoes_racao for select using (tem_permissao('dietas','visualizar'));
create policy "inserir producoes_racao" on producoes_racao for insert with check (tem_permissao('dietas','editar'));
create policy "atualizar producoes_racao" on producoes_racao for update using (tem_permissao('dietas','editar')) with check (tem_permissao('dietas','editar'));
create policy "excluir producoes_racao" on producoes_racao for delete using (tem_permissao('dietas','editar'));

-- ===================================================================
-- MIGRAÇÃO: Abate
-- Nova aba "Abates", dentro de Confinamento, Pasto e Cria, pra registrar
-- o abate de animais de um lote: quantidade abatida, peso médio por
-- animal e o valor da arroba na venda. Ao salvar:
--   - desconta a quantidade abatida do número de animais do lote (fecha
--     o lote automaticamente — data de encerramento = data do abate —
--     se isso zerar o número de animais);
--   - lança uma Receita automática em Resultados (arrobas = peso médio
--     ÷ 30 × quantidade; valor = arrobas × valor da arroba), vinculada
--     ao abate (excluir/editar o abate também exclui/atualiza a receita).
-- Como isso mexe em Receita (módulo Resultados, mantido separado
-- justamente pra controlar quem vê receita/resultado da operação),
-- registrar um abate exige editar tanto no módulo do lote quanto em
-- Resultados — não só um dos dois.
-- Pode rodar a qualquer momento.
-- ===================================================================
create table abates (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  quantidade numeric not null,
  peso_medio_kg numeric not null,
  valor_arroba numeric not null,
  observacao text default '',
  criado_por text,
  criado_em timestamptz default now()
);
alter table receitas add column if not exists abate_id bigint references abates(id) on delete cascade;

alter table abates enable row level security;
create policy "select abates" on abates for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
);
create policy "inserir abates" on abates for insert with check (
  (tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar'))
  and tem_permissao('resultados','editar')
);
create policy "atualizar abates" on abates for update using (
  (tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar'))
  and tem_permissao('resultados','editar')
) with check (
  (tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar'))
  and tem_permissao('resultados','editar')
);
create policy "excluir abates" on abates for delete using (
  (tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar'))
  and tem_permissao('resultados','editar')
);
