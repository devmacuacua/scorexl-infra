# Dia a dia

## Local

### Ligar / desligar

```bash
cd ~/projects/scorexl-infra
./scripts/dev.sh up
./scripts/dev.sh down
```

### Ver logs

```bash
./scripts/dev.sh logs
```

### Entrar na base

```bash
docker exec -it scorexl-postgres psql -U scorexl -d scorexl
```

### Apagar a base e recomeçar

```bash
./scripts/dev.sh down
docker volume rm scorexl_backend_postgres_data
```

## Produção

### Publicar versão nova

```bash
ssh scorexl 'cd ~/projects/scorexl-infra && git pull && ./scripts/deploy.sh'
```

### Ver estado e logs

```bash
ssh scorexl
docker compose -f ~/projects/scorexl-infra/docker-compose.yml ps
docker logs -f --tail=200 scorexl-backend
docker logs -f --tail=200 scorexl-web
```

### Mudar o nginx

```bash
ssh -t scorexl 'cd ~/projects/scorexl-infra && git pull && sudo ./scripts/bootstrap.sh'
```

### Mudar o `.env`

```bash
ssh scorexl
nano ~/projects/scorexl-infra/.env
cd ~/projects/scorexl-infra && ./scripts/deploy.sh
```

### Mudar a senha da base (mantém os dados)

```bash
nano ~/projects/scorexl-infra/.env      # BACKEND_POSTGRES_PASSWORD / UMAMI_POSTGRES_PASSWORD
cd ~/projects/scorexl-infra && ./scripts/apply-db-passwords.sh
```

### Apagar as bases e recomeçar ⚠️ perde os dados

```bash
cd ~/projects/scorexl-infra && docker compose down -v && ./scripts/deploy.sh
```

### Abrir a base no teu PC

```bash
ssh -N -L 5440:127.0.0.1:5440 scorexl
```

Liga a `localhost:5440`, base `scorexl`.

### Ver a cota de um desporto

```bash
curl https://mlb-api.scorexl.com/api/v1/quota
```
