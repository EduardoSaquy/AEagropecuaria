"""
Ensaio dos SQL de seguranca e da troca de nome do ERP (nao e um teste_*.py:
precisa de um Postgres de verdade, entao fica fora da rodada normal).

Executa de verdade, num Postgres descartavel, os 4 scripts:
  seguranca_01_fecha_view_para_anonimo.sql
  erp_20_tira_o_nome_antigo_do_banco.sql
  erp_21_confere_o_que_sobrou.sql
  erp_22_arremata_o_que_sobrou.sql
  seguranca_02_view_so_para_quem_tem_permissao.sql
  seguranca_02_confere_como_cada_um_ve.sql
sobre um banco montado como o de producao ANTES da troca de nome (view com a
coluna antiga, indice parcial unico, trava de origem, gatilho de auditoria,
tabela de pouso, comentarios) e confere o resultado.

Precisa de um venv a parte com o Postgres embutido (nada vai para o sistema):

    python -m venv pgvenv
    pgvenv/Scripts/python -m pip install pgserver psycopg2-binary
    pgvenv/Scripts/python ensaio_sql_banco.py

Ultima rodada: 16/10/2026, todas ok (o numero impresso no fim). O banco do ensaio imita o de
producao ANTES da troca (view com a coluna antiga, indice parcial unico, trava
de origem, gatilho de auditoria, tabela de pouso, comentarios).
"""
import json
import sys
import tempfile
import time
from pathlib import Path

import pgserver
import psycopg2

REPO = Path(__file__).resolve().parent
V = "con" + "ag"          # nome antigo, montado por pedacos
VC = V.capitalize()       # so a primeira letra maiuscula
VU = V.upper()            # tudo em maiusculas

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

pgdata = Path(tempfile.mkdtemp(prefix="ensaio_pg_"))
srv = pgserver.get_server(pgdata, cleanup_mode="delete")
uri = srv.get_uri()
print("servidor:", uri.split("@")[-1])

def nova_conexao():
    c = psycopg2.connect(uri)
    c.autocommit = True
    return c

def escalar(cur, sql, *args):
    cur.execute(sql, args or None)
    r = cur.fetchone()
    return r[0] if r else None

def roda_arquivo(nome, n_linhas_final=False):
    """roda o arquivo todo numa chamada so (como o editor do Supabase)"""
    sql = (REPO / nome).read_text(encoding="utf-8")
    con = nova_conexao()
    cur = con.cursor()
    try:
        cur.execute(sql)
        try:
            return cur.fetchall(), None
        except psycopg2.ProgrammingError:
            return None, None
    except Exception as e:
        return None, e
    finally:
        con.close()

