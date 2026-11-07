-- ============================================================
-- EXCLUSAO: tres pares de lancamentos que estavam lancados duas vezes (adubo, nutricao animal, combustivel)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- DECISAO DO EDUARDO (07/11/2026), depois de ver os seis lancamentos lado a lado:
--   par 1: #14296 e #14298, R$ 194.320,00 cada, adubo ............ lancado duas vezes; e da CANA
--   par 2: #17113 e #17115, R$ 50.000,00 cada, nutricao animal ... lancada duas vezes; e da PECUARIA
--   par 3: #2570  e #2571,  R$ 11.100,00 cada, combustivel ....... lancado duas vezes (a mao, 15/03/2026); e da CANA
-- Os dois primeiros pares tem codigos do ERP diferentes: o ERP tambem tem os dois, entao o erro e de la.
-- Se o ERP for reimportado, a linha apagada VOLTA: corrija la tambem, ou apague de novo.
--
-- O QUE FAZ (tudo ou nada nas travas gerais; um bloco so)
--   1. confere os seis lancamentos (valor exato de cada um); se algum faltar ou estiver diferente, RECUSA e nao mexe em nada;
--   2. de cada par fica o de MENOR numero e sai o outro (as duas linhas sao identicas);
--   3. um par so e tratado se as duas linhas forem identicas (tipo, centro, fornecedor, descricao, fazenda, datas),
--      nao tiverem contrato, lote, abate nem areas da pecuaria, e nada apontar para a que sai: senao o par
--      NAO e tocado e aparece na lista final dizendo por que (os outros seguem);
--   4. a linha que FICA passa a ter a atividade decidida:
--        - se estava dividida entre atividades ('geral' com partes), as partes viram UMA parte da atividade decidida
--          (mesmo modelo da rateio_27);
--        - se estava inteira em outra atividade, a atividade dela troca; se ja estava na certa, nao muda;
--   5. guarda copia de TODAS as linhas dos pares tratados (as que saem e as que ficam, com as partes) em
--      zz_backup_dup4_2026_11_07, zz_backup_dup4_rateios_2026_11_07 e zz_backup_dup4_pares_2026_11_07
--      (fechadas: so o dono do banco le);
--   6. apaga, ajusta e confere.
-- Rodar de novo recusa. PARA DESFAZER: ver o fim deste arquivo.
--
-- Efeito: o Financeiro perde R$ 255.420,00 que estava contado duas vezes (R$ 194.320,00 na Cana, R$ 50.000,00 na
-- Pecuaria e R$ 11.100,00 no combustivel, que passa a contar na Cana).
-- ============================================================

