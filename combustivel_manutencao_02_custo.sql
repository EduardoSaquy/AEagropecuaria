-- ============================================================
-- AE Combustivel: custo da manutencao (07/11/2026)
--
-- Acrescenta manutencoes.custo (R$, opcional). O app soma esse custo ao combustivel para
-- mostrar o CUSTO POR HORA (ou km) de cada equipamento em Rateio > Por Equipamento.
-- Nao muda nenhuma linha existente: custo comeca vazio. O app funciona antes e depois deste
-- script (so manda a coluna quando o custo e preenchido).
--
-- Rode este arquivo inteiro de uma vez. Pode rodar de novo sem problema.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='manutencoes') then
    raise exception 'PROJETO ERRADO ou combustivel_manutencao_01_schema.sql ainda nao rodou: a tabela manutencoes nao existe.';
  end if;
end $$;

alter table manutencoes add column if not exists custo numeric(12,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'manutencoes_custo_nao_negativo') then
    alter table manutencoes add constraint manutencoes_custo_nao_negativo check (custo is null or custo >= 0);
  end if;
end $$;

-- conferencia (uma consulta so, no fim)
select 'coluna manutencoes.custo' as item,
       coalesce((select data_type from information_schema.columns
                 where table_schema='public' and table_name='manutencoes' and column_name='custo'), 'NAO EXISTE') as valor,
       case when exists (select 1 from information_schema.columns
                         where table_schema='public' and table_name='manutencoes' and column_name='custo')
            then 'OK' else 'FALTA' end as situacao
union all
select 'trava: custo nao pode ser negativo', 'manutencoes_custo_nao_negativo',
       case when exists (select 1 from pg_constraint where conname = 'manutencoes_custo_nao_negativo') then 'OK' else 'FALTA' end
union all
select 'manutencoes ja lancadas (continuam como estavam)', (select count(*)::text from manutencoes), 'OK';
