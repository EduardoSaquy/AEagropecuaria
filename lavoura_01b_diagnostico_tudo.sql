-- ============================================================
-- DIAGNOSTICO COMPLETO EM UMA CONSULTA SO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole tudo, rode uma vez, me mande o resultado inteiro.
-- NAO ALTERA NADA.
--
-- Substitui o lavoura_01_diagnostico.sql (aquele exigia rodar consulta por
-- consulta). Aqui os quatro diagnosticos voltam numa tabela unica, entao o
-- editor do Supabase mostra tudo de uma vez.
--
-- ------------------------------------------------------------
-- COMO LER
--
-- A coluna bloco diz de qual diagnostico e a linha:
--
--   1 POLITICA          politicas de seguranca que citam as permissoes que
--                       eu vou dividir, e que precisam ser reescritas junto
--   2 PERMISSAO         cada chave de permissao em uso, e quantos usuarios
--                       a tem
--   3 RECEITA LAVOURA   se receitas_cana e receitas_graos ja estao no
--                       modelo unico. Espero que NAO estejam
--   4 FAZENDA           se cada fazenda e de uma frente so. A coluna e tem
--                       que dizer 'uma frente so' em todas as linhas
--
-- O significado das colunas a, b, c, d, e muda conforme o bloco. A primeira
-- linha de cada bloco e um cabecalho dizendo o que cada uma quer dizer.
-- ============================================================

with

-- ---------- CABECALHOS ----------
cabecalhos as (
  select 1 as ord, '1 POLITICA'::text as bloco, '-- tabela'::text as a,
         '-- politica'::text as b, '-- comando'::text as c,
         '-- condicao'::text as d, ''::text as e
  union all select 3, '2 PERMISSAO', '-- chave', '-- usuarios', '-- podem editar', '-- so visualizam', ''
  union all select 5, '3 RECEITA LAVOURA', '-- origem', '-- linhas no legado', '-- total no legado', '-- ja no modelo unico', ''
  union all select 7, '4 FAZENDA', '-- fazenda', '-- estado', '-- atividades declaradas', '-- frente dos talhoes', '-- conclusao'
),

-- ---------- 1) POLITICAS QUE CITAM AS PERMISSOES ----------
-- Preciso do texto exato porque o arquivo de schema do repositorio esta
-- desatualizado e ja me induziu ao erro tres vezes nesta migracao.
politicas as (
  select 2 as ord, '1 POLITICA'::text as bloco,
         tablename::text  as a,
         policyname::text as b,
         cmd::text        as c,
         left(coalesce(qual, '') || case when with_check is null then ''
                                         else ' [escrita] ' || with_check end, 220) as d,
         ''::text as e
  from pg_policies
  where schemaname = 'public'
    and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(cadastros|operacoes|financeiro|resultados)'
),

-- ---------- 2) CHAVES DE PERMISSAO EM USO ----------
-- Inventario do que existe de verdade nos usuarios, que pode nao bater com
-- o que os apps oferecem na tela.
perms as (
  select 4 as ord, '2 PERMISSAO'::text as bloco,
         chave::text as a,
         count(*)::text as b,
         count(*) filter (where nivel = 'editar')::text as c,
         count(*) filter (where nivel = 'visualizar')::text as d,
         ''::text as e
  from (
    select p.id, k.chave, p.permissoes ->> k.chave as nivel
    from profiles p
    cross join lateral jsonb_object_keys(coalesce(p.permissoes, '{}'::jsonb)) as k(chave)
  ) t
  group by chave
),

-- ---------- 3) RECEITAS DE LAVOURA NO MODELO UNICO ----------
-- Eu migrei despesas_cana e despesas_graos, mas nao migrei as receitas. Se
-- a coluna d vier zerada e a b maior que zero, esta confirmado: a receita
-- da lavoura so existe na tabela antiga, e tirar a tela de Receita dos apps
-- deixaria ela sem lugar nenhum para ser lancada.
receitas as (
  select 6 as ord, '3 RECEITA LAVOURA'::text as bloco,
         'receitas_cana'::text as a,
         (select count(*) from receitas_cana)::text as b,
         (select coalesce(sum(valor_total), 0) from receitas_cana)::text as c,
         (select count(*) from lancamentos_financeiros
            where tipo = 'receita' and atividade = 'cana')::text as d,
         ''::text as e
  union all
  select 6, '3 RECEITA LAVOURA', 'receitas_graos',
         (select count(*) from receitas_graos)::text,
         (select coalesce(sum(valor_total), 0) from receitas_graos)::text,
         (select count(*) from lancamentos_financeiros
            where tipo = 'receita' and atividade = 'graos')::text,
         ''
),

-- ---------- 4) CADA FAZENDA E DE UMA FRENTE SO? ----------
-- Cruza tres fontes independentes: as atividades declaradas da fazenda, a
-- frente dos talhoes dela (que vem da cultura) e a frente dos lancamentos
-- financeiros. E a unica premissa sua que ainda nao foi confirmada pelo
-- dado, e ela define se o filtro dos apps novos e por fazenda ou por talhao.
ativ as (
  select fazenda_id, string_agg(distinct atividade, ', ' order by atividade) as decl
  from fazenda_atividades where coalesce(area_ha, 0) > 0 group by fazenda_id
),
tal as (
  select t.fazenda_id, string_agg(distinct c.frente, ', ' order by c.frente) as frentes
  from talhoes_areas t join culturas c on c.id = t.cultura_id
  where t.tipo = 'talhao' and t.cultura_id is not null group by t.fazenda_id
),
lan as (
  select fazenda_id, string_agg(distinct atividade, ', ' order by atividade) as frentes
  from lancamentos_financeiros
  where fazenda_id is not null and atividade in ('cana', 'graos') group by fazenda_id
),
fazendas_diag as (
  select 8 as ord, '4 FAZENDA'::text as bloco,
         f.nome::text as a,
         coalesce(f.estado, '-')::text as b,
         coalesce(a2.decl, '-')::text as c,
         (coalesce(t.frentes, '-') || ' / lanc: ' || coalesce(l.frentes, '-'))::text as d,
         case when coalesce(t.frentes, '') like '%,%' or coalesce(l.frentes, '') like '%,%'
              then 'MISTURADA' else 'uma frente so' end::text as e
  from fazendas f
  left join ativ a2 on a2.fazenda_id = f.id
  left join tal  t  on t.fazenda_id  = f.id
  left join lan  l  on l.fazenda_id  = f.id
)

select bloco, a, b, c, d, e
from (
  select * from cabecalhos
  union all select * from politicas
  union all select * from perms
  union all select * from receitas
  union all select * from fazendas_diag
) tudo
order by ord, a;
