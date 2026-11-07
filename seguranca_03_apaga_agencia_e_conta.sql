-- ============================================================
-- SEGURANCA 03: APAGA as colunas agencia e conta de contas_bancarias
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- POR QUE
--   O app nunca guarda conta, agencia nem saldo bancario (decisao do Eduardo, por seguranca): a tabela contas_bancarias
--   so serve para dizer "de qual banco saiu o pagamento" (nome e banco). As duas colunas ficaram do desenho antigo, vazias
--   na tela. Dado que nao existe nao vaza: se um dia alguem lesse a tabela, nao haveria numero de conta para ler.
--
-- O QUE FAZ (um bloco so; se qualquer passo falhar, nada muda)
--   1. confere que e o projeto certo;
--   2. se as colunas ja nao existem, avisa e nao faz nada (pode rodar de novo sem problema);
--   3. CONTA quantas linhas tem agencia ou conta preenchida. Se tiver ALGUMA, RECUSA e diz quantas: nao apaga dado que alguem
--      digitou. Me mande o aviso;
--   4. se estao vazias, apaga as duas colunas (sem CASCADE: se uma visao ou funcao depender delas, o banco recusa e nada muda).
--   O app nao precisa de ajuste: ele le a tabela inteira e trata coluna ausente como texto vazio.
--
-- PARA DESFAZER (as colunas estavam vazias, entao nao se perde nada):
--   alter table contas_bancarias add column agencia text, add column conta text;
-- ============================================================

do $seg$
declare
  v_tem_ag boolean; v_tem_cc boolean; v_ag int := 0; v_cc int := 0;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.contas_bancarias') is null then
    raise exception 'Nao achei a tabela contas_bancarias.';
  end if;

  select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contas_bancarias' and column_name = 'agencia'),
         exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contas_bancarias' and column_name = 'conta')
    into v_tem_ag, v_tem_cc;

  if not v_tem_ag and not v_tem_cc then
    raise notice 'contas_bancarias ja nao tem agencia nem conta. Nada a fazer.';
    return;
  end if;

  if v_tem_ag then
    execute 'select count(*) from public.contas_bancarias where nullif(btrim(agencia), '''') is not null' into v_ag;
  end if;
  if v_tem_cc then
    execute 'select count(*) from public.contas_bancarias where nullif(btrim(conta), '''') is not null' into v_cc;
  end if;
  if v_ag > 0 or v_cc > 0 then
    raise exception 'RECUSADO: tem dado nas colunas (% linha(s) com agencia, % com conta). Nao apaguei nada. Me mande esta mensagem.', v_ag, v_cc;
  end if;

  if v_tem_ag then execute 'alter table public.contas_bancarias drop column agencia'; end if;
  if v_tem_cc then execute 'alter table public.contas_bancarias drop column conta'; end if;
  raise notice 'Colunas apagadas (estavam vazias).';
end
$seg$;

-- CONFERENCIA: as duas tem que estar "apagada"
select 'coluna ' || c.nome as item,
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'contas_bancarias' and column_name = c.nome)
            then 'AINDA EXISTE' else 'apagada' end as valor,
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'contas_bancarias' and column_name = c.nome)
            then 'ATENCAO' else 'OK' end as situacao
  from (values ('agencia'), ('conta')) as c(nome)
union all
select 'linhas em contas_bancarias (nao mudam)', count(*)::text, 'OK' from public.contas_bancarias
order by 1;
