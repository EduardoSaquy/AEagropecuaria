-- ============================================================
-- APAGA A RECEITA DUPLICADA DA PECUARIA EM MAR/MAI/JUN/AGO 2026
--
-- Substitui o conag_receita_03_remover_duplicidade.sql antigo, que
-- tambem apagava a Cana - NAO USE mais aquele arquivo: hoje a Cana em
-- 2026 so tem a versao do Conag sobrando (a lancada a mao ja foi
-- apagada por voce, manualmente), entao rodar aquele delete de novo
-- apagaria a receita inteira da Cana por engano. Este arquivo aqui so
-- mexe em Pecuaria.
--
-- CONFERIDO CONTRA O BANCO HOJE (29/08/2026): os 10 titulos / R$
-- 1.021.117,93 do Conag em mar/mai/jun/ago 2026 continuam la - a
-- duplicidade que voce resolveu manualmente foi so a da Cana, a da
-- Pecuaria ainda nao foi. Por isso a receita da Pecuaria em 2026
-- aparece hoje R$ 1.021.117,93 mais alta do que deveria.
--
-- O QUE FAZ: apaga so a receita da Pecuaria que veio do Conag
-- (conag_id preenchido) nos meses onde a duplicidade bate exato
-- (mar/mai/jun/ago). NAO toca em Cana, Graos, nem em receita lancada a
-- mao, nem em Pecuaria de jan/fev (venda nova, sem duplicidade) ou
-- julho (soma nao bate exato - decidir com mais calma depois, como já
-- estava documentado).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

delete from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null
  and mes in ('2026-03','2026-05','2026-06','2026-08');

select 1::numeric as ordem, 'PECUARIA: receita do Conag restante em mar/mai/jun/ago 2026 (deve ser zero)' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='receita' and conag_id is not null
   and mes in ('2026-03','2026-05','2026-06','2026-08')
union all
select 2, 'PECUARIA: receita 2026 total depois da limpeza (esperado: R$ 3.378.658,50)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='receita' and mes like '2026%'
union all
select 3, 'CANA: receita 2026 total (referencia - NAO mexe, so conferir que ficou igual)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='cana' and tipo='receita' and mes like '2026%'
order by ordem;

-- Depois disso, feche e abra o app de novo e confere Resultados > Pecuaria
-- pro Ano 2026 - a receita deve cair de R$ 4.399.776,43 pra R$ 3.378.658,50.
