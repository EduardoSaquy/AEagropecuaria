-- ===================================================================
-- Concede Cria:Editar a todo colaborador ativo que já tem algum acesso
-- à Pecuária — pedido do Eduardo, pra poder corrigir parto/desmama
-- lançado errado sem precisar ligar pra ele. Exclusão continua
-- restrita a admin/proprietário (pode_excluir(), já fechado em
-- partos/desmamas/lancamentos_financeiros).
--
-- "Algum acesso à Pecuária" = qualquer chave do grupo Pecuária (aba
-- Usuários > Pecuária no AE Matriz) com visualizar ou editar:
-- manejo, cadastro, insumos, dietas, lotesGeral, confinamento, pasto,
-- cria, vendas, pec_financeiro, pec_resultados.
--
-- Não mexe em admin/proprietário/consultor (acesso total ou fora do
-- pedido do Eduardo) nem em colaborador inativo.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

update profiles
   set permissoes = permissoes || jsonb_build_object('cria', 'editar')
 where papel = 'colaborador'
   and ativo = true
   and exists (
     select 1 from jsonb_each_text(permissoes) p(chave, valor)
      where p.chave in ('manejo','cadastro','insumos','dietas','lotesGeral',
                         'confinamento','pasto','cria','vendas','pec_financeiro','pec_resultados')
        and p.valor in ('visualizar','editar')
   );

select 1::numeric as ordem, nome || ' (' || usuario || ')' as item,
       permissoes->>'cria' as valor, 'esperado: editar' as situacao
  from profiles
 where papel = 'colaborador' and ativo = true
   and exists (
     select 1 from jsonb_each_text(permissoes) p(chave, valor)
      where p.chave in ('manejo','cadastro','insumos','dietas','lotesGeral',
                         'confinamento','pasto','cria','vendas','pec_financeiro','pec_resultados')
        and p.valor in ('visualizar','editar')
   )
 order by 1;
