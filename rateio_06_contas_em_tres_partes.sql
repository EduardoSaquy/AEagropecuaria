-- ============================================================
-- CONFERENCIA (SO LEITURA): as contas que ficaram divididas em partes iguais
-- entre as tres atividades (Pecuaria, Cana e Graos)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz), DEPOIS do rateio_05_conserto.sql.
-- Cole inteiro e rode. Nao altera nada. Devolve UMA tabela.
--
-- Olha so os lancamentos que o conserto refez (os que estao no backup
-- zz_backup_rateio_2026_11_05) e que hoje tem exatamente tres partes, uma de cada
-- atividade, com valores iguais (diferenca de ate R$ 0,02 pelos centavos).
-- Agrupa por centro de custo e fornecedor, do maior valor para o menor.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_rateio_2026_11_05') is null then
    raise exception 'Falta o backup zz_backup_rateio_2026_11_05: o rateio_05_conserto.sql ainda nao foi rodado.';
  end if;
end
$trava$;

with
partes as (
  select r.lancamento_id,
         count(*) as n,
         count(distinct r.atividade) as atividades,
         max(r.valor) - min(r.valor) as dif,
         bool_or(r.fazenda_id is not null) as com_fazenda
    from lancamento_rateios r
   where r.lancamento_id in (select lancamento_id from zz_backup_rateio_2026_11_05)
   group by r.lancamento_id
),
contas as (
  select l.id, l.valor, l.mes, p.com_fazenda,
         coalesce(cc.nome, '(sem centro de custo)') as centro_de_custo,
         coalesce(nullif(btrim(l.fornecedor), ''), nullif(btrim(l.descricao), ''), '(sem nome)') as fornecedor
    from lancamentos_financeiros l
    join partes p on p.lancamento_id = l.id
    left join centros_custo cc on cc.id = l.centro_custo_id
   where p.n = 3 and p.atividades = 3 and p.dif <= 0.02
),
grupos as (
  select centro_de_custo, fornecedor,
         count(*) as lancamentos,
         round(sum(valor), 2) as valor_total,
         round(sum(valor) / 3, 2) as cada_atividade,
         min(mes) || ' a ' || max(mes) as meses,
         case when bool_or(com_fazenda) then 'sim' else 'nao' end as de_uma_fazenda
    from contas
   group by centro_de_custo, fornecedor
),
saida as (
  select 1 as ord, -valor_total as sub, centro_de_custo, fornecedor, lancamentos,
         valor_total, cada_atividade, meses, de_uma_fazenda
    from grupos
  union all
  select 2, 0, 'TOTAL EM TRES PARTES IGUAIS', '', coalesce(sum(lancamentos), 0),
         coalesce(sum(valor_total), 0), coalesce(round(sum(valor_total) / 3, 2), 0), '', ''
    from grupos
)
select centro_de_custo, fornecedor, lancamentos, valor_total, cada_atividade, meses, de_uma_fazenda
  from saida
 order by ord, sub, centro_de_custo, fornecedor;
