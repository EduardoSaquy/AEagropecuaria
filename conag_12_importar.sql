-- ============================================================
-- ETAPA 3 DE 3: IMPORTA OS 9.400 LANCAMENTOS DO CONAG
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- ANTES: conag_10 (mesa de pouso), centros_05 (classe), centros_07 (de-para),
--        e o CSV ja carregado em conag_staging pelo Table Editor.
--
-- Roda quantas vezes quiser: o indice unico em conag_id impede repetir.
--
-- ------------------------------------------------------------
-- O QUE ENTRA
--
--   9.400 titulos, R$ 62.609.569,50, competencia de 2022-12 a 2029-08.
--   Todos sao contas a PAGAR, nenhum e previsao.
--
-- ------------------------------------------------------------
-- ONDE CADA UM CAI
--
--   5.952  ja vem com atividade  -> vao direto, sem rateio
--     791  geral de uma fazenda  -> rateados entre as atividades DAQUELA fazenda
--   2.657  administrativo        -> rateados entre todas as fazendas e atividades
--
-- ------------------------------------------------------------
-- COMO O RATEIO E CALCULADO
--
-- Pela proporcao do que REALMENTE aconteceu naquela fazenda naquela safra,
-- lida dos lancamentos que ja tem atividade. Nao e regra escrita na mao.
--
-- Na Invernada, por exemplo, isso da:
--
--   2022/23  graos  99%  pecuaria   1%
--   2023/24  graos  99%  pecuaria   1%
--   2024/25  graos  93%  pecuaria   7%
--   2025/26  graos  70%  pecuaria  30%
--
-- A pecuaria entrou na fazenda e o rateio acompanha sozinho. E por isso
-- que feijao e feno nao recebem nada: nunca tiveram gasto la, entao nao
-- entram na conta. Nenhuma regra precisou ser escrita para isso.
--
-- A fazenda Reunidas nao recebe rateio de administrativo - ela saiu do
-- negocio. Os 105 lancamentos proprios dela entram normalmente, para o
-- historico ficar completo.
--
-- ------------------------------------------------------------
-- POR QUE UMA TABELA DE RATEIO, E NAO QUEBRAR O LANCAMENTO EM VARIOS
--
-- Um titulo do Conag continua sendo UMA linha em lancamentos_financeiros.
-- O rateio mora em lancamento_rateios, uma linha por destino.
--
--   - a conferencia contra o Conag bate na unha: 9.400 la, 9.400 aqui
--   - se amanha a proporcao mudar, apaga o rateio e recalcula, sem tocar
--     no lancamento
--   - e a mesma forma do titulo_rateios que o Pagar/Receber ja usa
--
-- Quebrar em varias linhas transformaria 9.400 em ~13.000 e a contagem
-- deixaria de bater com a origem para sempre.
--
-- Os relatorios leem a VIEW lancamentos_rateados, que ja entrega os dois
-- casos misturados: onde ha rateio, as partes; onde nao ha, o lancamento
-- inteiro. Nenhuma tela precisa saber da diferenca.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_name='centros_custo' and column_name='classe') then
    raise exception 'RODE O centros_05 PRIMEIRO';
  end if;
  if not exists (select 1 from conag_plano_contas) then
    raise exception 'conag_plano_contas vazia - rode o centros_05';
  end if;
  if (select count(*) from conag_staging) = 0 then
    raise exception 'conag_staging vazia - carregue o CSV no Table Editor antes';
  end if;
end $$;


-- ------------------------------------------------------------
-- A SAFRA DE UM MES
--
-- Maio a abril, como no Conag e como no resto do app. Julho/2025 e
-- 2025/2026; marco/2026 tambem.
-- ------------------------------------------------------------
create or replace function safra_do_mes(mes text)
returns text language sql immutable as $$
  select case
           when mes is null or mes !~ '^\d{4}-\d{2}$' then null
           when substring(mes,6,2)::int >= 5
             then substring(mes,1,4) || '/' || (substring(mes,1,4)::int + 1)::text
             else (substring(mes,1,4)::int - 1)::text || '/' || substring(mes,1,4)
         end;
$$;


