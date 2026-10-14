#!/usr/bin/env bash
set -e

# Local: backend (build de ../scorexl-backend) + Postgres + umami. O web corre à parte (pnpm dev).
#   ./scripts/dev.sh up | down | logs | build

cd "$(dirname "$0")/.."

compose() {
  docker compose -f docker-compose.yml -f docker-compose.dev.yml "$@"
}

SERVICES="scorexl-backend scorexl-postgres scorexl-umami scorexl-umami-postgres"

case "${1:-up}" in
  up)    compose up -d --build $SERVICES && compose ps ;;
  down)  compose down ;;
  logs)  compose logs -f --tail=200 ;;
  build) compose build scorexl-backend ;;
  *)     echo "Uso: $0 {up|down|logs|build}" >&2; exit 1 ;;
esac
