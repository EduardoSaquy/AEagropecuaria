-- ============================================================
-- CONSERTO: rateio dos custos gerais da safra 2026/27 (regras da previa)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz), DEPOIS de rodar o
-- rateio_04_previa.sql e concordar com os numeros. Cole inteiro e rode.
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
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. recusa rodar se o que existe no banco nao for o que o diagnostico achou
--      (604 lancamentos do ERP, atividade geral, partes somando menos que o
--      valor, faltando R$ 979.432,02);
--   2. recusa se alguma lista de regras for invalida (atividade desconhecida,
--      funcionario inexistente ou sem alocacao, nome repetido);
--   3. guarda as partes antigas desses lancamentos na tabela
--      zz_backup_rateio_2026_11_05 (fechada: so o dono do banco le);
--   4. apaga as partes antigas e grava as novas;
--   5. confere que TODOS os 604 fecham o valor.
-- Nenhum lancamento e alterado, so as partes do rateio (lancamento_rateios).
-- Rodar de novo recusa (a tabela de backup ja existe).
--
-- PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $conserto$
declare
  v_esperado_n     int     := 604;
  v_esperado_falta numeric := 979432.02;
  v_n int; v_falta numeric; v_sem int; v_nao_fecha int;
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
  if to_regclass('public.zz_backup_rateio_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_rateio_2026_11_05: este conserto ja foi rodado. Nao rodo de novo.';
  end if;

  -- 1) os lancamentos a corrigir
  drop table if exists tmp_conj;
  create temp table tmp_conj as
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
       and abs(l.valor - p.soma) > 0.05;

  select count(*), coalesce(sum(valor - soma), 0) into v_n, v_falta from tmp_conj;
  if v_n <> v_esperado_n or abs(v_falta - v_esperado_falta) > 0.05 then
    raise exception 'Esperava % lancamentos faltando R$ %, achei % faltando R$ %. Nao mexo em nada.',
      v_esperado_n, v_esperado_falta, v_n, v_falta;
  end if;

  -- 2) as listas de regras
  drop table if exists tmp_de_para;
  create temp table tmp_de_para as
  select * from (values
      ('__NENHUM__', 0::bigint)
  ) t(forn_norm, funcionario_id);
  drop table if exists tmp_regras_nome;
  create temp table tmp_regras_nome as
  select * from (values
      ('__NENHUM__', 'cana', 1::numeric)
  ) t(forn_norm, atividade, peso);
  drop table if exists tmp_regras_centro;
  create temp table tmp_regras_centro as
  select * from (values
      ('NUTRICAO ANIMAL%', 'pecuaria'),
      ('REPRODUCAO ANIMAL%', 'pecuaria'),
      ('COMPRA DE ANIMAIS%', 'pecuaria')
  ) t(padrao, atividade);

  if exists (select 1 from tmp_regras_nome where atividade not in ('cana', 'graos', 'pecuaria') or peso <= 0)
     or exists (select 1 from tmp_regras_centro where atividade not in ('cana', 'graos', 'pecuaria')) then
    raise exception 'Regra com atividade invalida ou peso zero (use cana, graos, pecuaria). Nao mexo em nada.';
  end if;
  if exists (select 1 from tmp_de_para where forn_norm <> '__NENHUM__'
              and not exists (select 1 from funcionarios f where f.id = tmp_de_para.funcionario_id)) then
    raise exception 'de_para com funcionario que nao existe. Nao mexo em nada.';
  end if;
  if exists (select 1 from tmp_de_para where forn_norm <> '__NENHUM__'
              and not exists (select 1 from funcionario_atividades a
                               where a.funcionario_id = tmp_de_para.funcionario_id and coalesce(a.percentual, 0) > 0)) then
    raise exception 'de_para com funcionario SEM alocacao cadastrada. Nao mexo em nada.';
  end if;
  if exists (select 1 from tmp_de_para group by forn_norm having count(*) > 1) then
    raise exception 'de_para com o mesmo nome do ERP em duas linhas. Nao mexo em nada.';
  end if;

  -- 3) as partes novas (mesma conta da previa)
  drop table if exists tmp_novas;
  create temp table tmp_novas as
  with
  conj as (select * from tmp_conj),
  de_para as (select forn_norm, funcionario_id from tmp_de_para),
