-- ============================================================
-- SÓ LEITURA — o diagnóstico anterior filtrou só policy de cmd='SELECT'
-- e voltou vazio, mas uma policy sem "for select" explícito (cobre
-- todos os comandos: select/insert/update/delete) aparece como
-- cmd='ALL' no catálogo, não 'SELECT' -- essa consulta pega QUALQUER
-- policy de funcionarios, pra não ficar essa dúvida. Não muda nada.
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
       coalesce('using: ' || qual, '(sem using)') as situacao
  from pg_policies
 where schemaname='public' and tablename='funcionarios'
 order by 1;
