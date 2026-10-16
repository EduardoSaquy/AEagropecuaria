-- ============================================================
-- FECHA A VIEW lancamentos_rateados PARA QUEM NAO ESTA LOGADO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode de uma vez. Pode rodar mais de uma vez.
--
-- O QUE ESTAVA ERRADO
--
-- A chave "anon" fica no codigo publico do site (e do repositorio): ela e
-- feita para isso, e o banco se protege com RLS, que esconde as linhas de
-- quem nao esta logado. So que uma VIEW roda com os direitos de quem a
-- criou, nao de quem pergunta: ela passa por cima do RLS das tabelas que
-- ela junta. A lancamentos_rateados nunca foi fechada para o "anon", entao
-- qualquer pessoa com a chave publica lia o Financeiro inteiro por ela
-- (30 mil linhas em 16/10/2026, com fornecedor, valor, contrato e CNPJ/CPF).
-- As TABELAS estavam fechadas; so a view ficou aberta.
--
-- Fechada pelo Eduardo em 16/10/2026 e conferida de fora com
-- conferir_chave_publica.py (89 objetos, nenhum devolve linha para a chave
-- publica).
--
-- O QUE ESTE SCRIPT FAZ
--
-- Tira todo acesso do "anon" e do publico a essa view e garante a leitura
-- para quem esta logado (o app so le dela com a pessoa logada). Nada muda
-- para quem usa o app.
--
-- REGRA DAQUI EM DIANTE: toda view nova que le dado do Financeiro (ou de
-- qualquer tabela com RLS) precisa de
--     revoke all on public.<view> from anon, public;
-- logo depois do create. Confira com conferir_chave_publica.py.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.lancamentos_rateados') is null then
    raise exception 'A view lancamentos_rateados nao existe neste banco.';
  end if;
end
$trava$;

grant select on public.lancamentos_rateados to authenticated;
revoke all on public.lancamentos_rateados from anon;
revoke all on public.lancamentos_rateados from public;

-- Resultado esperado: anon_le = false, logado_le = true
select has_table_privilege('anon', 'public.lancamentos_rateados', 'select') as anon_le,
       has_table_privilege('authenticated', 'public.lancamentos_rateados', 'select') as logado_le;
