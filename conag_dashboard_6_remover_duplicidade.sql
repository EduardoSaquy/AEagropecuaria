-- ============================================================
-- PARTE 6 - APAGA A DESPESA DUPLICADA DE CANA/PECUARIA (jan/2026 em diante)
--
-- SO COLE ISTO DEPOIS de ter visto o resultado do
-- conag_dashboard_5_preview_duplicidade.sql e conferido que os numeros
-- batem com o esperado (Cana ~R$ 2.514.881,25 em 467 titulos; Pecuaria
-- ~R$ 1.022.327,73 em 436 titulos).
--
-- O QUE FAZ: apaga so os lancamentos de despesa que vieram do Conag
-- (conag_id preenchido) para Cana e Pecuaria, a partir de janeiro/2026 -
-- o periodo em que o time ja lancava a mesma despesa a mao no app. NAO
-- toca em nada lancado a mao, nem em Graos, nem em historico anterior a
-- 2026, nem em receita, nem em investimento.
--
-- Se um desses lancamentos tivesse caido em lancamento_rateios por algum
-- motivo (nao deveria - rateio e so pra atividade='geral'), o delete em
-- cascata (on delete cascade) limpa junto sozinho.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

delete from lancamentos_financeiros
where atividade in ('cana','pecuaria')
  and tipo = 'despesa'
  and conag_id is not null
  and mes >= '2026-01';

select 1::numeric as ordem, 'CANA: despesa restante do Conag (deve ser so historico, ate dez/2025)' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
from lancamentos_financeiros
where atividade='cana' and tipo='despesa' and conag_id is not null
union all
select 2, 'PECUARIA: despesa restante do Conag (deve ser so historico, ate dez/2025)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='despesa' and conag_id is not null
union all
select 3, 'CANA: despesa lancada a mao (nao mudou)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='cana' and tipo='despesa' and conag_id is null
union all
select 4, 'PECUARIA: despesa lancada a mao (nao mudou)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='despesa' and conag_id is null
union all
select 5, 'GRAOS: despesa do Conag (nao mudou - nunca teve duplicidade)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='graos' and tipo='despesa' and conag_id is not null
order by ordem;

-- Depois disso, feche e abra o app de novo (o service worker cacheia) e
-- confere Resultados > Cana e Resultados > Pecuaria contra o Conag outra
-- vez.
