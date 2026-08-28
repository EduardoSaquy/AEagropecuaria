-- ============================================================
-- IMPORTACAO DO CONAG - PARTE 2 de 3 (cole no SQL Editor do Supabase)
--
-- So cole isto DEPOIS de:
--   1. ter rodado o conag_dashboard_1_antes_do_csv.sql
--   2. ter importado o CSV em conag_staging pelo Table Editor
--
-- Confere antes de colar: no Table Editor, abra conag_staging e veja se
-- tem 9.400 linhas. Se tiver menos, a importacao do CSV nao terminou -
-- nao cole isto ainda.
-- ============================================================

create or replace function safra_do_mes(mes text)
returns text language sql immutable as $$
  select case
           when mes is null or mes !~ '^\d{4}-\d{2}$' then null
           when substring(mes,6,2)::int >= 5
             then substring(mes,1,4) || '/' || (substring(mes,1,4)::int + 1)::text
             else (substring(mes,1,4)::int - 1)::text || '/' || substring(mes,1,4)
         end;
$$;

insert into centros_custo (nome, tipo, subcategoria, classe, ativo)
select s.nome,
       coalesce(p.tipo, 'saida'),
       case when p.grupo = p.subcategoria then p.grupo
            else p.grupo || ' | ' || p.subcategoria end,
       p.classe,
       true
  from (select distinct btrim(centro_custo) as nome from conag_staging
         where coalesce(btrim(centro_custo),'') <> '') s
  join lateral (
        select grupo, subcategoria, classe, tipo
          from conag_plano_contas
         where plano_norm(conta) = plano_norm(s.nome)
         order by case when classe = 'DEDUCOES DA RECEITA BRUTA DE VENDAS' then 1 else 0 end
         limit 1) p on true
 where not exists (select 1 from centros_custo c where plano_norm(c.nome) = plano_norm(s.nome));

alter table lancamentos_financeiros add column if not exists vencimento date;

comment on column lancamentos_financeiros.vencimento is
  'Quando o titulo vence - fato de caixa. Diferente de data, que e quando o '
  'custo aconteceu. Nos lancamentos vindos do Conag, data e nula (so se '
  'conhece o mes de competencia) e o vencimento fica aqui.';

create table if not exists lancamento_rateios (
  id             bigint generated always as identity primary key,
  lancamento_id  bigint not null references lancamentos_financeiros(id) on delete cascade,
  atividade      text   not null,
  fazenda_id     bigint references fazendas(id),
  cultura_id     bigint references culturas(id),
  percentual     numeric(9,6) not null,
  valor          numeric(12,2) not null,
  origem         text   not null,
  created_at     timestamptz not null default now()
);

comment on table lancamento_rateios is
  'Onde o custo de um lancamento cai, quando ele nao pertence a uma '
  'atividade so. O lancamento continua inteiro em lancamentos_financeiros; '
  'aqui ficam as partes. Sem linha aqui, o lancamento vale por si.';

create unique index if not exists uq_rateio_destino
  on lancamento_rateios (lancamento_id, atividade, coalesce(fazenda_id, -1));
create index if not exists ix_rateio_lancamento on lancamento_rateios (lancamento_id);

create or replace view lancamentos_rateados as
select l.id as lancamento_id, r.id as rateio_id, l.tipo,
       r.atividade, r.fazenda_id, r.cultura_id, r.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, true as rateado,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento
  from lancamentos_financeiros l
  join lancamento_rateios r on r.lancamento_id = l.id
union all
select l.id, null, l.tipo,
       l.atividade, l.fazenda_id, l.cultura_id, l.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, false,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento
  from lancamentos_financeiros l
 where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);

comment on view lancamentos_rateados is
  'O financeiro ja rateado. Onde ha rateio, entrega as partes; onde nao ha, '
  'entrega o lancamento inteiro. E daqui que os Resultados devem ler.';

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
 -- lancamentos_financeiros tem "check (valor > 0)" -- a mesma regra que a
 -- tela do Matriz ja cobra no formulario ("valor maior que zero"). 72
 -- titulos do CSV vem com R$ 0,00 (nenhum negativo) e violavam essa trava,
 -- derrubando a importacao inteira. Ficam de fora, contados na conferencia.
 --
 -- AMORTIZACAO DE FINANCIAMENTO fica de fora: pagar o principal de um
 -- emprestimo nao e despesa, e divida saindo (regra do proprio CLAUDE.md,
 -- a mesma do modulo Financiamentos). So o juros vira lancamento, e o
 -- juros esta em conta separada (DESPESAS FINANCEIRAS), que continua
 -- entrando normalmente. Sao 75 titulos, R$ 17.829.159,91 - conferidos na
 -- linha 11.6.
 --
 -- Conta que cai no grupo INVESTIMENTOS do plano do Conag (maquina, terra,
 -- matriz, infraestrutura) vira tipo='investimento', nao despesa - senao
 -- infla o total de despesas com dinheiro que virou patrimonio, nao custo.
 where s.valor::numeric > 0
   and plano_norm(s.centro_custo) <> plano_norm('AMORTIZACAO DE FINANCIAMENTO')
on conflict (conag_id) where conag_id is not null do nothing;

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

-- Depois de colar isto, cole o conag_dashboard_3_conferencia.sql pra ver
-- se bateu tudo.
select 'Parte 2 ok. Agora rode o conag_dashboard_3_conferencia.sql.' as proximo_passo;
