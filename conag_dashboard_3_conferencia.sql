-- ============================================================
-- IMPORTACAO DO CONAG - PARTE 3 de 3, A CONFERENCIA (cole por ultimo)
--
-- Vai imprimir 14 linhas. As QUATRO que decidem se deu certo:
--
--   linha 3  (A view devolve o mesmo dinheiro?)     precisa dizer
--            "SIM - bate com a linha 2"
--   linha 4  (Titulo cujo rateio nao fecha)          precisa dizer
--            "nenhum - todos fecham"
--   linha 12 (Lancamentos NOSSOS, anteriores)        precisa ser 2760
--            (ou 2761, se o lancamento de teste id 3234 ainda existir)
--   linha 13 (Valor NOSSO, anterior)                 precisa ser
--            10447812.29 (ou 10453612.29)
--
-- Se qualquer uma dessas quatro vier diferente do esperado, PARE e me
-- manda o resultado inteiro (print da tela serve) — nao tenta consertar
-- por conta.
-- ============================================================

select 1::numeric as ordem, 'Titulos do Conag importados' as item,
       count(*)::text as valor, 'esperado: 9.400' as situacao
from lancamentos_financeiros where conag_id is not null
union all
select 2, 'Valor importado', round(sum(valor),2)::text, 'esperado: 62.609.569,50'
from lancamentos_financeiros where conag_id is not null
union all
select 3, 'A view devolve o mesmo dinheiro?',
       round(sum(valor),2)::text,
       case when round(sum(valor),2) = (select round(sum(valor),2)
                                          from lancamentos_financeiros
                                         where conag_id is not null)
            then 'SIM - bate com a linha 2'
            else 'NAO - PARE E ME AVISE' end
from lancamentos_rateados where conag_id is not null
union all
select 4, 'Titulo cujo rateio nao fecha',
       count(*)::text,
       case when count(*) = 0 then 'nenhum - todos fecham'
            else 'PARE E ME AVISE' end
from (select r.lancamento_id
        from lancamento_rateios r
        join lancamentos_financeiros l on l.id = r.lancamento_id
       group by r.lancamento_id, l.valor
      having round(sum(r.valor),2) <> round(l.valor,2)) x
union all
select 5, 'Titulos com atividade propria (sem rateio)', count(*)::text, 'esperado: 5.952'
from lancamentos_financeiros
where conag_id is not null and atividade <> 'geral'
union all
select 6, 'Rateados: geral de fazenda', count(distinct lancamento_id)::text, 'esperado: 791'
from lancamento_rateios where origem = 'geral da fazenda'
union all
select 7, 'Rateados: administrativo', count(distinct lancamento_id)::text,
       'esperado: 2.576 - veja a linha 8'
from lancamento_rateios where origem = 'administrativo'
union all
select 8, 'Nao rateados por serem centavo ou zero', count(*)::text,
       'esperado: 81, somando R$ 0,09'
from lancamentos_financeiros l
where l.conag_id is not null and l.atividade = 'geral'
  and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)
union all
select 9, 'Contas do Conag que existem como centro', count(*)::text,
       'esperado: 85 - as do CSV'
from (select distinct plano_norm(centro_custo) n from conag_staging) s
where exists (select 1 from centros_custo c where plano_norm(c.nome) = s.n)
union all
select 10, 'Titulos com cultura', count(*)::text, 'esperado: 1.872'
from lancamentos_financeiros where conag_id is not null and cultura_id is not null
union all
select 11, 'Titulos sem centro de custo', count(*)::text,
       case when count(*) = 0 then 'nenhum ficou de fora' else 'PARE E ME AVISE' end
from conag_staging s
where not exists (select 1 from lancamentos_financeiros l where l.conag_id = s.conag_id)
union all
select 11.5, 'Titulos com vencimento em outro mes', count(*)::text,
       'esperado: 4.836 - nota a prazo, data fica nula'
from lancamentos_financeiros
where conag_id is not null and vencimento is not null
  and to_char(vencimento,'YYYY-MM') <> mes
union all
select 12, 'Lancamentos NOSSOS, anteriores', count(*)::text, 'NAO pode ter mudado'
from lancamentos_financeiros where conag_id is null
union all
select 13, 'Valor NOSSO, anterior', round(sum(valor),2)::text, 'NAO pode ter mudado'
from lancamentos_financeiros where conag_id is null
order by ordem;
