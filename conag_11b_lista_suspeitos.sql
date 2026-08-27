-- ============================================================
-- ETAPA 2B: A LISTA DOS SUSPEITOS, UM POR UM
--
-- RODAR depois do conag_11_conferencia. So leitura.
--
-- O 11 diz QUANTOS parecem ja existir. Este diz QUAIS, lado a lado com o
-- lancamento do nosso banco que ele parece ser. E aqui que voce confere se
-- a semelhanca e mesmo duplicata ou se sao dois pagamentos parecidos de
-- verdade - o que acontece com salario, arrendamento e parcela de
-- financiamento, que repetem valor todo mes.
--
-- COMO LER
--   Se o par faz sentido, o lancamento do Conag nao entra e esta certo.
--   Se NAO faz, me avise: significa que a regra de 40 dias esta larga
--   demais e vai barrar coisa que deveria entrar.
-- ============================================================

do $$
begin
  if not exists (select 1 from conag_staging) then
    raise exception 'conag_staging vazia - carregue o CSV antes';
  end if;
end $$;

select
  s.conag_id                                   as id_conag,
  s.vencimento                                 as venc_conag,
  to_char(l.data, 'YYYY-MM-DD')                as data_nossa,
  abs(l.data - nullif(s.vencimento,'')::date)  as dias_de_diferenca,
  round(nullif(s.valor,'')::numeric, 2)        as valor,
  left(s.entidade, 28)                         as fornecedor,
  left(s.centro_custo, 30)                     as conta_conag,
  left(coalesce(l.descricao,''), 30)           as descricao_nossa,
  l.atividade                                  as atividade_nossa,
  s.atividade_conag
from conag_staging s
join lancamentos_financeiros l
  on l.conag_id is null
 and l.valor = nullif(s.valor,'')::numeric
 and norm_txt(l.fornecedor) = norm_txt(s.entidade)
 and norm_txt(s.entidade) <> ''
 and l.data is not null
 and abs(l.data - nullif(s.vencimento,'')::date) <= 40
order by nullif(s.valor,'')::numeric desc
limit 200;