def monta_banco(n_importados=9400):
    """banco como estava em producao antes da troca de nome"""
    con = nova_conexao(); cur = con.cursor()
    cur.execute("drop schema if exists public cascade; create schema public;")
    cur.execute("""
      do $$ begin
        if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
        if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
      end $$;
      grant usage on schema public to anon, authenticated;
      alter default privileges in schema public grant all on tables to anon, authenticated;
    """)
    cur.execute(f"""
      create table talhoes_areas (id int primary key);
      create table lancamentos_financeiros (
        id bigint generated always as identity primary key,
        tipo text, atividade text, fazenda_id int, valor numeric(14,2),
        descricao text, fornecedor text, data date, mes text,
        observacao text, criado_por text, {V}_id text, contrato text, cnpj_nota text);
      create unique index uq_lancamento_{V} on lancamentos_financeiros ({V}_id) where {V}_id is not null;
      comment on column lancamentos_financeiros.{V}_id is 'Id do titulo no {VC} (a segunda parte do Cod-Id).';
      create table lancamento_rateios (id bigint generated always as identity primary key,
        lancamento_id bigint references lancamentos_financeiros(id), atividade text, valor numeric(14,2));
      create view lancamentos_rateados as
        select l.id as lancamento_id, r.id as rateio_id, l.tipo, r.atividade, r.valor, l.descricao, l.fornecedor,
               l.{V}_id, l.contrato, true as rateado, l.observacao, l.criado_por, l.cnpj_nota
          from lancamentos_financeiros l join lancamento_rateios r on r.lancamento_id = l.id
        union all
        select l.id, null, l.tipo, l.atividade, l.valor, l.descricao, l.fornecedor,
               l.{V}_id, l.contrato, false, l.observacao, l.criado_por, l.cnpj_nota
          from lancamentos_financeiros l
         where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);
      comment on view lancamentos_rateados is 'O financeiro ja rateado.';
      create table financiamentos (id bigint generated always as identity primary key, banco text, observacao text);
      create table movimentos_financiamento (
        id bigint generated always as identity primary key,
        data date not null, tipo text not null check (tipo in ('entrada','amortizacao')),
        valor numeric(14,2) not null check (valor > 0), credor text, contrato text, descricao text,
        origem text not null default 'manual' check (origem in ('manual','{V}')),
        {V}_id bigint unique, financiamento_id bigint references financiamentos(id) on delete set null);
      create table {V}_staging (id int, {V}_id text, cnpj_nota text);
      comment on table {V}_staging is 'Mesa de pouso do CSV do {VC}.';
      create table {V}_plano_contas (grupo text);
      comment on table {V}_plano_contas is 'Plano de contas do {VC} lido do balancete.';
      create table custos_fixos (id bigint generated always as identity primary key, nome text, observacao text, valor_mensal numeric(14,2));
      create table log_alteracoes (id bigint generated always as identity primary key, tabela text, operacao text, antes jsonb, depois jsonb);
      create or replace function registrar_alteracao() returns trigger language plpgsql as $f$
      begin
        if TG_OP = 'UPDATE' and to_jsonb(OLD) = to_jsonb(NEW) then return NEW; end if;
        insert into log_alteracoes (tabela, operacao, antes, depois)
          values (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        return NEW;
      end $f$;
      create trigger trg_registrar_alteracao after insert or update or delete on lancamentos_financeiros
        for each row execute function registrar_alteracao();
    """)
    # dados: importados do ERP (n_importados) + 2 fornecedores reais + 1 lancamento digitado no app
    cur.execute(f"""
      alter table lancamentos_financeiros disable trigger trg_registrar_alteracao;
      insert into lancamentos_financeiros (tipo, atividade, valor, descricao, fornecedor, mes, observacao, criado_por, {V}_id, contrato)
      select 'despesa', 'cana', 100 + g, 'Adubo ' || g, 'FORNECEDOR ' || (g % 50), '2025-06',
             '{VC} ' || (1000 + g) || ' - Boleto', '{VC}', g::text, null
        from generate_series(1, {n_importados}) g;
      insert into lancamentos_financeiros (tipo, atividade, valor, descricao, fornecedor, mes, observacao, criado_por, {V}_id)
        values ('despesa','cana', 10, '{VC} — Contas a Pagar cana, rateio por área da fazenda', 'Rateio', '2026-02', '{VC} 77 - PIX', '{VC}', 'x1'),
               ('despesa','pecuaria', 20, 'Mão de obra - importação {VC}', 'Folha', '2026-03', '{VC} 78 - TED', '{VC}', 'x2'),
               ('despesa','geral', 30, '{VU} CONSULTORIA', '{VU} CONSULTORIA', '2026-04', null, 'Maria', null),
               ('despesa','geral', 40, 'Mensalidade', '{VU} - TECNOLOGIA AO AGRONEGOCIO LTDA', '2026-05', 'nota fiscal 9', 'Joao', null),
               ('despesa','geral', 50, 'Digitado no app', 'Posto', '2026-05', 'sem relacao', 'Maria', null);
      insert into lancamentos_financeiros (tipo, atividade, valor, descricao, fornecedor, mes, observacao, criado_por)
        select 'despesa', 'pecuaria', 500 + g, 'Mão de obra - importação {VC}', 'Folha', '2025-0' || g,
               'Importado da {VC} (soma dos funcionarios ativos no mes, sem nome individual/CPF/Pix). Nao classificado.', null
          from generate_series(1, 3) g;
      insert into custos_fixos (nome, observacao, valor_mensal) values
        ('Mão de obra - importação {VC}', 'Importado da {VC} (soma dos funcionarios ativos no mes)', 100),
        ('Mão de obra - importação {VC}', 'Importado da {VC} (soma dos funcionarios ativos no mes)', 110),
        ('Energia', 'Lancado na {VC} e conferido pela {VC}', 50),
        ('Manutencao', 'Conta de luz', 60);
      alter table lancamentos_financeiros enable trigger trg_registrar_alteracao;
      insert into lancamento_rateios (lancamento_id, atividade, valor)
        select id, 'cana', valor / 2 from lancamentos_financeiros where {V}_id = '5';
      insert into financiamentos (banco, observacao) values
        ('BB', 'Importado do {VC} (contrato C09): cronograma real, uma parcela por linha do {VC}; juros das parcelas a vencer estimado pela taxa informada.'),
        ('Sicoob', 'contrato digitado a mao');
      insert into movimentos_financiamento (data, tipo, valor, credor, contrato, descricao, origem, {V}_id)
        select date '2025-01-15' + g, 'amortizacao', 1000 + g, 'BANCO', 'C0' || (g % 3), 'Parcela {VC} ' || g, '{V}', g
          from generate_series(1, 20) g;
      insert into {V}_staging select g, g::text, '123' from generate_series(1, 5) g;
    """)
    con.close()

def estado():
    con = nova_conexao(); cur = con.cursor()
    d = {}
    d["cols_lanc"] = [r[0] for r in (cur.execute("select column_name from information_schema.columns where table_name='lancamentos_financeiros'") or cur.fetchall())]
    cur.execute("select column_name from information_schema.columns where table_name='movimentos_financiamento'"); d["cols_mov"] = [r[0] for r in cur.fetchall()]
    cur.execute("select column_name from information_schema.columns where table_name='lancamentos_rateados'"); d["cols_view"] = [r[0] for r in cur.fetchall()]
    cur.execute("select indexname from pg_indexes where schemaname='public' order by 1"); d["indices"] = [r[0] for r in cur.fetchall()]
    cur.execute("select to_regclass('public.%s_staging') is not null, to_regclass('public.%s_plano_contas') is not null, to_regclass('public.erp_plano_contas') is not null" % (V, V)); d["tabelas"] = cur.fetchone()
    cur.execute("select count(*) from log_alteracoes"); d["log"] = cur.fetchone()[0]
    cur.execute("select tgenabled from pg_trigger where tgname='trg_registrar_alteracao'"); d["gatilho"] = cur.fetchone()[0]
    con.close()
    return d

