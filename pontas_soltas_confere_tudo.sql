-- ============================================================
-- SO LEITURA - confere as pontas soltas que ficaram documentadas no
-- CLAUDE.md mas nunca foram confirmadas contra o banco de verdade.
-- Nao muda nada. Cola tudo de uma vez e roda.
--
-- O QUE CADA BLOCO CONFERE:
--
--   1-2. log_alteracoes: o CLAUDE.md diz "confirme que rodou antes de
--        assumir que existe - nao estava no schema_real.txt de 22/08".
--        Aqui confere se a tabela existe e se os gatilhos estao mesmo
--        ligados nas 4 tabelas que deveriam ter (lancamentos_financeiros,
--        abates, profiles, centros_custo).
--
--   3-6. Receita de Cana/Pecuaria 2026: o Eduardo disse que resolveu a
--        duplicidade manualmente (Conag x lancamento a mao) antes de eu
--        rodar os scripts preparados pra isso. Isso confere o estado
--        atual - se a linha 3 e a 4 vierem 0 (ou baixo), a limpeza
--        pegou; se vier alto, ainda tem duplicidade.
--
--   7-8. Investimento da Pecuaria em 2026: sobreposicao menor (~R$ 463
--        mil) que ficou de fora da limpeza de despesa por decidir com
--        mais calma (documentado no CLAUDE.md). So mostra os dois
--        números lado a lado - nao apaga nada, e so pra decidir se
--        ainda vale a pena mexer.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'tabela log_alteracoes existe' as item,
       case when exists(select 1 from information_schema.tables
                         where table_schema='public' and table_name='log_alteracoes')
            then 'sim' else 'NAO - PARE E ME AVISE' end as valor,
       'esperado: sim' as situacao
union all
select 2, 'gatilho em ' || event_object_table, trigger_name,
       'esperado: 1 gatilho em cada uma de lancamentos_financeiros/abates/profiles/centros_custo'
  from information_schema.triggers
 where trigger_schema='public'
   and event_object_table in ('lancamentos_financeiros','abates','profiles','centros_custo')
union all
select 3, 'CANA: receita do Conag ainda em 2026 (duplicidade que voce apagou manualmente)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='cana' and tipo='receita' and conag_id is not null and mes like '2026%'
union all
select 4, 'PECUARIA: receita do Conag ainda em mar/mai/jun/ago 2026 (idem)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='receita' and conag_id is not null
   and mes in ('2026-03','2026-05','2026-06','2026-08')
union all
select 5, 'CANA: receita 2026 total hoje (referencia)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros where atividade='cana' and tipo='receita' and mes like '2026%'
union all
select 6, 'PECUARIA: receita 2026 total hoje (referencia)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros where atividade='pecuaria' and tipo='receita' and mes like '2026%'
union all
select 7, 'PECUARIA: investimento do Conag em 2026 (candidato a sobreposicao)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='investimento' and conag_id is not null and mes >= '2026-01'
union all
select 8, 'PECUARIA: investimento lancado a mao em 2026 (referencia, nao mexe)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='investimento' and conag_id is null and mes >= '2026-01'
order by ordem;
