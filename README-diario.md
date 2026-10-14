# Dia a dia

Primeira vez: [README-setup-local.md](README-setup-local.md) · [README-setup-prod.md](README-setup-prod.md).

# Local

Na tua máquina, em `~/workspace-scorexl`.

## 1. Ligar e desligar

```bash
cd scorexl-infra
./scripts/dev.sh up             # backend (build do ../scorexl-backend) + Postgres + umami
./scripts/dev.sh logs
./scripts/dev.sh down
```

Ou, a mexer no backend: `docker compose up -d scorexl-postgres` e `./mvnw spring-boot:run` no `scorexl-backend`.

## 2. Web e mobile

```bash
cd scorexl-web && pnpm dev                 # http://localhost:3000
cd scorexl-mobile && npm run start
```

## 3. Base local

```bash
docker exec -it scorexl-postgres psql -U scorexl -d scorexl
```

## 4. Recomeçar com a base vazia

```bash
cd scorexl-infra
./scripts/dev.sh down
docker volume rm scorexl_backend_postgres_data
```

# Produção

No servidor novo, em `/opt/scorexl-infra` (entra com `ssh scorexl` — atalho no README-setup-prod).

## 1. Publicar uma versão nova

Depois do push no `scorexl-backend` ou `scorexl-web` (o GitHub Actions gera a imagem `:latest`):

```bash
ssh scorexl
cd /opt/scorexl-infra
./scripts/deploy.sh
```

## 2. Ver o estado e os logs

```bash
docker compose ps
docker stats --no-stream
docker logs -f --tail=200 scorexl-backend
docker logs -f --tail=200 scorexl-web
```

## 3. Mudar o nginx

Edita `nginx/*.conf` neste repo, envia para o servidor e reaplica (o script copia os ficheiros):

```bash
rsync -a nginx/ scorexl:/opt/scorexl-infra/nginx/
ssh scorexl 'cd /opt/scorexl-infra && sudo ./scripts/bootstrap.sh'
```

## 4. Mudar o `.env`

```bash
ssh scorexl
nano /opt/scorexl-infra/.env
cd /opt/scorexl-infra && docker compose up -d      # recria só os containers afetados
```

## 5. Base de dados para análise

A porta só existe em 127.0.0.1 no servidor, por isso abre um túnel:

```bash
ssh -L 5440:127.0.0.1:5440 scorexl
```

Depois liga a `localhost:5440`, base `scorexl`, utilizador `POSTGRES_USER`, senha `BACKEND_POSTGRES_PASSWORD`.
Cada desporto é um schema (`football`, `basketball`, …, `account`, `platform`).

## 6. Plano da API-Sports de um desporto

```bash
curl https://mlb-api.scorexl.com/api/v1/plan                 # ver plano + cota de hoje

curl -X PUT https://mlb-api.scorexl.com/api/v1/plan \
  -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" \
  -d '{"plan":"PAID"}'                                          # FREE ou PAID, vale em até 30s
```

## Scripts

| Script | Faz |
|---|---|
| `provision-droplet.sh` | setup inicial de um Ubuntu 24.04 (pode correr de novo) |
| `bootstrap.sh` | instala nginx, copia `nginx/*.conf`, recarrega |
| `deploy.sh` | `compose pull` + `up -d`; recusa correr sem migração feita |
| `migrate-to-single-backend.sh` | `dump` (antigo) / `restore <dir>` (novo) / `all` (mesmo servidor) |
| `dev.sh` | ambiente local, faz build a partir dos repos ao lado |
