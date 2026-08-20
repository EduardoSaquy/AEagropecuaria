-- ============================================================
-- PASSO 6 — LIMPEZA (só depois dos apps já estarem apontando pro banco único
-- e funcionando)
--
-- Duas partes: derrubar a ponte FDW (não é mais necessária) e apagar as
-- políticas de leitura anônima.
--
-- A segunda parte é o maior ganho de segurança da unificação: essas políticas
-- só existiam porque um app precisava ler o banco do outro sem ter login lá.
-- Enquanto elas estiverem no ar, QUALQUER pessoa com a chave pública (que fica
-- embutida no HTML dos apps, à vista) consegue ler essas tabelas inteiras sem
-- login nenhum. Com um banco só, isso deixa de ser necessário.
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA DE PROJETO — não remova
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'talhoes_areas'
  ) then
    raise exception E'PROJETO ERRADO.\nEste script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz). Troque de projeto.';
  end if;
end $$;


-- ------------------------------------------------------------
-- 6.1 — Derrubar a ponte com o banco antigo (rodar no LAVOURA)
-- ------------------------------------------------------------
drop schema if exists pec_origem_dados cascade;
drop server if exists pec_origem cascade;
-- a extensão pode ficar; não custa nada e não expõe nada sozinha.


-- ------------------------------------------------------------
-- 6.2 — Apagar as políticas de leitura anônima (rodar no LAVOURA)
--
-- Estas eram lidas pelo AE Pecuária quando ele era um projeto separado.
-- ------------------------------------------------------------
drop policy if exists "leitura anon (AE Pecuaria)" on fazendas;
drop policy if exists "leitura anon (AE Pecuaria)" on fazenda_atividades;
drop policy if exists "leitura anon (AE Pecuaria)" on funcionarios;
drop policy if exists "leitura anon (AE Pecuaria)" on funcionario_atividades;
drop policy if exists "leitura anon (AE Pecuaria)" on talhoes_areas;
drop policy if exists "leitura anon (AE Pecuaria)" on culturas;

-- Varredura de segurança: lista QUALQUER política que ainda libere acesso
-- anônimo. Depois da unificação isso deve voltar VAZIO.
select tablename, policyname, qual
from pg_policies
where schemaname = 'public'
  and (qual ilike '%anon%' or policyname ilike '%anon%')
order by tablename, policyname;


-- ------------------------------------------------------------
-- 6.3 — ✅ TESTE FINAL DE SEGURANÇA (fora do SQL Editor)
--
-- No navegador, numa aba anônima, abra o console e rode:
--
--   const c = supabase.createClient('https://kmkystqgpvmzrccxvyaz.supabase.co',
--                                   'sb_publishable_YclssD8pzNZhWO_Om0anMg_SwaZHQOa');
--   console.log(await c.from('lotes').select('*'));
--
-- Esperado DEPOIS da limpeza: 0 linhas (a RLS bloqueia sem login).
-- Se voltar dado, alguma política de leitura anônima escapou — rode o
-- select do 6.2 de novo e me mande o resultado.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 6.4 — O que NÃO fazer agora
--
-- NÃO apague o projeto antigo da Pecuária. Deixe-o parado, sem nenhum app
-- apontando pra ele, por pelo menos 2 semanas. Ele é a rede de segurança:
-- se aparecer qualquer diferença de número, é dele que a gente confere.
--
-- As Edge Functions criar-usuario e atualizar-permissoes do projeto antigo
-- também ficam onde estão — param de ser chamadas sozinhas quando o
-- AEpecuaria.html passar a usar a criar-usuario-cana do projeto único.
-- ------------------------------------------------------------
