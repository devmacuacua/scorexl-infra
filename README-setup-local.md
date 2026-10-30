# Setup local

Requisitos: Docker, Node 22 + pnpm, Java 21 (só para o modo B).

## 1. Clonar o scorexl-infra

```bash
mkdir -p ~/projects && cd ~/projects
git clone git@github.com:devmacuacua/scorexl-infra.git
cd scorexl-infra && git checkout single-backend
```

## 2. Clonar o resto (ao lado do infra)

```bash
cd ~/projects
git clone git@github.com:devmacuacua/scorexl-backend.git
git clone git@github.com:devmacuacua/scorexl-web.git
git clone git@github.com:devmacuacua/scorexl-mobile.git
```

## 3. `.env` do infra

```bash
cd ~/projects/scorexl-infra
cat > .env <<'X'
POSTGRES_USER=scorexl
BACKEND_POSTGRES_PASSWORD=scorexl
INTERNAL_API_KEY=dev
API_SPORTS_KEY=
X
```

## 4A. Backend em Docker

```bash
cd ~/projects/scorexl-infra
./scripts/dev.sh up
```

## 4B. Backend no IDE

```bash
cd ~/projects/scorexl-infra && docker compose up -d scorexl-postgres
cd ~/projects/scorexl-backend
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5440/scorexl SPRING_DATASOURCE_USERNAME=scorexl SPRING_DATASOURCE_PASSWORD=scorexl INTERNAL_API_KEY=dev
./mvnw spring-boot:run
```

## 5. Confirmar o backend

```bash
curl -s http://localhost:8080/mlb/api/v1/quota
```

## 6. Web

```bash
cd ~/projects/scorexl-web
pnpm install
cat > .env.local <<'X'
SCOREXL_API_URL=http://localhost:8080/football
SCOREXL_BASKETBALL_API_URL=http://localhost:8080/basketball
SCOREXL_NBA_API_URL=http://localhost:8080/nba
SCOREXL_VOLLEYBALL_API_URL=http://localhost:8080/volleyball
SCOREXL_MLB_API_URL=http://localhost:8080/mlb
SCOREXL_AFL_API_URL=http://localhost:8080/afl
SCOREXL_NFL_API_URL=http://localhost:8080/nfl
SCOREXL_NHL_API_URL=http://localhost:8080/nhl
SCOREXL_RUGBY_API_URL=http://localhost:8080/rugby
SCOREXL_HANDBALL_API_URL=http://localhost:8080/handball
SCOREXL_MMA_API_URL=http://localhost:8080/mma
SCOREXL_USER_API_URL=http://localhost:8080/user
NEXT_PUBLIC_BACKEND_URL=http://localhost:8080/football
INTERNAL_API_KEY=dev
X
pnpm dev
```

## 7. Mobile

Troca `192.168.1.10` pelo IP do teu PC (precisa do modo 4B).

```bash
cd ~/projects/scorexl-mobile
npm install
cat > .env <<'X'
EXPO_PUBLIC_FOOTBALL_API_URL=http://192.168.1.10:8080/football
EXPO_PUBLIC_BASKETBALL_API_URL=http://192.168.1.10:8080/basketball
EXPO_PUBLIC_NBA_API_URL=http://192.168.1.10:8080/nba
X
npm run start
```

## 8. Dados de produção (opcional)

```bash
ssh -N -L 5441:127.0.0.1:5440 scorexl &
pg_dump -h localhost -p 5441 -U scorexl -Fc scorexl > prod.dump
pg_restore -h localhost -p 5440 -U scorexl -d scorexl --no-owner --clean --if-exists prod.dump
```