-- ------------------------------------------------------------
-- AS CONTAS DE NIVEL 4 QUE FALTAVAM
--
-- Nascem do CSV, nao deste arquivo: assim o nome vem com acento do proprio
-- dado e este script nao precisa de um unico caractere acentuado.
--
-- So nasce quem ainda nao existe. Quem o centros_07 ja casou (SALARIOS
-- dentro de Mao de Obra, por exemplo) nao vira conta nova.
-- ------------------------------------------------------------
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
         -- TRIBUTOS existe em duas classes: a de custo vem antes da que
         -- desconta receita.
         order by case when classe = 'DEDUCOES DA RECEITA BRUTA DE VENDAS' then 1 else 0 end
         limit 1) p on true
 where not exists (select 1 from centros_custo c where plano_norm(c.nome) = plano_norm(s.nome));


-- ------------------------------------------------------------
-- ONDE O CUSTO CAI
--
-- Uma linha por destino. lancamento_id + atividade e unico: o mesmo titulo
-- nao pode cair duas vezes na mesma atividade da mesma fazenda.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- OS 9.400
--
-- DATA FICA NULA, DE PROPOSITO.
--
-- lancamentos_financeiros tem a trava mes_bate_com_data:
--     data is null or mes = to_char(data, 'YYYY-MM')
--
-- Ela existe desde o financeiro_01 e o comentario dela ja previa este caso:
-- com data, o mes tem que ser o dela; SEM data, o mes e livre e significa
-- competencia mensal - lancamento historico, sem dia especifico.
--
-- E exatamente o que estes 9.400 sao. No Conag, competencia e vencimento
-- sao fatos diferentes: o combustivel foi consumido em dezembro e o boleto
-- vence em 1o de janeiro. Em 4.836 dos 9.400 titulos (51,4%, R$ 23,6
-- milhoes) os dois meses nao batem, e 4.169 deles sao de exatamente um mes.
-- E o comportamento normal de nota a prazo, nao erro de dado.
--
-- Entao: mes recebe a competencia, que e o mes que o Resultado usa e de
-- onde sairam todos os totais por safra ja conferidos. E data fica nula,
-- porque o dia em que o custo aconteceu o Conag nao informa - so o mes.
--
-- O vencimento nao se perde: vai para coluna propria. Nao cabia em data,
-- que quer dizer "quando aconteceu", e nao "quando vence".
--
-- Relaxar a trava seria o caminho errado: ela nasceu de um bug real, que
-- derivava um campo do outro e inflou R$ 43.928,73 para R$ 1.230.390,69.
--
-- on conflict do nothing no conag_id: rodar de novo nao duplica.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- RATEIO 1: O GERAL DE UMA FAZENDA
--
-- 791 titulos que a fazenda se sabe e a atividade nao. Vao para as
-- atividades DAQUELA fazenda, na proporcao do que ja foi gasto la na mesma
-- safra. Se a safra nao tiver base, usa a fazenda inteira.
--
-- A base sao os lancamentos que TEM atividade - os nossos e os do Conag
-- juntos. E a melhor leitura do que de fato aconteceu na fazenda.
--
-- Parte que arredonda para menos de um centavo e descartada, e a sobra vai
-- para a maior parte. A soma do rateio fecha com o valor do titulo.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- RATEIO 2: O ADMINISTRATIVO
--
-- 2.657 titulos sem fazenda e sem atividade - escritorio, contabilidade,
-- cartorio, tributos, financiamento. R$ 18,5 milhoes.
--
-- Vao para todas as fazendas e todas as atividades, na proporcao do que
-- cada combinacao gastou na mesma safra. Quem produz mais carrega mais
-- administrativo, que e como o custo indireto de fato se comporta.
--
-- A Reunidas fica de fora: ela saiu do negocio. Os 105 lancamentos
-- proprios dela entram, mas ela nao carrega despesa de escritorio de hoje.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
--
-- A linha 3 e a que decide se a importacao serve: a view lancamentos_rateados
-- tem que devolver o mesmo dinheiro que entrou. Se ela nao bater, nada mais
-- importa.
-- ------------------------------------------------------------
select 1::numeric as ordem, 'Titulos do Conag importados' as item,
       count(*)::text as valor, 'esperado: 9.253 (9.400 - 72 de valor zero - 75 de amortizacao, ver linhas 11.4 e 11.6)' as situacao
