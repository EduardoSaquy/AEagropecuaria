-- ============================================================
-- Cana: campo "Area colhida (ha)" na colheita (pedido do Eduardo, 21/10/2026)
--
-- Quando parte do talhao nao e colhida (ex: cana planta do ano), o TCH pela
-- area inteira do talhao sai errado. Coluna opcional: em branco = o talhao
-- inteiro foi colhido, como sempre foi.
--
-- Tambem preenche a area colhida das 5 colheitas da Palmito de 20/10/2026,
-- que ja trazem a area na observacao ("dividida pela area colhida: X ha de").
-- Rode ANTES de usar o app atualizado: sem a coluna, salvar colheita da erro.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table public.colheitas_cana add column if not exists area_colhida numeric(12,2);
alter table public.colheitas_cana drop constraint if exists colheitas_cana_area_colhida_positiva;
alter table public.colheitas_cana add constraint colheitas_cana_area_colhida_positiva
  check (area_colhida is null or area_colhida > 0);
comment on column public.colheitas_cana.area_colhida is
  'Area efetivamente colhida (ha), quando menor que o talhao. Nula = talhao inteiro.';

update public.colheitas_cana
   set area_colhida = substring(observacao from 'area colhida: ([0-9]+\.?[0-9]*) ha de')::numeric
 where area_colhida is null
   and observacao like 'Producao total da fazenda (11.483,74 t) dividida pela area colhida:%';

select 'colheitas com area colhida informada' item, count(*)::text valor,
       coalesce(string_agg(to_char(data,'DD/MM/YYYY') || ' ' || area_colhida || ' ha', ', '), '-') situacao
  from public.colheitas_cana where area_colhida is not null;
