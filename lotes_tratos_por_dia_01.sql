-- lotes_tratos_por_dia_01.sql (14/11/2026)
-- Quantos tratos o lote recebe por dia (opcional). O AE Pecuaria mostra, na Saida de Racao, quantos ja foram
-- lancados hoje e os dias dos ultimos 7 com trato faltando. Coluna opcional: em branco o lote nao entra na conferencia.
-- O app funciona antes deste script (so manda a coluna quando ha valor). Pode rodar de novo.

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO: este script e do projeto unificado do AE Agropecuaria';
  end if;
end $$;

alter table public.lotes add column if not exists tratos_por_dia smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='lotes_tratos_por_dia_check') then
    alter table public.lotes add constraint lotes_tratos_por_dia_check check (tratos_por_dia is null or tratos_por_dia between 1 and 12);
  end if;
end $$;

comment on column public.lotes.tratos_por_dia is 'Tratos por dia do lote (opcional, 1 a 12): a Saida de Racao confere quantos foram lancados.';

select 'coluna tratos_por_dia' as item,
       (select count(*) from information_schema.columns where table_schema='public' and table_name='lotes' and column_name='tratos_por_dia')::text as valor,
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='lotes' and column_name='tratos_por_dia') then 'OK' else 'FALTA' end as situacao
union all
select 'trava de 1 a 12',
       (select count(*) from pg_constraint where conname='lotes_tratos_por_dia_check')::text,
       case when exists (select 1 from pg_constraint where conname='lotes_tratos_por_dia_check') then 'OK' else 'FALTA' end;

-- Para desfazer:
-- alter table public.lotes drop constraint if exists lotes_tratos_por_dia_check;
-- alter table public.lotes drop column if exists tratos_por_dia;