# ---------------------------------------------------------------- A
print("\n  1. seguranca_01_fecha_view_para_anonimo.sql")
monta_banco()
con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, "select has_table_privilege('anon','public.lancamentos_rateados','select')") is True, "antes: o anon le a view (reproduz o furo)")
con.close()
res, err = roda_arquivo("seguranca_01_fecha_view_para_anonimo.sql")
conf(err is None, "o script roda inteiro sem erro", str(err))
conf(res == [(False, True)], "resultado final: anon_le=false, logado_le=true", str(res))
con = nova_conexao(); cur = con.cursor()
cur.execute("set role anon")
try:
    cur.execute("select count(*) from lancamentos_rateados"); lido = cur.fetchone()[0]; negado = False
except psycopg2.errors.InsufficientPrivilege:
    lido, negado = None, True
cur.execute("reset role")
conf(negado, "o anon recebe 'permission denied' ao ler a view", str(lido))
cur.execute("set role authenticated")
cur.execute("select count(*) from lancamentos_rateados"); logado = cur.fetchone()[0]
cur.execute("reset role")
conf(logado > 9400, "quem esta logado continua lendo a view", str(logado))
con.close()
res2, err2 = roda_arquivo("seguranca_01_fecha_view_para_anonimo.sql")
conf(err2 is None and res2 == [(False, True)], "rodar de novo nao da erro nem muda o resultado", str(err2))

# ---------------------------------------------------------------- B
print("\n  2. erp_20_tira_o_nome_antigo_do_banco.sql")
monta_banco()
antes = estado()
conf(f"{V}_id" in antes["cols_lanc"] and f"{V}_id" in antes["cols_view"], "antes: colunas com o nome antigo existem")
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
conf(err is None, "o script roda inteiro sem erro", str(err))
conf(res and "Pronto" in res[0][0], "chega ao fim", str(res))
dep = estado()
conf("erp_id" in dep["cols_lanc"] and f"{V}_id" not in dep["cols_lanc"], "lancamentos_financeiros: coluna renomeada", str(dep["cols_lanc"]))
conf("erp_id" in dep["cols_mov"] and f"{V}_id" not in dep["cols_mov"], "movimentos_financiamento: coluna renomeada", str(dep["cols_mov"]))
conf("erp_id" in dep["cols_view"] and f"{V}_id" not in dep["cols_view"], "view lancamentos_rateados: coluna renomeada", str(dep["cols_view"]))
conf(not any(V in i for i in dep["indices"]) and "uq_lancamento_erp" in dep["indices"], "indices renomeados", str(dep["indices"]))
conf(dep["tabelas"] == (False, False, True), "tabela de pouso apagada e plano de contas renomeado", str(dep["tabelas"]))
conf(dep["log"] == antes["log"], "o log de alteracoes nao ganhou linhas da troca em massa", f'{antes["log"]} -> {dep["log"]}')
conf(dep["gatilho"] == "O", "o gatilho de auditoria voltou a ficar ligado", str(dep["gatilho"]))

con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where criado_por = '{VC}'") == 0, "criado_por: nenhum com o nome antigo")
conf(escalar(cur, "select count(*) from lancamentos_financeiros where criado_por = 'ERP'") == 9402, "criado_por: 9.402 viraram ERP")
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where observacao ilike '{V}%'") == 0, "observacao: nenhuma comeca com o nome antigo")
conf(escalar(cur, "select observacao from lancamentos_financeiros where erp_id = '1'") == "ERP 1001 - Boleto", "observacao: 'ERP 1001 - Boleto'", escalar(cur, "select observacao from lancamentos_financeiros where erp_id = '1'"))
conf(escalar(cur, "select observacao from lancamentos_financeiros where erp_id = 'x2'") == "ERP 78 - TED", "observacao do 2o exemplo")
conf(escalar(cur, "select descricao from lancamentos_financeiros where erp_id = 'x1'") == "ERP — Contas a Pagar cana, rateio por área da fazenda", "descricao com o nome no comeco foi trocada")
conf(escalar(cur, "select descricao from lancamentos_financeiros where erp_id = 'x2'") == "Mão de obra - importação ERP", "descricao com o nome no fim foi trocada")
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where fornecedor = '{VU} CONSULTORIA' and descricao = '{VU} CONSULTORIA'") == 1, "fornecedor real em MAIUSCULAS ficou intacto")
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where fornecedor = '{VU} - TECNOLOGIA AO AGRONEGOCIO LTDA'") == 1, "segundo fornecedor real ficou intacto")
conf(escalar(cur, "select observacao from lancamentos_financeiros where descricao = 'Digitado no app'") == "sem relacao", "lancamento digitado no app nao foi tocado")
conf(escalar(cur, "select count(*) from movimentos_financiamento where origem = 'erp'") == 20, "movimentos: origem passou a erp")
conf(escalar(cur, "select count(*) from movimentos_financiamento where descricao like 'Parcela ERP %'") == 20, "movimentos: descricao trocada")
try:
    cur.execute("insert into movimentos_financiamento (data,tipo,valor,origem) values ('2026-01-01','amortizacao',1,'qualquer')"); rejeitou = False
