-- ============================================================
-- SÓ LEITURA — Gustavo (colaborador) não consegue lançar saída de
-- ração. Hipótese: ele só tem Cria:Editar (do lote de permissões que
-- rodei essa semana) e "Nova saída de ração" (a de Confinamento/Pasto,
-- diferente da "Saída de ração (Cria)") exige a chave 'confinamento'
-- especificamente no app -- se ele estiver tentando lançar pra um
-- lote de Confinamento/Pasto, o botão nem aparece pra ele.
-- Essa consulta mostra as permissões dele e a policy de verdade em
-- saidas_racao, pra eu confirmar antes de dizer o que fazer. Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'permissoes do Gustavo' as item,
       p.permissoes::text as valor,
       'confere confinamento/pasto/cria' as situacao
  from profiles p
 where lower(p.nome) like '%gustavo%'
union all
select 2, tablename || ' - ' || policyname,
       'comando=' || cmd,
       coalesce('using: ' || qual, '') || coalesce(' | with check: ' || with_check, '')
  from pg_policies
 where schemaname='public' and tablename='saidas_racao'
 order by 1;
