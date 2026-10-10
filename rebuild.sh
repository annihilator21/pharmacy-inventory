#!/usr/bin/env bash
# Rebuild the pharmacy database from scratch.
# Usage:  ./rebuild.sh [database_name]      (default: pharmacy)
# Needs psql, createdb and dropdb on PATH and permission to create databases.
set -euo pipefail

DB="${1:-pharmacy}"
cd "$(dirname "$0")"

dropdb --if-exists "$DB"
createdb "$DB"

for f in 01_schema.sql 02_functions_triggers.sql 03_sample_data.sql; do
    echo "running $f"
    psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

echo "Rebuilt database '$DB'. Optional next steps:"
echo "  psql -d $DB -f 04_queries.sql"
echo "  psql -d $DB -f 05_transactions.sql   (run once per rebuild)"
echo "  psql -d $DB -f 06_constraint_tests.sql"
