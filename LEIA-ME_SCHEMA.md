# Sobre os arquivos `*_schema.sql`

**Eles não descrevem o banco de hoje.** Não use nenhum deles como referência
para escrever migração, política de segurança ou consulta.

## Por que

Foram escritos antes da unificação dos dois projetos Supabase, da migração
do financeiro para `lancamentos_financeiros` e da separação do AE Lavoura em
Cana e Cereais. Desde então o banco mudou por scripts que não voltaram para
cá.

Ler esses arquivos como se fossem o estado real produziu **quatro erros**
seguidos nesta sequência de trabalho:

| O que o arquivo dizia | O que o banco tinha |
|---|---|
| valores do CHECK de `papel` | outros valores, e mais deles |
| `lotes` sem chave estrangeira para `dietas` | a chave existia, adicionada depois |
| `centros_custo.fazenda_id` NOT NULL | já aceitava nulo |
| `centros_custo.frente` NOT NULL | o app grava nulo de propósito |

Três desses só apareceram quando a migração falhou no meio.

Além disso, `combustivel_schema.sql`, `cana_schema.sql` e
`cereais_schema.sql` criam as **mesmas tabelas base** com definições
diferentes entre si. Não há como saber qual rodou.

## O que usar no lugar

Leia o catálogo do banco direto:

```sql
-- colunas, tipos, obrigatoriedade e default
select c.relname||'.'||a.attname, format_type(a.atttypid, a.atttypmod),
       a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
from pg_class c
join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
where c.relkind='r' order by 1, a.attnum;

-- políticas de segurança
select tablename, policyname, cmd, qual, with_check from pg_policies
where schemaname='public' order by tablename, cmd;

-- restrições e chaves estrangeiras
select conrelid::regclass, conname, pg_get_constraintdef(oid)
from pg_constraint where connamespace='public'::regnamespace order by 1;
```

A última consulta do `auditoria_04_pendencias_do_banco.sql` já devolve a
primeira delas pronta. **Salve o resultado como `schema_real.txt` e regere
depois de cada migração** — é o que acaba com essa classe de erro.

## Por que não foram apagados

Servem de histórico de como cada app começou, e alguns comentários neles
explicam decisões que continuam valendo. O que não servem é de referência
do presente.
