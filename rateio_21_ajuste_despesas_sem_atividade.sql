-- ============================================================
-- AJUSTE: as duas despesas de 2026/27 que estavam sem atividade
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Depois da rateio_19_lista_sem_atividade.sql.
--
--   #21557  R$ 704,00   ANALISES AGRICOLAS (importacao do ERP) ........ Cana
--           regra do Eduardo (05/11/2026): "analises agricolas e seguro de safra: Cana".
--           Ficou de fora do conserto porque nao tinha NENHUMA parte de rateio.
--   #24184  R$ 2.581,99 SERVICOS PROFISSIONAIS (lancada a mao) ........ tres partes iguais
--           PADRAO PROVISORIO: e despesa de administracao, e a regra dele para o que e da
--           empresa toda e dividir igual entre Pecuaria, Cana e Graos.
--
-- Nao mexe em nenhuma outra linha (o gasto de R$ 200,00 em "outras despesas financeiras"
-- espera uma decisao dele).
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. confere as duas linhas (tipo, valor, centro de custo, atividade 'geral', SEM partes);
--   2. guarda copia em zz_backup_ajuste5_lanc_2026_11_05 (fechada: so o dono do banco le);
--   3. grava as partes: uma de Cana (704,00) e tres iguais (860,67 / 860,66 / 860,66);
--   4. confere que cada uma fecha o valor.
-- Nenhum lancamento e alterado, so as partes do rateio. Rodar de novo recusa.
--
-- PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $ajuste$
declare
  v_n int; v_k int; v_s numeric;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_ajuste5_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste5_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  -- 1) as duas linhas, como estao hoje
  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  select l.id, l.valor, l.tipo, l.atividade,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) as n_partes
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.id in (21557, 24184);

  select count(*) into v_n from tmp_alvo;
  if v_n <> 2 then
    raise exception 'Esperava 2 lancamentos, achei %. Nao mexo em nada.', v_n;
  end if;
  select count(*) into v_n from tmp_alvo
   where id = 21557 and tipo = 'despesa' and abs(valor - 704.00) < 0.005
     and centro_norm like 'ANALISES AGRICOLAS%' and atividade = 'geral' and n_partes = 0;
  if v_n <> 1 then
    raise exception 'A linha #21557 nao esta como a lista mostrou (R$ 704,00, analises agricolas, geral, sem partes). Nao mexo em nada.';
  end if;
  select count(*) into v_n from tmp_alvo
   where id = 24184 and tipo = 'despesa' and abs(valor - 2581.99) < 0.005
     and centro_norm like 'SERVICOS PROFISSIONAIS%' and atividade = 'geral' and n_partes = 0;
  if v_n <> 1 then
    raise exception 'A linha #24184 nao esta como a lista mostrou (R$ 2.581,99, servicos profissionais, geral, sem partes). Nao mexo em nada.';
  end if;

  -- 2) copia de seguranca (fechada para quem esta logado)
  create table zz_backup_ajuste5_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id in (select id from tmp_alvo);
  alter table zz_backup_ajuste5_lanc_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste5_lanc_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste5_lanc_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste5_lanc_2026_11_05 from authenticated;
  end if;

  -- 3) as partes: analises = uma parte de Cana; servicos = tres partes iguais (Cana leva o centavo)
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    values (21557, 'cana', null, 1, 704.00, 'administrativo');
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    values (24184, 'cana',     null, 0.333333, 860.67, 'administrativo'),
           (24184, 'graos',    null, 0.333333, 860.66, 'administrativo'),
           (24184, 'pecuaria', null, 0.333333, 860.66, 'administrativo');

  -- 4) confere direto na tabela
  select count(*) into v_n
    from tmp_alvo a
    join (select lancamento_id, count(*) as k, sum(valor) as s from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = a.id
   where abs(a.valor - p.s) > 0.005 or (a.id = 21557 and p.k <> 1) or (a.id = 24184 and p.k <> 3);
  if v_n > 0 then
    raise exception 'Depois de gravar, % lancamentos nao fecharam o valor. Desfazendo tudo.', v_n;
  end if;
end
$ajuste$;

-- CONFERENCIA FINAL (uma tabela). Tudo tem que dizer OK.
select 'Lancamento #21557 (analises): como conta agora' as item,
       coalesce((select string_agg(atividade || ' R$ ' || valor::text, ' / ' order by atividade)
                   from lancamento_rateios where lancamento_id = 21557), '(sem partes)') as valor,
       case when (select count(*) from lancamento_rateios where lancamento_id = 21557 and atividade = 'cana') = 1
             and (select count(*) from lancamento_rateios where lancamento_id = 21557) = 1
            then 'OK' else 'PROBLEMA' end as situacao
union all
select 'Lancamento #24184 (servicos profissionais): como conta agora',
       coalesce((select string_agg(atividade || ' R$ ' || valor::text, ' / ' order by atividade)
                   from lancamento_rateios where lancamento_id = 24184), '(sem partes)'),
       case when (select count(*) from lancamento_rateios where lancamento_id = 24184) = 3
             and abs((select sum(valor) from lancamento_rateios where lancamento_id = 24184) - 2581.99) < 0.005
            then 'OK' else 'PROBLEMA' end
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
--   delete from lancamento_rateios where lancamento_id in (21557, 24184);
-- ------------------------------------------------------------
