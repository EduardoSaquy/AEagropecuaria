-- ============================================================
-- SO LEITURA - confere a policy de select em entidades.documento
--
-- Achado da varredura: entidades.documento pode ter CNPJ/CPF de
-- fornecedor. O AEMatriz.html LE esse campo (mas nunca escreve nele -
-- confirmado no codigo do app) e so mostra pra quem tem sessao
-- autenticada (podeVerContas()). Isso nao prova nada sobre a policy do
-- banco em si - so quem tem acesso ao Supabase consegue ver a policy de
-- verdade. Esta consulta mostra.
--
-- O QUE OLHAR NO RESULTADO:
--   - linha 1: se RLS esta LIGADO na tabela entidades. Se vier
--     "DESLIGADO", qualquer policy abaixo e irrelevante - a tabela
--     inteira fica aberta pra quem tiver a anon key. PARE E ME AVISE
--     se vier assim.
--   - linha 2+: cada policy de SELECT em entidades. "roles" mostra quem
--     ela vale (anon = qualquer um com a anon key, sem estar logado;
--     authenticated = so quem fez login). Se aparecer uma policy pra
--     "anon" com using(true) (ou parecido, sem checar auth.uid()),
--     documento esta exposto pela chave anonima - viola a regra
--     permanente do CLAUDE.md.
--   - ultima linha: quantos registros de entidades ja tem documento
--     preenchido hoje - se vier 0, o risco e teorico (coluna existe,
--     ninguem usou ainda); se vier maior que 0, e dado real exposto se
--     a policy acima permitir leitura anonima.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'RLS na tabela entidades' as item,
       case when relrowsecurity then 'LIGADO' else 'DESLIGADO - PARE E ME AVISE' end as valor,
       'esperado: LIGADO' as situacao
  from pg_class
 where relname = 'entidades' and relnamespace = 'public'::regnamespace
union all
select 2, 'policy: ' || policyname,
       'comando=' || cmd || ' | roles=' || roles::text,
       coalesce('using: ' || qual, '(sem using — bloqueia tudo nesse comando)')
  from pg_policies
 where schemaname='public' and tablename='entidades'
union all
select 3, 'registros com documento preenchido hoje',
       count(*)::text,
       case when count(*)=0 then 'risco teorico (coluna vazia)' else 'dado real — confira a policy acima' end
  from entidades
 where documento is not null and btrim(documento) <> ''
order by ordem;
