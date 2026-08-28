-- ============================================================
-- ADICIONA O CAMPO "SAFRA" NO LANCAMENTO (despesa e receita)
--
-- O QUE FAZ: cria a coluna lancamentos_financeiros.ano_safra (numero
-- inteiro, o ano de INICIO da safra maio-abril - ex.: 2025 quer dizer
-- "safra 2025/2026"). So isso, nao mexe em nenhum dado existente: toda
-- linha ja gravada fica com ano_safra = null.
--
-- PRA QUE SERVE: quando a venda (ou a despesa) acontece depois do fim
-- da safra mas pertence a producao da safra anterior - por exemplo, gado
-- vendido em junho que foi engordado na safra passada - o mes da
-- transacao (mes/data) nao muda, mas agora da pra marcar manualmente a
-- qual safra aquele valor realmente pertence, no formulario de lancamento
-- do AE Matriz.
--
-- NAO E O MESMO CAMPO que lancamentos_financeiros.safra_id (que ja
-- existe): aquele e uma referencia (foreign key) pra tabela safras, que
-- exige fazenda_id e cultura_id preenchidos - so serve pra Cana/Graos, e
-- veio da migracao antiga da Lavoura, sem uso hoje. ano_safra e livre
-- (so um numero), serve pra qualquer atividade (Pecuaria inclusive) e
-- fica null por padrao - null significa "usa o mes normalmente", que e
-- o comportamento de sempre.
--
-- IMPORTANTE: este campo, sozinho, ainda NAO muda a aba Safra do
-- Resultados - ela continua agrupando por mes (competencia), como
-- sempre fez. Isto so guarda a informacao pra decidir depois se/como
-- ligar a aba Safra nele.
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

select 'ok, coluna ano_safra criada (ou ja existia)' as item,
       count(*) filter (where ano_safra is not null)::text as titulos_ja_marcados,
       count(*)::text as total_lancamentos
  from lancamentos_financeiros;
