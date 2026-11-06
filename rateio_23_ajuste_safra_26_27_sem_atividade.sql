-- ============================================================
-- AJUSTE: os 4 lancamentos da safra 2026/27 que estavam sem atividade
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Depois da rateio_19_lista_sem_atividade.sql. Substitui a rateio_21 (que nao deve ser rodada).
--
-- DECISAO DO EDUARDO (05/11/2026), um por um:
--   #21557  R$    704,00  despesa  ANALISES AGRICOLAS (importacao do ERP) ....... Graos
--   #24184  R$  2.581,99  despesa  SERVICOS PROFISSIONAIS (lancada a mao) ....... tres partes iguais
--   #22992  R$    200,00  despesa  OUTRAS DESPESAS FINANCEIRAS (lancada a mao) .. Cana
--   #22814  R$ 33.000,00  receita  VENDA DE VEICULOS E MAQUINAS (importacao) .... Pecuaria
--
-- COMO GRAVA
--   as duas importacoes (#21557 e #22814) e a de tres partes (#24184) ganham partes de rateio
--   (como as outras do ERP: o lancamento segue 'geral' e as partes dizem onde cai);
--   a lancada a mao de uma atividade so (#22992) tem a ATIVIDADE do proprio lancamento trocada.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. confere cada linha (tipo, valor, centro de custo, atividade 'geral', SEM partes, de 2026/27);
--   2. recusa se alguma estiver diferente do que a lista mostrou;
--   3. guarda copia em zz_backup_ajuste7_lanc_2026_11_05 (fechada: so o dono do banco le);
--   4. grava; 5. confere que cada uma fecha o valor.
-- Rodar de novo recusa. PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $ajuste$
declare
  v_n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_ajuste7_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste7_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  -- 1) as linhas, como estao hoje
  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  select l.id, l.valor, l.tipo, l.atividade,
         coalesce(l.mes, to_char(coalesce(l.data, l.vencimento), 'YYYY-MM')) as mes_ref,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) as n_partes
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.id in (21557, 24184, 22992, 22814);

  -- 2) trava: cada linha como a lista mostrou
  select count(*) into v_n from tmp_alvo;
  if v_n <> 4 then
    raise exception 'Esperava 4 lancamentos, achei %. Nao mexo em nada.', v_n;
  end if;
  if exists (select 1 from tmp_alvo where n_partes > 0 or atividade <> 'geral') then
    raise exception 'Algum dos 4 lancamentos ja tem partes ou ja tem atividade (talvez a rateio_21 tenha sido rodada). Me avise antes de mexer: nao mexo em nada.';
  end if;
  select count(*) into v_n from tmp_alvo
   where mes_ref >= '2026-05'
     and ((id = 21557 and tipo = 'despesa' and abs(valor - 704.00) < 0.005   and centro_norm like 'ANALISES AGRICOLAS%')
       or (id = 24184 and tipo = 'despesa' and abs(valor - 2581.99) < 0.005  and centro_norm like 'SERVICOS PROFISSIONAIS%')
       or (id = 22992 and tipo = 'despesa' and abs(valor - 200.00) < 0.005   and centro_norm like 'OUTRAS DESPESAS FINANCEIRAS%')
       or (id = 22814 and tipo = 'receita' and abs(valor - 33000.00) < 0.005 and centro_norm like 'VENDA DE VEICULOS%'));
  if v_n <> 4 then
    raise exception 'So % das 4 linhas estao como a lista mostrou (tipo, valor, centro e safra 2026/27). Nao mexo em nada.', v_n;
  end if;

  -- 3) copia de seguranca (fechada para quem esta logado)
  create table zz_backup_ajuste7_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id in (select id from tmp_alvo);
  alter table zz_backup_ajuste7_lanc_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste7_lanc_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste7_lanc_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste7_lanc_2026_11_05 from authenticated;
  end if;

  -- 4) grava
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    values (21557, 'graos',    null, 1, 704.00,   'administrativo'),
           (22814, 'pecuaria', null, 1, 33000.00, 'administrativo'),
           (24184, 'cana',     null, 0.333333, 860.67, 'administrativo'),
           (24184, 'graos',    null, 0.333333, 860.66, 'administrativo'),
           (24184, 'pecuaria', null, 0.333333, 860.66, 'administrativo');
  update lancamentos_financeiros set atividade = 'cana' where id = 22992;

  -- 5) confere direto nas tabelas
  select count(*) into v_n
    from tmp_alvo a
    join (select lancamento_id, count(*) as k, sum(valor) as s from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = a.id
   where a.id in (21557, 22814, 24184)
     and (abs(a.valor - p.s) > 0.005 or (a.id = 24184 and p.k <> 3) or (a.id <> 24184 and p.k <> 1));
  if v_n > 0 then
    raise exception 'Depois de gravar, % lancamentos nao fecharam o valor. Desfazendo tudo.', v_n;
  end if;
  if (select atividade from lancamentos_financeiros where id = 22992) <> 'cana' then
    raise exception 'A linha #22992 nao ficou em Cana. Desfazendo tudo.';
  end if;
end
$ajuste$;

-- CONFERENCIA FINAL (uma tabela). Tudo tem que dizer OK.
select 'Lancamento #' || a.id || ' (' || a.tipo || ' R$ ' || a.valor::text || '): como conta agora' as item,
       coalesce((select string_agg(r.atividade || ' R$ ' || r.valor::text, ' / ' order by r.atividade)
                   from lancamento_rateios r where r.lancamento_id = a.id),
                'inteiro em ' || a.atividade) as valor,
       case when a.id = 21557 and (select string_agg(atividade, ',') from lancamento_rateios where lancamento_id = 21557) = 'graos' then 'OK'
            when a.id = 22814 and (select string_agg(atividade, ',') from lancamento_rateios where lancamento_id = 22814) = 'pecuaria' then 'OK'
            when a.id = 22992 and a.atividade = 'cana' and not exists (select 1 from lancamento_rateios where lancamento_id = 22992) then 'OK'
            when a.id = 24184 and (select count(*) from lancamento_rateios where lancamento_id = 24184) = 3
                 and abs((select sum(valor) from lancamento_rateios where lancamento_id = 24184) - 2581.99) < 0.005 then 'OK'
            else 'PROBLEMA' end as situacao
  from lancamentos_financeiros a
 where a.id in (21557, 24184, 22992, 22814)
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
--   delete from lancamento_rateios where lancamento_id in (21557, 24184, 22814);
--   update lancamentos_financeiros l set atividade = b.atividade
--     from zz_backup_ajuste7_lanc_2026_11_05 b where b.id = l.id;
-- ------------------------------------------------------------
