-- ============================================================
-- MODELO UNICO DE LANCAMENTO FINANCEIRO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
--
-- NAO RODE AINDA. Leia primeiro e me diga se concorda com o modelo.
-- Depois que voce aprovar, eu ajusto os apps e a gente roda os dois juntos:
-- rodar so este script deixaria o AE Pecuaria mostrando dado antigo
-- enquanto o Matriz ja usaria o novo.
--
-- ------------------------------------------------------------
-- O PROBLEMA QUE ELE RESOLVE
--
-- Hoje a mesma coisa - uma despesa - tem tres formatos diferentes:
--
--   custos_fixos (Pecuaria):  sem fazenda, centro de custo em texto livre,
--                             rateio por atividade, tem recorrente
--   despesas_cana (Lavoura):  fazenda obrigatoria, centro de custo por FK,
--                             categoria de lista fixa, sem recorrente
--   despesas_graos (Lavoura): igual a de cana
--
-- Por isso o Financeiro do Matriz so aceitava lancamento de pecuaria: o
-- formulario que eu portei veio da Pecuaria e nao tem nem campo de fazenda.
--
-- Colocar um seletor de operacao em cima disso daria tres formularios
-- diferentes na mesma tela. A solucao e um modelo so, com a atividade
-- virando campo em vez de virar tabela.
--
-- ------------------------------------------------------------
-- DECISOES QUE VOCE TOMOU, E ONDE ELAS APARECEM AQUI
--
-- 1. Fazenda obrigatoria, com opcao Geral
--    -> fazenda_id aceita nulo, e nulo significa "Geral / toda a empresa".
--       A tela obriga a escolher, tendo Geral como uma das opcoes.
--
-- 2. Centro de custo de lista fixa
--    -> centro_custo_id e NOT NULL e aponta para centros_custo, que ja
--       existe. Acabou o texto livre que hoje faz "Mao de obra",
--       "Mao-de-obra" e "MAO DE OBRA" virarem tres linhas no relatorio.
--
-- 3. Recorrente para todas as atividades
--    -> data nula significa recorrente, em qualquer atividade. Mesma regra
--       que a pecuaria ja usava: lancamento com data conta so no mes dele e
--       substitui o recorrente naquele mes.
-- ============================================================

do $modelo$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$modelo$;


-- ------------------------------------------------------------
-- 1) CENTROS DE CUSTO PASSAM A PODER SER GLOBAIS
--
-- Hoje centros_custo exige fazenda_id, entao o mesmo centro precisaria ser
-- recadastrado em cada fazenda. Com fazenda_id nulo, ele vale para todas.
-- O indice parcial impede dois centros globais com o mesmo nome (a
-- restricao unica atual nao pega isso, porque no Postgres nulos sao sempre
-- considerados diferentes entre si).
-- ------------------------------------------------------------
alter table centros_custo alter column fazenda_id drop not null;
create unique index if not exists uq_centro_custo_global
  on centros_custo (nome) where fazenda_id is null;


-- ------------------------------------------------------------
-- 2) A TABELA UNICA
-- ------------------------------------------------------------
create table if not exists lancamentos_financeiros (
  id bigint generated always as identity primary key,

  -- o que e
  tipo      text not null check (tipo in ('despesa','receita','investimento')),
  atividade text not null check (atividade in ('graos','cana','pecuaria','geral')),

  -- de quem e. fazenda_id nulo = Geral / toda a empresa.
  fazenda_id      bigint references fazendas(id),
  centro_custo_id bigint not null references centros_custo(id),

  -- o basico, tudo obrigatorio
  descricao text    not null check (length(trim(descricao)) > 0),
  valor     numeric(12,2) not null check (valor > 0),

  -- data nula = recorrente, vale para qualquer mes sem lancamento proprio.
  -- mes e derivado da data e existe so para consulta rapida por periodo.
  data date,
  mes  text,

  fornecedor text,
  observacao text,

  -- vinculos que so fazem sentido em algumas atividades. Ficam nulos nas
  -- outras, em vez de virarem tabela separada.
  talhao_id bigint references talhoes_areas(id),  -- lavoura
  lote_id   bigint references lotes(id),          -- pecuaria
  areas     text[] not null default '{}',         -- pecuaria: confinamento/pasto/cria
  arrobas   numeric,                              -- receita de pecuaria

  created_at timestamptz not null default now(),
  criado_por text,

  -- mes tem que bater com a data, ou os dois nulos (recorrente)
  constraint mes_bate_com_data check (
    (data is null and mes is null) or (data is not null and mes = to_char(data, 'YYYY-MM'))
  )
);

create index if not exists idx_lanc_fin_tipo_atividade on lancamentos_financeiros (tipo, atividade);
create index if not exists idx_lanc_fin_mes            on lancamentos_financeiros (mes);
create index if not exists idx_lanc_fin_fazenda        on lancamentos_financeiros (fazenda_id);

alter table lancamentos_financeiros enable row level security;

-- Quem ve e quem lanca: mesmo modulo do Matriz. Admin e proprietario
-- passam por cima, como nos outros apps.
drop policy if exists "ve lancamentos" on lancamentos_financeiros;
create policy "ve lancamentos" on lancamentos_financeiros
  for select using (is_admin() or tem_permissao('matriz_financeiro','visualizar'));

drop policy if exists "lanca" on lancamentos_financeiros;
create policy "lanca" on lancamentos_financeiros
  for insert with check (is_admin() or tem_permissao('matriz_financeiro','editar'));

drop policy if exists "edita lancamentos" on lancamentos_financeiros;
create policy "edita lancamentos" on lancamentos_financeiros
  for update using (is_admin() or tem_permissao('matriz_financeiro','editar'))
          with check (is_admin() or tem_permissao('matriz_financeiro','editar'));

drop policy if exists "exclui lancamentos" on lancamentos_financeiros;
create policy "exclui lancamentos" on lancamentos_financeiros
  for delete using (is_admin() or tem_permissao('matriz_financeiro','editar'));


-- ------------------------------------------------------------
-- 3) CONFERENCIA: o que sera migrado quando voce aprovar
--
-- Este bloco NAO migra nada. So mostra o tamanho do trabalho e, o mais
-- importante, quais centros de custo serao criados a partir do texto livre
-- que existe hoje. Olhe essa lista com atencao: e onde as duplicatas de
-- grafia vao aparecer, e vale corrigir ANTES de migrar.
-- ------------------------------------------------------------
select 'despesas da pecuaria (custos_fixos)' as origem, count(*) as linhas from custos_fixos
union all select 'receitas da pecuaria',      count(*) from receitas
union all select 'investimentos da pecuaria', count(*) from investimentos
union all select 'despesas de cana',          count(*) from despesas_cana
union all select 'despesas de graos',         count(*) from despesas_graos
union all select 'centros de custo ja cadastrados', count(*) from centros_custo;

-- Centros de custo que teriam de ser criados a partir do texto livre de
-- hoje. Duplicatas de grafia aparecem aqui como linhas separadas.
select distinct categoria as centro_de_custo_encontrado, count(*) as usos
from custos_fixos
where coalesce(trim(categoria), '') <> ''
group by categoria
order by count(*) desc, categoria;
