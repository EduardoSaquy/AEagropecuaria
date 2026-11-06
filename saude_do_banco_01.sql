-- ============================================================
-- SAUDE DO BANCO (SO LEITURA): procura erros de lancamento e dado estranho
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela: cada linha e uma checagem, com a
-- quantidade achada, o dinheiro envolvido e um "OK" ou "ATENCAO".
-- As linhas AMOSTRA mostram ate 5 exemplos de cada checagem com problema.
--
-- Blocos: A) lancamentos, B) contas a pagar e a receber, C) financiamentos,
-- D) pecuaria (lotes e pesagens), E) cadastros.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with
-- ---------- A) lancamentos ----------
l as (
  select f.id, f.tipo, f.atividade, f.valor, f.data, f.mes, f.vencimento, f.erp_id, f.centro_custo_id,
         coalesce(f.data, f.vencimento) as quando,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(f.fornecedor), ''), f.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm
    from lancamentos_financeiros f
),
a1 as (select id, valor, 'valor zero ou negativo' as motivo from l where valor <= 0),
a2 as (select id, valor, 'data fora de 2020 a 2030' as motivo from l
        where quando is not null and (quando < date '2020-01-01' or quando > date '2030-12-31')),
a3 as (select id, valor, 'despesa/investimento sem centro de custo' as motivo from l
        where centro_custo_id is null and tipo in ('despesa', 'investimento')),
a4 as (select l.id, l.valor, 'despesa em centro de ENTRADA' as motivo
         from l join centros_custo c on c.id = l.centro_custo_id
        where l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada'
       union all
       select l.id, l.valor, 'receita em centro de SAIDA'
         from l join centros_custo c on c.id = l.centro_custo_id
        where l.tipo = 'receita' and c.tipo = 'saida'),
a5 as (select id, valor, 'despesa recorrente (sem data e sem mes: vale em TODO mes)' as motivo from l
        where tipo = 'despesa' and data is null and mes is null),
a6 as (select l.id, l.valor, 'rateio que nao fecha o valor' as motivo
         from l join (select lancamento_id, sum(valor) as s from lancamento_rateios group by lancamento_id) p
           on p.lancamento_id = l.id
        where abs(l.valor - p.s) > 0.05),
a7 as (select id, valor, 'atividade geral SEM partes (fora das 3 atividades)' as motivo from l
        where atividade = 'geral' and abs(valor) >= 1
          and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)),
a8 as (select id, valor, 'mesmo fornecedor, valor e dia repetidos' as motivo
         from (select id, valor, count(*) over (partition by tipo, forn_norm, valor, quando) as n
                 from l where quando is not null and forn_norm <> '' and valor >= 50) x
        where n > 1),
a9 as (select id, valor, 'ERP repetido (mesmo erp_id em mais de uma linha)' as motivo
         from (select id, valor, count(*) over (partition by erp_id) as n from l where erp_id is not null) x
        where n > 1),
-- ---------- B) contas a pagar e a receber ----------
b1 as (select t.id, t.valor, 'titulo sem nenhum rateio' as motivo
         from titulos t
        where coalesce(t.cancelado, false) = false
          and not exists (select 1 from titulo_rateios r where r.titulo_id = t.id)),
b2 as (select t.id, t.valor, 'soma dos rateios diferente do valor do titulo' as motivo
         from titulos t join (select titulo_id, sum(valor) as s from titulo_rateios group by titulo_id) p
           on p.titulo_id = t.id
        where abs(t.valor - p.s) > 0.05),
b3 as (select id, valor, 'baixado mais do que o valor do titulo' as motivo
         from titulos where coalesce(valor_baixado, 0) > valor + 0.05),
b4 as (select id, valor, 'vencido ha mais de 90 dias e ainda em aberto' as motivo
         from titulos
        where coalesce(cancelado, false) = false and coalesce(situacao, 'aberto') <> 'pago'
          and vencimento < current_date - 90),
-- ---------- C) financiamentos ----------
c1 as (select f.id, f.valor_principal as valor, 'contrato ativo sem nenhuma parcela' as motivo
         from financiamentos f
        where f.status = 'ativo' and not exists (select 1 from parcelas_financiamento p where p.financiamento_id = f.id)),
