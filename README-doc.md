# scorexl-infra — detalhes

## Servidor

| IP | Utilizador | Projeto |
|---|---|---|
| `209.38.194.84` | `fmacuacua` (root bloqueado) | `/home/fmacuacua/projects/scorexl-infra` |

O droplet antigo (`188.166.116.252`) foi destruído: a instalação começou do zero, sem migração de dados.
Os jogos e as odds voltam a encher-se pelos jobs agendados do backend; o histórico de picks, utilizadores
e assinaturas antigos perdeu-se.

## Stack

| Container | Porta | |
|---|---|---|
| `scorexl-backend` | 127.0.0.1:8080 | todos os desportos + utilizadores |
| `scorexl-postgres` | 127.0.0.1:5440 | base `scorexl`, um schema por desporto + `account` + `platform` |
| `scorexl-web` | 127.0.0.1:3000 | site |
| `scorexl-umami` / `scorexl-umami-postgres` | 127.0.0.1:18000 / 5445 | analytics |

Domínios (nginx na porta 80, atrás do Cloudflare):

| Domínio | Vai para |
|---|---|
| `scorexl.com`, `www` | web |
| `api.scorexl.com` | backend `/football` |
| `<desporto>-api.scorexl.com` | backend `/<desporto>` |
| `analytics.scorexl.com` | umami |

**Porque 127.0.0.1:** o Docker escreve as próprias regras de iptables e ignora o ufw. Uma porta em
`0.0.0.0` fica aberta à internet mesmo com o ufw ligado. Por isso a base só se abre por túnel SSH.

O `bootstrap.sh` **copia** `nginx/*.conf` para `/etc/nginx/sites-available` — editar o repo não muda
nada até correr o bootstrap.

O web fala com o backend pela rede Docker (`http://scorexl-backend:8080/<módulo>`), não pelos
subdomínios públicos.


## Variáveis de ambiente

Tudo num só `.env` em `~/projects/scorexl-infra` no servidor (no local: `scorexl-infra/.env`) (não versionado; modelo em `.env.example`). O
`docker-compose.yml` passa-o ao backend e ao web.

**Base de dados e backend**

| Variável | Para quê |
|---|---|
| `POSTGRES_USER` | utilizador do Postgres (backend e umami) |
| `BACKEND_POSTGRES_PASSWORD` | senha do `scorexl-postgres` |
| `API_SPORTS_KEY` | chave da API-Sports de todos os desportos (`MLB_API_SPORTS_KEY` etc. sobrepõe um só) |
| `INTERNAL_API_KEY` | protege as rotas 🔒 (sync manual, plano, admin) — partilhada com o web |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_EMAIL` | push notifications |
| `CORS_ALLOWED_ORIGINS` | origens permitidas no módulo `user` |
| `BACKEND_JAVA_TOOL_OPTIONS` | opcional, padrão `-Xmx1g -XX:MaxMetaspaceSize=384m -Xss512k` |

**Web**

| Variável | Para quê |
|---|---|
| `SCOREXL_*_API_URL` | não precisas de definir: o compose já aponta para `http://scorexl-backend:8080/<módulo>` |
| `NEXT_PUBLIC_SCOREXL_API_URL`, `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | entram no build da imagem (GitHub Actions), não aqui |
| `AUTH_URL`, `AUTH_TRUST_HOST`, `AUTH_SECRET` | sessão (Auth.js) |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | login Google |
| `CRON_SECRET` | rotas de cron |
| `UMAMI_SCRIPT_URL`, `UMAMI_WEBSITE_ID` | analytics no site |

**Umami e imagens**

| Variável | Para quê |
|---|---|
| `UMAMI_POSTGRES_DB`, `UMAMI_POSTGRES_PASSWORD`, `UMAMI_APP_SECRET` | analytics |
| `GH_PACKAGES_TOKEN` | `docker login ghcr.io` para puxar as imagens privadas |

As `<DESPORTO>_POSTGRES_*` e `USER_POSTGRES_PASSWORD` são do stack antigo e já não são usadas.

## Migração

Não usada (não havia dados para migrar). O `migrate-to-single-backend.sh` fica no repo para o caso de um
servidor com o stack antigo: o `deploy.sh` só recusa correr se encontrar containers `scorexl-*-api` antigos
sem migração feita.

## Plano da API-Sports

Cada desporto está em FREE (padrão, 100 chamadas/dia, sem explorer) ou PAID. Detalhes no
`README-doc.md` do `scorexl-backend`.

## Scripts

| Script | Faz |
|---|---|
| `provision-droplet.sh` | setup de um Ubuntu 24.04: Docker, nginx, ufw (22, 80), fail2ban, updates automáticos, swap 2 GB, logs limitados, aplica o nginx. Corre do clone; pode correr de novo. |
| `bootstrap.sh` | instala nginx (e Docker se faltar), copia `nginx/*.conf`, recarrega |
| `deploy.sh` | login no GHCR (`GH_PACKAGES_TOKEN` do `.env`) + `compose pull` + `up -d` |
| `migrate-to-single-backend.sh` | ver acima |
| `dev.sh` | local: build a partir de `../scorexl-backend`; não sobe o web (corre com `pnpm dev`) |

## Notas do setup local

- `API_SPORTS_KEY` vazia no local: com a chave real, os jobs gastam a cota de produção (a conta é a mesma).
- Modo 4A (Docker) — o backend só escuta em 127.0.0.1; o telemóvel não chega lá. Para o mobile, usa o modo 4B.
- O módulo `user` não tem endereço público: sem backend local, login e favoritos não funcionam.
- Mobile: usa o IP do PC na rede, não `localhost`.
