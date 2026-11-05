-- ============================================================
-- CONFERENCIA (SO LEITURA): os lancamentos que precisam de rateio, por conta,
-- com o funcionario cadastrado que bate com o nome e a alocacao dele
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- PARA QUE SERVE
-- Os 604 lancamentos do ERP (atividade geral) cujo rateio nao fecha o valor
-- (rateio_02_diagnostico.sql) vao ser divididos em partes iguais entre as tres
-- atividades, EXCETO o salario de quem tem alocacao cadastrada na aba Funcionarios
-- (funcionario_atividades: % de cada atividade): esse segue a alocacao da pessoa.
-- A lista mostra os 604 agrupados por centro de custo e fornecedor, do maior valor
-- para o menor, e para cada grupo o funcionario que tem o mesmo nome ("igual") ou
-- nome parecido (dois nomes em comum, "parecido") e a alocacao dele.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.funcionarios') is null or to_regclass('public.funcionario_atividades') is null then
    raise exception 'Faltam as tabelas funcionarios/funcionario_atividades.';
  end if;
end
$trava$;

with
conj as (
  select l.id, l.valor, l.mes, l.fazenda_id,
         coalesce(cc.nome, '(sem centro de custo)') as centro_de_custo,
         coalesce(nullif(btrim(l.fornecedor), ''), nullif(btrim(l.descricao), ''), '(sem nome)') as fornecedor
    from lancamentos_financeiros l
    join (select lancamento_id, sum(valor) as soma
            from lancamento_rateios group by lancamento_id) p on p.lancamento_id = l.id
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.atividade = 'geral' and l.erp_id is not null and l.valor > 0
     and abs(l.valor - p.soma) > 0.05
),
grupos as (
  select centro_de_custo, fornecedor,
         regexp_replace(translate(upper(fornecedor),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g') as nome_norm,
         count(*) as lancamentos,
         sum(valor) as valor_total,
         min(mes) as de, max(mes) as ate,
         bool_or(fazenda_id is not null) as tem_fazenda,
         row_number() over (order by sum(valor) desc, centro_de_custo, fornecedor) as posicao
    from conj
   group by centro_de_custo, fornecedor
),
func as (
  select f.id, f.nome, f.ativo,
         regexp_replace(translate(upper(f.nome),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g') as nome_norm,
         coalesce((select string_agg(fa.atividade || ' ' || coalesce(fa.percentual, 0)::text || '%', ' / ' order by fa.atividade)
                     from funcionario_atividades fa
                    where fa.funcionario_id = f.id and coalesce(fa.percentual, 0) > 0),
                  'SEM alocacao cadastrada') as alocacao
    from funcionarios f
),
casados as (
  select g.centro_de_custo, g.fornecedor,
         f.nome as func_nome, f.ativo, f.alocacao,
         case when btrim(regexp_replace(g.nome_norm, '\s+', ' ', 'g'))
                 = btrim(regexp_replace(f.nome_norm, '\s+', ' ', 'g'))
              then 'igual' else 'parecido' end as tipo
    from grupos g
    join func f
      on (select count(*)
            from (select x from unnest(string_to_array(btrim(regexp_replace(g.nome_norm, '\s+', ' ', 'g')), ' ')) as t(x)
                  intersect
                  select y from unnest(string_to_array(btrim(regexp_replace(f.nome_norm, '\s+', ' ', 'g')), ' ')) as u(y)) z
           where length(z.x) >= 3) >= 2
),
saida as (
  select 1 as ord, g.posicao as sub, g.centro_de_custo, g.fornecedor, g.lancamentos,
         round(g.valor_total, 2) as valor_total, g.de || ' a ' || g.ate as meses,
         case when g.tem_fazenda then 'sim' else 'nao' end as de_uma_fazenda,
         coalesce((select string_agg(c.tipo || ': ' || c.func_nome
                                     || case when c.ativo then '' else ' (inativo)' end
                                     || ' = ' || c.alocacao, ' ; ' order by c.tipo, c.func_nome)
                     from casados c
                    where c.centro_de_custo = g.centro_de_custo and c.fornecedor = g.fornecedor), '') as funcionario
    from grupos g
   where g.posicao <= 60
  union all
  select 2, 0, 'TODOS OS OUTROS GRUPOS', count(*)::text || ' grupos', coalesce(sum(lancamentos), 0),
         round(coalesce(sum(valor_total), 0), 2), '', '', ''
    from grupos
   where posicao > 60
  union all
  select 3, 0, 'TOTAL DOS LANCAMENTOS A CORRIGIR', '', count(*),
         round(coalesce(sum(valor), 0), 2), '', '', ''
    from conj
)
select centro_de_custo, fornecedor, lancamentos, valor_total, meses, de_uma_fazenda, funcionario
  from saida
 order by ord, sub;