c2 as (select f.id, f.valor_principal as valor, 'amortizacao das parcelas diferente do principal' as motivo
         from financiamentos f
         join (select financiamento_id, sum(valor_amortizacao) as s, count(*) as n from parcelas_financiamento group by financiamento_id) p
           on p.financiamento_id = f.id
        where f.status = 'ativo' and f.numero_parcelas = p.n and abs(f.valor_principal - p.s) > 1.00),
c3 as (select p.id, p.valor_amortizacao + p.valor_juros as valor, 'parcela pendente ja vencida' as motivo
         from parcelas_financiamento p join financiamentos f on f.id = p.financiamento_id
        where f.status = 'ativo' and p.status in ('pendente', 'atrasada') and p.data_vencimento < current_date),
c4 as (select p.id, p.valor_juros as valor, 'parcela paga com juros mas sem lancamento de juros' as motivo
         from parcelas_financiamento p join financiamentos f on f.id = p.financiamento_id
        where p.status = 'paga' and p.valor_juros > 0 and coalesce(cardinality(p.lancamentos_financeiro_ids), 0) = 0
          and f.observacao is distinct from null and f.observacao not like 'Importado do ERP%'),
-- ---------- D) pecuaria ----------
d1 as (select id, 0::numeric as valor, 'lote ativo com 0 animais ou menos' as motivo
         from lotes where data_fim is null and coalesce(numero_animais, 0) <= 0),
d2 as (select lo.id, 0::numeric as valor, 'lote ativo sem pesagem nos ultimos 60 dias' as motivo
         from lotes lo
        where lo.data_fim is null and coalesce(lo.numero_animais, 0) > 0
          and not exists (select 1 from pesagens p where p.lote_id = lo.id and p.data >= current_date - 60)),
d3 as (select id, peso_medio_kg as valor, 'pesagem com peso fora de 20 a 1.000 kg' as motivo
         from pesagens where peso_medio_kg < 20 or peso_medio_kg > 1000),
d4 as (select id, 0::numeric as valor, 'ganho de peso absurdo entre duas pesagens (acima de 3 kg/dia ou perda de mais de 1 kg/dia)' as motivo
         from (select p.id,
                      (p.peso_medio_kg - lag(p.peso_medio_kg) over w) / nullif(p.data - lag(p.data) over w, 0) as gmd
                 from pesagens p window w as (partition by p.lote_id order by p.data, p.id)) x
        where gmd > 3 or gmd < -1),
d5 as (select id, 0::numeric as valor, 'lote encerrado antes de comecar' as motivo
         from lotes where data_fim is not null and data_inicio is not null and data_fim < data_inicio),
