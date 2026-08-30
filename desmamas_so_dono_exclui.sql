-- ===================================================================
-- Restringe exclusão de desmamas a admin/proprietário — mesma regra
-- já aplicada em lancamentos_financeiros ("so dono exclui") e partos
-- ("so dono exclui"), confirmadas via financeiro_bezerro_confere_delete.sql.
-- desmamas era a única das três ainda aceitando qualquer usuário com
-- cria:editar (inclusive colaborador, mesmo a tela escondendo o botão
-- Excluir pra esse papel — a policy antiga deixava excluir direto pela
-- API). Editar continua igual: quem tem cria:editar edita normalmente,
-- só exclusão muda.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from pg_proc where proname='pode_excluir') then
    raise exception 'pode_excluir() nao existe - confere se rodou contas_01_estrutura.sql';
  end if;
end $$;

drop policy if exists "excluir desmamas" on desmamas;
create policy "so dono exclui" on desmamas for delete using (pode_excluir());

select 1::numeric as ordem, tablename || ' - ' || policyname as item,
       'DELETE' as valor, coalesce(qual,'(sem using)') as situacao
  from pg_policies
 where schemaname='public' and cmd='DELETE'
   and tablename in ('lancamentos_financeiros','partos','desmamas')
 order by 1;
