# scorexl-infra

Como o ScoreXL roda em produção: um `docker-compose.yml`, configs do nginx e scripts.
Branch `single-backend` = stack novo (1 backend + 1 Postgres). `main` = stack antigo
(13 APIs + 13 Postgres), ainda em produção até o cutover.

## Stack

| Container | Imagem | Porta (só 127.0.0.1) |
|---|---|---|
| `scorexl-backend` | `ghcr.io/devmacuacua/scorexl-backend` | 8080 |
| `scorexl-postgres` | `postgres:16` — DB `scorexl`, um schema por esporte + `account` + `platform` | 5440 |
| `scorexl-web` | `ghcr.io/devmacuacua/scorexl-web` | 3000 |
| `scorexl-umami` + `scorexl-umami-postgres` | analytics | 18000 / 5445 |

nginx (porta 80, atrás do Cloudflare) mapeia os domínios:
`scorexl.com` → web, `analytics.scorexl.com` → umami, `api.scorexl.com` → `/football`,
`<esporte>-api.scorexl.com` → `/<esporte>` no backend.

Portas só em 127.0.0.1 porque o Docker ignora o ufw. Acesso ao banco para análise:

```bash
ssh -i ~/.ssh/id_rsa_do -L 5440:127.0.0.1:5440 root@209.38.194.84   # depois: localhost:5440
```

## Dia a dia (no servidor, em /opt/scorexl-infra)

```bash
./scripts/deploy.sh               # pull das imagens :latest + up -d
sudo ./scripts/bootstrap.sh       # reaplica nginx/*.conf (o script COPIA os arquivos)
docker compose ps
docker logs -f --tail=200 scorexl-backend
```

`.env` (não versionado; modelo em `.env.example`): `POSTGRES_USER`, `BACKEND_POSTGRES_PASSWORD`,
`API_SPORTS_KEY`, `INTERNAL_API_KEY`, `GH_PACKAGES_TOKEN`, `VAPID_*`, `UMAMI_*` e as do web.

Local: `./scripts/dev.sh up` builda a partir dos repos irmãos (`../scorexl-backend`, ...).

## Servidores

| | IP | |
|---|---|---|
| novo | `209.38.194.84` | stack novo, criado 2026-10-14 |
| antigo | `188.166.116.252` | produção atual / rollback. SSH só de IPs liberados |

## Cutover para o droplet novo

- [x] droplet criado (Ubuntu 24.04), chave `id_rsa_do`
- [x] provisionado: `ssh root@209.38.194.84 'bash -s' < scripts/provision-droplet.sh`
      (Docker, nginx, ufw 22/80, fail2ban, updates automáticos, swap 2 GB, logs limitados)
- [x] repo em `/opt/scorexl-infra`:
      `rsync -a --exclude .env --exclude backups --exclude .git ./ root@209.38.194.84:/opt/scorexl-infra/`
- [ ] **redimensionar para 4 GB / 2 vCPU** (foi criado com 512 MB): painel → Power off → Resize →
      "CPU and RAM + disk" → Power on
- [ ] `.env` do antigo → novo, e acrescentar `BACKEND_POSTGRES_PASSWORD`:
      `scp -3 root@188.166.116.252:<pasta do infra>/.env root@209.38.194.84:/opt/scorexl-infra/.env`
- [ ] no novo, preparar (sem downtime):
      ```bash
      grep ^GH_PACKAGES_TOKEN= .env | cut -d= -f2- | docker login ghcr.io -u devmacuacua --password-stdin
      docker compose pull && ./scripts/bootstrap.sh
      ```
- [ ] **início do downtime** — dump no antigo (num worktree, sem mexer no que está rodando):
      ```bash
      cd <pasta do infra> && git fetch && git worktree add /opt/scorexl-migrate origin/single-backend
      cd /opt/scorexl-migrate && ./scripts/migrate-to-single-backend.sh dump
      ```
      Para as APIs antigas e gera `backups/<ts>.tgz` (13 bancos + umami + contagem de linhas).
- [ ] copiar o dump:
      `scp -3 root@188.166.116.252:/opt/scorexl-migrate/backups/<ts>.tgz root@209.38.194.84:/opt/scorexl-infra/backups/`
- [ ] no novo, restaurar (confere cada tabela) e subir:
      ```bash
      tar -C backups -xzf backups/<ts>.tgz && ./scripts/migrate-to-single-backend.sh restore backups/<ts>
      ./scripts/deploy.sh
      ```
- [ ] testar antes do DNS:
      ```bash
      curl -s -H 'Host: basketball-api.scorexl.com' http://127.0.0.1/api/v1/plan
      curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: scorexl.com' http://127.0.0.1/
      ```
- [ ] Cloudflare: registros A (`scorexl.com`, `www`, `api`, `*-api`, `analytics`) →
      `209.38.194.84` — **fim do downtime**
- [ ] planos: todo esporte começa em FREE; se a conta da API-Sports for Pro, passar para PAID
      (ver README do `scorexl-backend`)

**Rollback:** DNS de volta para `188.166.116.252` e, no antigo, `docker start` nas APIs que o
dump parou (ele imprime a lista). Destruir o droplet antigo só depois de alguns dias estáveis.

Mesmo servidor em vez de droplet novo: `git checkout single-backend`, `.env` com
`BACKEND_POSTGRES_PASSWORD`, `./scripts/migrate-to-single-backend.sh` (modo `all`),
`./scripts/deploy.sh`, `sudo ./scripts/bootstrap.sh`.

## Scripts

| Script | O quê |
|---|---|
| `provision-droplet.sh` | setup único de um Ubuntu 24.04 novo (idempotente) |
| `bootstrap.sh` | instala nginx (e Docker se faltar), copia `nginx/*.conf`, recarrega |
| `deploy.sh` | `compose pull` + `up -d`; recusa rodar sem `.single-backend-migrated` |
| `migrate-to-single-backend.sh` | `all` / `dump` / `restore <dir>` — migração dos 13 bancos |
| `dev.sh` | ambiente local buildando dos repos irmãos |