-- ---------- E) cadastros ----------
e1 as (select min(id) as id, 0::numeric as valor, 'fornecedor/cliente cadastrado em duplicidade: ' || nome_norm as motivo
         from (select id, btrim(regexp_replace(translate(upper(nome), E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g')) as nome_norm
                 from entidades) z
        group by nome_norm having count(*) > 1),
e2 as (select id, 0::numeric as valor, 'centro de custo ativo sem tipo (entrada/saida)' as motivo
         from centros_custo where coalesce(ativo, true) and tipo is null),
todos as (
  select 'A' as bloco, 1 as n, 'lancamentos: valor zero ou negativo' as titulo, motivo, id, valor from a1
  union all select 'A', 2, 'lancamentos: data fora de 2020 a 2030', motivo, id, valor from a2
  union all select 'A', 3, 'lancamentos: despesa/investimento sem centro de custo', motivo, id, valor from a3
  union all select 'A', 4, 'lancamentos: centro de custo do lado errado', motivo, id, valor from a4
  union all select 'A', 5, 'lancamentos: despesas recorrentes (valem em todo mes)', motivo, id, valor from a5
  union all select 'A', 6, 'lancamentos: rateio que nao fecha o valor', motivo, id, valor from a6
  union all select 'A', 7, 'lancamentos: geral sem partes (fora das 3 atividades)', motivo, id, valor from a7
  union all select 'A', 8, 'lancamentos: mesmo fornecedor, valor e dia repetidos (pode ser compra repetida de verdade)', motivo, id, valor from a8
  union all select 'A', 9, 'lancamentos: erp_id repetido', motivo, id, valor from a9
  union all select 'B', 1, 'contas: titulo sem rateio', motivo, id, valor from b1
  union all select 'B', 2, 'contas: rateio nao fecha o titulo', motivo, id, valor from b2
  union all select 'B', 3, 'contas: baixado acima do valor', motivo, id, valor from b3
  union all select 'B', 4, 'contas: vencido ha mais de 90 dias em aberto', motivo, id, valor from b4
  union all select 'C', 1, 'financiamentos: ativo sem parcela', motivo, id, valor from c1
  union all select 'C', 2, 'financiamentos: parcelas nao somam o principal', motivo, id, valor from c2
  union all select 'C', 3, 'financiamentos: parcela vencida e pendente', motivo, id, valor from c3
  union all select 'C', 4, 'financiamentos: parcela paga sem lancamento de juros', motivo, id, valor from c4
  union all select 'D', 1, 'pecuaria: lote ativo sem animais', motivo, id, valor from d1
  union all select 'D', 2, 'pecuaria: lote ativo sem pesagem ha 60 dias', motivo, id, valor from d2
  union all select 'D', 3, 'pecuaria: peso de pesagem implausivel', motivo, id, valor from d3
  union all select 'D', 4, 'pecuaria: ganho de peso absurdo entre pesagens', motivo, id, valor from d4
  union all select 'D', 5, 'pecuaria: lote encerrado antes de comecar', motivo, id, valor from d5
  union all select 'E', 1, 'cadastro: nomes de fornecedor em duplicidade', motivo, id, valor from e1
  union all select 'E', 2, 'cadastro: centro de custo ativo sem tipo', motivo, id, valor from e2
),
resumo as (
  select bloco, n, titulo, count(*) as qtd, coalesce(round(sum(valor), 2), 0) as dinheiro
    from todos group by bloco, n, titulo
),
todas_checagens as (
  select bloco, n, titulo from (values
    ('A', 1, 'lancamentos: valor zero ou negativo'), ('A', 2, 'lancamentos: data fora de 2020 a 2030'),
    ('A', 3, 'lancamentos: despesa/investimento sem centro de custo'), ('A', 4, 'lancamentos: centro de custo do lado errado'),
    ('A', 5, 'lancamentos: despesas recorrentes (valem em todo mes)'), ('A', 6, 'lancamentos: rateio que nao fecha o valor'),
    ('A', 7, 'lancamentos: geral sem partes (fora das 3 atividades)'),
    ('A', 8, 'lancamentos: mesmo fornecedor, valor e dia repetidos (pode ser compra repetida de verdade)'),
    ('A', 9, 'lancamentos: erp_id repetido'),
    ('B', 1, 'contas: titulo sem rateio'), ('B', 2, 'contas: rateio nao fecha o titulo'),
    ('B', 3, 'contas: baixado acima do valor'), ('B', 4, 'contas: vencido ha mais de 90 dias em aberto'),
    ('C', 1, 'financiamentos: ativo sem parcela'), ('C', 2, 'financiamentos: parcelas nao somam o principal'),
    ('C', 3, 'financiamentos: parcela vencida e pendente'), ('C', 4, 'financiamentos: parcela paga sem lancamento de juros'),
    ('D', 1, 'pecuaria: lote ativo sem animais'), ('D', 2, 'pecuaria: lote ativo sem pesagem ha 60 dias'),
    ('D', 3, 'pecuaria: peso de pesagem implausivel'), ('D', 4, 'pecuaria: ganho de peso absurdo entre pesagens'),
    ('D', 5, 'pecuaria: lote encerrado antes de comecar'),
    ('E', 1, 'cadastro: nomes de fornecedor em duplicidade'), ('E', 2, 'cadastro: centro de custo ativo sem tipo')
  ) v(bloco, n, titulo)
),
saida as (
  select 0 as ord, t.bloco || t.n::text as chave, t.bloco || ') ' || t.titulo as item,
         coalesce(r.qtd, 0)::text as valor,
         case when coalesce(r.qtd, 0) = 0 then 'OK'
              else 'ATENCAO' || case when r.dinheiro <> 0 then ' | R$ ' || r.dinheiro::text else '' end end as situacao
    from todas_checagens t left join resumo r on r.bloco = t.bloco and r.n = t.n
  union all
  select 1, bloco || n::text, '   amostra ' || bloco || n::text || ': #' || id,
         'R$ ' || round(valor, 2)::text, motivo
    from (select t.*, row_number() over (partition by bloco, n order by abs(valor) desc, id) as rk from todos t) z
   where rk <= 5
)
select item, valor, situacao from saida order by chave, ord, item;