do $dup$
declare
  v_n int; v_valor numeric; v_ref bigint; v_ids bigint[]; v_apagados int; v_motivos text;
  r record; f record; t text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_dup4_2026_11_07') is not null then
    raise exception 'Ja existe zz_backup_dup4_2026_11_07: esta exclusao dos tres pares ja foi feita. Nao rodo de novo.';
  end if;

  -- 1) os tres pares: quem fica, quem sai, o valor conferido e a atividade decidida
  drop table if exists tmp_par;
  create temp table tmp_par (
    par int primary key, nome text, valor numeric, mantem_id bigint, apaga_id bigint, atividade_final text,
    pulado boolean not null default false, motivo_pulo text);
  insert into tmp_par (par, nome, valor, mantem_id, apaga_id, atividade_final) values
    (1, 'adubo (Cana)',                  194320.00, 14296, 14298, 'cana'),
    (2, 'nutricao animal (Pecuaria)',     50000.00, 17113, 17115, 'pecuaria'),
    (3, 'combustivel (Cana)',             11100.00,  2570,  2571, 'cana');

  -- 2) trava: os seis lancamentos existem, com o valor conferido
  select count(*) into v_n
    from tmp_par p
   where (select count(*) from lancamentos_financeiros l
           where l.id in (p.mantem_id, p.apaga_id) and abs(l.valor - p.valor) < 0.005) <> 2;
  if v_n > 0 then
    raise exception 'Esperava os seis lancamentos conferidos (3 pares de valores iguais); % par(es) nao estao como a conferencia mostrou. Nao mexo em nada.', v_n;
  end if;

  -- 3) cada par so e tratado se for mesmo uma repeticao limpa
  update tmp_par p
     set pulado = true,
         motivo_pulo = 'as duas linhas nao sao identicas (tipo, centro, fornecedor, descricao, fazenda ou datas): confira e decida'
    from lancamentos_financeiros m, lancamentos_financeiros d
   where m.id = p.mantem_id and d.id = p.apaga_id
     and not (m.tipo is not distinct from d.tipo
          and m.centro_custo_id is not distinct from d.centro_custo_id
          and m.fornecedor is not distinct from d.fornecedor
          and m.descricao is not distinct from d.descricao
          and m.fazenda_id is not distinct from d.fazenda_id
          and m.data is not distinct from d.data
          and m.mes is not distinct from d.mes
          and m.vencimento is not distinct from d.vencimento);

  update tmp_par p
     set pulado = true,
         motivo_pulo = 'uma das linhas tem contrato, lote, abate ou areas da pecuaria: nao mexi, decida'
    from lancamentos_financeiros l
   where not p.pulado and l.id in (p.mantem_id, p.apaga_id)
     and not (l.contrato is null and l.lote_id is null and l.abate_id is null
              and coalesce(l.areas::text, '') in ('', '{}', '[]', 'null'));

  -- a linha que fica: 'geral' tem de ter as partes; fora disso nao pode ter partes
  update tmp_par p
     set pulado = true,
         motivo_pulo = 'a linha que ficaria nao esta no formato esperado (geral com partes que fecham, ou inteira sem partes): nao mexi, decida'
    from lancamentos_financeiros l
   where not p.pulado and l.id = p.mantem_id
     and not ((l.atividade = 'geral'
               and exists (select 1 from lancamento_rateios x where x.lancamento_id = l.id)
               and abs(l.valor - (select sum(x.valor) from lancamento_rateios x where x.lancamento_id = l.id)) <= 0.05)
           or (l.atividade <> 'geral'
               and not exists (select 1 from lancamento_rateios x where x.lancamento_id = l.id)));

  -- nada pode apontar para a linha que sai
  for r in select par, apaga_id from tmp_par where not pulado order by par loop
    for f in
      select c.conrelid::regclass::text as tabela, a.attname::text as coluna
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and c.confrelid = 'public.lancamentos_financeiros'::regclass
         and c.conrelid <> 'public.lancamento_rateios'::regclass
         and array_length(c.conkey, 1) = 1
    loop
      execute format('select count(*) from %s where %I = $1', f.tabela, f.coluna) into v_ref using r.apaga_id;
      if v_ref > 0 then
        update tmp_par
           set pulado = true,
               motivo_pulo = 'a tabela ' || f.tabela || ' tem registro apontando para a linha que sairia: nao apaguei, decida'
         where par = r.par;
        exit;
      end if;
    end loop;
  end loop;

  select coalesce(array_agg(apaga_id order by apaga_id), '{}') into v_ids from tmp_par where not pulado;
  if cardinality(v_ids) = 0 then
    select string_agg('par ' || par || ': ' || motivo_pulo, ' | ' order by par) into v_motivos from tmp_par;
    raise exception 'Nenhum dos tres pares pode ser tratado (%). Nao mexo em nada.', v_motivos;
  end if;

  -- 4) copia completa antes de mexer (fechada para quem esta logado)
  create table zz_backup_dup4_2026_11_07 as
    select l.* from lancamentos_financeiros l
     where l.id in (select mantem_id from tmp_par where not pulado union all select apaga_id from tmp_par where not pulado);
  create table zz_backup_dup4_rateios_2026_11_07 as
    select x.* from lancamento_rateios x where x.lancamento_id in (select id from zz_backup_dup4_2026_11_07);
  create table zz_backup_dup4_pares_2026_11_07 as select * from tmp_par;
  foreach t in array array['zz_backup_dup4_2026_11_07', 'zz_backup_dup4_rateios_2026_11_07', 'zz_backup_dup4_pares_2026_11_07']
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

  -- 5) apaga a repetida (as partes saem junto)
  delete from lancamentos_financeiros where id = any(v_ids);
  get diagnostics v_apagados = row_count;
  if v_apagados <> cardinality(v_ids) then
    raise exception 'Apaguei % linhas e eram % para apagar. Desfazendo tudo.', v_apagados, cardinality(v_ids);
  end if;
  select count(*) into v_n from lancamentos_financeiros where id = any(v_ids);
  if v_n > 0 then
    raise exception 'Depois de apagar, % lancamentos ainda existem. Desfazendo tudo.', v_n;
  end if;
  select count(*) into v_n
    from tmp_par p
   where not p.pulado and not exists (select 1 from lancamentos_financeiros l where l.id = p.mantem_id);
  if v_n > 0 then
    raise exception 'Depois de apagar, % lancamentos que deviam ficar sumiram. Desfazendo tudo.', v_n;
  end if;

  -- 6) a linha que fica passa a ter a atividade decidida
  for r in
    select p.par, p.mantem_id, p.atividade_final, l.atividade as atual, l.valor, l.fazenda_id
      from tmp_par p join lancamentos_financeiros l on l.id = p.mantem_id
     where not p.pulado order by p.par
  loop
    if r.atual = 'geral' then
      delete from lancamento_rateios where lancamento_id = r.mantem_id;
      insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
        values (r.mantem_id, r.atividade_final, r.fazenda_id, 1, r.valor, 'administrativo');
    elsif r.atual <> r.atividade_final then
      update lancamentos_financeiros set atividade = r.atividade_final where id = r.mantem_id;
    end if;
  end loop;

  select count(*) into v_n
    from tmp_par p
   where not p.pulado
     and not (case when exists (select 1 from lancamento_rateios x where x.lancamento_id = p.mantem_id)
                   then not exists (select 1 from lancamento_rateios x where x.lancamento_id = p.mantem_id and x.atividade <> p.atividade_final)
                        and (select count(*) from lancamento_rateios x where x.lancamento_id = p.mantem_id) = 1
                        and abs((select sum(x.valor) from lancamento_rateios x where x.lancamento_id = p.mantem_id) - p.valor) < 0.005
                   else exists (select 1 from lancamentos_financeiros l where l.id = p.mantem_id and l.atividade = p.atividade_final)
              end);
  if v_n > 0 then
    raise exception '% linha(s) que ficam nao ficaram na atividade decidida. Desfazendo tudo.', v_n;
  end if;