except psycopg2.errors.CheckViolation:
    rejeitou = True
conf(rejeitou, "a trava de origem continua valendo (rejeita valor fora de manual/erp)")
cur.execute("insert into movimentos_financiamento (data,tipo,valor,origem) values ('2026-01-01','amortizacao',1,'manual')")
conf(True, "origem 'manual' continua aceita")
cur.execute("select observacao from financiamentos order by id"); fin = [r[0] for r in cur.fetchall()]
conf(fin[0].startswith("Importado do ERP (contrato C09)") and "linha do ERP;" in fin[0], "contrato importado: observacao trocada", fin[0][:90])
conf(fin[1] == "contrato digitado a mao", "contrato digitado a mao ficou como estava")
# unicidade do id do ERP continua valendo
try:
    cur.execute("insert into lancamentos_financeiros (tipo, valor, erp_id) values ('despesa', 1, '1')"); dup = False
except psycopg2.errors.UniqueViolation:
    dup = True
conf(dup, "o indice unico do id do ERP continua impedindo duplicar")
# view: lê pelo novo nome
conf(escalar(cur, "select count(*) from lancamentos_rateados where erp_id is not null") >= 9400, "a view devolve a coluna nova")
# comentarios
cur.execute("select col_description('lancamentos_financeiros'::regclass, (select attnum from pg_attribute where attrelid='lancamentos_financeiros'::regclass and attname='erp_id'))")
conf("ERP" in cur.fetchone()[0], "comentario da coluna trocado")
conf("ERP" in escalar(cur, "select obj_description('erp_plano_contas'::regclass)"), "comentario da tabela de plano de contas trocado")
con.close()

# segunda rodada
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
conf(err is None and res and "Pronto" in res[0][0], "rodar de novo nao da erro (idempotente)", str(err))
dep2 = estado()
conf(dep2["log"] == dep["log"], "segunda rodada tambem nao mexe no log")

# ---------------------------------------------------------------- C
print("\n  3. erp_21_confere_o_que_sobrou.sql")
res, err = roda_arquivo("erp_21_confere_o_que_sobrou.sql")
conf(err is None, "o script roda sem erro", str(err))
linhas = {(t, o): n for t, o, n in (res or [])}
print("      sobrou:", linhas)
esperado = {("texto", "lancamentos_financeiros.fornecedor"), ("texto", "lancamentos_financeiros.descricao")}
conf(esperado <= set(linhas), "lista os dois fornecedores reais (fornecedor e descricao)")
arremate = {("texto", "lancamentos_financeiros.observacao"), ("texto", "custos_fixos.nome"), ("texto", "custos_fixos.observacao")}
conf(arremate <= set(linhas), "a conferencia acha o que o erp_20 deixou para tras (observacao com o nome no meio e custos_fixos)")
extras = {k for k in linhas if k not in esperado and k not in arremate and k[1].split(".")[0] != "log_alteracoes"}
conf(not extras, "e nada alem disso (o erp_22 trata esses)", str(extras))
conf(linhas.get(("texto", "lancamentos_financeiros.fornecedor")) == 2, "contagem de fornecedor = 2", str(linhas.get(("texto", "lancamentos_financeiros.fornecedor"))))

# ---------------------------------------------------------------- guarda
print("\n  4. guardas")
monta_banco()
con = nova_conexao(); cur = con.cursor()
cur.execute(f"create function relatorio_antigo() returns bigint language sql as $$ select count(*) from lancamentos_financeiros where {V}_id is not null $$;")
con.close()
antes = estado()
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
conf(err is not None and "relatorio_antigo" in str(err), "funcao que cita o nome antigo faz o script parar", str(err)[:120])
dep = estado()
conf(dep["cols_lanc"] == antes["cols_lanc"] and dep["tabelas"] == antes["tabelas"], "e nada foi alterado (transacao desfeita)")

monta_banco(n_importados=50)
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
dep = estado()
conf(err is None and dep["tabelas"][0] is True, "com poucos lancamentos importados a tabela de pouso e MANTIDA", str(err))

# ---------------------------------------------------------------- D
print("\n  5. erp_22_arremata_o_que_sobrou.sql (o que a conferencia achou na producao)")
# sem o erp_20 antes, o script se recusa e nao muda nada
monta_banco()
antes = estado()
res, err = roda_arquivo("erp_22_arremata_o_que_sobrou.sql")
conf(err is not None and "erp_20" in str(err), "sem o erp_20 antes, recusa e avisa", str(err)[:100])
conf(estado()["cols_lanc"] == antes["cols_lanc"], "e nao muda nada")

