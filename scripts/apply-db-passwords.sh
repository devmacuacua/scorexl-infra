#!/usr/bin/env bash
set -e

# Muda a senha dos Postgres para a que está no .env e faz deploy.
# O Postgres só lê POSTGRES_PASSWORD na primeira vez que cria a base; depois disso
# a senha vive dentro do volume. Por isso: 1) nano .env  2) ./scripts/apply-db-passwords.sh
#
# Dentro do container o psql liga por socket local (sem senha), por isso funciona
# mesmo antes de a senha antiga ser trocada.

cd "$(dirname "$0")/.."

val() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }

apply() {
  local container=$1 password=$2
  [ -z "$password" ] && { echo "$container: senha vazia no .env — ignorado"; return; }
  docker inspect "$container" >/dev/null 2>&1 || { echo "$container: não existe — ignorado"; return; }
  local escaped=${password//\'/\'\'}
  docker exec -i "$container" sh -c 'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d postgres' \
    <<<"ALTER USER \"$(val POSTGRES_USER)\" PASSWORD '$escaped';"
  echo "$container: senha atualizada"
}

apply scorexl-postgres "$(val BACKEND_POSTGRES_PASSWORD)"
apply scorexl-umami-postgres "$(val UMAMI_POSTGRES_PASSWORD)"

./scripts/deploy.sh
