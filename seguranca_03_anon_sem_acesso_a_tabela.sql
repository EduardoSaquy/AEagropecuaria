-- ============================================================
-- QUEM NAO ESTA LOGADO NAO TEM ACESSO A TABELA NENHUMA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz). Cole inteiro e
-- rode de uma vez. Pode rodar mais de uma vez.
--
-- POR QUE
--
-- A chave "anon" fica no codigo publico do site. Hoje o que protege as
-- tabelas dela e o RLS, e o RLS e uma regra POR TABELA: toda tabela ou view
-- nova que nasce sem ele (ou sem revoke) fica aberta, e foi exatamente assim
-- que a lancamentos_rateados ficou aberta ate 16/10/2026. O editor do
-- Supabase cria tudo ja liberado para o "anon".
--
-- Nenhum app usa o "anon" para ler dado: todos exigem login antes (o login e
-- feito no servico de autenticacao, que nao passa por estas tabelas). Entao
-- o "anon" nao precisa de privilegio nenhum nas tabelas, views e sequencias
-- do schema public. Tirar tudo:
--   - fecha o que existe e o que alguem criar sem pensar nisso;
--   - faz a consulta anonima responder "permissao negada" na hora, em vez de
--     o banco avaliar a politica linha por linha ate estourar os 3 s (era o
--     que acontecia com lancamentos_financeiros: nao vazava, mas era uma
--     consulta cara que qualquer um podia disparar).
--
-- Quem esta logado ("authenticated") e o servidor ("service_role") nao mudam.
-- As funcoes tambem nao mudam (as de permissao precisam continuar chamaveis).
--
-- No fim, uma linha: quantos objetos ainda estao abertos ao anon (tem que ser
-- 0) e se quem esta logado continua lendo os lancamentos (tem que ser true).
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- o que for criado daqui para frente pelo editor (que roda como postgres)
-- tambem nasce fechado para o anon
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

select count(*) as abertos_ao_anon,
       coalesce(string_agg(c.relname, ', ' order by c.relname), '(nenhum)') as quais,
       has_table_privilege('authenticated', 'public.lancamentos_financeiros', 'select') as logado_le_lancamentos
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relkind in ('r', 'p', 'v', 'm', 'S')
   and (has_table_privilege('anon', c.oid, 'select')
     or has_table_privilege('anon', c.oid, 'insert')
     or has_table_privilege('anon', c.oid, 'update')
     or has_table_privilege('anon', c.oid, 'delete'));