# estado da producao depois do erp_20 antigo: pouco importado => tabela de pouso mantida
monta_banco(n_importados=50)
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
conf(err is None and estado()["tabelas"][0] is True, "ponto de partida: erp_20 rodou e a tabela de pouso ficou")
con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where observacao like 'Importado da {VC}%'") == 3, "ponto de partida: 3 observacoes com o nome no meio sobraram")
con.close()
log0 = estado()["log"]

res, err = roda_arquivo("erp_22_arremata_o_que_sobrou.sql")
conf(err is None, "com poucos importados roda sem erro", str(err))
conf(estado()["tabelas"][0] is True, "e MANTEM a tabela de pouso (importacao ainda nao esta no banco)")

# agora a producao: ~8,5 mil importados (depois da duplicidade apagada)
con = nova_conexao(); cur = con.cursor()
cur.execute("alter table lancamentos_financeiros disable trigger trg_registrar_alteracao")
cur.execute("insert into lancamentos_financeiros (tipo, valor, erp_id) select 'despesa', 1, 'y' || g from generate_series(1, 8500) g")
cur.execute("alter table lancamentos_financeiros enable trigger trg_registrar_alteracao")
log0 = escalar(cur, "select count(*) from log_alteracoes")
con.close()
res, err = roda_arquivo("erp_22_arremata_o_que_sobrou.sql")
conf(err is None, "com 8,5 mil importados roda sem erro", str(err))
d = estado()
conf(d["tabelas"][0] is False, "e apaga a tabela de pouso (a trava de 9 mil era alta demais)")
conf(d["log"] == log0, "sem linhas novas no registro de alteracoes", f'{log0} -> {d["log"]}')
conf(d["gatilho"] == "O", "gatilho de auditoria de volta ao normal")

con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where observacao ilike '%{V}%'") == 0, "observacao: nenhuma com o nome")
conf(escalar(cur, "select count(*) from lancamentos_financeiros where observacao like 'Importado do ERP (soma dos funcionarios%'") == 3, "observacao: 'Importado da <nome>' virou 'Importado do ERP'")
cur.execute("select nome, observacao from custos_fixos order by id")
cf = cur.fetchall()
conf(cf[0] == ("Mão de obra - importação ERP", "Importado do ERP (soma dos funcionarios ativos no mes)"), "custos_fixos: nome e observacao trocados", str(cf[0]))
conf(cf[2][1] == "Lancado no ERP e conferido pelo ERP", "custos_fixos: 'na' e 'pela' concordam com ERP", cf[2][1])
conf(cf[3] == ("Manutencao", "Conta de luz"), "custos_fixos: linha sem o nome ficou intacta")
conf(escalar(cur, f"select count(*) from lancamentos_financeiros where fornecedor = '{VU} CONSULTORIA'") == 1, "fornecedor real em MAIUSCULAS continua intacto")
conf(escalar(cur, "select descricao from lancamentos_financeiros where erp_id = 'x2'") == "Mão de obra - importação ERP", "o que o erp_20 ja tinha trocado nao mudou")
con.close()
linhas = {(t, o): n for t, o, n in (res or [])}
print("      sobrou:", linhas)
conf(("texto", "lancamentos_financeiros.fornecedor") in linhas and linhas[("texto", "lancamentos_financeiros.fornecedor")] == 2, "a conferencia do fim lista so os 2 fornecedores reais")
conf(not {k for k in linhas if k[1].split(".")[0] not in ("lancamentos_financeiros", "log_alteracoes")}, "e nenhuma tabela, coluna, trava ou comentario antigo", str(linhas))

res2, err2 = roda_arquivo("erp_22_arremata_o_que_sobrou.sql")
conf(err2 is None, "rodar de novo nao da erro (idempotente)", str(err2))
conf(estado()["log"] == log0, "e tambem nao mexe no registro de alteracoes")

# o limite: 8,5 mil importados e suficiente para o erp_20 tambem
monta_banco(n_importados=8500)
res, err = roda_arquivo("erp_20_tira_o_nome_antigo_do_banco.sql")
conf(err is None and estado()["tabelas"][0] is False, "erp_20 com 8,5 mil importados tambem apaga a tabela de pouso", str(err))

# ---------------------------------------------------------------- E
print("\n  6. seguranca_02_view_so_para_quem_tem_permissao.sql")

def uid(nome):
    import hashlib
    h = hashlib.md5(nome.encode()).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"

USUARIOS = {   # nome: (papel, ativo, permissoes, o que deve ver na view)
    "admin":      ("admin", True, {}, "tudo"),
    "dono":       ("proprietario", True, {}, "tudo"),
    "res_ver":    ("gestor", True, {"matriz_resultados": "visualizar"}, "tudo"),
    "res_editar": ("gestor", True, {"matriz_resultados": "editar"}, "tudo"),
    "fin_ver":    ("gestor", True, {"matriz_financeiro": "visualizar"}, "tudo"),
    "pec_fin":    ("gestor", True, {"pec_financeiro": "visualizar"}, "pecuaria"),
    "pec_res":    ("gestor", True, {"pec_resultados": "editar"}, "pecuaria"),
    "vendas":     ("gestor", True, {"vendas": "visualizar"}, "pecuaria"),
    "confina":    ("operador", True, {"confinamento": "visualizar"}, "pecuaria"),
    "pasto":      ("operador", True, {"pasto": "editar"}, "pecuaria"),
    "cria":       ("operador", True, {"cria": "visualizar"}, "pecuaria"),
    "lotes":      ("operador", True, {"lotesGeral": "visualizar"}, "pecuaria"),
    "manejo":     ("operador", True, {"manejo": "editar", "cadastro": "editar"}, "nada"),
    "cana":       ("operador", True, {"cana_cadastros": "editar", "operacoes": "editar"}, "nada"),
    "comb":       ("operador", True, {"combustivel_abastecimento": "editar"}, "nada"),
    "painel":     ("gestor", True, {"matriz_painel_cana": "visualizar", "matriz_financiamentos": "editar"}, "nada"),
    "sem_nada":   ("operador", True, {}, "nada"),
    "pec_so_edita_outro": ("operador", True, {"pec_financeiro": "nenhum"}, "nada"),
    "admin_inativo": ("admin", False, {}, "nada"),
}

