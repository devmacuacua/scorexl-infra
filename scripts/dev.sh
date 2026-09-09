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

# afl/nhl/rugby/handball/f1/mma removed 2026-09-07 — never produced a
# single value_bet, commented out in docker-compose.yml, no point deploying
# them by default. Re-add here (and uncomment their compose blocks) if
# revisited. nfl re-added 2026-09-09 — pipeline-trigger bug fixed, real
# picks confirmed flowing.
VALID_SPORTS=(football basketball nba volleyball mlb nfl)
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
    # scorexl-web is never built locally via this overlay — run it directly
    # in VS Code (its own dev server) instead of through Docker, per user
    # workflow (2026-09-07). It still has a real, uncommented block in
    # docker-compose.yml (needed for production), just excluded from this
    # dev build-context regeneration.
    if name == "scorexl-web":
        continue
    # scorexl-umami runs the prebuilt ghcr.io/umami-software/umami image —
    # there's no sibling scorexl-umami source checkout to build from, so it
    # can't get a build-context override like the sport services (2026-09-07).
    if name == "scorexl-umami":
        continue
    lines.append(f"  {name}:")
    lines.append(f"    build:")
    lines.append(f"      context: ../{cname}")
    lines.append(f"    image: !reset null")

# Postgres volumes in docker-compose.yml are pinned external:true, pointing
# at the legacy per-sport infra repos' real production volumes (see
# README's migration/cutover section) — those never exist on a dev laptop,
# so local `up` fails with "external volume ... not found". Override each
# external volume to a plain local one here so dev gets fresh empty
# databases instead (2026-09-07).
vol_section = re.search(r'^volumes:\n((?:  .+\n?)+)', content, re.MULTILINE).group(1)
vol_blocks = re.findall(r'^  (\S+):\n((?:    .+\n?)*)', vol_section, re.MULTILINE)
external_vols = [name for name, block in vol_blocks if "external: true" in block]
if external_vols:
    lines.append("volumes:")
    for v in external_vols:
        lines.append(f"  {v}:")
        lines.append(f"    external: false")
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
      echo "Building + starting: $SPORT (+ always-on user-api — web runs separately in VS Code)"
      SERVICES=$(compose --profile "$SPORT" config --services | grep -v '^scorexl-web$')
      compose --profile "$SPORT" up -d --build $SERVICES
    else
      echo "Building + starting everything (all sports — web runs separately in VS Code)"
      COMPOSE_ARGS=()
      for s in "${VALID_SPORTS[@]}"; do COMPOSE_ARGS+=(--profile "$s"); done
      SERVICES=$(compose "${COMPOSE_ARGS[@]}" config --services | grep -v '^scorexl-web$')
      compose "${COMPOSE_ARGS[@]}" up -d --build --remove-orphans $SERVICES
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
