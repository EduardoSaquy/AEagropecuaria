-- ============================================================
-- IMPORTACAO DO CONAG - PARTE 1 de 3 (cole no SQL Editor do Supabase)
--
-- Versao pra quem esta no navegador (tablet/celular), sem terminal.
-- E o MESMO conag_tudo.sql, so dividido em 3 pedacos porque uma parte
-- dele (carregar o CSV) so funciona por terminal (psql). Aqui voce troca
-- essa parte pelo Table Editor, que faz a mesma coisa.
--
-- ORDEM:
--   1. Cole ESTE arquivo aqui, roda.
--   2. Table Editor -> conag_staging -> Insert -> Import data from CSV
--      -> escolhe conag/lancamentos_para_importar.csv (baixa do repo se
--      precisar) -> confirma. Os nomes das colunas do CSV batem exatos com
--      as da tabela, entao o Supabase mapeia sozinho.
--   3. Cole o conag_dashboard_2_depois_do_csv.sql, roda.
--
-- PRE-REQUISITOS ja feitos por voce no dashboard:
--   centros_05_dois_niveis.sql   (coluna classe + arvore do Conag)
--   centros_07_de_para.sql       (deu 7 / 1.375 / 2)
-- Se algum faltar, este arquivo para na primeira linha e diz qual.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_name='centros_custo' and column_name='classe') then
    raise exception 'FALTA O centros_05 - rode ele antes';
  end if;
  if not exists (select 1 from pg_proc where proname='plano_norm') then
    raise exception 'FALTA O centros_05 - a funcao plano_norm nao existe';
  end if;
end $$;

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
  administrativo   text,
  contrato         text
);
comment on table conag_staging is
  'Mesa de pouso do CSV do Conag. Some depois da importacao conferida.';

alter table lancamentos_financeiros
  add column if not exists conag_id text;

create unique index if not exists uq_lancamento_conag
  on lancamentos_financeiros (conag_id) where conag_id is not null;

comment on column lancamentos_financeiros.conag_id is
  'Id do titulo no Conag (a segunda parte do Cod-Id). Nulo em lancamento '
  'feito no proprio app. Unico: a importacao pode rodar duas vezes sem '
  'duplicar.';

alter table lancamentos_financeiros
  add column if not exists cnpj_nota text;

alter table lancamentos_financeiros
  add column if not exists contrato text;

-- Se rodou sem erro, agora vai no Table Editor importar o CSV pra dentro
-- de conag_staging (passo 2 acima), e depois cola o arquivo _2_.
select 'Parte 1 ok. Agora importe o CSV em conag_staging pelo Table Editor.' as proximo_passo;
