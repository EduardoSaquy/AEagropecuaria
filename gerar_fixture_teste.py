#!/usr/bin/env python3
"""
Gera um banco de teste com a estrutura REAL, lida de schema_real.txt.

POR QUE ISTO EXISTE

Eu escrevi um FK para 'talhoes' e o teste passou, porque o fixture que eu
tinha montado a mao inventava uma tabela 'talhoes'. O erro so apareceu na
tela do Eduardo. Fixture escrito de memoria nao testa nada - ele so
confirma a memoria.

Agora o fixture vem do catalogo real. Se a tabela nao existe la, ela nao
existe aqui, e o teste quebra antes de chegar no Supabase.
"""
import re, sys
from pathlib import Path

SCHEMA = Path(__file__).parent / "schema_real.txt"

# tabelas que os scripts de contas a pagar dependem
PRECISO = ["profiles", "fazendas", "centros_custo", "talhoes_areas",
           "lancamentos_financeiros", "culturas"]

TIPO = {  # normaliza o que o dump traz
    "timestamp with time zone": "timestamptz",
}

def colunas(texto, tabela):
    out = []
    for linha in texto.splitlines():
        linha = linha.split("--")[0].rstrip()
        if not linha.startswith(tabela + "."):
            continue
        resto = linha[len(tabela) + 1:]
        m = re.match(r"^(\S+)\s+(.*)$", resto)
        if not m:
            continue
        nome, decl = m.group(1), m.group(2).strip()
        # auth.uid() nao existe no teste antes do stub; troca por null
        decl = decl.replace("default auth.uid()", "")
        for de, para in TIPO.items():
            decl = decl.replace(de, para)
        out.append((nome, decl))
    return out

def main():
    if not SCHEMA.exists():
        sys.exit("schema_real.txt nao encontrado - ele e a referencia da estrutura")
    texto = SCHEMA.read_text()
    partes = ["""-- GERADO por gerar_fixture_teste.py a partir de schema_real.txt.
-- Nao editar a mao: se faltar coluna, corrija o schema_real.txt.
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('teste.uid', true),'')::uuid $$;
"""]
    faltando = []
    for t in PRECISO:
        cols = colunas(texto, t)
        if not cols:
            faltando.append(t)
            continue
        corpo = ",\n  ".join(f"{n} {d}" for n, d in cols)
        # id vira identity para os inserts do teste funcionarem
        corpo = re.sub(r"^id bigint NOT NULL",
                       "id bigint generated always as identity primary key",
                       corpo, flags=re.M)
        corpo = re.sub(r"^id uuid NOT NULL", "id uuid primary key", corpo, flags=re.M)
        partes.append(f"create table {t} (\n  {corpo}\n);")

    if faltando:
        sys.exit("tabelas ausentes no schema_real.txt: " + ", ".join(faltando))

    partes.append("""
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(select 1 from profiles where id = auth.uid() and papel='admin' and ativo);
$$;
create or replace function tem_permissao(modulo text, nivel text) returns boolean
language sql security definer set search_path = public stable as $$
  select case when is_admin() then true
    when nivel='visualizar' then (select permissoes->>modulo in ('visualizar','editar')
                                    from profiles where id=auth.uid() and ativo)
    else (select permissoes->>modulo = 'editar'
            from profiles where id=auth.uid() and ativo) end;
$$;

insert into fazendas (nome, estado) values ('Palhadao','SP'), ('Tocantins','TO');
insert into culturas (nome, frente) values ('Cana','cana'), ('Soja','cereais');
insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id)
  values (1,'T-01','talhao',50.00,1);
insert into centros_custo (nome, tipo, subcategoria) values
  ('ADUBOS E FERTILIZANTES','saida','OPERACIONAL | INSUMOS AGROPECUARIOS'),
  ('NUTRICAO ANIMAL','saida','OPERACIONAL | INSUMOS AGROPECUARIOS'),
  ('TRIBUTOS','saida','TRIBUTOS | TRIBUTOS E CONTRIBUICOES');
insert into lancamentos_financeiros
  (tipo,atividade,fazenda_id,centro_custo_id,descricao,valor,data,mes,fornecedor) values
  ('despesa','cana',1,1,'Adubo antigo',1000.00,'2026-07-10','2026-07','AGROSAQUY'),
  ('despesa','pecuaria',1,2,'Racao',500.00,'2026-07-11','2026-07','agrosaquy  '),
  ('despesa','geral',null,3,'Imposto',250.00,'2026-07-12','2026-07',null);
insert into profiles (id,nome,usuario,papel,permissoes) values
 ('11111111-1111-1111-1111-111111111111','Admin','admin','admin','{}'),
 ('22222222-2222-2222-2222-222222222222','Dono','dono','proprietario','{"matriz_financeiro":"editar","contas":"editar"}'),
 ('33333333-3333-3333-3333-333333333333','Escritorio','escrit','colaborador','{"matriz_financeiro":"editar","contas":"editar"}'),
 ('44444444-4444-4444-4444-444444444444','SoFinanceiro','sofin','colaborador','{"matriz_financeiro":"editar"}'),
 ('55555555-5555-5555-5555-555555555555','Estranho','estranho','colaborador','{}');
""")
    print("\n".join(partes))

main()
