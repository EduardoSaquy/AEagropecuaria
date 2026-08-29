-- ============================================================
-- SO LEITURA - parte 2: with_check das policies + definicao das funcoes
--
-- A parte 1 mostrou "roles={public}" nas 4 policies de entidades - isso
-- e normal no Supabase (a restricao de verdade fica dentro de using/
-- with_check, chamando funcoes como is_dono()/tem_permissao(), que
-- dependem de auth.uid()). Mas a parte 1 so pediu a clausula USING, nao
-- a WITH CHECK (que e a que vale pra INSERT e pra validar linha nova em
-- UPDATE) - erro meu, esta parte 2 corrige.
--
-- O QUE OLHAR:
--   - linhas 1-4: with_check de cada policy. Se a de INSERT ("cria
--     entidades") vier vazia/null, qualquer um que bata nesse policy
--     consegue inserir uma linha sem restricao nenhuma de conteudo -
--     nao e o mesmo risco de "leitura anonima" da regra do CLAUDE.md,
--     mas vale saber.
--   - linhas 5+: o corpo das funcoes is_dono()/tem_permissao() usadas
--     nas policies. Se alguma delas NAO tiver "auth.uid()" no corpo,
--     ela nao depende de estar logado - aí sim as policies acima
--     seriam anonimas de verdade, mesmo com "public" no nome do role.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'with_check: ' || policyname as item,
       coalesce(with_check, '(vazio)') as valor,
       case when with_check is null then 'PARE E ME AVISE se for INSERT/UPDATE' else 'ok, tem checagem' end as situacao
  from pg_policies
 where schemaname='public' and tablename='entidades'
union all
select 2, 'funcao: ' || p.proname,
       case when pg_get_functiondef(p.oid) ilike '%auth.uid()%' then 'usa auth.uid()' else 'NAO usa auth.uid() - PARE E ME AVISE' end,
       left(pg_get_functiondef(p.oid), 300)
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('is_dono', 'tem_permissao')
order by ordem;
