#!/usr/bin/env bash
set -e

# Local development wrapper — builds every image from its sibling source
# checkout (../scorexl-<name>) instead of pulling from GHCR, via the
# docker-compose.dev.yml build-context overlay. Never used by deploy.sh, so
# production is completely unaffected by this file.
#
# Usage:
#   ./scripts/dev.sh up                 # build + start everything (all sports + web)
#   ./scripts/dev.sh up volleyball       # build + start only the volleyball block
#   ./scripts/dev.sh up --profile nba    # same, explicit flag form
#   ./scripts/dev.sh down                # stop everything started by this script
#   ./scripts/dev.sh logs volleyball     # follow logs for one sport's services
#   ./scripts/dev.sh build               # just build images, don't start anything
#   ./scripts/dev.sh regen               # regenerate docker-compose.dev.yml after
#                                         # adding/removing a service in docker-compose.yml

cd "$(dirname "$0")/.."

VALID_SPORTS=(football basketball nba volleyball mlb afl nfl nhl rugby handball f1 mma)
CMD="${1:-up}"
ARG="${2:-}"

parse_sport() {
  case "$1" in
    --profile) echo "$2" ;;
    "") echo "" ;;
    *) echo "$1" ;;
  esac
}

compose() {
  docker compose -f docker-compose.yml -f docker-compose.dev.yml "$@"
}

case "$CMD" in
  regen)
    echo "Regenerating docker-compose.dev.yml from docker-compose.yml..."
    python3 - <<'PYEOF'
import re
content = open("docker-compose.yml").read()
services = re.findall(r'^  (\S+):\n((?:    .+\n?)+)', content, re.MULTILINE)
lines = ["# Auto-generated build-context overlay for local development.",
         "#",
         "# Only used via scripts/dev.sh — never referenced by scripts/deploy.sh, so",
         "# production always pulls prebuilt images from GHCR and is unaffected by",
         "# this file (production has no sibling source checkouts to build from).",
         "#",
         "# Regenerate if new services are added to docker-compose.yml:",
         "#   ./scripts/dev.sh regen",
         "services:"]
for name, block in services:
    m = re.search(r'container_name:\s*(\S+)', block)
    if not m:
        continue
    cname = m.group(1)
    if "postgres" in cname:
        continue
    lines.append(f"  {name}:")
    lines.append(f"    build:")
    lines.append(f"      context: ../{cname}")
    lines.append(f"    image: !reset null")
open("docker-compose.dev.yml", "w").write("\n".join(lines) + "\n")
print("wrote docker-compose.dev.yml")
PYEOF
    ;;

  build)
    SPORT="$(parse_sport "$ARG")"
    if [ -n "$SPORT" ]; then
      match=false
      for s in "${VALID_SPORTS[@]}"; do [ "$s" = "$SPORT" ] && match=true; done
      if [ "$match" != true ]; then
        echo "Unknown sport '$SPORT'. Valid options: ${VALID_SPORTS[*]}" >&2
        exit 1
      fi
      compose --profile "$SPORT" build
    else
      COMPOSE_ARGS=()
      for s in "${VALID_SPORTS[@]}"; do COMPOSE_ARGS+=(--profile "$s"); done
      compose "${COMPOSE_ARGS[@]}" build
    fi
    ;;

  up)
    SPORT="$(parse_sport "$ARG")"
    if [ -n "$SPORT" ]; then
      match=false
      for s in "${VALID_SPORTS[@]}"; do [ "$s" = "$SPORT" ] && match=true; done
      if [ "$match" != true ]; then
        echo "Unknown sport '$SPORT'. Valid options: ${VALID_SPORTS[*]}" >&2
        exit 1
      fi
      echo "Building + starting: $SPORT (+ always-on web/user-api)"
      compose --profile "$SPORT" up -d --build
    else
      echo "Building + starting everything (all sports + web)"
      COMPOSE_ARGS=()
      for s in "${VALID_SPORTS[@]}"; do COMPOSE_ARGS+=(--profile "$s"); done
      compose "${COMPOSE_ARGS[@]}" up -d --build --remove-orphans
    fi
    echo
    echo "Running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;

  down)
    COMPOSE_ARGS=()
    for s in "${VALID_SPORTS[@]}"; do COMPOSE_ARGS+=(--profile "$s"); done
    compose "${COMPOSE_ARGS[@]}" down
    ;;

  logs)
    SPORT="$(parse_sport "$ARG")"
    if [ -n "$SPORT" ]; then
      compose --profile "$SPORT" logs -f --tail=200 $(docker compose -f docker-compose.yml -f docker-compose.dev.yml --profile "$SPORT" config --services | grep "^scorexl-$SPORT")
    else
      compose logs -f --tail=200
    fi
    ;;

  *)
    echo "Usage: $0 {up|down|build|logs|regen} [sport|--profile <sport>]" >&2
    exit 1
    ;;
esac
