#!/usr/bin/env bash
# Ensaio completo da importacao do ERP num Postgres descartavel:
# fixture do schema real -> centros_05 -> centros_07 -> erp_10 -> CSV -> erp_12.
set -euo pipefail
cd "$(dirname "$0")"
PS=/tmp/pgsock; PP=5433; DB=${1:-ensaio_erp}
python3 gerar_fixture_teste.py > /tmp/fixture.sql
psql -h $PS -p $PP -U postgres -q -c "drop database if exists $DB;" -c "create database $DB;"
psql -h $PS -p $PP -U postgres -d $DB -q -f /tmp/fixture.sql
psql -h $PS -p $PP -U postgres -d $DB -q -f erp/ensaio_dados.sql
for f in centros_05_dois_niveis.sql centros_07_de_para.sql erp_10_estrutura.sql; do
  psql -h $PS -p $PP -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null
done
psql -h $PS -p $PP -U postgres -d $DB -q -c "\copy erp_staging (erp_id,erp_cod,entidade,centro_custo,contrato,cnpj_nota,forma_pagamento,vencimento,competencia,valor,previsao,usuario,atividade_erp,fazenda_erp,atividade,cultura,administrativo) from 'erp/lancamentos_para_importar.csv' with (format csv, header true)"
psql -h $PS -p $PP -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f erp_12_importar.sql | grep -v NOTICE
echo "--- de novo, para conferir que nao duplica ---"
psql -h $PS -p $PP -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f erp_12_importar.sql | grep -v NOTICE | head -6