from lancamentos_financeiros where conag_id is not null
union all
select 2, 'Valor importado', round(sum(valor),2)::text, 'esperado: 44.780.409,59 (62.609.569,50 - 17.829.159,91 de amortizacao excluida)'
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
select 5, 'Titulos com atividade propria (sem rateio)', count(*)::text,
       'esperado: 5.927 (era 5.952, 25 de amortizacao tinham atividade propria e saem)'
from lancamentos_financeiros
where conag_id is not null and atividade <> 'geral'
union all
select 6, 'Rateados: geral de fazenda', count(distinct lancamento_id)::text, 'esperado: 791'
from lancamento_rateios where origem = 'geral da fazenda'
union all
select 7, 'Rateados: administrativo', count(distinct lancamento_id)::text,
       'esperado: 2.526 (era 2.576, 50 de amortizacao geral/sem fazenda saem) - veja a linha 8'
from lancamento_rateios where origem = 'administrativo'
union all
select 8, 'Nao rateados por serem centavo ou zero', count(*)::text,
       'esperado: 9, somando R$ 0,09'
from lancamentos_financeiros l
where l.conag_id is not null and l.atividade = 'geral'
  and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)
union all
select 9, 'Contas do Conag que existem como centro', count(*)::text,
       'esperado: 85 - as do CSV'
from (select distinct plano_norm(centro_custo) n from conag_staging) s
where exists (select 1 from centros_custo c where plano_norm(c.nome) = s.n)
union all
select 10, 'Titulos com cultura', count(*)::text,
       'esperado: 1.855 (era 1.872, 17 de amortizacao tinham cultura)'
from lancamentos_financeiros where conag_id is not null and cultura_id is not null
union all
select 11, 'Titulos sem centro de custo', count(*)::text,
       case when count(*) = 0 then 'nenhum ficou de fora' else 'PARE E ME AVISE' end
from conag_staging s
where not exists (select 1 from lancamentos_financeiros l where l.conag_id = s.conag_id)
  and s.valor::numeric > 0
  and plano_norm(s.centro_custo) <> plano_norm('AMORTIZACAO DE FINANCIAMENTO')
union all
select 11.4, 'Titulos com valor R$ 0,00 (nao importados)', count(*)::text,
       'esperado: 72 - lancamentos_financeiros exige valor > 0'
from conag_staging s
where s.valor::numeric = 0
  and not exists (select 1 from lancamentos_financeiros l where l.conag_id = s.conag_id)
union all
select 11.5, 'Titulos com vencimento em outro mes', count(*)::text,
       'esperado: 4.805 (era 4.813, 8 de amortizacao tinham vencimento em outro mes) - nota a prazo, data fica nula'
from lancamentos_financeiros
where conag_id is not null and vencimento is not null
  and to_char(vencimento,'YYYY-MM') <> mes
union all
select 11.6, 'Titulos de amortizacao de financiamento (nao importados)', count(*)::text,
       'esperado: 75, R$ 17.829.159,91 - pagar o principal nao e despesa, e divida saindo (regra do CLAUDE.md)'
from conag_staging s
where plano_norm(s.centro_custo) = plano_norm('AMORTIZACAO DE FINANCIAMENTO')
  and not exists (select 1 from lancamentos_financeiros l where l.conag_id = s.conag_id)
union all
select 11.7, 'Titulos classificados como investimento (tipo investimento, nao despesa)', count(*)::text,
       'esperado: 337, R$ 7.212.288,44 - maquina/terra/matriz/infraestrutura, nao entra como despesa'
from lancamentos_financeiros
where conag_id is not null and tipo = 'investimento'
union all
select 12, 'Lancamentos NOSSOS, anteriores', count(*)::text, 'NAO pode ter mudado'
from lancamentos_financeiros where conag_id is null
union all
select 13, 'Valor NOSSO, anterior', round(sum(valor),2)::text, 'NAO pode ter mudado'
from lancamentos_financeiros where conag_id is null
order by ordem;
