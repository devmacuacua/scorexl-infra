#!/usr/bin/env bash
set -euo pipefail

# One-shot data migration: 13 per-sport Postgres containers -> one scorexl-postgres,
# one schema per module (football, basketball, ..., account for the user module).
#
# Run on the droplet, from this repo checked out on the single-backend branch,
# while the OLD stack is still up. It:
#   1. stops the old *-api containers (so nothing writes mid-dump) — DBs keep running
#   2. pg_dumps every old DB's public schema into backups/<timestamp>/
#   3. starts scorexl-postgres (must be empty) and restores each dump into its own schema
#   4. compares exact row counts table by table, old vs new
#   5. only if everything matches: writes .single-backend-migrated (deploy.sh needs it)
#
# On any failure the old API containers are started again, so production goes back
# to exactly how it was. Old postgres containers and volumes are never modified —
# they remain the rollback path until you remove them by hand.
#
# Usage: ./scripts/migrate-to-single-backend.sh [--allow-missing]
#   --allow-missing  skip a module whose old postgres container doesn't exist
#                    (its schema then starts empty); default is to abort.

cd "$(dirname "$0")/.."

ALLOW_MISSING=false
[ "${1:-}" = "--allow-missing" ] && ALLOW_MISSING=true

# module (= target schema) : old postgres container : old api container
MODULES=(
  "football:scorexl-football-postgres:scorexl-football-api"
  "basketball:scorexl-basketball-postgres:scorexl-basketball-api"
  "nba:scorexl-nba-postgres:scorexl-nba-api"
  "volleyball:scorexl-volleyball-postgres:scorexl-volleyball-api"
  "mlb:scorexl-mlb-postgres:scorexl-mlb-api"
  "afl:scorexl-afl-postgres:scorexl-afl-api"
  "nfl:scorexl-nfl-postgres:scorexl-nfl-api"
  "nhl:scorexl-nhl-postgres:scorexl-nhl-api"
  "rugby:scorexl-rugby-postgres:scorexl-rugby-api"
  "handball:scorexl-handball-postgres:scorexl-handball-api"
  "f1:scorexl-f1-postgres:scorexl-f1-api"
  "mma:scorexl-mma-postgres:scorexl-mma-api"
  "account:scorexl-user-postgres:scorexl-user-api"
)
TARGET=scorexl-postgres
TARGET_DB=scorexl

# exact count of every base table in a schema, one "table|count" line each
count_sql() {
  cat <<SQL
SELECT table_name || '|' || (xpath('/row/c/text()',
         query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
FROM information_schema.tables
WHERE table_schema = '$1' AND table_type = 'BASE TABLE'
ORDER BY table_name;
SQL
}

# psql inside a container, using that container's own POSTGRES_USER/POSTGRES_DB
cpsql() {
  local container=$1 sql=$2
  docker exec -i "$container" sh -c 'psql -v ON_ERROR_STOP=1 -X -At -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<<"$sql"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

grep -q '^BACKEND_POSTGRES_PASSWORD=..*' .env || { echo "BACKEND_POSTGRES_PASSWORD missing in .env (see .env.example)" >&2; exit 1; }
[ -f .single-backend-migrated ] && { echo ".single-backend-migrated already exists — migration was already done." >&2; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/$TS"
mkdir -p "$OUT"

ACTIVE=()
for entry in "${MODULES[@]}"; do
  IFS=: read -r module pg api <<<"$entry"
  if ! running "$pg"; then
    if $ALLOW_MISSING; then
      echo "!! $pg not running — $module will start with an empty schema"
      continue
    fi
    echo "$pg is not running. Start it, or re-run with --allow-missing to skip $module." >&2
    exit 1
  fi
  ACTIVE+=("$entry")
done

STOPPED=()
restore_old_stack() {
  if [ ${#STOPPED[@]} -gt 0 ]; then
    echo ">> FAILED — restarting old API containers: ${STOPPED[*]}"
    docker start "${STOPPED[@]}" >/dev/null || true
  fi
  echo ">> production is back on the old stack. If $TARGET got partially restored, wipe it before retrying:"
  echo "   docker compose rm -sf $TARGET && docker volume rm scorexl_backend_postgres_data"
}
trap 'restore_old_stack' ERR

echo ">> 1/5 stopping old API containers (DBs stay up) — downtime starts now"
for entry in "${ACTIVE[@]}"; do
  IFS=: read -r module pg api <<<"$entry"
  if running "$api"; then docker stop "$api" >/dev/null; STOPPED+=("$api"); fi
done

echo ">> 2/5 dumping into $OUT"
for entry in "${ACTIVE[@]}"; do
  IFS=: read -r module pg api <<<"$entry"
  docker exec "$pg" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -n public -Fc --no-owner --no-privileges' > "$OUT/$module.dump"
  cpsql "$pg" "$(count_sql public)" > "$OUT/$module.counts.old"
  echo "   $module: $(wc -l < "$OUT/$module.counts.old") tables, $(du -h "$OUT/$module.dump" | cut -f1)"
done

echo ">> 3/5 starting $TARGET"
docker compose up -d "$TARGET"
for _ in $(seq 1 60); do
  docker exec "$TARGET" sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1 && break
  sleep 1
done
existing=$(cpsql "$TARGET" "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');")
if [ "$existing" != "0" ]; then
  echo "$TARGET already has $existing tables — refusing to restore over existing data." >&2
  false
fi

echo ">> 4/5 restoring each dump into its own schema"
for entry in "${ACTIVE[@]}"; do
  IFS=: read -r module pg api <<<"$entry"
  # pg_restore always targets the schema the objects came from (public): restore into
  # an empty public, then rename it to the module's schema and recreate public.
  cpsql "$TARGET" "DROP SCHEMA IF EXISTS public CASCADE;"
  if ! docker exec -i "$TARGET" pg_restore -l < "$OUT/$module.dump" | grep -qE ' SCHEMA - public '; then
    cpsql "$TARGET" "CREATE SCHEMA public;"
  fi
  docker exec -i "$TARGET" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error' < "$OUT/$module.dump"
  cpsql "$TARGET" "ALTER SCHEMA public RENAME TO \"$module\"; CREATE SCHEMA public;"
  echo "   $module restored"
done

echo ">> 5/5 verifying exact row counts"
for entry in "${ACTIVE[@]}"; do
  IFS=: read -r module pg api <<<"$entry"
  cpsql "$TARGET" "$(count_sql "$module")" > "$OUT/$module.counts.new"
  if ! diff -u "$OUT/$module.counts.old" "$OUT/$module.counts.new"; then
    echo "Row counts differ for $module (see diff above)." >&2
    false
  fi
  echo "   $module OK ($(awk -F'|' '{s+=$2} END{print s+0}' "$OUT/$module.counts.new") rows)"
done

trap - ERR
date -Iseconds > .single-backend-migrated
cat <<EOF

Migration done and verified. Old API containers are STOPPED; old DBs and volumes untouched.
Dumps + counts: $OUT

Next:
  ./scripts/deploy.sh                          # pulls scorexl-backend, starts it, removes old containers
  sudo nginx -t && sudo systemctl reload nginx # subdomains -> 127.0.0.1:8080/<sport>/

Rollback (before deleting anything):
  git checkout main && rm .single-backend-migrated && ./scripts/deploy.sh
  then reload nginx again.
EOF
