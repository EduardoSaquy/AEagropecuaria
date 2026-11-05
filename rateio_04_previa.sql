-- ============================================================
-- PREVIA (SO LEITURA): como ficaria o rateio dos custos gerais da safra 2026/27
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela (item / valor / situacao).
--
-- ALVO: os lancamentos do ERP, atividade geral, cujas partes em lancamento_rateios
-- nao somam o valor (rateio_02_diagnostico.sql: 604 lancamentos, R$ 979.432,02 que
-- nao chegavam a atividade nenhuma).
--
-- REGRA (decisao do Eduardo, 05/11/2026), da mais forte para a mais fraca:
--   1. a conta tem FAZENDA: vai para as atividades daquela fazenda (fazenda_atividades,
--      com area), em partes iguais; sem nenhuma cadastrada, entre as tres;
--   2. sem fazenda e e de um FUNCIONARIO pareado em "de_para": divide pela alocacao
--      dele na aba Funcionarios (funcionario_atividades, % de cada atividade);
--   2b. sem fazenda e e de uma pessoa sem cadastro mas com atividade informada em
--      "regras_nome": divide pelos pesos informados;
--   3. sem fazenda e o centro de custo e de uma atividade so por natureza
--      ("regras_centro"): vai inteira para ela;
--   4. o resto: tres partes iguais (Pecuaria, Cana e Graos), a mesma regra que o app
--      ja usa para o juros de capital de giro.
--
-- "de_para" liga o nome do fornecedor no ERP ao id do funcionario do cadastro (o
-- cadastro so tem o primeiro nome). Nomes de pessoas NAO vao para o repositorio:
-- a versao com os nomes fica so no computador (AEagropecuaria_dados_privados).
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.fazenda_atividades') is null
     or to_regclass('public.funcionarios') is null
     or to_regclass('public.funcionario_atividades') is null then
    raise exception 'Faltam as tabelas fazenda_atividades/funcionarios/funcionario_atividades.';
  end if;
end
$trava$;

