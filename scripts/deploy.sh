#!/usr/bin/env bash
set -e

# Usage:
#   ./scripts/deploy.sh                 # pull + up everything (all sports + web)
#   ./scripts/deploy.sh football        # pull + up only the football block
#   ./scripts/deploy.sh --profile nba   # same, explicit flag form
#
# scorexl-web / scorexl-user-api / scorexl-user-postgres have no profile —
# they're always-on infra shared by every sport, so they're included in every
# invocation regardless of which sport (if any) is selected.
#
# This only runs `docker compose pull && up -d` — it does not touch nginx or
# any old infra repo's containers. Cutover from the old per-sport repos is a
# separate, manual step — see README.md.

VALID_SPORTS=(football basketball nba volleyball mlb afl nfl nhl rugby handball)
SPORT=""

case "$1" in
  --profile)
    SPORT="$2"
    ;;
  "" )
    SPORT=""
    ;;
  *)
    SPORT="$1"
    ;;
esac

COMPOSE_ARGS=()

if [ -n "$SPORT" ]; then
  match=false
  for s in "${VALID_SPORTS[@]}"; do
    [ "$s" = "$SPORT" ] && match=true
  done
  if [ "$match" != true ]; then
    echo "Unknown sport '$SPORT'. Valid options: ${VALID_SPORTS[*]}" >&2
    exit 1
  fi
  echo "Deploying only: $SPORT (+ always-on web/user-api)"
  COMPOSE_ARGS=(--profile "$SPORT")
else
  echo "Deploying everything (all sports + web)"
  for s in "${VALID_SPORTS[@]}"; do
    COMPOSE_ARGS+=(--profile "$s")
  done
fi

echo "Deploy started at $(date)"

echo "Pulling latest images..."
docker compose "${COMPOSE_ARGS[@]}" pull

# --remove-orphans only when deploying everything: with a partial --profile
# deploy, compose treats every other sport's containers as "orphans" (they're
# not part of the active profile set for this invocation) and would stop
# them, which defeats the point of a partial deploy. Only safe to prune
# orphans when every profile is active, i.e. no sport arg was given.
UP_ARGS=(up -d)
if [ -z "$SPORT" ]; then
  UP_ARGS+=(--remove-orphans)
fi

echo "Recreating containers..."
docker compose "${COMPOSE_ARGS[@]}" "${UP_ARGS[@]}"

echo "Running containers:"
docker ps

echo "Cleaning unused images..."
docker image prune -f

echo "Deploy completed successfully!"