end
$dup$;

-- CONFERENCIA FINAL (uma tabela). Os resumos em cima, cada par embaixo.
with
d as (select * from zz_backup_dup4_pares_2026_11_07),
partes as (
  select lancamento_id, string_agg(atividade || ' R$ ' || soma, ' / ' order by atividade) as txt
    from (select lancamento_id, atividade, round(sum(valor), 2)::text as soma
            from lancamento_rateios group by lancamento_id, atividade) z
   group by lancamento_id
),
vivo as (
  select p.par,
         coalesce(x.txt, 'inteiro em ' || l.atividade) as como,
         case when exists (select 1 from lancamento_rateios r where r.lancamento_id = p.mantem_id)
              then not exists (select 1 from lancamento_rateios r where r.lancamento_id = p.mantem_id and r.atividade <> p.atividade_final)
              else l.atividade = p.atividade_final end as certo
    from d p
    join lancamentos_financeiros l on l.id = p.mantem_id
    left join partes x on x.lancamento_id = l.id
   where not p.pulado
),
resumo as (
  select 1 as ord, 'Lancamentos apagados (copia no backup)' as item,
         count(*)::text as valor,
         'R$ ' || round(coalesce(sum(valor), 0), 2)::text as situacao
    from d where not pulado
  union all
  select 2, 'Pares que NAO tratei (ficaram os dois, decida)',
         count(*)::text, case when count(*) = 0 then 'OK' else 'veja a lista abaixo' end
    from d where pulado
  union all
  select 3, 'Linhas que ficaram na atividade decidida',
         count(*)::text, case when bool_and(certo) then 'OK' else 'PROBLEMA' end
    from vivo
  union all
  select 4, 'Copias guardadas no backup (lancamentos / partes)',
         (select count(*) from zz_backup_dup4_2026_11_07)::text || ' / ' || (select count(*) from zz_backup_dup4_rateios_2026_11_07)::text,
         'zz_backup_dup4_*_2026_11_07'
  union all
  select 5, 'Lancamentos com rateio que NAO fecha o valor (em todo o banco)',
         count(*)::text,
         case when count(*) = 0 then 'OK' else 'PROBLEMA: rode o rateio_02_diagnostico.sql' end
    from lancamentos_financeiros l
    join (select lancamento_id, sum(valor) as soma from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = l.id
   where abs(l.valor - p.soma) > 0.05
  union all
  select 6, 'R$ que a visao rateada ainda perde (despesa, todos os anos)',
         round(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
               - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0), 2)::text,
         case when abs(coalesce((select sum(valor) from lancamentos_financeiros where tipo = 'despesa'), 0)
                     - coalesce((select sum(valor) from lancamentos_rateados where tipo = 'despesa'), 0)) <= 1.00
              then 'OK' else 'PROBLEMA' end
),
detalhe as (
  select 9 as ord,
         'par ' || d.par || ' | ' || d.nome || ' | R$ ' || round(d.valor, 2)::text as item,
         case when d.pulado then 'NAO tratei' else 'apagada #' || d.apaga_id end as valor,
         case when d.pulado then d.motivo_pulo
              else 'ficou #' || d.mantem_id || ' (' || v.como || ') | ' || case when v.certo then 'OK' else 'PROBLEMA' end end as situacao
    from d
    left join vivo v on v.par = d.par
)
select item, valor, situacao
  from (select * from resumo union all select * from detalhe) z
 order by ord, item;

-- ------------------------------------------------------------
-- PARA DESFAZER (so se precisar; rode separado, depois de conferir):
--   delete from lancamento_rateios where lancamento_id in (select id from zz_backup_dup4_2026_11_07);
--   update lancamentos_financeiros l set atividade = b.atividade
--     from zz_backup_dup4_2026_11_07 b where b.id = l.id;
--   insert into lancamentos_financeiros overriding system value
--     select b.* from zz_backup_dup4_2026_11_07 b
--      where not exists (select 1 from lancamentos_financeiros x where x.id = b.id);
--   insert into lancamento_rateios overriding system value
--     select * from zz_backup_dup4_rateios_2026_11_07;
-- ------------------------------------------------------------
