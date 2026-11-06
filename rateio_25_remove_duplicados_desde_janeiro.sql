-- ============================================================
-- EXCLUSAO: lancamentos repetidos de janeiro a abril/2026 (lancada a mao x importacao), fica um so
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Depois de ver o resultado da rateio_17_pares_desde_janeiro.sql (a mesma regra de par).
--
-- O QUE E: a rateio_14 e a rateio_15 olhavam de 15/04/2026 em diante. A rateio_17 olhou desde
-- 01/01/2026 e achou 56 pares: a mesma conta lancada a mao (migrada do app da Pecuaria) e
-- importada do ERP, mesmo fornecedor, mesmo valor, MESMO DIA (R$ 769.448,59).
--
-- ESTE SCRIPT TRATA DE 50 PARES, R$ 106.279,83 (despesas e as parcelas da cooperativa).
-- FICAM DE FORA, de proposito:
--   . as 5 compras de INVESTIMENTO (compra de matrizes e consorcio, R$ 662.924,46): enquanto o
--     Eduardo nao confirmar se cada pagamento saiu do banco uma vez so, as duas linhas ficam
--     (#490/#20585, #491/#20586, #497/#20805, #496/#20806 e #500/#21098);
--   . o Auto Posto de R$ 244,30 de 15/04 (#3018 e #21300): eram duas compras iguais, cada uma
--     lancada a mao e importada; a rateio_15 ja tirou a repeticao de uma delas, e as duas que
--     sobraram sao as duas compras.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. acha os pares como a rateio_17, menos os 6 acima;
--   2. recusa se nao forem EXATAMENTE 50 pares, R$ 106.279,83, todos da classe B
--      (lancada a mao x importacao); qualquer par com documento do ERP (classe A) recusa;
--   3. escolhe qual das duas linhas de cada par fica:
--        se a importacao ja foi refeita pelo rateio_05_conserto (esta em
--        zz_backup_rateio_2026_11_05): fica a importacao e sai a lancada a mao;
--        se NAO foi (competencia antiga, o caso de todos estes): fica a LANCADA A MAO
--        (e o registro nativo; regra de agosto/2026) e sai a importacao;
--   4. NAO apaga a linha que tiver contrato de financiamento, lote, abate ou areas da
--      pecuaria, nem a que outro registro aponta: o par fica inteiro e aparece na lista;
--   5. guarda copia completa em zz_backup_dup2_2026_11_05 (lancamentos),
--      zz_backup_dup2_rateios_2026_11_05 (partes) e zz_backup_dup2_pares_2026_11_05
--      (a decisao de cada par), fechadas: so o dono do banco le;
--   6. apaga (as partes do rateio saem junto) e confere.
-- Rodar de novo recusa (a copia ja existe). PARA DESFAZER: ver o fim deste arquivo.
--
-- ATENCAO: em 17 dos 50 pares a importacao esta DIVIDIDA entre atividades (combustivel e
-- cooperativa, R$ 45.451,61) e a lancada a mao esta inteira em Pecuaria. Ficando a lancada a
-- mao, esses R$ 45.451,61 passam a contar 100% em Pecuaria.
-- ============================================================

do $dup$
declare
  v_a_n int := 0;   v_a_valor numeric := 0.00;
  v_b_n int := 50;  v_b_valor numeric := 106279.83;
  v_n int; v_valor numeric; v_ids bigint[]; v_ref bigint; v_apagados int; r record; t text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_dup2_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_dup2_2026_11_05: esta exclusao de janeiro a abril ja foi feita. Nao rodo de novo.';
  end if;
  if to_regclass('public.zz_backup_rateio_2026_11_05') is null then
    raise exception 'Falta o backup zz_backup_rateio_2026_11_05 (o rateio_05_conserto.sql). Sem ele nao sei qual importacao ja segue as regras. Nao mexo em nada.';
  end if;

  -- 1) a base e os pares (mesma regra da rateio_14)
  drop table if exists tmp_base;
  create temp table tmp_base as
  select l.id, l.valor, l.erp_id,
         substring(l.observacao from '^ERP [0-9]+') as documento,
         coalesce(l.data, l.vencimento) as quando,
         (l.contrato is null and l.lote_id is null and l.abate_id is null
            and coalesce(l.areas::text, '') in ('', '{}', '[]', 'null')) as limpo,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm
    from lancamentos_financeiros l
   where l.valor > 0 and l.tipo in ('despesa', 'investimento')
     and coalesce(l.data, l.vencimento) >= date '2026-01-01';

  drop table if exists tmp_pares;
  create temp table tmp_pares as
  select o_id, i_id, classe
    from (select o.id as o_id, i.id as i_id,
                 case when o.documento is not null and o.documento = i.documento then 'A' else 'B' end as classe,
                 row_number() over (partition by o.id order by abs(o.quando - i.quando), i.id) as rk
            from tmp_base o
            join tmp_base i on i.erp_id is not null and o.erp_id is null
                           and i.forn_norm = o.forn_norm and i.valor = o.valor
                           and abs(o.quando - i.quando) <= 7
                           and (o.documento is null or o.documento = i.documento)) x
   where rk = 1
     and not (o_id = 3018 and i_id = 21300)    -- as duas compras iguais de 15/04: nao e repeticao
     and not (o_id = 490 and i_id = 20585)     -- investimento: espera a confirmacao dele
     and not (o_id = 491 and i_id = 20586)     -- idem
     and not (o_id = 497 and i_id = 20805)     -- idem
     and not (o_id = 496 and i_id = 20806)     -- idem
     and not (o_id = 500 and i_id = 21098);    -- idem (consorcio)

  -- 2) trava: exatamente o que foi conferido
  select count(*), coalesce(sum(o.valor), 0) into v_n, v_valor
    from tmp_pares p join tmp_base o on o.id = p.o_id where p.classe = 'A';
  if v_n <> v_a_n or abs(v_valor - v_a_valor) > 0.05 then
    raise exception 'Classe A: esperava % pares, R$ %; achei % pares, R$ %. Nao mexo em nada.', v_a_n, v_a_valor, v_n, v_valor;
  end if;
  select count(*), coalesce(sum(o.valor), 0) into v_n, v_valor
    from tmp_pares p join tmp_base o on o.id = p.o_id where p.classe = 'B';
  if v_n <> v_b_n or abs(v_valor - v_b_valor) > 0.05 then
    raise exception 'Classe B: esperava % pares, R$ %; achei % pares, R$ %. Nao mexo em nada.', v_b_n, v_b_valor, v_n, v_valor;
  end if;

  -- 3) qual linha de cada par fica
  drop table if exists tmp_refeita;
  create temp table tmp_refeita as select distinct lancamento_id as id from zz_backup_rateio_2026_11_05;

  drop table if exists tmp_dec;
  create temp table tmp_dec as
  with b as (
    select p.o_id, p.i_id, p.classe, (p.i_id in (select id from tmp_refeita)) as refeita,
           min(p.o_id) over (partition by p.i_id) as o_primeira
      from tmp_pares p
  )
  select b.o_id, b.i_id, b.classe,
         case when b.classe = 'A' or b.refeita then b.o_id
              when b.o_id = b.o_primeira then b.i_id
              else b.o_id end as apaga_id,
         case when b.classe = 'A' or b.refeita then b.i_id
              else b.o_primeira end as mantem_id,
         case when b.classe = 'A' then 'A: mesma conta do ERP lancada duas vezes; fica a importacao'
              when b.refeita then 'B: a importacao ja segue as regras de hoje; sai a lancada a mao'
              when b.o_id = b.o_primeira then 'B: importacao de competencia antiga, sem regra aplicada; fica a lancada a mao'
              else 'B: lancada a mao repetida (mesmo dia e valor); fica uma so' end as motivo,
         false as pulado, null::text as motivo_pulo
    from b;

  -- 4) a linha a apagar nao pode carregar algo que a outra nao tem
  update tmp_dec d
     set pulado = true,
         motivo_pulo = 'a linha a apagar tem contrato, lote, abate ou areas da pecuaria: nao apaguei, decida'
    from tmp_base x
   where x.id = d.apaga_id and not x.limpo;

  select count(*) into v_n from tmp_dec a join tmp_dec m on m.mantem_id = a.apaga_id
   where not a.pulado and not m.pulado;
  if v_n > 0 then
    raise exception 'Um mesmo lancamento seria apagado e mantido ao mesmo tempo (% casos). Nao mexo em nada.', v_n;
  end if;
  select count(*) - count(distinct apaga_id) into v_n from tmp_dec where not pulado;
  if v_n > 0 then
    raise exception 'O mesmo lancamento aparece para apagar mais de uma vez (% casos). Nao mexo em nada.', v_n;
  end if;

  select coalesce(array_agg(apaga_id order by apaga_id), '{}') into v_ids from tmp_dec where not pulado;

  -- 5) nenhum outro registro pode apontar para o que vai ser apagado
  for r in
    select c.conrelid::regclass::text as tabela, a.attname::text as coluna
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.lancamentos_financeiros'::regclass
       and c.conrelid <> 'public.lancamento_rateios'::regclass
       and array_length(c.conkey, 1) = 1
  loop
    execute format('select count(*) from %s where %I = any($1)', r.tabela, r.coluna) into v_ref using v_ids;
    if v_ref > 0 then
      raise exception 'A tabela % tem % registros apontando para lancamentos que seriam apagados. Nao mexo em nada.', r.tabela, v_ref;
    end if;
  end loop;

  -- 6) copia completa antes de apagar (fechada para quem esta logado)
  create table zz_backup_dup2_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id = any(v_ids);
  create table zz_backup_dup2_rateios_2026_11_05 as
    select x.* from lancamento_rateios x where x.lancamento_id = any(v_ids);
  create table zz_backup_dup2_pares_2026_11_05 as
    select d.*, o.forn_norm as fornecedor, o.valor
      from tmp_dec d join tmp_base o on o.id = d.o_id;
  foreach t in array array['zz_backup_dup2_2026_11_05', 'zz_backup_dup2_rateios_2026_11_05', 'zz_backup_dup2_pares_2026_11_05']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public', t);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke all on %I from anon', t);
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      execute format('revoke all on %I from authenticated', t);
    end if;
  end loop;

  -- 7) apaga e confere
  delete from lancamentos_financeiros where id = any(v_ids);
  get diagnostics v_apagados = row_count;
  if v_apagados <> coalesce(cardinality(v_ids), 0) then
    raise exception 'Apaguei % linhas e eram % para apagar. Desfazendo tudo.', v_apagados, cardinality(v_ids);
  end if;
  select count(*) into v_n from lancamentos_financeiros where id = any(v_ids);
  if v_n > 0 then
    raise exception 'Depois de apagar, % lancamentos ainda existem. Desfazendo tudo.', v_n;
  end if;
  select count(*) into v_n
    from tmp_dec d
   where not d.pulado and not exists (select 1 from lancamentos_financeiros l where l.id = d.mantem_id);
  if v_n > 0 then
    raise exception 'Depois de apagar, % lancamentos que deviam ficar sumiram. Desfazendo tudo.', v_n;
  end if;
