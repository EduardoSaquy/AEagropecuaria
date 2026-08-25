-- ============================================================
-- EXCLUIR PASSA A SER SO DE ADMIN OU PROPRIETARIO
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- ------------------------------------------------------------
-- O QUE MUDA
--
-- Hoje quem tem 'editar' num modulo tambem APAGA nele. Quem lanca uma
-- pesagem pode apagar um lote; quem lanca despesa pode apagar lancamento.
-- A partir daqui, apagar e so de admin ou proprietario, no banco - nao so
-- na tela.
--
-- ------------------------------------------------------------
-- O QUE NAO MUDA, E POR QUE
--
-- Dez tabelas ficam como estao. Nelas o app apaga POR CONTA PROPRIA,
-- dentro de outra operacao, e restringir quebraria rotina de quem nao e
-- dono - calado, que e o pior jeito:
--
--   movimentos                 refeitos ao editar saida de racao e pasto.
--                              Sem apagar, os antigos ficam e os novos
--                              entram: o estoque desconta duas vezes.
--   pesagens_animais           desfazer um manejo que falhou no meio
--   reproducao_custos          idem
--   diagnosticos_gestacionais  idem
--   protocolos_inseminacao     idem
--   desmamas                   idem
--   pesagens                   desfazer pesagem que ficou sem detalhe
--   abates                     desfazer venda que ficou pela metade
--   producoes_racao            desfazer producao sem baixa de estoque
--   titulo_rateios             trocados ao editar o titulo
--
-- Quem faz manejo e lanca pasto e justamente quem NAO e dono.
--
-- Nessas dez, esconder o botao na tela e so tela: quem soubesse chamar a
-- API ainda apagaria. Fechar de verdade exige mover essas rotinas para
-- funcoes no banco. Fica anotado, nao e agora.
--
-- ------------------------------------------------------------
-- E O PROPRIETARIO, QUE ESTAVA DE FORA
--
-- Oito tabelas usam is_admin(), que so reconhece papel = 'admin'. A Alice,
-- a Marcia e o Paulo sao 'proprietario' e nao passam - mesmo os apps
-- tratando proprietario como acesso total. Esta divergencia entre app e
-- banco e corrigida aqui junto.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
  if not exists (select 1 from pg_proc where proname = 'pode_excluir') then
    raise exception 'pode_excluir() nao existe - rode o contas_01_estrutura primeiro';
  end if;
end $$;


-- ------------------------------------------------------------
-- APLICA
-- ------------------------------------------------------------
do $$
declare
  alvo text;
  pol  text;
  -- Tudo que e decisao de gente clicar em Excluir. As dez da maquinaria
  -- ficam de fora de proposito, e profiles tambem: apagar conta de acesso
  -- e outra natureza de decisao e continua so do admin.
  alvos text[] := array[
    'animais','aplicacoes_cana','aplicacoes_graos','centros_custo',
    'colheitas_cana','colheitas_graos','config_fazenda','config_financeiro',
    'contas_bancarias','culturas','custos_fixos','despesas_cana','despesas_graos',
    'dietas','entidades','entradas_insumo_cana','entradas_insumo_graos',
    'fazendas','fazenda_atividades','funcionarios','funcionario_atividades',
    'ingredientes','insumos_cana','insumos_graos','investimentos',
    'lancamentos_financeiros','leituras_cocho','lotes','manejos','partos',
    'pasto','plantios_cana','plantios_graos','precos_arroba','receitas',
    'receitas_cana','receitas_graos','safras','saidas_racao','talhoes_areas',
    'titulo_baixas','titulos'
  ];
begin
  foreach alvo in array alvos loop
    if not exists (select 1 from information_schema.tables
                   where table_schema='public' and table_name=alvo) then
      raise notice 'tabela % nao existe neste banco, pulando', alvo;
      continue;
    end if;
    -- apaga QUALQUER politica de delete que exista, com o nome que tiver
    for pol in select policyname from pg_policies
               where schemaname='public' and tablename=alvo and cmd='DELETE' loop
      execute format('drop policy %I on %I', pol, alvo);
    end loop;
    execute format(
      'create policy "so dono exclui" on %I for delete using (pode_excluir())', alvo);
  end loop;
end $$;


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
-- ------------------------------------------------------------
with maquinaria as (
  select unnest(array['movimentos','pesagens_animais','reproducao_custos',
    'diagnosticos_gestacionais','protocolos_inseminacao','desmamas','pesagens',
    'abates','producoes_racao','titulo_rateios']) as tabela
)
select 1 as ordem, 'Tabelas so para dono' as item,
       count(*)::text as valor,
       case when count(*) >= 40 then 'OK' else 'confira a lista' end as situacao
from pg_policies where schemaname='public' and cmd='DELETE' and qual like '%pode_excluir%'
union all
select 2, 'Maquinaria preservada', count(*)::text,
       case when count(*) = 10 then 'OK - as dez continuam abertas'
            else '*** alguma foi restringida por engano ***' end
from pg_policies p join maquinaria m on m.tabela = p.tablename
where p.schemaname='public' and p.cmd='DELETE' and p.qual not like '%pode_excluir%'
union all
select 3, 'Ainda so admin (proprietario fora)', count(*)::text,
       case when count(*) <= 1 then 'OK - so profiles, de proposito'
            else '*** sobrou tabela com is_admin ***' end
from pg_policies where schemaname='public' and cmd='DELETE'
  and qual like '%is_admin%' and qual not like '%pode_excluir%'
union all
select 4, 'Total de politicas de exclusao', count(*)::text, 'referencia'
from pg_policies where schemaname='public' and cmd='DELETE'
order by ordem;