def monta_banco_permissoes(n=3000, rateados=100):
    con = nova_conexao(); cur = con.cursor()
    cur.execute("drop schema if exists public cascade; drop schema if exists auth cascade; create schema public; create schema auth;")
    cur.execute("""
      do $$ begin
        if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
        if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
        if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
      end $$;
      grant usage on schema public, auth to anon, authenticated, service_role;
      alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
      create function auth.uid() returns uuid language sql stable as $$
        select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
      grant execute on function auth.uid() to anon, authenticated, service_role;
    """)
    cur.execute("""
      create table talhoes_areas (id int primary key);
      create table profiles (id uuid primary key, nome text, papel text not null default 'operador',
                             permissoes jsonb not null default '{}'::jsonb, ativo boolean not null default true);
      create function is_admin() returns boolean language sql security definer set search_path = public stable as $$
        select exists(select 1 from profiles where id = auth.uid() and papel = 'admin' and ativo = true) $$;
      create function acesso_total() returns boolean language sql security definer set search_path = public stable as $$
        select exists(select 1 from profiles where id = auth.uid() and papel in ('admin', 'proprietario') and ativo = true) $$;
      create function tem_permissao(modulo text, nivel text) returns boolean language sql security definer set search_path = public stable as $$
        select case
          when acesso_total() then true
          when nivel = 'visualizar' then (select permissoes->>modulo in ('visualizar','editar') from profiles where id = auth.uid() and ativo = true)
          else (select permissoes->>modulo = 'editar' from profiles where id = auth.uid() and ativo = true)
        end $$;
      create table lancamentos_financeiros (
        id bigint generated always as identity primary key,
        tipo text, atividade text, fazenda_id int, cultura_id int, valor numeric(14,2),
        centro_custo_id int, descricao text, fornecedor text, data date, mes text,
        erp_id text, contrato text, observacao text, talhao_id int, lote_id int,
        areas text[], arrobas numeric, abate_id int, criado_por text, quantidade numeric,
        unidade text, safra_id int, cnpj_nota text, vencimento date, ano_safra int);
      create table lancamento_rateios (
        id bigint generated always as identity primary key,
        lancamento_id bigint references lancamentos_financeiros(id),
        atividade text, fazenda_id int, cultura_id int, valor numeric(14,2));
      alter table lancamentos_financeiros enable row level security;
      create policy "ve lancamentos" on lancamentos_financeiros for select using (
        is_admin() or tem_permissao('matriz_financeiro','visualizar')
        or (atividade = 'pecuaria' and (tem_permissao('pec_financeiro','visualizar') or tem_permissao('pec_resultados','visualizar') or tem_permissao('vendas','visualizar'))));
    """)
    for nome, (papel, ativo, perm, _) in USUARIOS.items():
        cur.execute("insert into profiles (id, nome, papel, permissoes, ativo) values (%s, %s, %s, %s, %s)",
                    (uid(nome), nome, papel, json.dumps(perm), ativo))
    cur.execute(f"""
      insert into lancamentos_financeiros (tipo, atividade, valor, descricao, fornecedor, mes, observacao, erp_id, cnpj_nota, ano_safra)
      select 'despesa', (array['cana','graos','pecuaria','geral'])[1 + g % 4], 10 + g, 'Lancamento ' || g,
             'FORNECEDOR ' || (g % 30), '2026-0' || (1 + g % 9), 'obs ' || g, g::text, '1234567800' || (g % 100), 2025
        from generate_series(1, {n}) g;
      insert into lancamento_rateios (lancamento_id, atividade, valor)
        select l.id, a, (l.valor / 3)::numeric(14,2)
          from (select id, valor from lancamentos_financeiros where atividade = 'geral' order by id limit {rateados}) l
          cross join unnest(array['cana','graos','pecuaria']) a;
    """)
    con.close()
    # o que o seguranca_01 ja fechou em producao; a view nasce do script de verdade
    res, err = roda_arquivo("lancamentos_rateados_03_ano_safra.sql")
    assert err is None, err
    res, err = roda_arquivo("seguranca_01_fecha_view_para_anonimo.sql")
    assert err is None, err

