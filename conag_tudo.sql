-- ============================================================
-- IMPORTACAO DO CONAG - TUDO NUM ARQUIVO SO
--
-- PARA O CODE RODAR, nao para colar no dashboard.
--
--   psql "<STRING DE CONEXAO DO SUPABASE>" -v ON_ERROR_STOP=1 -f conag_tudo.sql
--
-- A string de conexao esta em Supabase > Project Settings > Database >
-- Connection string > URI. Use a do modo "Session" (porta 5432).
--
-- Rode de dentro da pasta do repositorio: o \copy la embaixo procura o CSV
-- em conag/lancamentos_para_importar.csv, caminho relativo.
--
-- ------------------------------------------------------------
-- PRE-REQUISITOS ja feitos por voce no dashboard:
--   centros_05_dois_niveis.sql   (coluna classe + arvore do Conag)
--   centros_07_de_para.sql       (deu 7 / 1.375 / 2)
--
-- Se algum faltar, este arquivo para na primeira linha e diz qual.
--
-- ------------------------------------------------------------
-- O QUE ELE FAZ, EM ORDEM
--   1. cria conag_staging e as colunas conag_id, cnpj_nota, contrato
--   2. carrega o CSV - 9.400 linhas, R$ 62.609.569,50
--   3. cria as 85 contas de nivel 4, a tabela de rateio e a view
--   4. importa os 9.400
--   5. rateia os 791 do geral de fazenda e os 2.657 do administrativo
--   6. confere e imprime 13 linhas
--
-- Roda quantas vezes quiser: o indice unico em conag_id nao deixa duplicar.
-- Ensaiado ponta a ponta com este mesmo CSV num Postgres 16 local.
-- ============================================================

\set ON_ERROR_STOP on
\timing off

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_name='centros_custo' and column_name='classe') then
    raise exception 'FALTA O centros_05 - rode ele antes';
  end if;
  if not exists (select 1 from pg_proc where proname='plano_norm') then
    raise exception 'FALTA O centros_05 - a funcao plano_norm nao existe';
  end if;
end $$;

\echo ''
\echo '== 1/6 mesa de pouso =='

drop table if exists conag_staging;
create table conag_staging (
  conag_id         text,
  conag_cod        text,
  entidade         text,
  centro_custo     text,
  cnpj_nota        text,
  forma_pagamento  text,
  vencimento       text,
  competencia      text,
  valor            text,
  previsao         text,
  usuario          text,
  atividade_conag  text,
  fazenda_conag    text,
  atividade        text,
  cultura          text,
  administrativo   text,
  contrato         text
);
comment on table conag_staging is
  'Mesa de pouso do CSV do Conag. Some depois da importacao conferida.';

alter table lancamentos_financeiros
  add column if not exists conag_id text;

create unique index if not exists uq_lancamento_conag
  on lancamentos_financeiros (conag_id) where conag_id is not null;

comment on column lancamentos_financeiros.conag_id is
  'Id do titulo no Conag (a segunda parte do Cod-Id). Nulo em lancamento '
  'feito no proprio app. Unico: a importacao pode rodar duas vezes sem '
  'duplicar.';

alter table lancamentos_financeiros
  add column if not exists cnpj_nota text;

alter table lancamentos_financeiros
  add column if not exists contrato text;


\echo ''
\echo '== 2/6 carrega o CSV =='
\copy conag_staging (conag_id,conag_cod,entidade,centro_custo,contrato,cnpj_nota,forma_pagamento,vencimento,competencia,valor,previsao,usuario,atividade_conag,fazenda_conag,atividade,cultura,administrativo) from 'conag/lancamentos_para_importar.csv' with (format csv, header true)


\echo ''
\echo '== 3/6 contas de nivel 4, rateio e view =='
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
       l.conag_id, l.contrato, true as rateado
  from lancamentos_financeiros l
  join lancamento_rateios r on r.lancamento_id = l.id
union all
select l.id, null, l.tipo,
       l.atividade, l.fazenda_id, l.cultura_id, l.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, false
  from lancamentos_financeiros l
 where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);

comment on view lancamentos_rateados is
  'O financeiro ja rateado. Onde ha rateio, entrega as partes; onde nao ha, '
  'entrega o lancamento inteiro. E daqui que os Resultados devem ler.';


\echo ''
\echo '== 4/6 importa os 9.400 =='
alter table lancamentos_financeiros add column if not exists vencimento date;

comment on column lancamentos_financeiros.vencimento is
  'Quando o titulo vence - fato de caixa. Diferente de data, que e quando o '
  'custo aconteceu. Nos lancamentos vindos do Conag, data e nula (so se '
  'conhece o mes de competencia) e o vencimento fica aqui.';
insert into lancamentos_financeiros
  (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
   vencimento, fornecedor, cultura_id, conag_id, cnpj_nota, contrato, criado_por, observacao)
select 'despesa',
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
 where s.valor::numeric > 0
on conflict (conag_id) where conag_id is not null do nothing;


\echo ''
\echo '== 5/6 rateio =='
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


\echo ''
\echo '== 6/6 conferencia =='
select 1::numeric as ordem, 'Titulos do Conag importados' as item,
       count(*)::text as valor, 'esperado: 9.328 (9.400 - 72 de valor zero, ver linha 11.4)' as situacao
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
       'esperado: 9, somando R$ 0,09 (era 81 antes de excluir os 72 de valor zero da linha 11.4 - a soma nao mudou, so a contagem)'
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
  and s.valor::numeric > 0
union all
select 11.4, 'Titulos com valor R$ 0,00 (nao importados)', count(*)::text,
       'esperado: 72 - lancamentos_financeiros exige valor > 0'
from conag_staging s
where s.valor::numeric = 0
  and not exists (select 1 from lancamentos_financeiros l where l.conag_id = s.conag_id)
union all
select 11.5, 'Titulos com vencimento em outro mes', count(*)::text,
       'esperado: 4.813 - nota a prazo, data fica nula (era 4.836 antes de excluir os 72 de valor zero da linha 11.4)'
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
