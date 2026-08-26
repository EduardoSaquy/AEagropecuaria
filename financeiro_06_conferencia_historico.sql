-- ============================================================
-- CONFERENCIA MES A MES DE TODO O HISTORICO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Nao altera nada: so compara e mostra.
--
-- ------------------------------------------------------------
-- POR QUE
--
-- A conferencia anterior olhou so o mes atual. A migracao cobre anos de
-- historico, e os dois erros que ja apareceram (nome colado com descricao,
-- e mes derivado da data) afetavam justamente os lancamentos antigos. Uma
-- diferenca em 2024 so seria notada quando alguem fosse olhar 2024.
--
-- Este script repete a regra do app (agrupa por nome + centro de custo +
-- atividades; dentro do grupo o lancamento do mes substitui o recorrente)
-- em TODOS os meses, nas duas tabelas, e mostra onde diverge.
--
-- COMO LER O RESULTADO
--
-- A primeira consulta lista SO os meses com diferenca. O ideal e ela voltar
-- vazia. A segunda mostra os totais gerais, para uma conferencia de conjunto.
-- ============================================================

-- ------------------------------------------------------------
-- 0) TRAVA DE PROJETO
-- ------------------------------------------------------------
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

-- ------------------------------------------------------------
-- 1) DESPESAS DA PECUARIA, MES A MES
--    Volta vazio = tudo confere.
-- ------------------------------------------------------------
with meses as (
  select distinct mes as m from custos_fixos where mes is not null
  union
  select distinct mes from lancamentos_financeiros
    where tipo = 'despesa' and atividade = 'pecuaria' and mes is not null
),
antigo as (
  select
    cf.nome || '||' || coalesce(cf.categoria, '') || '||'
      || array_to_string(array(select unnest(coalesce(cf.areas, '{}')) order by 1), ',') as chave,
    cf.mes, cf.valor_mensal
  from custos_fixos cf
  where coalesce(cf.valor_mensal, 0) > 0
),
novo as (
  select
    l.descricao || '||' || coalesce(c.nome, '') || '||'
      || array_to_string(array(select unnest(coalesce(l.areas, '{}')) order by 1), ',') as chave,
    l.mes, l.valor
  from lancamentos_financeiros l
  join centros_custo c on c.id = l.centro_custo_id
  where l.tipo = 'despesa' and l.atividade = 'pecuaria'
),
por_mes as (
  select
    t.m as mes,
    (select coalesce(sum(a.valor_mensal), 0) from antigo a
      where a.mes = t.m
         or (a.mes is null and not exists (
               select 1 from antigo b where b.chave = a.chave and b.mes = t.m))) as total_antes,
    (select coalesce(sum(n.valor), 0) from novo n
      where n.mes = t.m
         or (n.mes is null and not exists (
               select 1 from novo b where b.chave = n.chave and b.mes = t.m))) as total_agora
  from meses t
)
select mes, total_antes, total_agora,
       round(total_agora - total_antes, 2) as diferenca
from por_mes
where total_antes <> total_agora
order by mes;


-- ------------------------------------------------------------
-- 2) TOTAIS GERAIS DE CADA ORIGEM
--    A coluna confere tem que dar OK em todas as linhas.
-- ------------------------------------------------------------
select 'despesas pecuaria' as origem,
       (select count(*) from custos_fixos where coalesce(valor_mensal,0) > 0) as linhas_antes,
       (select count(*) from lancamentos_financeiros where tipo='despesa' and atividade='pecuaria') as linhas_agora,
       (select coalesce(sum(valor_mensal),0) from custos_fixos where coalesce(valor_mensal,0) > 0) as total_antes,
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='pecuaria') as total_agora,
       case when (select coalesce(sum(valor_mensal),0) from custos_fixos where coalesce(valor_mensal,0) > 0)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='pecuaria')
            then 'OK' else '*** DIFERENTE ***' end as confere
union all
select 'receitas pecuaria',
       (select count(*) from receitas where coalesce(valor,0) > 0 and data is not null),
       (select count(*) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria'),
       (select coalesce(sum(valor),0) from receitas where coalesce(valor,0) > 0 and data is not null),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria'),
       case when (select coalesce(sum(valor),0) from receitas where coalesce(valor,0) > 0 and data is not null)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria')
            then 'OK' else '*** DIFERENTE ***' end
union all
select 'investimentos',
       (select count(*) from investimentos where coalesce(valor,0) > 0 and data is not null),
       (select count(*) from lancamentos_financeiros where tipo='investimento'),
       (select coalesce(sum(valor),0) from investimentos where coalesce(valor,0) > 0 and data is not null),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='investimento'),
       case when (select coalesce(sum(valor),0) from investimentos where coalesce(valor,0) > 0 and data is not null)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='investimento')
            then 'OK' else '*** DIFERENTE ***' end
union all
select 'despesas cana',
       (select count(*) from despesas_cana where coalesce(valor,0) > 0),
       (select count(*) from lancamentos_financeiros where tipo='despesa' and atividade='cana'),
       (select coalesce(sum(valor),0) from despesas_cana where coalesce(valor,0) > 0),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='cana'),
       case when (select coalesce(sum(valor),0) from despesas_cana where coalesce(valor,0) > 0)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='cana')
            then 'OK' else '*** DIFERENTE ***' end;


-- ------------------------------------------------------------
-- 3) O QUE FICOU SEM CLASSIFICACAO
--    Nao e erro, e uma lista de pendencias: lancamentos que entraram sem
--    centro de custo definido na origem. Vale revisar com calma na tela.
-- ------------------------------------------------------------
select c.nome as centro_de_custo, count(*) as lancamentos, sum(l.valor) as total
from lancamentos_financeiros l
join centros_custo c on c.id = l.centro_custo_id
where c.nome = 'Nao classificado'
group by c.nome;