def como(nome_ou_uid, role="authenticated"):
    """conexao que se comporta como o PostgREST: papel do banco + dados do JWT, numa transacao"""
    con = psycopg2.connect(uri); con.autocommit = False
    cur = con.cursor()
    cur.execute(f"set local role {role}")
    u = uid(nome_ou_uid) if nome_ou_uid in USUARIOS else nome_ou_uid
    cur.execute("select set_config('request.jwt.claims', %s, true), set_config('request.jwt.claim.sub', %s, true)",
                (json.dumps({"sub": u, "role": role}), u))
    return con, cur

def conta(nome, role="authenticated", where=""):
    con, cur = como(nome, role)
    try:
        cur.execute(f"select count(*), count(*) filter (where atividade = 'pecuaria'), count(distinct atividade) from lancamentos_rateados {where}")
        return cur.fetchone()
    except psycopg2.errors.InsufficientPrivilege:
        return "negado"
    finally:
        con.rollback(); con.close()

monta_banco_permissoes()
con = nova_conexao(); cur = con.cursor()
total = escalar(cur, "select count(*) from lancamentos_rateados")
pecuaria = escalar(cur, "select count(*) from lancamentos_rateados where atividade = 'pecuaria'")
cur.execute("select column_name, ordinal_position, data_type from information_schema.columns where table_name='lancamentos_rateados' order by ordinal_position")
colunas_antes = cur.fetchall()
con.close()
conf(total == 3000 - 100 + 300 and pecuaria == 750 + 100, f"base do ensaio: {total} linhas na view, {pecuaria} de pecuaria", f"{total} {pecuaria}")

# o problema, reproduzido: antes da regra, quem nao tem permissao nenhuma le tudo
conf(conta("sem_nada")[0] == total, "antes: um usuario sem permissao nenhuma le a view inteira (reproduz o furo)", str(conta("sem_nada")))

res, err = roda_arquivo("seguranca_02_view_so_para_quem_tem_permissao.sql")
conf(err is None, "o script roda inteiro sem erro", str(err))
conf(res is not None and len(res) == len(USUARIOS), f"termina com a lista de quem ve o que ({len(USUARIOS)} pessoas)", str(len(res or [])))
lista = {n: v for n, _, v in (res or [])}
esperado_lista = {n: ({"tudo": "tudo", "pecuaria": "so pecuaria", "nada": "nada"}[o] if USUARIOS[n][1] else "(inativo)") for n, (_, _, _, o) in USUARIOS.items()}
conf(lista == esperado_lista, "a lista final bate com a regra para cada perfil", str({k: (lista.get(k), v) for k, v in esperado_lista.items() if lista.get(k) != v}))

con = nova_conexao(); cur = con.cursor()
cur.execute("select column_name, ordinal_position, data_type from information_schema.columns where table_name='lancamentos_rateados' order by ordinal_position")
conf(cur.fetchall() == colunas_antes, "a view manteve as mesmas colunas, na mesma ordem e com os mesmos tipos")
con.close()

# cada perfil enxerga exatamente o que a regra manda, pela mesma porta da API (papel authenticated + JWT)
for nome, (papel, ativo, perm, ve) in USUARIOS.items():
    r = conta(nome)
    if not ativo or ve == "nada":
        ok = r[0] == 0
    elif ve == "pecuaria":
        ok = r[0] == pecuaria and r[2] == 1
    else:
        ok = r[0] == total and r[2] == 4
    conf(ok, f"{nome:20s} -> {ve:8s} (viu {r[0]} linhas, {r[2]} atividades)", str(r))

conf(conta("00000000-0000-0000-0000-00000000dead")[0] == 0, "JWT valido de quem nao tem perfil nenhum: nao ve nada")
conf(conta("sem_nada", where="where atividade = 'pecuaria'")[0] == 0, "e filtrar por atividade no pedido nao muda nada para quem nao tem permissao")
pec = conta("pec_fin", where="where atividade <> 'pecuaria'")
conf(pec[0] == 0, "quem so tem Pecuaria pedindo cana/graos/geral na API: nada", str(pec))
conf(conta("anon", role="anon") == "negado", "o anon continua recebendo 'permission denied'")
conf(conta("sem_nada", role="service_role")[0] == total, "service_role (automacao do banco) ve tudo")
con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, "select count(*) from lancamentos_rateados") == total, "o editor do Supabase (postgres) ve tudo: os scripts de conferencia continuam valendo")
con.close()

# a pecuaria enxerga a fatia rateada de um lancamento 'geral' (a tabela sozinha esconderia), sem ver a base 'geral'
con, cur = como("pec_fin")
cur.execute("select count(*) from lancamentos_rateados where atividade = 'pecuaria' and rateado")
fatias = cur.fetchone()[0]
cur.execute("select count(*) from lancamentos_financeiros where atividade = 'pecuaria'")
na_tabela = cur.fetchone()[0]
cur.execute("select count(*) from lancamentos_financeiros where atividade = 'geral'")
geral_na_tabela = cur.fetchone()[0]
con.rollback(); con.close()
conf(fatias == 100, "a Pecuaria continua vendo a fatia rateada dela (100 lancamentos 'geral' repartidos)", str(fatias))
conf(na_tabela == 750 and geral_na_tabela == 0, "e a tabela segue com a regra de antes (so atividade pecuaria, nenhum 'geral')", f"{na_tabela} {geral_na_tabela}")

