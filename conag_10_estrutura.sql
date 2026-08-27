-- ============================================================
-- ETAPA 1 DE 3: PREPARA O TERRENO PARA A IMPORTACAO DO CONAG
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- Este script NAO importa nada. Ele so cria a mesa onde os dados vao
-- pousar e as colunas que faltam. Nenhum dos 2.760 lancamentos atuais e
-- tocado.
--
-- DEPOIS DELE voce carrega o CSV na tabela conag_staging pela tela do
-- Supabase (Table Editor > conag_staging > Insert > Import data from CSV),
-- e so entao roda a etapa 2, que e a CONFERENCIA - ela mostra o que seria
-- duplicado antes de qualquer coisa entrar.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;


-- ------------------------------------------------------------
-- A MESA DE POUSO
--
-- Tudo texto de proposito: o CSV vem com virgula decimal, data em varios
-- formatos e nome com acento. Converter na hora da carga faria a carga
-- falhar por causa de uma linha ruim. Aqui entra tudo, e a conversao
-- acontece na etapa 3, onde da para ver o que nao converteu.
-- ------------------------------------------------------------
drop table if exists conag_staging;
create table conag_staging (
  conag_id         text,
  conag_cod        text,
  entidade         text,
  centro_custo     text,
  cnpj_nota        text,
  forma_pagamento  text,
  vencimento       text,
  competencia      text,
  valor            text,
  previsao         text,
  usuario          text,
  atividade_conag  text,
  fazenda_conag    text,
  atividade        text,
  cultura          text,
  administrativo   text
);
comment on table conag_staging is
  'Mesa de pouso do CSV do Conag. Some depois da importacao conferida.';


-- ------------------------------------------------------------
-- DE ONDE VEIO CADA LANCAMENTO
--
-- Sem esta coluna nao ha como saber, daqui a seis meses, o que veio do
-- Conag e o que foi lancado no app - nem como rodar a importacao de novo
-- sem duplicar. O indice unico e o que impede a segunda rodada de repetir
-- a primeira.
-- ------------------------------------------------------------
alter table lancamentos_financeiros
  add column if not exists conag_id text;

create unique index if not exists uq_lancamento_conag
  on lancamentos_financeiros (conag_id) where conag_id is not null;

comment on column lancamentos_financeiros.conag_id is
  'Id do titulo no Conag (a segunda parte do Cod-Id). Nulo em lancamento '
  'feito no proprio app. Unico: a importacao pode rodar duas vezes sem '
  'duplicar.';


-- ------------------------------------------------------------
-- POR QUAL EMPRESA O TITULO FOI PAGO
--
-- O Conag guarda o CPF/CNPJ da nota, e ha titulos com DOIS documentos na
-- mesma linha - rateio entre as pessoas juridicas. Fica como texto: e
-- informacao fiscal, nao dimensao de custo, e inventar uma tabela de
-- pessoas juridicas agora seria construir para um uso que ainda nao existe.
-- ------------------------------------------------------------
alter table lancamentos_financeiros
  add column if not exists cnpj_nota text;


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
-- ------------------------------------------------------------
select 1 as ordem, 'conag_staging criada' as item,
       (select count(*) from information_schema.tables
         where table_schema='public' and table_name='conag_staging')::text as valor,
       'vazia, esperando o CSV' as situacao
union all
select 2, 'coluna conag_id',
       (select count(*) from information_schema.columns
         where table_name='lancamentos_financeiros' and column_name='conag_id')::text,
       'criada'
union all
select 3, 'indice unico do conag_id',
       (select count(*) from pg_indexes
         where tablename='lancamentos_financeiros' and indexname='uq_lancamento_conag')::text,
       'impede importar duas vezes'
union all
select 4, 'Lancamentos hoje', count(*)::text, 'nao pode ter mudado'
from lancamentos_financeiros
union all
select 5, 'Total hoje', round(sum(valor),2)::text, 'nao pode ter mudado'
from lancamentos_financeiros
order by ordem;
