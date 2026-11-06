-- ============================================================
-- AJUSTE: a lancada a mao do consorcio (#500, R$ 22.799,46) passa a tres partes iguais
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- DECISAO DO EDUARDO (05/11/2026): "o consorcio e rateado entre as atividades". A importacao do
-- mesmo consorcio (#21098, boleto) ja esta dividida pelo ERP e NAO e tocada aqui: as duas linhas
-- ficam, porque ele disse que nao sao o mesmo pagamento.
--
-- COMO GRAVA: o lancamento passa a 'geral' e ganha tres partes iguais (Pecuaria, Cana e Graos),
-- como as outras linhas que se dividem entre atividades.
--
-- O QUE FAZ (tudo ou nada: um bloco so; se qualquer trava falhar, desfaz tudo)
--   1. confere a linha (investimento, R$ 22.799,46, 17/03/2026, centro "investimento em ativos",
--      hoje inteira em Pecuaria e SEM partes);
--   2. recusa se estiver diferente;
--   3. guarda copia em zz_backup_ajuste10_lanc_2026_11_05 (fechada: so o dono do banco le);
--   4. grava as tres partes (7.599,82 cada); 5. confere que fecha o valor.
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
  if to_regclass('public.zz_backup_ajuste10_lanc_2026_11_05') is not null then
    raise exception 'Ja existe zz_backup_ajuste10_lanc_2026_11_05: este ajuste ja foi rodado. Nao rodo de novo.';
  end if;

  drop table if exists tmp_alvo;
  create temp table tmp_alvo as
  select l.id, l.valor, l.tipo, l.atividade, l.data, l.vencimento,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         (select count(*) from lancamento_rateios r where r.lancamento_id = l.id) as n_partes
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.id = 500;

  select count(*) into v_n from tmp_alvo
   where tipo = 'investimento' and abs(valor - 22799.46) < 0.005 and centro_norm like 'INVESTIMENTO EM ATIVOS%'
     and coalesce(data, vencimento) = date '2026-03-17' and atividade = 'pecuaria' and n_partes = 0;
  if v_n <> 1 then
    raise exception 'A linha #500 nao esta como a conferencia mostrou (investimento, R$ 22.799,46, 17/03/2026, investimento em ativos, inteira em Pecuaria, sem partes). Nao mexo em nada.';
  end if;

  create table zz_backup_ajuste10_lanc_2026_11_05 as
    select l.* from lancamentos_financeiros l where l.id = 500;
  alter table zz_backup_ajuste10_lanc_2026_11_05 enable row level security;
  revoke all on zz_backup_ajuste10_lanc_2026_11_05 from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on zz_backup_ajuste10_lanc_2026_11_05 from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on zz_backup_ajuste10_lanc_2026_11_05 from authenticated;
  end if;

  update lancamentos_financeiros set atividade = 'geral' where id = 500;
  insert into lancamento_rateios (lancamento_id, atividade, fazenda_id, percentual, valor, origem)
    values (500, 'cana',     null, 0.333333, 7599.82, 'administrativo'),
           (500, 'graos',    null, 0.333333, 7599.82, 'administrativo'),
           (500, 'pecuaria', null, 0.333333, 7599.82, 'administrativo');

  select count(*) into v_n
    from lancamento_rateios where lancamento_id = 500;
  if v_n <> 3 or abs((select sum(valor) from lancamento_rateios where lancamento_id = 500) - 22799.46) > 0.005 then
    raise exception 'Depois de gravar, a #500 nao ficou com tres partes que fecham R$ 22.799,46. Desfazendo tudo.';
  end if;
end
$ajuste$;

select 'Lancamento #500 (consorcio lancado a mao): como conta agora' as item,
       coalesce((select string_agg(atividade || ' R$ ' || valor::text, ' / ' order by atividade)
                   from lancamento_rateios where lancamento_id = 500), '(sem partes)') as valor,
       case when (select count(*) from lancamento_rateios where lancamento_id = 500) = 3
             and abs((select sum(valor) from lancamento_rateios where lancamento_id = 500) - 22799.46) < 0.005
            then 'OK' else 'PROBLEMA' end as situacao
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
--   delete from lancamento_rateios where lancamento_id = 500;
--   update lancamentos_financeiros l set atividade = b.atividade
--     from zz_backup_ajuste10_lanc_2026_11_05 b where b.id = l.id;
-- ------------------------------------------------------------
