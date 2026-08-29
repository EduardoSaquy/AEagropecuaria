-- ============================================================
-- SO LEITURA - parte 3: corpo completo de tem_permissao() e acesso_total()
--
-- A parte 2 cortou tem_permissao() em 300 caracteres e ela chama outra
-- funcao (acesso_total()) que ainda nao vi. Sem o corpo completo das
-- duas nao da pra confirmar que a policy de SELECT em entidades
-- realmente exige login - so leitura, nao muda nada.
--
-- Como o resultado de cada funcao pode vir grande, cada uma sai numa
-- linha so (nao corta) - copia o texto inteiro da coluna "corpo" de
-- cada linha e me manda os dois.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select p.proname as funcao, pg_get_functiondef(p.oid) as corpo
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('tem_permissao', 'acesso_total')
order by p.proname;
