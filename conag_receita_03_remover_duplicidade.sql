-- ============================================================
-- PARTE 3 - APAGA A RECEITA DUPLICADA DE CANA/PECUARIA EM 2026
--
-- AVISO: o Eduardo resolveu essa duplicidade manualmente antes deste
-- arquivo ser rodado. NAO COLAR sem antes conferir o estado atual do
-- banco - rodar de novo por cima de uma correcao manual ja feita pode
-- apagar algo que nao devia. Fica de referencia, nao como script pronto.
--
-- SO COLE DEPOIS de ver o conag_receita_02_preview_duplicidade.sql e
-- conferir que a linha 1 deu 5 titulos / R$ 2.587.195,27 (Cana) e a
-- linha 2 deu 10 titulos / R$ 1.021.117,93 (Pecuaria mar/mai/jun/ago).
--
-- O QUE FAZ: apaga so a receita que veio do Conag (conag_id preenchido)
-- para Cana inteira em 2026 e para Pecuaria nos meses onde a duplicidade
-- bate exato (mar/mai/jun/ago). NAO toca na receita lancada a mao, nem em
-- Graos, nem em Pecuaria de jan/fev/jul (jul fica de fora de proposito -
-- a soma nao bate exato com o que ja existia, entao pode ter venda nova
-- misturada com duplicada; decide com mais calma depois).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

delete from lancamentos_financeiros
where atividade='cana' and tipo='receita' and conag_id is not null and mes like '2026%';

delete from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null
  and mes in ('2026-03','2026-05','2026-06','2026-08');

select 1::numeric as ordem, 'CANA: receita do Conag restante em 2026 (deve ser zero)' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
from lancamentos_financeiros
where atividade='cana' and tipo='receita' and conag_id is not null and mes like '2026%'
union all
select 2, 'PECUARIA: receita do Conag restante em mar/mai/jun/ago 2026 (deve ser zero)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null
  and mes in ('2026-03','2026-05','2026-06','2026-08')
union all
select 3, 'CANA: receita 2026 total (so a lancada a mao, agora unica)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='cana' and tipo='receita' and mes like '2026%'
union all
select 4, 'PECUARIA: receita 2026 total (a mao + jan/fev/jul do Conag)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and mes like '2026%'
order by ordem;

-- Depois disso, feche e abra o app de novo e confere Resultados > Cana
-- pro Ano 2026 - a receita deve ter caido pela metade do que estava.
