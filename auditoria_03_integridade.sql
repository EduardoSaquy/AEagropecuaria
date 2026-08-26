-- ============================================================
-- INTEGRIDADE: EXCLUSAO QUE TRAVA E CHAVE SEM INDICE
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- 1. EXCLUIR LOTE COM VENDA E IMPOSSIVEL, COM ERRO INCOMPREENSIVEL
--
-- O aviso da tela promete: "vendas nao sao apagadas - ficam sem lote
-- associado". Isso vale para a tabela abates, que tem on delete set null.
-- Mas a receita gerada pela venda mora em lancamentos_financeiros, e la a
-- chave estrangeira foi declarada SEM clausula on delete - o que no
-- Postgres significa NO ACTION, ou seja, bloqueia.
--
-- Resultado: um lote encerrado que teve venda nunca sai da lista. O erro
-- que aparece fala de "foreign key constraint", e nao ha nada na Pecuaria
-- que permita desvincular a receita do lote.
--
-- O mesmo vale para talhao, safra e cultura: apagar um talhao bloqueia por
-- causa dos lancamentos ligados a ele.
--
-- A correcao e set null nesses quatro: o lancamento continua existindo, com
-- o valor intacto, so perde o vinculo - exatamente o que a tela promete.
--
-- centro_custo_id fica de fora de proposito: ali bloquear e o certo. Um
-- lancamento sem centro de custo nao teria como entrar em relatorio nenhum,
-- e a tela ja oferece desativar o centro em vez de excluir.
--
-- ------------------------------------------------------------
-- 2. CHAVE ESTRANGEIRA SEM INDICE
--
-- Toda exclusao de registro pai varre a tabela filha inteira para conferir
-- as referencias. Com 2.759 lancamentos ninguem nota; a tabela concentra o
-- financeiro de tres operacoes e cresce.
-- ============================================================

do $integridade$
declare
  r record;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 1) on delete set null nos vinculos opcionais ----------
  for r in
    select conname, a.attname as coluna, confrelid::regclass::text as referencia
    from pg_constraint c
    join lateral unnest(c.conkey) k(attnum) on true
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f'
      and c.conrelid = 'lancamentos_financeiros'::regclass
      and a.attname in ('lote_id','talhao_id','safra_id','cultura_id')
      and c.confdeltype <> 'n'          -- 'n' = SET NULL, ja esta certo
  loop
    execute format('alter table lancamentos_financeiros drop constraint %I', r.conname);
    execute format(
      'alter table lancamentos_financeiros add constraint %I foreign key (%I) references %s(id) on delete set null',
      r.conname, r.coluna, r.referencia);
    raise notice 'Agora % nao bloqueia mais a exclusao de %', r.coluna, r.referencia;
  end loop;

  -- ---------- 2) indices nas chaves estrangeiras ----------
  create index if not exists idx_lanc_fin_safra   on lancamentos_financeiros (safra_id);
  create index if not exists idx_lanc_fin_cultura on lancamentos_financeiros (cultura_id);
end
$integridade$;

analyze lancamentos_financeiros;


-- ============================================================
-- CONFERENCIA 1 - O QUE ACONTECE AO APAGAR O PAI
--
-- Esperado:
--   lote_id, talhao_id, safra_id, cultura_id  ->  SET NULL
--   centro_custo_id                           ->  bloqueia (de proposito)
--   abate_id                                  ->  CASCADE (apaga a receita
--                                                 junto com a venda)
-- ============================================================
select a.attname as coluna,
       confrelid::regclass::text as referencia,
       case c.confdeltype
         when 'a' then 'bloqueia'
         when 'r' then 'bloqueia'
         when 'n' then 'SET NULL'
         when 'c' then 'CASCADE'
         when 'd' then 'volta ao padrao'
       end as ao_apagar_o_pai
from pg_constraint c
join lateral unnest(c.conkey) k(attnum) on true
join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
where c.contype = 'f' and c.conrelid = 'lancamentos_financeiros'::regclass
order by a.attname;


-- ============================================================
-- CONFERENCIA 2 - CHAVE ESTRANGEIRA AINDA SEM INDICE
--
-- Cada linha e uma coluna onde apagar o registro pai varre a tabela filha
-- inteira. O ideal e voltar vazia para lancamentos_financeiros.
-- ============================================================
select conrelid::regclass::text as tabela, a.attname as coluna,
       confrelid::regclass::text as referencia
from pg_constraint c
join lateral unnest(c.conkey) k(attnum) on true
join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
where c.contype = 'f' and c.connamespace = 'public'::regnamespace
  and not exists (select 1 from pg_index i
                  where i.indrelid = c.conrelid and i.indkey[0] = k.attnum)
order by 1, 2;
