# Dia a dia

## Local

### Ligar / desligar

```bash
cd ~/workspace-scorexl/scorexl-infra
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
ssh scorexl 'cd ~/scorexl && ./scripts/deploy.sh'
```

### Ver estado e logs

```bash
ssh scorexl
docker compose -f ~/scorexl/docker-compose.yml ps
docker logs -f --tail=200 scorexl-backend
docker logs -f --tail=200 scorexl-web
```

### Mudar o nginx

```bash
rsync -a nginx/ scorexl:~/scorexl/nginx/
ssh -t scorexl 'cd ~/scorexl && sudo ./scripts/bootstrap.sh'
```

### Mudar o `.env`

```bash
ssh scorexl
nano ~/scorexl/.env
cd ~/scorexl && docker compose up -d
```

### Abrir a base no teu PC

```bash
ssh -N -L 5440:127.0.0.1:5440 scorexl
```

Liga a `localhost:5440`, base `scorexl`.

### Mudar o plano de um desporto

```bash
curl https://mlb-api.scorexl.com/api/v1/plan
curl -X PUT https://mlb-api.scorexl.com/api/v1/plan -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" -d '{"plan":"PAID"}'
```
