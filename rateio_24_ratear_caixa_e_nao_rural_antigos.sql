-- ============================================================
-- AJUSTE: ratear em tres partes iguais o que ainda esta SEM atividade nas receitas antigas
--         (movimentos de caixa e "outros recebimentos nao relacionados a atividade rural")
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Depois da rateio_18_sem_atividade.sql (a conferencia final).
--
-- DECISAO DO EDUARDO (05/11/2026): ratear tambem estes dois grupos entre Pecuaria, Cana e
-- Graos. Antes eles tinham ficado de fora de proposito, porque NAO sao receita de atividade;
-- ele decidiu o contrario, sabendo disso.
--
-- EFEITO NOS NUMEROS: as telas por atividade (Resultados de Pecuaria, Cana e Graos) passam a
-- somar R$ 637.894,77 de entradas de caixa como receita, um terco em cada. Quase tudo e de
-- 2022/23 (R$ 327 mil) e 2023/24 (R$ 293 mil). A aba Empresa NAO muda (ela ja somava tudo).
--
-- O QUE ENTRA (39 receitas, R$ 637.894,77, todas anteriores a maio/2026, 'geral' sem partes):
--   movimentos de caixa ........... 32 lancamentos R$ 620.569,54 (ajuste de saldo bancario,
--                                   resgate de aplicacao, estorno, outras movimentacoes, aporte,
--                                   rendimentos)
--   outros recebimentos nao relacionados a atividade rural .. 7 lancamentos R$ 17.325,23
-- NAO entram: os centavos (valor menor que R$ 1,00) e nada da safra 2026/27.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. acha as receitas 'geral' SEM partes, anteriores a 2026-05, desses dois grupos;
--   2. recusa se nao forem exatamente 32 + 7 lancamentos, R$ 620.569,54 + R$ 17.325,23;
--   3. guarda copia em zz_backup_ajuste8_lanc_2026_11_05 (fechada: so o dono do banco le);
--   4. grava tres partes iguais por lancamento (Cana leva o centavo que sobra);
--   5. confere que cada uma fecha o valor.
-- Nenhum lancamento e alterado, so as partes do rateio. Rodar de novo recusa.
--
-- PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $ajuste$
declare
  v_n_caixa int; v_valor_caixa numeric; v_n_rural int; v_valor_rural numeric; v_n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_ajuste8_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste8_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  -- 1) os lancamentos alvo
  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  with base as (
    select l.id, l.valor,
           coalesce(l.mes, to_char(coalesce(l.data, l.vencimento), 'YYYY-MM')) as mes_ref,
           btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
             E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm
      from lancamentos_financeiros l
      left join centros_custo cc on cc.id = l.centro_custo_id
     where l.tipo = 'receita' and l.atividade = 'geral' and abs(l.valor) >= 1
       and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)
  )
  select b.id, b.valor,
         case when b.centro_norm like 'OUTROS RECEBIMENTOS NAO RELACIONADOS%' then 'rural'
              else 'caixa' end as grupo
    from base b
   where b.mes_ref is not null and b.mes_ref < '2026-05'
     and (b.centro_norm like 'AJUSTE DE SALDO%' or b.centro_norm like 'RESGATE DE APLICACOES%'
          or b.centro_norm like 'ESTORNO%' or b.centro_norm like 'OUTRAS MOVIMENTACOES DE CAIXA%'
          or b.centro_norm like 'APORTE DE CAPITAL%' or b.centro_norm like 'RENDIMENTOS DE APLICACOES%'
          or b.centro_norm like 'OUTROS RECEBIMENTOS NAO RELACIONADOS%');

  -- 2) trava: exatamente o que a conferencia mostrou
  select count(*), coalesce(sum(valor), 0) into v_n_caixa, v_valor_caixa from tmp_alvo where grupo = 'caixa';
  select count(*), coalesce(sum(valor), 0) into v_n_rural, v_valor_rural from tmp_alvo where grupo = 'rural';
  if v_n_caixa <> 32 or abs(v_valor_caixa - 620569.54) > 0.05
     or v_n_rural <> 7 or abs(v_valor_rural - 17325.23) > 0.05 then
    raise exception 'Esperava 32 lancamentos de caixa (R$ 620569.54) e 7 nao relacionados (R$ 17325.23); achei % (R$ %) e % (R$ %). Nao mexo em nada.',
      v_n_caixa, v_valor_caixa, v_n_rural, v_valor_rural;
  end if;

  -- 3) copia de seguranca (fechada para quem esta logado)
  create table zz_backup_ajuste8_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id in (select id from tmp_alvo);
  alter table zz_backup_ajuste8_lanc_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste8_lanc_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste8_lanc_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste8_lanc_2026_11_05 from authenticated;
  end if;

  -- 4) tres partes iguais; graos e pecuaria levam o valor arredondado, cana leva o resto
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    select a.id, x.atividade, null, 0.333333,
           case when x.atividade = 'cana' then a.valor - 2 * round(a.valor / 3, 2) else round(a.valor / 3, 2) end,
           'administrativo'
      from tmp_alvo a
     cross join (values ('cana'), ('graos'), ('pecuaria')) as x(atividade);

  -- 5) confere direto na tabela
  select count(*) into v_n
    from tmp_alvo a
    join (select lancamento_id, count(*) as k, sum(valor) as s from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = a.id
   where p.k <> 3 or abs(a.valor - p.s) > 0.005;
  if v_n > 0 then
    raise exception 'Depois de gravar, % lancamentos nao ficaram com tres partes que fecham o valor. Desfazendo tudo.', v_n;
  end if;
end
$ajuste$;

-- CONFERENCIA FINAL (uma tabela). Tudo tem que dizer OK.
select 'Receitas antigas rateadas em tres partes iguais (copia no backup)' as item,
       (select count(*) from zz_backup_ajuste8_lanc_2026_11_05)::text as valor,
       case when (select count(*) from zz_backup_ajuste8_lanc_2026_11_05) = 39 then 'OK' else 'PROBLEMA' end as situacao
union all
select 'R$ rateados',
       'R$ ' || (select round(sum(valor), 2) from zz_backup_ajuste8_lanc_2026_11_05)::text,
       case when abs((select sum(valor) from zz_backup_ajuste8_lanc_2026_11_05) - 637894.77) < 0.05 then 'OK' else 'PROBLEMA' end
union all
select 'Receita que ainda esta sem atividade (so centavos tem que sobrar)',
       'R$ ' || coalesce(round(sum(valor), 2), 0)::text,
       case when coalesce(sum(valor), 0) < 5 then 'OK' else 'PROBLEMA: rode o rateio_18' end
  from lancamentos_rateados
 where tipo = 'receita' and atividade not in ('pecuaria', 'cana', 'graos')
union all
select 'Lancamentos com rateio que NAO fecha o valor (em todo o banco)',
       count(*)::text, case when count(*) = 0 then 'OK' else 'PROBLEMA: rode o rateio_02_diagnostico.sql' end
  from lancamentos_financeiros l
  join (select lancamento_id, sum(valor) as soma from lancamento_rateios group by lancamento_id) p
    on p.lancamento_id = l.id
 where abs(l.valor - p.soma) > 0.05
order by 1;

-- ------------------------------------------------------------
-- PARA DESFAZER (so se precisar; rode separado, depois de conferir):
--   delete from lancamento_rateios
--    where lancamento_id in (select id from zz_backup_ajuste8_lanc_2026_11_05);
-- ------------------------------------------------------------
