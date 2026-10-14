#!/usr/bin/env bash
set -euo pipefail

# Data migration: 13 per-sport Postgres containers -> one scorexl-postgres,
# one schema per module (football, basketball, ..., account for the user module).
#
#   all             same host: dump + restore + verify in one go (old stack running here)
#   dump            OLD host: stop old APIs, dump every DB (+ umami) into backups/<ts>/
#   restore <dir>   NEW host: restore a dump dir into scorexl-postgres (+ umami), verify
#
# Run from this repo checked out on the single-backend branch. Every restore is
# verified with exact per-table row counts against the counts taken at dump time;
# only then is .single-backend-migrated written (deploy.sh refuses without it).
#
# On a failure while the old APIs are stopped (all/dump), they're started again, so
# production goes back to exactly how it was. Old postgres containers and volumes are
# never modified — they stay the rollback path until you remove them by hand.
#
# Usage: ./scripts/migrate-to-single-backend.sh [all|dump|restore <dir>] [--allow-missing]
#   --allow-missing  skip a module whose old postgres container doesn't exist
#                    (its schema then starts empty); default is to abort.

cd "$(dirname "$0")/.."

MODE=all
DIR=""
ALLOW_MISSING=false
while [ $# -gt 0 ]; do
  case "$1" in
    all|dump) MODE=$1 ;;
    restore) MODE=restore; DIR=${2:-}; [ $# -ge 2 ] && shift ;;
    --allow-missing) ALLOW_MISSING=true ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[ "$MODE" = restore ] && [ ! -d "$DIR" ] && { echo "restore needs a dump directory (backups/<ts>)" >&2; exit 2; }

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
UMAMI_PG=scorexl-umami-postgres

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

wait_ready() {
  for _ in $(seq 1 60); do
    docker exec "$1" sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "$1 not ready after 60s" >&2
  return 1
}

user_tables() {
  cpsql "$1" "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');"
}

