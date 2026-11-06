-- ============================================================
-- AJUSTE: receitas ANTERIORES a safra 2026/27 que estavam sem atividade: tres partes iguais
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Depois da rateio_19_lista_sem_atividade.sql.
--
-- DECISAO DO EDUARDO (05/11/2026): "o que for da safra 26/27 para tras pode ratear entre as
-- tres atividades". A safra 2026/27 NAO entra aqui: ele decide uma a uma.
--
-- O QUE ENTRA (10 receitas, R$ 28.865,55, todas anteriores a maio/2026, hoje 'geral' sem partes):
--   venda fisica de producao .......... 6 lancamentos  R$ 13.810,00
--   prestacao de servicos agropecuarios  1 lancamento  R$  1.350,00
--   manutencao/prestadores da casa-sede  1 lancamento  R$  2.000,00
--   venda de veiculos e maquinas ...... 2 lancamentos  R$ 11.705,55
--
-- O QUE FICA DE FORA DE PROPOSITO (continua sem atividade):
--   movimentos de caixa que nao sao receita de atividade (ajuste de saldo bancario, resgate de
--   aplicacao, estorno, outras movimentacoes de caixa, aporte de capital, rendimentos), R$ 620.569,54;
--   "outros recebimentos nao relacionados a atividade rural", R$ 17.325,23; e centavos.
--   Ratear isso poria R$ 638 mil de "receita" que nao e de atividade dentro de Pecuaria, Cana e Graos.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. confere cada uma das 10 linhas (receita, valor, 'geral', SEM partes, anterior a 2026-05,
--      e que o centro de custo nao e movimento de caixa nem "nao relacionado a atividade rural");
--   2. recusa se nao forem exatamente 10 linhas e R$ 28.865,55;
--   3. guarda copia em zz_backup_ajuste6_lanc_2026_11_05 (fechada: so o dono do banco le);
--   4. grava tres partes iguais por lancamento (Cana leva o centavo que sobra);
--   5. confere que cada uma fecha o valor.
-- Nenhum lancamento e alterado, so as partes do rateio. Rodar de novo recusa.
--
-- PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $ajuste$
declare
  v_ids bigint[] := array[22935, 22921, 22919, 22873, 22909, 22913, 22931, 22944, 22840, 22929];
  v_n int; v_total numeric;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_ajuste6_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste6_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  select l.id, l.valor, l.tipo, l.atividade,
         coalesce(l.mes, to_char(coalesce(l.data, l.vencimento), 'YYYY-MM')) as mes_ref,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) as n_partes
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.id = any(v_ids);

  -- 1) e 2) trava: cada linha como a lista mostrou
  select count(*) into v_n from tmp_alvo;
  if v_n <> 10 then
    raise exception 'Esperava 10 lancamentos, achei %. Nao mexo em nada.', v_n;
  end if;
  select count(*) into v_n from tmp_alvo
   where tipo = 'receita' and atividade = 'geral' and n_partes = 0 and mes_ref < '2026-05'
     and not (centro_norm like 'AJUSTE DE SALDO%' or centro_norm like 'RESGATE DE APLICACOES%'
              or centro_norm like 'ESTORNO%' or centro_norm like 'OUTRAS MOVIMENTACOES DE CAIXA%'
              or centro_norm like 'APORTE DE CAPITAL%' or centro_norm like 'RENDIMENTOS DE APLICACOES%'
              or centro_norm like 'OUTROS RECEBIMENTOS NAO RELACIONADOS%');
  if v_n <> 10 then
    raise exception 'So % das 10 linhas estao como a lista mostrou (receita, geral, sem partes, antes de maio/2026, fora de movimento de caixa). Nao mexo em nada.', v_n;
  end if;
  select coalesce(sum(valor), 0) into v_total from tmp_alvo;
  if abs(v_total - 28865.55) > 0.05 then
    raise exception 'Esperava R$ 28865.55 no total, achei R$ %. Nao mexo em nada.', v_total;
  end if;

  -- 3) copia de seguranca (fechada para quem esta logado)
  create table zz_backup_ajuste6_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id in (select id from tmp_alvo);
  alter table zz_backup_ajuste6_lanc_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste6_lanc_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste6_lanc_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste6_lanc_2026_11_05 from authenticated;
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
select 'Receitas antigas rateadas em tres partes iguais' as item,
       count(*)::text as valor,
       case when count(*) = 10 then 'OK' else 'PROBLEMA' end as situacao
  from lancamentos_financeiros l
 where l.id in (22935, 22921, 22919, 22873, 22909, 22913, 22931, 22944, 22840, 22929)
   and (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) = 3
union all
select 'R$ rateados (copia no backup)',
       'R$ ' || (select round(sum(valor), 2) from zz_backup_ajuste6_lanc_2026_11_05)::text,
       'zz_backup_ajuste6_lanc_2026_11_05'
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
--    where lancamento_id in (select id from zz_backup_ajuste6_lanc_2026_11_05);
-- ------------------------------------------------------------
