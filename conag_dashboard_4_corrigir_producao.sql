-- ============================================================
-- IMPORTACAO DO CONAG - PARTE 4 de 4, CORRIGE O QUE JA FOI IMPORTADO
--
-- So cole isto se voce ja rodou as partes 1, 2 e 3 antes desta correcao
-- existir. A importacao rodou, mas com um erro: TODO titulo do Conag
-- virou tipo='despesa', inclusive amortizacao de financiamento e compra
-- de maquina/terra/matriz/gado para investimento - que nao sao despesa.
-- Isso inflou o total de despesas em cerca de R$ 25 milhoes.
--
-- Cana e Cereais/Graos NAO tem esse problema - conferido: o CSV ja traz
-- os dois separados certinho (1.762 titulos de cana, 1.689 de graos, sem
-- misturar).
--
-- O QUE ESTE ARQUIVO FAZ, NESTA ORDEM:
--   1. apaga so os lancamentos do Conag (os que tem conag_id preenchido)
--      e o rateio deles. NAO toca em nada lancado no proprio app.
--   2. reimporta direto de conag_staging - que ainda esta com o CSV
--      carregado, nao precisa importar de novo - agora com:
--        - AMORTIZACAO DE FINANCIAMENTO de fora (75 titulos,
--          R$ 17.829.159,91): pagar o principal do emprestimo nao e
--          despesa, e divida saindo (mesma regra do modulo Financiamentos)
--        - maquina/terra/matriz/infraestrutura (337 titulos,
--          R$ 7.212.288,44) como tipo='investimento', nao despesa
--   3. rateia de novo - os pesos mudam porque 75 titulos saem da conta
--   4. confere - a mesma tabela de sempre, com as linhas novas 11.6 e 11.7
--
-- PRE-REQUISITO: conag_staging ainda com os 9.400 registros. Se essa
-- tabela foi apagada, recarregue o CSV pelo Table Editor (passo 2 do
-- arquivo _1_) antes de colar isto.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='conag_staging') then
    raise exception 'conag_staging nao existe - rode o arquivo _1_ e recarregue o CSV antes';
  end if;
  if (select count(*) from conag_staging) < 9000 then
    raise exception 'conag_staging nao tem os 9.400 registros - recarregue o CSV antes (passo 2 do arquivo _1_)';
  end if;
end $$;

-- 1/4: apaga so o que veio do Conag, para reimportar certo
delete from lancamento_rateios
 where lancamento_id in (select id from lancamentos_financeiros where conag_id is not null);

delete from lancamentos_financeiros where conag_id is not null;

-- 2/4: reimporta, agora com tipo certo e sem amortizacao
insert into lancamentos_financeiros
  (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
   vencimento, fornecedor, cultura_id, conag_id, cnpj_nota, contrato, criado_por, observacao)
select case when p.grupo = 'INVESTIMENTOS' then 'investimento' else 'despesa' end,
       s.atividade,
       f.id,
       c.id,
       btrim(s.entidade),
       s.valor::numeric,
       null::date,
       s.competencia,
       s.vencimento::date,
       btrim(s.entidade),
       cu.id,
       s.conag_id,
       nullif(btrim(s.cnpj_nota), ''),
       nullif(btrim(s.contrato), ''),
       'Conag',
       'Conag ' || s.conag_cod || ' - ' || coalesce(nullif(btrim(s.forma_pagamento),''), 'sem forma')
  from conag_staging s
  join centros_custo c  on plano_norm(c.nome) = plano_norm(s.centro_custo)
  left join lateral (
        select grupo from conag_plano_contas
         where plano_norm(conta) = plano_norm(s.centro_custo)
         order by case when classe = 'DEDUCOES DA RECEITA BRUTA DE VENDAS' then 1 else 0 end
         limit 1) p on true
  left join lateral (
        select id from fazendas
         where coalesce(btrim(s.fazenda_conag),'') <> ''
           and plano_norm(nome) like '%' || plano_norm(
                 regexp_replace(btrim(s.fazenda_conag), '^FAZENDA (DAS |DA |DO )?', '')) || '%'
         order by length(nome)
         limit 1) f on true
  left join lateral (
        select id from culturas
         where coalesce(btrim(s.cultura),'') <> ''
           and plano_norm(nome) = plano_norm(s.cultura)
         limit 1) cu on true
 where s.valor::numeric > 0
   and plano_norm(s.centro_custo) <> plano_norm('AMORTIZACAO DE FINANCIAMENTO')
