# scorexl-infra — detalhes

## Servidor

| IP | Utilizador | Projeto |
|---|---|---|
| `159.89.3.248` | `fmacuacua` (root bloqueado) | `/home/fmacuacua/projects/scorexl-infra` |

Os palpites vêm do feed [scorexl-picks](https://github.com/devmacuacua/scorexl-picks); o backend
copia-os para a base, liquida-os e envia as push. Já não há motores nem chamadas à API-Sports.

## Stack

| Container | Porta | |
|---|---|---|
| `scorexl-backend` | 127.0.0.1:8080 | picks (feed), utilizadores, push, histórico do basquetebol |
| `scorexl-postgres` | 127.0.0.1:5440 | base `scorexl`, um schema por módulo (`picks`, `account`, `basketball`) |
| `scorexl-web` | 127.0.0.1:3000 | site |
| `scorexl-umami` / `scorexl-umami-postgres` | 127.0.0.1:18000 / 5445 | analytics |

Domínios (nginx na porta 80, atrás do Cloudflare):

| Domínio | Vai para |
|---|---|
| `scorexl.com`, `www` | web |
| `api.scorexl.com/picks/…` | backend `/picks` (só GET) — site e app |
| `api.scorexl.com/user/…` | backend `/user` — conta e push; o backend exige token |
| `basketball-api.scorexl.com` | backend `/basketball` (histórico) |
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
| `INTERNAL_API_KEY` | chave do servidor do site para o módulo `user` do backend — partilhada com o web |
| `GOOGLE_CLIENT_IDS` | client IDs OAuth aceites nos tokens Google da app (web, Android, iOS) |
| `EXPO_ACCESS_TOKEN` | opcional, push para telemóveis com "enhanced push security" |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_EMAIL` | push notifications |
| `CORS_ALLOWED_ORIGINS` | origens permitidas no módulo `user` |
| `BACKEND_JAVA_TOOL_OPTIONS` | opcional, padrão `-Xmx512m -XX:MaxMetaspaceSize=256m -Xss512k` |

**Web**

| Variável | Para quê |
|---|---|
| `SCOREXL_PICKS_API_URL`, `SCOREXL_USER_API_URL` | não precisas de definir: o compose já aponta para `http://scorexl-backend:8080/<módulo>` |
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `NEXT_PUBLIC_ADSENSE_*` | entram no build da imagem (GitHub Actions), não aqui |
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

## Scripts

| Script | Faz |
|---|---|
| `provision-droplet.sh` | setup de um Ubuntu 24.04: Docker, nginx, ufw (22, 80), fail2ban, updates automáticos, swap 2 GB, logs limitados, aplica o nginx. Corre do clone; pode correr de novo. |
| `bootstrap.sh` | instala nginx (e Docker se faltar), copia `nginx/*.conf`, recarrega |
| `deploy.sh` | login no GHCR (`GH_PACKAGES_TOKEN` do `.env`) + `compose pull` + `up -d` + limpa imagens antigas |
| `apply-db-passwords.sh` | aplica `BACKEND_POSTGRES_PASSWORD` / `UMAMI_POSTGRES_PASSWORD` do `.env` dentro dos Postgres (que só leem a senha ao criar a base) e faz deploy |
| `dev.sh` | local: `up` / `down` / `logs` / `build` — backend (build de `../scorexl-backend`), Postgres e umami; o web corre com `pnpm dev` |

## Notas do setup local

- Web local precisa de Node 22 (o Tailwind 4.3 falha no Node 20).
- Modo 4A (Docker) — o backend só escuta em 127.0.0.1; o telemóvel não chega lá. Para o mobile, usa o modo 4B.
- Sem backend local, login, conta e push não funcionam.
- Mobile: usa o IP do PC na rede, não `localhost`.
