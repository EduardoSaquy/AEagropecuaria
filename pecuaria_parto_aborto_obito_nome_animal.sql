-- ============================================================
-- Pecuaria - parto pode ser aborto, obito do bezerro antes da
-- desmama e nome livre do animal (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Pode rodar antes ou depois do app novo: parto normal e animal sem
-- nome gravam sem estas colunas; aborto, obito e nome precisam delas
-- (sem elas o app avisa para rodar este SQL).
--
-- partos.tipo         nascimento (padrao, todos os partos que ja existem) ou aborto
-- partos.data_obito   bezerro que morreu antes da desmama (so em nascimento)
-- partos.causa_obito  texto livre, opcional
-- animais.nome        texto livre: apelido, marca, caracteristica do animal
--
-- So cria colunas e travas. Nao apaga nem muda dado nenhum.
-- Repetivel: rodar de novo nao muda nada.
-- Termina com a conferencia (item / valor / situacao), incluindo os
-- numeros de animal que ainda tem texto (o app agora so aceita algarismos).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table partos  add column if not exists tipo text not null default 'nascimento';
alter table partos  add column if not exists data_obito date;
alter table partos  add column if not exists causa_obito text;
alter table animais add column if not exists nome text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'partos_tipo_valido') then
    alter table partos add constraint partos_tipo_valido
      check (tipo in ('nascimento', 'aborto'));
  end if;
  -- obito so de bezerro que nasceu, e nunca antes do nascimento
  if not exists (select 1 from pg_constraint where conname = 'partos_obito_so_de_nascido') then
    alter table partos add constraint partos_obito_so_de_nascido
      check (data_obito is null or (tipo = 'nascimento' and data_obito >= data));
  end if;
  -- aborto nao tem bezerro
  if not exists (select 1 from pg_constraint where conname = 'partos_aborto_sem_bezerro') then
    alter table partos add constraint partos_aborto_sem_bezerro
      check (tipo <> 'aborto' or (sexo_bezerro is null and raca_bezerro is null));
  end if;
end $$;

-- ============================================================
-- conferencia
-- ============================================================
with colunas as (
  select c.table_name || '.' || c.column_name as nome
    from information_schema.columns c
   where c.table_schema = 'public'
     and (c.table_name, c.column_name) in (('partos','tipo'), ('partos','data_obito'),
                                           ('partos','causa_obito'), ('animais','nome'))
),
travas as (
  select conname from pg_constraint
   where conname in ('partos_tipo_valido', 'partos_obito_so_de_nascido', 'partos_aborto_sem_bezerro')
),
com_texto as (
  select 'animais.numero' as campo, numero as valor from animais where numero !~ '^[0-9]+$'
  union all select 'partos.numero_mae', numero_mae from partos where numero_mae !~ '^[0-9]+$'
  union all select 'diagnosticos_gestacionais.numero_vaca', numero_vaca from diagnosticos_gestacionais where numero_vaca !~ '^[0-9]+$'
  union all select 'reproducao_custos.numero_vaca', numero_vaca from reproducao_custos where numero_vaca !~ '^[0-9]+$'
  union all select 'pesagens_animais.numero_animal', numero_animal from pesagens_animais where numero_animal !~ '^[0-9]+$'
  union all select 'protocolos_inseminacao.numero_animal', numero_animal from protocolos_inseminacao where numero_animal !~ '^[0-9]+$'
),
por_campo as (
  select campo, count(*) as qtd,
         string_agg(distinct valor, ' | ') as exemplos
    from com_texto
   group by campo
)
select 1 as ordem, 'colunas novas (partos.tipo, data_obito, causa_obito, animais.nome)' as item,
       (select count(*) from colunas)::text || ' de 4' as valor,
       case when (select count(*) from colunas) = 4 then 'OK' else 'FALTA COLUNA' end as situacao
union all
select 2, 'travas novas em partos',
       (select count(*) from travas)::text || ' de 3',
       case when (select count(*) from travas) = 3 then 'OK' else 'FALTA TRAVA' end
union all
select 3, 'partos por tipo',
       coalesce((select string_agg(tipo || ': ' || n, ' / ' order by tipo)
                   from (select tipo, count(*) as n from partos group by tipo) x), 'nenhum parto'),
       'OK'
union all
select 4, 'numeros com texto em ' || campo,
       qtd::text || ' -> ' || left(exemplos, 300),
       'CORRIGIR: o numero vira so algarismos e o texto vai no Nome do animal'
  from por_campo
union all
select 5, 'numeros de animal com texto (todas as tabelas)',
       coalesce((select sum(qtd) from por_campo), 0)::text,
       case when not exists (select 1 from por_campo) then 'OK' else 'ver linhas acima' end
order by 1, 2;
