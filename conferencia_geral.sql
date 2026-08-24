-- ============================================================
-- CONFERENCIA GERAL - TUDO O QUE MUDOU NESTA SEQUENCIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole tudo, rode uma vez, me mande o resultado inteiro.
-- NAO ALTERA NADA. So le e confere.
--
-- ------------------------------------------------------------
-- COMO LER
--
-- A coluna situacao diz OK ou aponta o problema. O ideal e OK em todas as
-- linhas. Qualquer coisa diferente de OK, me mande.
--
-- A coluna item usa numeracao so para voce citar a linha ao me responder -
-- nao e ordem de importancia.
-- ============================================================

with

-- ---------- 1) O DINHEIRO CONTINUA TODO LA ----------
-- O total tem que ser a soma exata das cinco origens migradas:
-- 473 despesas + 15 receitas + 21 investimentos da pecuaria,
-- 2.245 despesas + 5 receitas da cana = 2.759 linhas, R$ 10.226.028,01.
-- Se voce lancou coisa nova depois, os numeros sobem - o que nao pode e
-- descer.
dinheiro as (
  select
    '01 lancamentos' as item,
    (select count(*)::text from lancamentos_financeiros) || ' linhas, R$ ' ||
    to_char((select coalesce(sum(valor),0) from lancamentos_financeiros), 'FM999G999G999D00') as valor,
    case when (select count(*) from lancamentos_financeiros) >= 2759
          and (select coalesce(sum(valor),0) from lancamentos_financeiros) >= 10226028.01
         then 'OK' else '*** MENOS QUE O MIGRADO ***' end as situacao
),

-- ---------- 2) CENTROS DE CUSTO ----------
centros as (
  select '02 centros de custo' as item,
    (select count(*)::text from centros_custo) || ' centros' as valor,
    case when (select count(*) from centros_custo where fazenda_id is not null) > 0
           then '*** AINDA TEM CENTRO PRESO A FAZENDA ***'
         when (select count(*) from (select 1 from centros_custo
                 group by lower(btrim(nome)) having count(*)>1) x) > 0
           then '*** AINDA TEM NOME REPETIDO ***'
         when not exists (select 1 from pg_indexes
                 where schemaname='public' and indexname='uq_centro_custo_nome')
           then '*** FALTA O INDICE QUE IMPEDE REPETIR ***'
         else 'OK' end as situacao
),

-- ---------- 3) LANCAMENTO ORFAO ----------
orfaos as (
  select '03 lancamento sem centro' as item,
    (select count(*)::text from lancamentos_financeiros l
      where not exists (select 1 from centros_custo c where c.id = l.centro_custo_id)) || ' orfaos' as valor,
    case when exists (select 1 from lancamentos_financeiros l
                      where not exists (select 1 from centros_custo c where c.id = l.centro_custo_id))
         then '*** TEM ORFAO ***' else 'OK' end as situacao
),

-- ---------- 4) MES FORA DE FORMATO ----------
-- Lancamento com mes tipo '2025-7' existe na tabela e some de todo
-- relatorio. Tem que ser zero, e a trava tem que existir.
mes_ok as (
  select '04 formato do mes' as item,
    (select count(*)::text from lancamentos_financeiros
      where mes is not null and mes !~ '^\d{4}-(0[1-9]|1[0-2])$') || ' fora de formato' as valor,
    case when exists (select 1 from lancamentos_financeiros
                      where mes is not null and mes !~ '^\d{4}-(0[1-9]|1[0-2])$')
           then '*** TEM MES INVALIDO ***'
         when not exists (select 1 from pg_constraint
                 where conrelid='lancamentos_financeiros'::regclass and conname='mes_formato_valido')
           then '*** FALTA A TRAVA DE FORMATO ***'
         else 'OK' end as situacao
),

