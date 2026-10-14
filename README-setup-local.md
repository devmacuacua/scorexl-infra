# Setup local

Preparar a máquina de desenvolvimento, uma vez, para todos os projetos (backend, web, mobile).
Produção: [README-setup-prod.md](README-setup-prod.md).

## 1. Requisitos

- Docker (com `docker compose`)
- Java 21 — só se fores correr o backend fora do Docker
- Node 22 + pnpm (`corepack enable`)
- Chave SSH registada no GitHub

## 2. Clonar os repos lado a lado

```bash
mkdir -p ~/workspace-scorexl && cd ~/workspace-scorexl
for r in scorexl-infra scorexl-backend scorexl-web scorexl-mobile; do
  git clone git@github.com:devmacuacua/$r.git
done
git -C scorexl-infra checkout single-backend
```

O `dev.sh` do infra faz build a partir de `../scorexl-backend`, por isso as pastas têm de ficar lado a lado.

## 3. `.env` do infra (local)

```bash
cd ~/workspace-scorexl/scorexl-infra
cp .env.example .env
```

Preenche no mínimo:

```
POSTGRES_USER=scorexl
BACKEND_POSTGRES_PASSWORD=scorexl
INTERNAL_API_KEY=dev
API_SPORTS_KEY=
```

⚠️ Deixa `API_SPORTS_KEY` vazia. Com a chave real, os jobs do backend local chamam a API-Sports e
gastam a cota de produção (a conta é a mesma).

## 4. Base de dados + backend

Escolhe uma das duas formas.

**A. Tudo em Docker** (não vais mexer no backend):

```bash
cd ~/workspace-scorexl/scorexl-infra
./scripts/dev.sh up             # build de ../scorexl-backend + Postgres + umami
```

**B. Backend no teu IDE** (vais mexer no backend):

```bash
cd ~/workspace-scorexl/scorexl-infra
docker compose up -d scorexl-postgres            # Postgres em localhost:5440

cd ~/workspace-scorexl/scorexl-backend
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5440/scorexl
export SPRING_DATASOURCE_USERNAME=scorexl SPRING_DATASOURCE_PASSWORD=scorexl
export INTERNAL_API_KEY=dev
./mvnw spring-boot:run
```

Nos dois casos o backend fica em `http://localhost:8080`. Confirma:

```bash
curl -s http://localhost:8080/mlb/api/v1/plan
```

As tabelas e schemas são criados no primeiro arranque (base vazia — para ter dados, ver "Dados de
produção" no fim).

## 5. Web

```bash
cd ~/workspace-scorexl/scorexl-web
pnpm install
cp .env.example .env.local
```

No `.env.local`, aponta para o backend local:

| Variável | Valor local |
|---|---|
| `SCOREXL_API_URL` | `http://localhost:8080/football` |
| `SCOREXL_<DESPORTO>_API_URL` | `http://localhost:8080/<desporto>` |
| `SCOREXL_USER_API_URL` | `http://localhost:8080/user` |
| `NEXT_PUBLIC_SCOREXL_API_URL` | `http://localhost:8080/football/api/v1` |
| `NEXT_PUBLIC_BACKEND_URL` | `http://localhost:8080/football` |
| `INTERNAL_API_KEY` | `dev` (igual ao do backend) |

`<DESPORTO>` = `BASKETBALL`, `NBA`, `VOLLEYBALL`, `MLB`, `AFL`, `NFL`, `NHL`, `RUGBY`, `HANDBALL`, `MMA`.

Sem backend local, podes apontar para produção (`https://api.scorexl.com`, `https://<desporto>-api.scorexl.com`);
o `user` não tem endereço público, por isso login e favoritos não funcionam assim.

Login Google, push, etc. só se fores mexer nisso: `AUTH_SECRET`, `GOOGLE_CLIENT_ID/SECRET`, `VAPID_*`.

```bash
pnpm dev                        # http://localhost:3000
```

## 6. Mobile

```bash
cd ~/workspace-scorexl/scorexl-mobile
npm install
cp .env.example .env
```

No `.env`, usa o IP do PC na rede (o telemóvel não vê o `localhost` do PC):

| Variável | Backend local | Produção |
|---|---|---|
| `EXPO_PUBLIC_FOOTBALL_API_URL` | `http://<IP do PC>:8080/football` | `https://api.scorexl.com` |
| `EXPO_PUBLIC_BASKETBALL_API_URL` | `http://<IP do PC>:8080/basketball` | `https://basketball-api.scorexl.com` |
| `EXPO_PUBLIC_NBA_API_URL` | `http://<IP do PC>:8080/nba` | `https://nba-api.scorexl.com` |

⚠️ No modo A o backend só escuta em `127.0.0.1`; para o telemóvel chegar lá, usa o modo B ou os endereços de produção.

```bash
npm run start
```

## Dados de produção (opcional)

Para ter dados reais localmente, copia um dump do servidor (túnel SSH — ver README-diario):

```bash
ssh -L 5441:127.0.0.1:5440 scorexl          # noutro terminal
pg_dump -h localhost -p 5441 -U scorexl -Fc scorexl > prod.dump
pg_restore -h localhost -p 5440 -U scorexl -d scorexl --no-owner --clean --if-exists prod.dump
```