end
$dup$;

-- CONFERENCIA FINAL (uma tabela). Os resumos em cima, cada par embaixo.
with
d as (select * from zz_backup_dup2_pares_2026_11_05),
partes as (
  select lancamento_id, string_agg(atividade || ' R$ ' || soma, ' / ' order by atividade) as txt
    from (select lancamento_id, atividade, round(sum(valor), 2)::text as soma
            from lancamento_rateios group by lancamento_id, atividade) z
   group by lancamento_id
),
vivo as (
  select l.id,
         case when l.erp_id is not null then 'importacao do ERP'
              when l.criado_por like 'ERP (acerto%' then 'acerto de 21/10'
              else 'lancada a mao' end as origem,
         coalesce(p.txt, 'inteiro em ' || l.atividade) as como
    from lancamentos_financeiros l left join partes p on p.lancamento_id = l.id
   where l.id in (select mantem_id from d)
),
morto as (
  select b.id,
         case when b.erp_id is not null then 'importacao do ERP'
              when b.criado_por like 'ERP (acerto%' then 'acerto de 21/10'
              else 'lancada a mao' end as origem
    from zz_backup_dup2_2026_11_05 b
),
resumo as (
  select 1 as ord, 'Lancamentos apagados (copia no backup)' as item,
         (select count(*) from zz_backup_dup2_2026_11_05)::text as valor,
         'R$ ' || (select round(coalesce(sum(valor), 0), 2) from zz_backup_dup2_2026_11_05)::text as situacao
  union all
  select 2, 'Classe A apagados (acerto repetido da importacao)',
         count(*)::text, 'R$ ' || round(coalesce(sum(valor), 0), 2)::text
    from d where classe = 'A' and not pulado
  union all
  select 3, 'Classe B apagados (lancada a mao x importacao)',
         count(*)::text, 'R$ ' || round(coalesce(sum(valor), 0), 2)::text
    from d where classe = 'B' and not pulado
  union all
  select 4, 'Pares que NAO apaguei (ficaram os dois, decida)',
         count(*)::text, case when count(*) = 0 then 'OK' else 'veja a lista abaixo' end
    from d where pulado
  union all
  select 5, 'Pares que ainda existem inteiros (tem que bater com a linha de cima)',
         count(*)::text,
         case when count(*) = (select count(*) from d where pulado) then 'OK' else 'PROBLEMA' end
    from d
   where exists (select 1 from lancamentos_financeiros l where l.id = d.o_id)
     and exists (select 1 from lancamentos_financeiros l where l.id = d.i_id)
  union all
  select 6, 'Partes de rateio apagadas junto (copia no backup)',
         (select count(*) from zz_backup_dup2_rateios_2026_11_05)::text, 'zz_backup_dup2_rateios_2026_11_05'
  union all
  select 7, 'Lancamentos com rateio que NAO fecha o valor (em todo o banco)',
         count(*)::text,
         case when count(*) = 0 then 'OK' else 'PROBLEMA: rode o rateio_02_diagnostico.sql' end
    from lancamentos_financeiros l
    join (select lancamento_id, sum(valor) as soma from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = l.id
   where abs(l.valor - p.soma) > 0.05
  union all
  select 8, 'R$ que a visao rateada ainda perde (despesa, todos os anos)',
         round(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
               - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0), 2)::text,
         case when abs(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
                     - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0)) <= 1.00
              then 'OK' else 'PROBLEMA' end
),
detalhe as (
  select 9 as ord,
         d.fornecedor || ' | R$ ' || round(d.valor, 2)::text || ' | par ' || d.o_id || ' e ' || d.i_id as item,
         case when d.pulado then 'NAO apaguei'
              else 'apagada: ' || m.origem || ' #' || d.apaga_id end as valor,
         case when d.pulado then d.motivo_pulo
              else 'ficou: ' || v.origem || ' #' || d.mantem_id || ' (' || v.como || ') | ' || d.motivo end as situacao
    from d
    left join morto m on m.id = d.apaga_id
    left join vivo v on v.id = d.mantem_id
)
select item, valor, situacao
  from (select * from resumo union all select * from detalhe) z
 order by ord, item;

-- ------------------------------------------------------------
-- PARA DESFAZER (so se precisar; rode separado, depois de conferir):
--   insert into lancamentos_financeiros overriding system value
--     select * from zz_backup_dup2_2026_11_05;
--   insert into lancamento_rateios overriding system value
--     select * from zz_backup_dup2_rateios_2026_11_05;
-- ------------------------------------------------------------
