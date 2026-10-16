-- ============================================================
-- CAMPO SAFRA (ano_safra) - COLE TUDO DE UMA VEZ SO
-- Junta lancamentos_ano_safra_01 + lancamentos_rateados_03 num arquivo so
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table lancamentos_financeiros add column if not exists ano_safra integer;

comment on column lancamentos_financeiros.ano_safra is
  'Ano de inicio da safra (maio a abril) a que este lancamento pertence, quando diferente do mes/data da transacao. Ex.: 2025 = safra 2025/2026. Null = usa o mes normalmente. Independente de safra_id (FK pra tabela safras, so cana/graos).';

create or replace view lancamentos_rateados as
select l.id as lancamento_id, r.id as rateio_id, l.tipo,
       r.atividade, r.fazenda_id, r.cultura_id, r.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.erp_id, l.contrato, true as rateado,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento,
       l.ano_safra
  from lancamentos_financeiros l
  join lancamento_rateios r on r.lancamento_id = l.id
union all
select l.id, null, l.tipo,
       l.atividade, l.fazenda_id, l.cultura_id, l.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.erp_id, l.contrato, false,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento,
       l.ano_safra
  from lancamentos_financeiros l
 where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);

-- A view passa por cima do RLS: sem isto, qualquer pessoa com a chave publica do
-- site le o Financeiro inteiro por ela (ver seguranca_01_fecha_view_para_anonimo.sql)
-- e todo usuario logado le tudo, mesmo sem permissao (seguranca_02_...sql).
do $trava_view$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on lancamentos_rateados from anon;
  end if;
  revoke all on lancamentos_rateados from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on lancamentos_rateados to authenticated;
  end if;
  -- a regra de permissao, se o seguranca_02 ja foi rodado neste banco
  if to_regprocedure('public.aplicar_regra_na_view_lancamentos_rateados()') is not null then
    perform public.aplicar_regra_na_view_lancamentos_rateados();
  end if;
end
$trava_view$;

comment on view lancamentos_rateados is
  'O financeiro ja rateado. Onde ha rateio, entrega as partes; onde nao ha, '
  'entrega o lancamento inteiro. E daqui que os Resultados devem ler.';

select 1::numeric as ordem, 'coluna ano_safra' as item,
       'ok, criada' as valor, 'confere que existe' as situacao
where exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='lancamentos_financeiros' and column_name='ano_safra')
union all
select 2, 'view lancamentos_rateados', count(*)::text || ' colunas',
       case when count(*) filter (where column_name='ano_safra')=1 then 'OK - tem ano_safra' else 'PARE E ME AVISE' end
  from information_schema.columns
 where table_schema='public' and table_name='lancamentos_rateados'
order by ordem;

-- Depois disso, feche e abra o AE Matriz de novo e confira Resultados.
