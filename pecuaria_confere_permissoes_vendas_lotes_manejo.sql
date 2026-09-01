-- ============================================================
-- SÓ LEITURA — varredura de segurança pediu conferência: no AEpecuaria.html
-- a tela de permissões deixa conceder 4 chaves de forma independente
-- ('vendas', 'lotesGeral', 'cadastro', 'manejo'), cada uma liberando uma
-- aba sozinha (grupoVisivel(), linhas 948-951). Mas em nenhum arquivo .sql
-- do repositório essas 4 chaves aparecem dentro de um tem_permissao(...)
-- de policy nenhuma -- só confinamento/pasto/cria/pec_financeiro/
-- pec_resultados aparecem. Isso sugere que quem ganhar SÓ uma dessas 4
-- (sem confinamento/pasto/cria junto) vê a aba aparecer, mas os dados por
-- trás (abates/lotes/animais/manejos) voltam vazios pela RLS -- mas
-- supabase_schema.sql é doc velha (CLAUDE.md avisa que já enganou 4
-- vezes), então isso precisa ser confirmado contra o banco de verdade
-- antes de eu decidir o que corrigir. Não muda nada.
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
 where schemaname='public' and tablename in ('abates','lotes','animais','manejos')
 order by 1;