on conflict (conag_id) where conag_id is not null do nothing;

-- 3/4: rateio - identico ao da parte 2, so refeito em cima dos dados certos
with base_fs as (
  select l.fazenda_id, safra_do_mes(l.mes) as safra, l.atividade, sum(l.valor) as v
    from lancamentos_financeiros l
   where l.atividade <> 'geral' and l.fazenda_id is not null and l.valor > 0
   group by 1,2,3
),
base_f as (
  select l.fazenda_id, l.atividade, sum(l.valor) as v
    from lancamentos_financeiros l
   where l.atividade <> 'geral' and l.fazenda_id is not null and l.valor > 0
   group by 1,2
),
alvo as (
  select l.id, l.fazenda_id, l.valor as total, safra_do_mes(l.mes) as safra
    from lancamentos_financeiros l
   where l.conag_id is not null and l.atividade = 'geral' and l.fazenda_id is not null
     and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)
),
partes as (
  select a.id, a.fazenda_id, a.total, b.atividade, b.v
    from alvo a join base_fs b on b.fazenda_id = a.fazenda_id and b.safra = a.safra
  union all
  select a.id, a.fazenda_id, a.total, b.atividade, b.v
    from alvo a join base_f b on b.fazenda_id = a.fazenda_id
   where not exists (select 1 from base_fs x
                      where x.fazenda_id = a.fazenda_id and x.safra = a.safra)
),
fracao as (
  select p.*, p.v / nullif(sum(p.v) over (partition by p.id), 0) as fr from partes p
),
mantidos as (
  select f.*, round(f.total * f.fr, 2) as bruto from fracao f
   where round(f.total * f.fr, 2) >= 0.01
),
fechado as (
  select m.*,
         row_number() over (partition by m.id order by m.fr desc, m.atividade) as rn,
         m.total - sum(m.bruto) over (partition by m.id) as sobra
    from mantidos m
)
insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
select id, atividade, fazenda_id, round(fr, 6),
       bruto + case when rn = 1 then sobra else 0 end,
       'geral da fazenda'
  from fechado
on conflict do nothing;

with base_s as (
  select safra_do_mes(l.mes) as safra, l.fazenda_id, l.atividade, sum(l.valor) as v
    from lancamentos_financeiros l
    join fazendas f on f.id = l.fazenda_id
   where l.atividade <> 'geral' and l.valor > 0
     and plano_norm(f.nome) not like '%REUNIDAS%'
   group by 1,2,3
),
base_t as (
  select l.fazenda_id, l.atividade, sum(l.valor) as v
    from lancamentos_financeiros l
    join fazendas f on f.id = l.fazenda_id
   where l.atividade <> 'geral' and l.valor > 0
     and plano_norm(f.nome) not like '%REUNIDAS%'
   group by 1,2
),
alvo as (
  select l.id, l.valor as total, safra_do_mes(l.mes) as safra
    from lancamentos_financeiros l
   where l.conag_id is not null and l.atividade = 'geral' and l.fazenda_id is null
     and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)
),
partes as (
  select a.id, a.total, b.fazenda_id, b.atividade, b.v
    from alvo a join base_s b on b.safra = a.safra
  union all
  select a.id, a.total, b.fazenda_id, b.atividade, b.v
    from alvo a join base_t b on true
   where not exists (select 1 from base_s x where x.safra = a.safra)
),
fracao as (
  select p.*, p.v / nullif(sum(p.v) over (partition by p.id), 0) as fr from partes p
),
mantidos as (
  select f.*, round(f.total * f.fr, 2) as bruto from fracao f
   where round(f.total * f.fr, 2) >= 0.01
),
fechado as (
  select m.*,
         row_number() over (partition by m.id order by m.fr desc, m.fazenda_id, m.atividade) as rn,
         m.total - sum(m.bruto) over (partition by m.id) as sobra
    from mantidos m
)
insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
select id, atividade, fazenda_id, round(fr, 6),
       bruto + case when rn = 1 then sobra else 0 end,
       'administrativo'
  from fechado
on conflict do nothing;

-- 4/4: confere - cole o conag_dashboard_3_conferencia.sql em seguida, ou
-- rode a consulta abaixo, que e a mesma coisa.
select 'Parte 4 ok. Agora rode o conag_dashboard_3_conferencia.sql (ele mudou: agora sao 17 linhas).' as proximo_passo;
