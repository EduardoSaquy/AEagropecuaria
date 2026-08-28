-- ============================================================
-- PARTE 5 (so leitura) - PREVIEW DA DUPLICIDADE CANA/PECUARIA 2026
--
-- NAO APAGA NADA. So mostra o que a parte 6 vai apagar, pra voce
-- conferir os numeros antes.
--
-- O QUE ACONTECEU:
--
-- Cana e Pecuaria comecaram a ser lancadas A MAO no AE Matriz em
-- janeiro/2026 (a Cana nem existia antes disso no app - o LEIA-ME do
-- Conag ja registrava isso: "a migracao trouxe so o recente, pecuaria de
-- 2024, cana de 2026"). A importacao do Conag cobre ate agosto/2026, sem
-- excluir esse periodo - entao de jan/2026 em diante, a MESMA despesa
-- real ficou lancada duas vezes: uma vez a mao, outra vez pelo Conag.
--
-- Confirmado mes a mes: os dois lados aparecem juntos, em valores parecidos,
-- exatamente de jan/2026 a ago/2026 (antes disso, so o Conag; depois, so a
-- mao). Graos nao tem esse problema - nunca teve lancamento a mao.
--
-- A DECISAO (sua, ja confirmada): fica a lancada a mao (e o registro
-- nativo do time), sai a do Conag, so nesse periodo de sobreposicao.
-- Investimento fica de fora por enquanto - a sobreposicao la e pequena e
-- mais espalhada, decide depois com calma.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'Vai ser apagado: CANA, despesa do Conag, jan/2026 em diante' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
from lancamentos_financeiros
where atividade='cana' and tipo='despesa' and conag_id is not null and mes >= '2026-01'
union all
select 2, 'Vai ser apagado: PECUARIA, despesa do Conag, jan/2026 em diante',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='pecuaria' and tipo='despesa' and conag_id is not null and mes >= '2026-01'
union all
select 3, 'NAO mexe: CANA/PECUARIA, despesa do Conag, ate dez/2025 (historico, sem sobreposicao)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade in ('cana','pecuaria') and tipo='despesa' and conag_id is not null and mes < '2026-01'
union all
select 4, 'NAO mexe: CANA/PECUARIA, lancado a mao (fica, e o que conta a partir de agora)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade in ('cana','pecuaria') and tipo='despesa' and conag_id is null
union all
select 5, 'NAO mexe: GRAOS do Conag (sem duplicidade - zero lancamento a mao)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade='graos' and tipo='despesa' and conag_id is not null
union all
select 6, 'NAO mexe: Investimento de Cana/Pecuaria (fica pra depois)',
       count(*)::text, round(sum(valor),2)::text
from lancamentos_financeiros
where atividade in ('cana','pecuaria') and tipo='investimento' and conag_id is not null
order by ordem;

-- Se as linhas 1 e 2 baterem com o que eu te mandei (Cana ~R$ 2.514.881,25
-- em 467 titulos; Pecuaria ~R$ 1.022.327,73 em 436 titulos), pode colar o
-- conag_dashboard_6_remover_duplicidade.sql em seguida.