regras_nome as (select forn_norm, atividade, peso from tmp_regras_nome),
regras_centro as (select padrao, atividade from tmp_regras_centro),
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
  )
  select id, atividade, fazenda_id, origem, regra, valor, round(fr, 6) as percentual
    from novas;

  -- 4) travas antes de mexer: todos com parte, todos fecham, nenhuma parte zerada
  select count(*) into v_sem from tmp_conj c
   where not exists (select 1 from tmp_novas n where n.id = c.id);
  if v_sem > 0 then
    raise exception '% lancamentos ficariam sem nenhuma parte. Nao mexo em nada.', v_sem;
  end if;
  select count(*) into v_nao_fecha from (
    select c.id from tmp_conj c join tmp_novas n on n.id = c.id
     group by c.id, c.valor having abs(sum(n.valor) - c.valor) > 0.01) z;
  if v_nao_fecha > 0 then
    raise exception '% lancamentos nao fechariam o valor. Nao mexo em nada.', v_nao_fecha;
  end if;
  if exists (select 1 from tmp_novas where valor <= 0) then
    raise exception 'Alguma parte nova ficaria com valor zero ou negativo. Nao mexo em nada.';
  end if;

  -- 5) copia de seguranca das partes antigas (fechada para quem esta logado)
  create table zz_backup_rateio_2026_11_05 as
    select r.* from lancamento_rateios r where r.lancamento_id in (select id from tmp_conj);
  alter table zz_backup_rateio_2026_11_05 enable row level security;
  revoke all on zz_backup_rateio_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_rateio_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_rateio_2026_11_05 from authenticated;
  end if;

  -- 6) troca as partes
  delete from lancamento_rateios where lancamento_id in (select id from tmp_conj);
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    select id, atividade, fazenda_id, percentual, valor, origem from tmp_novas;

  -- 7) confere direto na tabela
  select count(*) into v_nao_fecha
    from tmp_conj c
    join (select lancamento_id, sum(valor) as s from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = c.id
   where abs(c.valor - p.s) > 0.01;
  if v_nao_fecha > 0 then
    raise exception 'Depois de gravar, % lancamentos nao fecham. Desfazendo tudo.', v_nao_fecha;
  end if;
  select count(*) into v_sem from tmp_conj c
   where not exists (select 1 from lancamento_rateios r where r.lancamento_id = c.id);
  if v_sem > 0 then
    raise exception 'Depois de gravar, % lancamentos ficaram sem parte. Desfazendo tudo.', v_sem;
  end if;
end
$conserto$;

-- CONFERENCIA FINAL (uma tabela). Tudo tem que dizer OK.
with partes as (
  select lancamento_id, sum(valor) as soma from lancamento_rateios group by lancamento_id
)
select 'Lancamentos com rateio que NAO fecha o valor (em todo o banco)' as item,
       count(*)::text as valor,
       case when count(*) = 0 then 'OK' else 'PROBLEMA: rode o rateio_02_diagnostico.sql' end as situacao
  from lancamentos_financeiros l join partes p on p.lancamento_id = l.id
 where abs(l.valor - p.soma) > 0.05
union all
select 'R$ que a visao rateada ainda perde (despesa, todos os anos)',
       round(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
             - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0), 2)::text,
       case when abs(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
                   - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0)) <= 1.00
            then 'OK' else 'PROBLEMA' end
union all
select 'Partes antigas guardadas no backup',
       (select count(*) from zz_backup_rateio_2026_11_05)::text,
       'zz_backup_rateio_2026_11_05'
union all
select 'Das contas corrigidas, R$ que ficaram em ' || r.atividade,
       round(sum(r.valor), 2)::text,
       round(100 * sum(r.valor) / (select sum(valor) from lancamento_rateios
                                    where lancamento_id in (select lancamento_id from zz_backup_rateio_2026_11_05)), 1)::text || '%'
  from lancamento_rateios r
 where r.lancamento_id in (select lancamento_id from zz_backup_rateio_2026_11_05)
 group by r.atividade
order by 1;

-- ------------------------------------------------------------
-- PARA DESFAZER (so se precisar; rode separado, depois de conferir):
--   delete from lancamento_rateios
--    where lancamento_id in (select lancamento_id from zz_backup_rateio_2026_11_05);
--   insert into lancamento_rateios
--     (id, lancamento_id, atividade, fazenda_id, cultura_id, percentual, valor, origem, created_at)
--     overriding system value
--     select id, lancamento_id, atividade, fazenda_id, cultura_id, percentual, valor, origem, created_at
--       from zz_backup_rateio_2026_11_05;
-- ------------------------------------------------------------
