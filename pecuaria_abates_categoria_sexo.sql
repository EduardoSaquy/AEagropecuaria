-- ===================================================================
-- AE Pecuária — abates ganha "categoria" (bezerro/abate/venda viva) e
-- "sexo", pra separar a receita por categoria em Resultados > Operacional
-- ===================================================================
-- Pedido do Eduardo: quer ver, no Resultados > Operacional, a receita da
-- Pecuária separada por categoria (bezerro / macho pra abate / vaca pra
-- abate) -- hoje o app não distingue isso em lugar nenhum. Ele confirmou
-- que a distinção certa é: categoria escolhida na hora de lançar a venda
-- (Bezerro / Abate / Venda viva) + sexo escolhido na hora também (não dá
-- pra inferir com segurança só do lote, porque um lote misto pode ter
-- venda só dos machos, por exemplo).
--
-- Vendas já lançadas ficam com categoria/sexo em branco -- não dá pra
-- recuperar isso do que já foi salvo. AEpecuaria.html e AEMatriz.html
-- (as duas telas que lançam venda) já foram ajustados pra pedir os dois
-- campos daqui pra frente.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table abates add column if not exists categoria text;
alter table abates add column if not exists sexo text;

select 1::numeric as ordem, 'colunas novas em abates' as item,
       string_agg(column_name, ', ' order by column_name) as valor,
       'OK' as situacao
  from information_schema.columns
 where table_schema='public' and table_name='abates' and column_name in ('categoria','sexo');
