#!/usr/bin/env bash
# Roda os scripts de plano de contas contra a ESTRUTURA REAL, num Postgres
# descartavel. O fixture vem de schema_real.txt via gerar_fixture_teste.py -
# escrever fixture a mao foi exatamente o que deixou 'centro_id' passar.
set -euo pipefail
cd "$(dirname "$0")"
PGSOCK=${PGSOCK:-/tmp/pgsock}; PGPORT=${PGPORT:-5433}; DB=${DB:-teste_plano}
python3 gerar_fixture_teste.py > /tmp/fixture.sql
psql -h "$PGSOCK" -p "$PGPORT" -U postgres -q -c "drop database if exists $DB;" -c "create database $DB;"
psql -h "$PGSOCK" -p "$PGPORT" -U postgres -d "$DB" -q -f /tmp/fixture.sql
for f in centros_05_dois_niveis.sql centros_07_de_para.sql centros_07_de_para.sql; do
  echo "=== $f ==="
  psql -h "$PGSOCK" -p "$PGPORT" -U postgres -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f" | tail -12
done
