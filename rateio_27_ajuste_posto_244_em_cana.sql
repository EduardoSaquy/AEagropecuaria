-- ============================================================
-- AJUSTE: as duas compras de combustivel de R$ 244,30 de 15/04/2026 passam a ser Cana
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- DECISAO DO EDUARDO (05/11/2026): "o do posto e Cana". Sao as duas compras iguais do mesmo
-- dia (as duas linhas que a rateio_15 e a rateio_25 deixaram, por serem as duas compras):
--   #3018   lancada a mao, hoje inteira em Pecuaria ................ passa a ser Cana (a atividade
--                                                                   do proprio lancamento muda)
--   #21300  importacao do ERP, hoje dividida em 10 partes .......... uma parte de Cana, R$ 244,30
-- Nao mexe em nenhum outro lancamento do mesmo fornecedor.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. confere as duas linhas (despesa de combustivel, R$ 244,30, como estao hoje);
--   2. recusa se alguma estiver diferente;
--   3. guarda copia em zz_backup_ajuste9_lanc_2026_11_05 e zz_backup_ajuste9_rateios_2026_11_05
--      (fechadas: so o dono do banco le);
--   4. grava; 5. confere que fecha o valor.
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
  if to_regclass('public.zz_backup_ajuste9_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste9_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  select l.id, l.valor, l.tipo, l.atividade, l.data, l.vencimento,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) as n_partes,
         (select coalesce(sum(r.valor), 0) from lancamento_rateios r where r.lancamento_id = l.id) as soma_partes
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.id in (3018, 21300);

  select count(*) into v_n from tmp_alvo;
  if v_n <> 2 then
    raise exception 'Esperava 2 lancamentos, achei %. Nao mexo em nada.', v_n;
  end if;
  select count(*) into v_n from tmp_alvo
   where tipo = 'despesa' and abs(valor - 244.30) < 0.005 and centro_norm like 'COMBUSTIVEIS%'
     and coalesce(data, vencimento) = date '2026-04-15'
     and ((id = 3018  and atividade = 'pecuaria' and n_partes = 0)
       or (id = 21300 and atividade = 'geral' and n_partes > 0 and abs(soma_partes - valor) < 0.05));
  if v_n <> 2 then
    raise exception 'As duas linhas nao estao como a conferencia mostrou (despesa de combustivel, R$ 244,30, 15/04/2026; #3018 inteira em Pecuaria, #21300 dividida). Nao mexo em nada.';
  end if;

  create table zz_backup_ajuste9_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id in (3018, 21300);
  create table zz_backup_ajuste9_rateios_2026_11_05 as
    select r.* from lancamento_rateios r where r.lancamento_id in (3018, 21300);
  alter table zz_backup_ajuste9_lanc_2026_11_05 enable row level security;
  alter table zz_backup_ajuste9_rateios_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste9_lanc_2026_11_05 from public;
  revoke all on zz_backup_ajuste9_rateios_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste9_lanc_2026_11_05 from anon;
    revoke all on zz_backup_ajuste9_rateios_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste9_lanc_2026_11_05 from authenticated;
    revoke all on zz_backup_ajuste9_rateios_2026_11_05 from authenticated;
  end if;

  update lancamentos_financeiros set atividade = 'cana' where id = 3018;
  delete from lancamento_rateios where lancamento_id = 21300;
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    values (21300, 'cana', null, 1, 244.30, 'administrativo');

  if (select atividade from lancamentos_financeiros where id = 3018) <> 'cana' then
    raise exception 'A linha #3018 nao ficou em Cana. Desfazendo tudo.';
  end if;
  select count(*) into v_n from lancamento_rateios where lancamento_id = 21300 and atividade = 'cana' and abs(valor - 244.30) < 0.005;
  if v_n <> 1 or (select count(*) from lancamento_rateios where lancamento_id = 21300) <> 1 then
    raise exception 'A linha #21300 nao ficou com uma parte de Cana de R$ 244,30. Desfazendo tudo.';
  end if;
end
$ajuste$;

select 'Lancamento #3018 (lancada a mao): atividade agora' as item,
       atividade as valor, case when atividade = 'cana' then 'OK' else 'PROBLEMA' end as situacao
  from lancamentos_financeiros where id = 3018
union all
select 'Lancamento #21300 (importacao): como conta agora',
       coalesce((select string_agg(atividade || ' R$ ' || valor::text, ' / ' order by atividade)
                   from lancamento_rateios where lancamento_id = 21300), '(sem partes)'),
       case when (select string_agg(atividade, ',') from lancamento_rateios where lancamento_id = 21300) = 'cana' then 'OK' else 'PROBLEMA' end
union all
select 'Copias guardadas no backup (lancamentos / partes)',
       (select count(*) from zz_backup_ajuste9_lanc_2026_11_05)::text || ' / '
         || (select count(*) from zz_backup_ajuste9_rateios_2026_11_05)::text,
       'zz_backup_ajuste9_*_2026_11_05'
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
--   delete from lancamento_rateios where lancamento_id in (3018, 21300);
--   insert into lancamento_rateios overriding system value
--     select * from zz_backup_ajuste9_rateios_2026_11_05;
--   update lancamentos_financeiros l set atividade = b.atividade
--     from zz_backup_ajuste9_lanc_2026_11_05 b where b.id = l.id;
-- ------------------------------------------------------------
