#!/usr/bin/env bash
# tools/validate-migrations.sh
# Aplica TODAS as migrations em ordem contra o DB Supabase local e valida
# que a chain está íntegra (sem drift). Depois opcionalmente roda os
# integration tests. Uso em CI e dev local para destravar validação
# end-to-end.
#
# REQUER: supabase_db_omni_runner container up (supabase start).
# ATENÇÃO: RESETA o schema public. Não rode contra dados reais.

set -euo pipefail

CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_omni_runner}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-supabase/migrations}"
RUN_TESTS="${RUN_TESTS:-1}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[validate-migrations] Container ${CONTAINER} não está rodando." >&2
  echo "  → rode 'supabase start' primeiro." >&2
  exit 2
fi

echo "[validate-migrations] Reset do schema public + reaplicação em ordem"

# 1. Reset: drop schema public + recria (mantém auth, storage, vault etc).
# Default privileges e grants espelham o setup que supabase init instala —
# sem isso, tabelas criadas por migrations ficam sem GRANT e authenticated/
# service_role batem em "permission denied" no PostgREST.
docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public AUTHORIZATION postgres;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA public TO postgres, service_role;

-- Replica os DEFAULT PRIVILEGES que supabase init aplica em fresh installs.
-- Aplica tanto do ponto de vista de `postgres` quanto de `supabase_admin`
-- (ambos aparecem como OWNER dependendo de quem executa a migration).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES    TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;

-- Limpa auth.users de runs anteriores (idempotência)
DELETE FROM auth.users
 WHERE email LIKE 'inttest-%@test.local'
    OR email LIKE '%@test.local'
    OR email = 'anonimo-lgpd@internal.omnirunner.app';
-- Limpa histórico de migrations (para aplicarmos do zero)
TRUNCATE supabase_migrations.schema_migrations;
SQL

echo "[validate-migrations] Schema public resetado. Aplicando migrations..."

count=0
failed=0
failed_list=""

for m in $(ls "$MIGRATIONS_DIR" | sort); do
  count=$((count + 1))
  version="${m%%_*}"
  if ! docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
       < "$MIGRATIONS_DIR/$m" > "/tmp/mig_${version}.log" 2>&1; then
    failed=$((failed + 1))
    failed_list="${failed_list}${m}\n"
    echo "  ✗ $m  (log: /tmp/mig_${version}.log)"
    tail -5 "/tmp/mig_${version}.log" | sed 's/^/      /'
    continue
  fi
  # Registra a migration aplicada (para idempotência futura)
  docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "INSERT INTO supabase_migrations.schema_migrations (version) VALUES ('${version}') ON CONFLICT DO NOTHING;" \
    >/dev/null
  if [ $((count % 20)) -eq 0 ]; then
    echo "  [${count}/165] $m"
  fi
done

echo ""
echo "[validate-migrations] Aplicadas: $((count - failed))/${count}"
if [ "$failed" -gt 0 ]; then
  echo "[validate-migrations] FALHAS:"
  printf "%b" "$failed_list" | sed 's/^/  - /'
  exit 3
fi

# Reload schema cache do PostgREST
docker exec "$CONTAINER" psql -U postgres -d postgres -c "NOTIFY pgrst, 'reload schema';" >/dev/null

echo "[validate-migrations] ✅ Chain completa sem erro"

if [ "$RUN_TESTS" = "1" ]; then
  echo ""
  echo "[validate-migrations] Rodando integration tests..."
  NODE_PATH=portal/node_modules npx tsx tools/integration_tests.ts
fi
