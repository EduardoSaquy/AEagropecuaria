-- ============================================================
-- CORRIGE A EXCLUSAO DO RATEIO
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- ------------------------------------------------------------
-- O DEFEITO
--
-- Eu restringi a exclusao de titulo_rateios a admin/proprietario junto com
-- as outras tabelas novas. Mas o rateio nao e um registro que alguem
-- "exclui": e uma LINHA DENTRO DO FORMULARIO do titulo. Ao editar um
-- titulo, o app apaga os rateios antigos e grava os novos.
--
-- Resultado para quem edita contas mas nao e dono (a Creunice):
--
--   DELETE 0        a RLS apaga zero linhas, SEM erro
--   INSERT 0 2      os rateios novos entram por cima
--   ERROR           "a soma dos rateios nao fecha com o valor do titulo"
--
-- Ela recebe um erro sobre soma que nao tem nada a ver com a causa. O
-- gatilho impediu a corrupcao - sem ele o titulo ficaria com o rateio
-- duplicado e o custo dobrado.
--
-- ------------------------------------------------------------
-- A CORRECAO
--
-- Quem pode EDITAR o titulo pode trocar as linhas de rateio dele. A regra
-- de "so dono exclui" continua valendo para o TITULO: apagar o titulo
-- leva os rateios junto pela chave estrangeira, e isso continua sendo so
-- de admin ou proprietario.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;

drop policy if exists "exclui titulo_rateios" on titulo_rateios;

-- sem "to authenticated": as demais politicas deste projeto tambem nao
-- usam, e o papel so existe dentro do Supabase - o script quebraria em
-- qualquer teste fora dele.
create policy "exclui titulo_rateios" on titulo_rateios
  for delete
  using (
    is_dono()
    or (tem_permissao('matriz_financeiro','visualizar') and tem_permissao('contas','editar'))
  );


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
-- ------------------------------------------------------------
select
  'titulo_rateios' as tabela,
  (select count(*) from pg_policies
    where schemaname='public' and tablename='titulo_rateios' and cmd='DELETE'
      and qual like '%contas%')::text as politica_corrigida,
  case when exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='titulo_rateios' and cmd='DELETE'
      and qual like '%contas%'
  ) then 'OK - quem edita contas ja consegue trocar o rateio'
     else '*** NAO APLICOU ***' end as situacao;