with
conj as (
  select l.id, l.valor, l.fazenda_id, l.mes, p.soma,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as centro_norm,
         coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '(sem nome)') as fornecedor,
         coalesce(cc.nome, '(sem centro)') as centro
    from lancamentos_financeiros l
    join (select lancamento_id, sum(valor) as soma
            from lancamento_rateios group by lancamento_id) p on p.lancamento_id = l.id
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.atividade = 'geral' and l.erp_id is not null and l.valor > 0
     and abs(l.valor - p.soma) > 0.05
),
atuais as (
  select r.lancamento_id as id, r.atividade, r.fazenda_id, r.valor
    from lancamento_rateios r
    join conj c on c.id = r.lancamento_id
),
de_para (forn_norm, funcionario_id) as (
  values
      ('__NENHUM__', 0::bigint)
),
regras_nome (forn_norm, atividade, peso) as (
  values
      ('__NENHUM__', 'cana', 1::numeric)
),
regras_centro (padrao, atividade) as (
  values
      ('NUTRICAO ANIMAL%', 'pecuaria'),
      ('REPRODUCAO ANIMAL%', 'pecuaria'),
      ('COMPRA DE ANIMAIS%', 'pecuaria')
),
tres as (
  select * from (values ('cana'), ('graos'), ('pecuaria')) t(atividade)
),
da_fazenda as (
  select fazenda_id, atividade
    from fazenda_atividades
   where coalesce(area_ha, 0) > 0 and atividade in ('cana', 'graos', 'pecuaria')
),
alocacao as (
  select funcionario_id, atividade, percentual
    from funcionario_atividades
   where coalesce(percentual, 0) > 0 and atividade in ('cana', 'graos', 'pecuaria')
),
por_func as (
  select c.id, a.atividade, a.percentual::numeric as peso, d.funcionario_id
    from conj c
    join de_para d on d.forn_norm = c.forn_norm
    join alocacao a on a.funcionario_id = d.funcionario_id
   where c.fazenda_id is null
),
por_nome as (
  select c.id, n.atividade, n.peso
    from conj c
    join regras_nome n on n.forn_norm = c.forn_norm
   where c.fazenda_id is null
     and c.id not in (select id from por_func)
),
por_centro as (
  select c.id, r.atividade, 1::numeric as peso
    from conj c
    join regras_centro r on c.centro_norm like r.padrao
   where c.fazenda_id is null
     and c.id not in (select id from por_func)
     and c.id not in (select id from por_nome)
),
pesos as (
  select c.id, c.valor as total, c.fazenda_id, d.atividade, 1::numeric as peso,
         'geral da fazenda'::text as origem, 'fazenda'::text as regra
    from conj c join da_fazenda d on d.fazenda_id = c.fazenda_id
   where c.fazenda_id is not null
  union all
  select c.id, c.valor, c.fazenda_id, t.atividade, 1, 'geral da fazenda', 'fazenda'
    from conj c cross join tres t
   where c.fazenda_id is not null
     and not exists (select 1 from da_fazenda d where d.fazenda_id = c.fazenda_id)
  union all
  select c.id, c.valor, null::bigint, f.atividade, f.peso, 'administrativo', 'funcionario'
    from conj c join por_func f on f.id = c.id
  union all
  select c.id, c.valor, null::bigint, n.atividade, n.peso, 'administrativo', 'nome'
    from conj c join por_nome n on n.id = c.id
  union all
  select c.id, c.valor, null::bigint, g.atividade, g.peso, 'administrativo', 'centro'
    from conj c join por_centro g on g.id = c.id
  union all
  select c.id, c.valor, null::bigint, t.atividade, 1, 'administrativo', 'padrao'
    from conj c cross join tres t
   where c.fazenda_id is null
     and c.id not in (select id from por_func)
     and c.id not in (select id from por_nome)
     and c.id not in (select id from por_centro)
),
cont as (
  select p.*, sum(p.peso) over (partition by p.id) as soma_peso,
         row_number() over (partition by p.id order by p.peso desc, p.atividade) as rn
    from pesos p
),
br as (
  select c.*, round(c.total * c.peso / c.soma_peso, 2) as bruto from cont c
),
novas as (
  select b.id, b.atividade, b.fazenda_id, b.origem, b.regra, b.peso / b.soma_peso as fr,
         b.bruto + case when b.rn = 1 then b.total - sum(b.bruto) over (partition by b.id) else 0 end as valor
    from br b
),
regra_do_lanc as (
  select distinct id, regra from pesos
),
atividades as (
  select atividade from tres
),
pessoal_sem_cadastro as (
  select c.centro, c.fornecedor, count(*) as n, sum(c.valor) as v
    from conj c
   where c.fazenda_id is null
     and c.id not in (select id from por_func)
     and c.id not in (select id from por_nome)
     and (c.centro_norm like 'SALARIO%' or c.centro_norm like 'FERIAS%' or c.centro_norm like 'DIARISTA%'
          or c.centro_norm like '13%' or c.centro_norm like 'AQUISICAO DE REFEICOES%'
          or c.centro_norm like 'GRATIFICACO%')
   group by c.centro, c.fornecedor
),
saida_base as (
  select 10 as ord, 'Lancamentos a corrigir' as item,
         count(*)::text as valor,
         'valor total R$ ' || round(sum(valor), 2)::text as situacao
    from conj
  union all
  select 20, 'Hoje, ' || a.atividade,
         round(coalesce((select sum(valor) from atuais x where x.atividade = a.atividade), 0), 2)::text,
         round(100 * coalesce((select sum(valor) from atuais x where x.atividade = a.atividade), 0)
               / (select sum(valor) from conj), 1)::text || '% do valor dos lancamentos'
    from atividades a
  union all
  select 30, 'Depois, ' || a.atividade,
         round(coalesce((select sum(valor) from novas x where x.atividade = a.atividade), 0), 2)::text,
         round(100 * coalesce((select sum(valor) from novas x where x.atividade = a.atividade), 0)
               / nullif((select sum(valor) from novas), 0), 1)::text || '%'
    from atividades a
  union all
  select 40, 'Muda no resultado de ' || a.atividade || ' (depois menos hoje)',
         round(coalesce((select sum(valor) from novas x where x.atividade = a.atividade), 0)
               - coalesce((select sum(valor) from atuais x where x.atividade = a.atividade), 0), 2)::text,
         'custo a mais (+) ou a menos (-) nesta atividade'
    from atividades a
  union all
  select 50 + case r.regra when 'fazenda' then 0 when 'funcionario' then 1 when 'nome' then 2 when 'centro' then 3 else 4 end,
         case r.regra when 'fazenda' then 'Regra 1: tem fazenda (atividades da fazenda)'
                      when 'funcionario' then 'Regra 2: salario pela alocacao do funcionario'
                      when 'nome' then 'Regra 2b: pessoa sem cadastro, atividade informada'
                      when 'centro' then 'Regra 3: centro de custo de uma atividade so'
                      else 'Regra 4: tres partes iguais (padrao)' end,
         count(*)::text,
         'R$ ' || round(sum(c.valor), 2)::text
    from regra_do_lanc r join conj c on c.id = r.id
   group by r.regra
  union all
  select 60, 'Funcionario pareado: ' || f.nome || ' <- ' || c.fornecedor,
         round(sum(c.valor), 2)::text,
         count(*)::text || ' lancamentos; alocacao '
           || (select string_agg(a.atividade || ' ' || a.percentual::text || '%', ' / ' order by a.atividade)
                 from alocacao a where a.funcionario_id = f.id)
    from (select distinct c0.id, c0.valor, c0.fornecedor, p0.funcionario_id
            from conj c0 join por_func p0 on p0.id = c0.id) c
    join funcionarios f on f.id = c.funcionario_id
   group by f.id, f.nome, c.fornecedor
  union all
  select 70, 'Pessoal SEM funcionario pareado (cai nas tres partes): ' || s.fornecedor,
         round(s.v, 2)::text,
         s.n::text || ' lancamentos, centro ' || s.centro
    from pessoal_sem_cadastro s
  union all
  select 80, 'Lancamentos que ficariam SEM nenhuma parte',
         count(*)::text,
         'tem que ser 0'
    from conj where id not in (select id from novas)
  union all
  select 81, 'Lancamentos que fecham o valor (diferenca ate R$ 0,01)',
         count(*)::text,
         'de ' || (select count(*) from conj)::text
    from (select c.id from conj c
            join novas n on n.id = c.id
           group by c.id, c.valor
          having abs(sum(n.valor) - c.valor) <= 0.01) z
  union all
  select 82, 'Pareamentos repetidos (mesmo nome do ERP em duas linhas)',
         count(*)::text,
         'tem que ser 0'
    from (select forn_norm from de_para group by forn_norm having count(*) > 1) z
),
lanc_info as (
  select distinct r.id, r.regra, c.centro, c.fornecedor, c.valor, c.mes
    from regra_do_lanc r join conj c on c.id = r.id
),
g1 as (
  select i.regra, i.centro, i.fornecedor, count(*) as n, sum(i.valor) as v,
         min(i.mes) as de, max(i.mes) as ate
    from lanc_info i
   group by i.regra, i.centro, i.fornecedor
),
g2 as (
  select i.regra, i.centro, i.fornecedor, n.atividade, sum(n.valor) as v
    from lanc_info i join novas n on n.id = i.id
   group by i.regra, i.centro, i.fornecedor, n.atividade
),
saida_lista as (
  select 100 + case g.regra when 'fazenda' then 0 when 'funcionario' then 1 when 'nome' then 2 when 'centro' then 3 else 4 end as ord,
         -g.v as sub,
         case g.regra when 'fazenda' then 'Regra 1 (fazenda)' when 'funcionario' then 'Regra 2 (funcionario)'
                      when 'nome' then 'Regra 2b (nome)'
                      when 'centro' then 'Regra 3 (centro)' else 'Regra 4 (tres partes)' end
           || ' | ' || g.centro || ' | ' || g.fornecedor as item,
         round(g.v, 2)::text as valor,
         g.n::text || ' lanc., ' || coalesce(g.de, '?') || ' a ' || coalesce(g.ate, '?') || ' -> '
           || (select string_agg(x.atividade || ' R$ ' || round(x.v, 2)::text, ' / ' order by x.atividade)
                 from g2 x where x.regra = g.regra and x.centro = g.centro and x.fornecedor = g.fornecedor) as situacao
    from g1 g
)
select item, valor, situacao
  from (select ord, 0::numeric as sub, item, valor, situacao from saida_base
        union all
        select ord, sub, item, valor, situacao from saida_lista) z
 order by ord, sub, item;