-- ---------- 5) PECUARIA LIMITADA A PECUARIA ----------
-- As politicas que citam pec_ tem que citar tambem atividade pecuaria.
escopo as (
  select '05 escopo da pecuaria' as item,
    (select count(*)::text from pg_policies
      where schemaname='public' and tablename='lancamentos_financeiros') || ' politicas' as valor,
    case when exists (
           select 1 from pg_policies
           where schemaname='public' and tablename='lancamentos_financeiros'
             and coalesce(qual,'')||coalesce(with_check,'') like '%pec\_%'
             and coalesce(qual,'')||coalesce(with_check,'') not like '%pecuaria%')
         then '*** PEC SEM LIMITE DE ATIVIDADE ***'
         when not exists (
           select 1 from pg_policies
           where schemaname='public' and tablename='lancamentos_financeiros'
             and coalesce(qual,'')||coalesce(with_check,'') like '%pec\_%')
         then '*** PECUARIA SEM ACESSO NENHUM ***'
         else 'OK' end as situacao
),

-- ---------- 6) TABELA ABERTA PARA QUALQUER UM ----------
-- Tabela sem RLS no schema public e lida e gravada com a chave publica,
-- que esta a vista no codigo-fonte das paginas.
abertas as (
  select '06 tabela sem RLS' as item,
    coalesce((select string_agg(c.relname, ', ' order by c.relname)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind='r' and not c.relrowsecurity), 'nenhuma') as valor,
    case when exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                      where n.nspname='public' and c.relkind='r' and not c.relrowsecurity)
         then '*** TEM TABELA ABERTA ***' else 'OK' end as situacao
),

-- ---------- 7) POLITICA SEM CONDICAO ----------
-- Varredura mais ampla que a da limpeza antiga: olha tambem os PAPEIS da
-- politica e o with_check, que e onde mora a permissao de escrita.
frouxas as (
  select '07 politica sem condicao' as item,
    coalesce((select string_agg(tablename||'.'||policyname, ', ' order by tablename)
      from pg_policies where schemaname='public'
        and ( 'anon' = any(roles)
           or btrim(coalesce(qual,''))       in ('true','(true)')
           or btrim(coalesce(with_check,'')) in ('true','(true)') )), 'nenhuma') as valor,
    case when exists (select 1 from pg_policies where schemaname='public'
            and ( 'anon' = any(roles)
               or btrim(coalesce(qual,''))       in ('true','(true)')
               or btrim(coalesce(with_check,'')) in ('true','(true)') ))
         then '*** TEM POLITICA ABERTA ***' else 'OK' end as situacao
),

-- ---------- 8) PROPRIETARIO COM ACESSO TOTAL ----------
acesso as (
  select '08 acesso do proprietario' as item,
    (select count(*)::text from profiles where ativo and papel='proprietario') || ' proprietarios' as valor,
    case when not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='acesso_total')
           then '*** FALTA acesso_total() ***'
         when not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='tem_permissao'
                            and p.prosrc like '%acesso_total%')
           then '*** tem_permissao AINDA USA is_admin ***'
         else 'OK' end as situacao
),

-- ---------- 9) INDICES ----------
indices as (
  select '09 indices do financeiro' as item,
    (select count(*)::text from pg_indexes
      where schemaname='public' and tablename='lancamentos_financeiros') || ' indices' as valor,
    case when not exists (select 1 from pg_indexes where schemaname='public'
            and tablename='lancamentos_financeiros' and indexname='idx_lanc_fin_centro')
         then '*** FALTA INDICE NO CENTRO DE CUSTO ***' else 'OK' end as situacao
),

-- ---------- 10) RECEITA DE LAVOURA NO MODELO UNICO ----------
receitas as (
  select '10 receita de lavoura' as item,
    'R$ ' || to_char((select coalesce(sum(valor),0) from lancamentos_financeiros
                      where tipo='receita' and atividade in ('cana','graos')), 'FM999G999G999D00') as valor,
    case when (select coalesce(sum(valor),0) from lancamentos_financeiros
               where tipo='receita' and atividade='cana') >= 2587195.27
         then 'OK' else '*** RECEITA DE CANA FALTANDO ***' end as situacao
)

select item, valor, situacao from (
  select * from dinheiro union all select * from centros  union all
  select * from orfaos   union all select * from mes_ok   union all
  select * from escopo   union all select * from abertas  union all
  select * from frouxas  union all select * from acesso   union all
  select * from indices  union all select * from receitas
) tudo
order by item;
