-- ============================================================
-- PARTE 2 (so leitura) - PREVIEW DA DUPLICIDADE DE RECEITA 2026
--
-- AVISO: o Eduardo resolveu essa duplicidade manualmente antes deste
-- arquivo ser rodado ou conferido contra o banco real. NAO RODAR sem
-- antes conferir o estado atual (pode nao bater mais com os numeros
-- abaixo, ou nao ter mais nada pra apagar). Fica de referencia do
-- diagnostico que levou a duplicidade, nao como script pronto pra colar.
--
-- NAO APAGA NADA. So mostra o que a parte 3 vai apagar.
--
-- O QUE ACONTECEU: a planilha do Conag que importei tem receita de 2026
-- que e a MESMA venda que voce ja tinha lancado a mao no app (mesmo mes,
-- mesmo valor, centavo a centavo) - identico ao que ja tinha acontecido
-- com a despesa hoje mais cedo. A Cana esta 100% duplicada em 2026 (as 5
-- vendas do ano inteiro). A Pecuaria esta duplicada em parte: marco, maio,
-- junho e agosto batem exato; janeiro e fevereiro sao venda nova, sem
-- duplicidade; julho fica de fora por enquanto porque a soma nao bate
-- exata (pode ser duplicidade parcial - precisa olhar com mais calma).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'Vai ser apagado: CANA, receita do Conag em 2026 (100% duplicada)' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
from lancamentos_financeiros
where atividade='cana' and tipo='receita' and conag_id is not null and mes like '2026%'
union all
select 2, 'Vai ser apagado: PECUARIA, receita do Conag em mar/mai/jun/ago 2026 (duplicada)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null
  and mes in ('2026-03','2026-05','2026-06','2026-08')
union all
select 3, 'NAO mexe ainda: PECUARIA, receita do Conag em julho/2026 (soma nao bate exato - investigar depois)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null and mes = '2026-07'
union all
select 4, 'NAO mexe: PECUARIA, receita do Conag em jan/fev 2026 (venda nova, sem duplicidade)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='receita' and conag_id is not null and mes in ('2026-01','2026-02')
union all
select 5, 'NAO mexe: receita lancada a mao (fica, e o que conta a partir de agora)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade in ('cana','pecuaria') and tipo='receita' and conag_id is null
order by ordem;

-- Se a linha 1 vier 5 titulos / R$ 2.587.195,27 e a linha 2 vier 10
-- titulos / R$ 1.021.117,93, pode colar o conag_receita_03_remover_duplicidade.sql.
