-- ============================================================
-- PASSO 3 — COPIAR OS DADOS DA PECUÁRIA PARA O LAVOURA
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ** (kmkystqgpvmzrccxvyaz),
-- depois que o PASSO 2 (estrutura) já estiver aplicado.
--
-- Este script LÊ do banco da Pecuária e ESCREVE no do Lavoura. O banco da
-- Pecuária não é alterado em nada — só leitura.
--
-- ⚠️ SENHA: o bloco 3.2 tem um placeholder SENHA_DO_BANCO_DA_PECUARIA.
-- Pegue em: projeto da Pecuária → Project Settings → Database → Database
-- Password. Preencha você mesmo, direto no editor. Não é a chave anon,
-- é a senha do Postgres. Não compartilhe ela comigo nem em prints.
-- ============================================================


-- ------------------------------------------------------------
-- 3.1 — Extensão que permite ler outro Postgres
-- ------------------------------------------------------------
create extension if not exists postgres_fdw;


-- ------------------------------------------------------------
-- 3.2 — Conexão com o banco da Pecuária
-- ------------------------------------------------------------
drop server if exists pec_origem cascade;

create server pec_origem
  foreign data wrapper postgres_fdw
  options (
    host 'db.leojfqlbdtlriemdgnyw.supabase.co',
    port '5432',
    dbname 'postgres'
  );

create user mapping for current_user
  server pec_origem
  options (
    user 'postgres',
    password 'SENHA_DO_BANCO_DA_PECUARIA'   -- <<< TROQUE AQUI
  );

-- Espelha as tabelas da Pecuária num schema separado (pec_origem_dados).
-- São tabelas "janela": não copiam dado, só apontam pro banco de lá.
drop schema if exists pec_origem_dados cascade;
create schema pec_origem_dados;

import foreign schema public
  from server pec_origem
  into pec_origem_dados;

-- ✅ TESTE DA CONEXÃO — se esta linha der erro, o FDW não passou.
-- Nesse caso pare aqui e me avise: partimos pro plano B (CSV pelo Table Editor).
select count(*) as teste_conexao_lotes from pec_origem_dados.lotes;


-- ------------------------------------------------------------
-- 3.3 — Cópia, na ordem certa (pai antes de filho)
--
-- A ordem foi calculada a partir das FKs reais da Pecuária. Não reordene.
-- 'overriding system value' é necessário porque as colunas id são
-- 'generated always as identity' — sem isso o Postgres recusa o id original
-- e a numeração histórica se perde.
--
-- Não copiamos: profiles (vira merge no passo 4) e fazendas (morta).
-- ------------------------------------------------------------
insert into lotes                     overriding system value select * from pec_origem_dados.lotes;
insert into abates                    overriding system value select * from pec_origem_dados.abates;
insert into animais                   overriding system value select * from pec_origem_dados.animais;
insert into config_fazenda            overriding system value select * from pec_origem_dados.config_fazenda;
insert into config_financeiro         overriding system value select * from pec_origem_dados.config_financeiro;
insert into custos_fixos              overriding system value select * from pec_origem_dados.custos_fixos;
insert into partos                    overriding system value select * from pec_origem_dados.partos;
insert into desmamas                  overriding system value select * from pec_origem_dados.desmamas;
insert into diagnosticos_gestacionais overriding system value select * from pec_origem_dados.diagnosticos_gestacionais;
insert into dietas                    overriding system value select * from pec_origem_dados.dietas;
insert into ingredientes              overriding system value select * from pec_origem_dados.ingredientes;
insert into investimentos             overriding system value select * from pec_origem_dados.investimentos;
insert into leituras_cocho            overriding system value select * from pec_origem_dados.leituras_cocho;
insert into manejos                   overriding system value select * from pec_origem_dados.manejos;
insert into movimentos                overriding system value select * from pec_origem_dados.movimentos;
insert into pasto                     overriding system value select * from pec_origem_dados.pasto;
insert into pesagens                  overriding system value select * from pec_origem_dados.pesagens;
insert into pesagens_animais          overriding system value select * from pec_origem_dados.pesagens_animais;
insert into precos_arroba             overriding system value select * from pec_origem_dados.precos_arroba;
insert into producoes_racao           overriding system value select * from pec_origem_dados.producoes_racao;
insert into protocolos_inseminacao    overriding system value select * from pec_origem_dados.protocolos_inseminacao;
insert into receitas                  overriding system value select * from pec_origem_dados.receitas;
insert into reproducao_custos         overriding system value select * from pec_origem_dados.reproducao_custos;
insert into saidas_racao              overriding system value select * from pec_origem_dados.saidas_racao;


-- ------------------------------------------------------------
-- 3.4 — Acertar as sequências de id
--
-- Sem isto, o próximo cadastro tenta usar id 1 e estoura com "duplicate key".
-- Este bloco varre todas as tabelas copiadas e reposiciona cada sequência
-- logo acima do maior id existente.
-- ------------------------------------------------------------
do $$
declare
  t text;
  seq text;
  maxid bigint;
begin
  foreach t in array array[
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  ] loop
    seq := pg_get_serial_sequence('public.' || t, 'id');
    if seq is not null then
      execute format('select coalesce(max(id), 0) from public.%I', t) into maxid;
      execute format('select setval(%L, %s)', seq, greatest(maxid, 1));
      raise notice 'sequência de % reposicionada em %', t, greatest(maxid, 1);
    end if;
  end loop;
end $$;


-- ------------------------------------------------------------
-- 3.5 — ✅ CONFERÊNCIA OBRIGATÓRIA
--
-- Compara linha a linha origem x destino. A coluna "confere" tem que dar
-- OK em TODAS as tabelas. Se alguma der DIFERENTE, pare e me chame antes
-- de seguir pro passo 4.
-- ------------------------------------------------------------
do $$
declare
  t text;
  n_orig bigint;
  n_dest bigint;
begin
  raise notice '%-28s %10s %10s  %s', 'TABELA', 'ORIGEM', 'DESTINO', 'CONFERE';
  foreach t in array array[
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  ] loop
    execute format('select count(*) from pec_origem_dados.%I', t) into n_orig;
    execute format('select count(*) from public.%I', t) into n_dest;
    raise notice '%-28s %10s %10s  %s', t, n_orig, n_dest,
      case when n_orig = n_dest then 'OK' else '*** DIFERENTE ***' end;
  end loop;
end $$;
