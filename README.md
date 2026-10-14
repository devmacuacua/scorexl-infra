# scorexl-infra

Produção do ScoreXL: `docker-compose.yml`, configs do nginx e scripts.

- Branch `single-backend` → stack novo: 1 backend + 1 Postgres (droplet `209.38.194.84`)
- Branch `main` → stack antigo: 13 APIs + 13 Postgres (droplet `188.166.116.252`), em produção até ao cutover

| Container | Porta (só 127.0.0.1) |
|---|---|
| `scorexl-backend` | 8080 |
| `scorexl-postgres` (DB `scorexl`, um schema por desporto) | 5440 |
| `scorexl-web` | 3000 |
| `scorexl-umami` / `scorexl-umami-postgres` | 18000 / 5445 |

O nginx (porta 80, atrás do Cloudflare) liga os domínios: `scorexl.com` → web,
`api.scorexl.com` → `/football`, `<desporto>-api.scorexl.com` → `/<desporto>`, `analytics.scorexl.com` → umami.

- **[README-setup.md](README-setup.md)** — primeira vez: novo VPS passo a passo, variáveis de ambiente, migração
- **[README-diario.md](README-diario.md)** — dia a dia: deploy, logs, base de dados, planos, scripts