# nao mexeu na tabela nem nas funcoes de permissao
con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, "select count(*) from pg_policies where tablename = 'lancamentos_financeiros'") == 1, "a politica da tabela lancamentos_financeiros nao foi tocada")
conf(escalar(cur, "select count(*) from lancamentos_financeiros") == 3000, "e nenhuma linha foi alterada")
# desempenho: a leitura de uma pagina como a do app (1000 linhas, ordenada) para quem ve tudo e para a pecuaria
con.close()
for quem in ("res_ver", "pec_fin"):
    con, cur = como(quem)
    t0 = time.time()
    for _ in range(5):
        cur.execute("select * from lancamentos_rateados where atividade = 'pecuaria' order by lancamento_id, rateio_id limit 1000 offset 0")
        cur.fetchall()
    dt = (time.time() - t0) / 5
    con.rollback(); con.close()
    conf(dt < 0.5, f"{quem}: pagina de 1000 linhas ordenada em {dt*1000:.0f} ms (limite do ensaio 500 ms)", f"{dt:.3f}s")
con, cur = como("res_ver")
cur.execute("explain select * from lancamentos_rateados where atividade = 'cana'")
plano = "\n".join(r[0] for r in cur.fetchall())
con.rollback(); con.close()
conf("InitPlan" in plano, "a pergunta de permissao roda uma vez por consulta (InitPlan), nao uma vez por linha")

# a conferencia com dados reais: cada pessoa ativa assume o papel authenticated com o JWT dela
res, err = roda_arquivo("seguranca_02_confere_como_cada_um_ve.sql")
conf(err is None, "seguranca_02_confere_como_cada_um_ve.sql roda sem erro", str(err))
linhas_conf = res or []
ativos = [n for n, v in USUARIOS.items() if v[1]]
conf(len(linhas_conf) == 1 + len(ativos), f"lista o total da view e as {len(ativos)} pessoas ativas", str(len(linhas_conf)))
if linhas_conf:
    nome0, papel0, deve0, vistas0, vpec0, outras0, sit0 = linhas_conf[0]
    conf(vistas0 == total and vpec0 == pecuaria, "primeira linha: o total da view e o de pecuaria", str(linhas_conf[0]))
    por_nome = {l[0]: l for l in linhas_conf[1:]}
    conf(all(l[6] == "ok" for l in linhas_conf[1:]), "todas as pessoas: situacao ok (o banco fez o que a regra manda)",
         str([l for l in linhas_conf[1:] if l[6] != "ok"]))
    conf(por_nome["pec_fin"][3] == pecuaria and por_nome["pec_fin"][5] == 0, "e a Pecuaria so enxergou linhas de pecuaria", str(por_nome["pec_fin"]))
    conf(por_nome["sem_nada"][3] == 0, "e quem nao tem permissao enxergou zero")
conf("admin_inativo" not in {l[0] for l in linhas_conf}, "pessoa inativa nao entra na lista")

# idempotencia e quem recria a view
con = nova_conexao(); cur = con.cursor()
conf(escalar(cur, "select public.aplicar_regra_na_view_lancamentos_rateados()") == "A view ja tem a regra de permissao.", "aplicar de novo diz que ja esta aplicada")
nesting = escalar(cur, "select (length(pg_get_viewdef('lancamentos_rateados'::regclass)) - length(replace(pg_get_viewdef('lancamentos_rateados'::regclass), 've_todo_o_financeiro', ''))) / length('ve_todo_o_financeiro')")
# na definicao impressa o nome aparece duas vezes por aplicacao (a chamada e o apelido da subconsulta)
conf(nesting == 2, "e a regra aparece uma vez so na definicao (nao empilha)", str(nesting))
con.close()
res, err = roda_arquivo("seguranca_02_view_so_para_quem_tem_permissao.sql")
conf(err is None and len(res or []) == len(USUARIOS), "rodar o script de novo nao da erro")
res, err = roda_arquivo("lancamentos_rateados_03_ano_safra.sql")
conf(err is None, "o script que RECRIA a view roda sem erro com a regra instalada", str(err))
r = conta("sem_nada")
conf(r[0] == 0 and conta("res_ver")[0] == total and conta("pec_fin")[0] == pecuaria, "e depois de recriada a regra continua valendo (o script chama a funcao no fim)", f"{r} {conta('res_ver')} {conta('pec_fin')}")
conf(conta("anon", role="anon") == "negado", "e o anon continua negado")

# a funcao aplicadora nao e chamavel por quem usa a API
for quem, role in (("pec_fin", "authenticated"), ("anon", "anon")):
    con, cur = como(quem, role)
    try:
        cur.execute("select public.aplicar_regra_na_view_lancamentos_rateados()"); chamou = True
    except psycopg2.errors.InsufficientPrivilege:
        chamou = False
    con.rollback(); con.close()
    conf(not chamou, f"{role} nao consegue chamar a funcao que aplica a regra")

print(f"\n  {passes} passaram, {falhas} falharam")
srv.cleanup()
sys.exit(1 if falhas else 0)
