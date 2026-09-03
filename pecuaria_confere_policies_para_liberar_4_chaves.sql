-- ============================================================
-- SÓ LEITURA — pra "vendas", "lotesGeral", "cadastro" e "manejo" (as 4
-- chaves de permissão do AEpecuaria.html que só controlam se a aba
-- aparece, sem valer nada de verdade) passarem a liberar a ação sozinhas
-- (registrar venda, criar lote/animal, fazer manejo), preciso saber a
-- policy de escrita ATUAL de cada tabela envolvida antes de escrever a
-- correção — pra somar "ou tem_permissao(...)" na condição certa, sem
-- reescrever a condição errada por cima. Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, tablename || ' - ' || policyname as item,
       'comando=' || cmd as valor,
       coalesce('using: ' || qual, '') || coalesce(' | with check: ' || with_check, '') as situacao
  from pg_policies
 where schemaname='public'
   and tablename in ('lotes','animais','abates','manejos','pesagens',
                      'pesagens_animais','reproducao_custos',
                      'diagnosticos_gestacionais','partos','desmamas',
                      'lancamentos_financeiros')
 order by 1;
