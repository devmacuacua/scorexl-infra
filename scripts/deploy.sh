#!/usr/bin/env bash
set -e

# Produção: login no GHCR (GH_PACKAGES_TOKEN do .env), pull das imagens :latest, up -d.
#   cd ~/projects/scorexl-infra && ./scripts/deploy.sh

cd "$(dirname "$0")/.."

TOKEN=$(grep -E '^GH_PACKAGES_TOKEN=' .env 2>/dev/null | cut -d= -f2-)
if [ -z "$TOKEN" ]; then
  echo "Falta GH_PACKAGES_TOKEN no .env (PAT do GitHub com read:packages)." >&2
  exit 1
fi
if ! echo "$TOKEN" | docker login ghcr.io -u devmacuacua --password-stdin >/dev/null; then
  echo "Login no GHCR falhou: o GH_PACKAGES_TOKEN expirou ou não tem read:packages." >&2
  exit 1
fi

echo "Deploy $(date)"
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
docker image prune -f >/dev/null
echo "Deploy ok"