STOPPED=()
on_failure() {
  if [ ${#STOPPED[@]} -gt 0 ]; then
    echo ">> FAILED — restarting old API containers: ${STOPPED[*]}"
    docker start "${STOPPED[@]}" >/dev/null || true
    echo ">> production is back on the old stack."
  fi
  if [ "$MODE" != dump ]; then
    echo ">> if $TARGET got partially restored, wipe it before retrying:"
    echo "   docker compose rm -sf $TARGET && docker volume rm scorexl_backend_postgres_data"
  fi
}
trap 'on_failure' ERR

# ---------------------------------------------------------------------------- dump

dump_all() {
  local out=$1
  mkdir -p "$out"
  local active=()
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
    active+=("$entry")
  done

  echo ">> stopping old API containers (DBs stay up) — downtime starts now"
  for entry in "${active[@]}"; do
    IFS=: read -r module pg api <<<"$entry"
    if running "$api"; then docker stop "$api" >/dev/null; STOPPED+=("$api"); fi
  done

  echo ">> dumping into $out"
  : > "$out/modules"
  for entry in "${active[@]}"; do
    IFS=: read -r module pg api <<<"$entry"
    docker exec "$pg" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -n public -Fc --no-owner --no-privileges' > "$out/$module.dump"
    cpsql "$pg" "$(count_sql public)" > "$out/$module.counts.old"
    echo "$module" >> "$out/modules"
    echo "   $module: $(wc -l < "$out/$module.counts.old") tables, $(du -h "$out/$module.dump" | cut -f1)"
  done

  if running "$UMAMI_PG"; then
    docker exec "$UMAMI_PG" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-privileges' > "$out/umami.dump"
    cpsql "$UMAMI_PG" "$(count_sql public)" > "$out/umami.counts.old"
    echo "   umami: $(wc -l < "$out/umami.counts.old") tables, $(du -h "$out/umami.dump" | cut -f1)"
  fi
}

# ------------------------------------------------------------------------- restore

restore_all() {
  local out=$1
  grep -q '^BACKEND_POSTGRES_PASSWORD=..*' .env || { echo "BACKEND_POSTGRES_PASSWORD missing in .env (see .env.example)" >&2; exit 1; }
  [ -f .single-backend-migrated ] && { echo ".single-backend-migrated already exists — migration was already done." >&2; exit 1; }
  [ -s "$out/modules" ] || { echo "$out/modules missing — not a dump directory from this script" >&2; exit 1; }

  echo ">> starting $TARGET"
  docker compose up -d "$TARGET"
  wait_ready "$TARGET"
  local existing
  existing=$(user_tables "$TARGET")
  if [ "$existing" != "0" ]; then
    echo "$TARGET already has $existing tables — refusing to restore over existing data." >&2
    false
  fi

  echo ">> restoring each dump into its own schema"
  while read -r module; do
    # pg_restore always targets the schema the objects came from (public): restore into
    # an empty public, then rename it to the module's schema and recreate public.
    cpsql "$TARGET" "DROP SCHEMA IF EXISTS public CASCADE;"
    if ! docker exec -i "$TARGET" pg_restore -l < "$out/$module.dump" | grep -qE ' SCHEMA - public '; then
      cpsql "$TARGET" "CREATE SCHEMA public;"
    fi
    docker exec -i "$TARGET" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error' < "$out/$module.dump"
    cpsql "$TARGET" "ALTER SCHEMA public RENAME TO \"$module\"; CREATE SCHEMA public;"
    echo "   $module restored"
  done < "$out/modules"

  echo ">> verifying exact row counts"
  while read -r module; do
    cpsql "$TARGET" "$(count_sql "$module")" > "$out/$module.counts.new"
    if ! diff -u "$out/$module.counts.old" "$out/$module.counts.new"; then
      echo "Row counts differ for $module (see diff above)." >&2
      false
    fi
    echo "   $module OK ($(awk -F'|' '{s+=$2} END{print s+0}' "$out/$module.counts.new") rows)"
  done < "$out/modules"
}

# umami keeps its own DB/container; only moved when it changes host (restore mode).
# Must run before the umami app first starts, or its own migrations create tables.
restore_umami() {
  local out=$1
  [ -f "$out/umami.dump" ] || { echo "   (no umami dump — skipped)"; return 0; }
  docker compose up -d "$UMAMI_PG"
  wait_ready "$UMAMI_PG"
  if [ "$(user_tables "$UMAMI_PG")" != "0" ]; then
    echo "   !! $UMAMI_PG is not empty (umami already started?) — umami NOT restored; restore it by hand from $out/umami.dump"
    return 0
  fi
  docker exec -i "$UMAMI_PG" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error' < "$out/umami.dump"
  cpsql "$UMAMI_PG" "$(count_sql public)" > "$out/umami.counts.new"
  if ! diff -u "$out/umami.counts.old" "$out/umami.counts.new"; then
    echo "Row counts differ for umami (see diff above)." >&2
    false
  fi
  echo "   umami OK"
}

finish() {
  trap - ERR
  date -Iseconds > .single-backend-migrated
}

TS=$(date +%Y%m%d-%H%M%S)
case "$MODE" in
  all)
    dump_all "backups/$TS"
    restore_all "backups/$TS"
    finish
    cat <<EOF

Migration done and verified. Old API containers are STOPPED; old DBs and volumes untouched.
Dumps + counts: backups/$TS

Next:
  ./scripts/deploy.sh                          # pulls scorexl-backend, starts it, removes old containers
  sudo ./scripts/bootstrap.sh                  # copies nginx/*.conf: subdomains -> 127.0.0.1:8080/<sport>/

Rollback (before deleting anything):
  git checkout main && rm .single-backend-migrated && ./scripts/deploy.sh && sudo ./scripts/bootstrap.sh
EOF
    ;;
  dump)
    dump_all "backups/$TS"
    trap - ERR
    tar -C backups -czf "backups/$TS.tgz" "$TS"
    cat <<EOF

Dump done: backups/$TS.tgz ($(du -h "backups/$TS.tgz" | cut -f1)). Old API containers are STOPPED
(web keeps serving, with errors) — downtime runs until the new droplet takes traffic.

Next, from your machine:
  scp root@<old-ip>:$(pwd)/backups/$TS.tgz fmacuacua@<new-ip>:~/scorexl/backups/
On the new droplet:
  tar -C backups -xzf backups/$TS.tgz && ./scripts/migrate-to-single-backend.sh restore backups/$TS

Abort/rollback here: docker start ${STOPPED[*]:-<old api containers>}
EOF
    ;;
  restore)
    restore_all "$DIR"
    restore_umami "$DIR"
    finish
    cat <<EOF

Restore done and verified on this host. Next:
  ./scripts/deploy.sh
  sudo ./scripts/bootstrap.sh
then smoke-test (README "New droplet") before switching DNS.
EOF
    ;;
esac
