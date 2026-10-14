# Setup de produção

Preparar o VPS, uma vez: servidor, `.env` e migração do droplet antigo.
Local: [README-setup-local.md](README-setup-local.md).

## Novo droplet — passo a passo

Estado (2026-10-14): passos 1, 2, 4 e 5 feitos; 3 a meio (está com 2 GB / 1 vCPU). Próximo: **3**, depois **6** e **7**.

### 1. Criar o droplet ✅

No painel da DigitalOcean: Ubuntu 24.04, **4 GB / 2 vCPU**, mesma região do antigo, chave SSH `id_rsa_do`, backups ligados.

### 2. Provisionar ✅

Corre no teu PC, dentro deste repo:

```bash
ssh -i ~/.ssh/id_rsa_do root@209.38.194.84 'bash -s' < scripts/provision-droplet.sh
rsync -a --exclude .env --exclude backups --exclude .git -e "ssh -i ~/.ssh/id_rsa_do" ./ root@209.38.194.84:/opt/scorexl-infra/
```

Instala Docker, nginx, ufw (22 e 80), fail2ban, atualizações automáticas, swap de 2 GB e limita os logs do Docker.

### 3. Redimensionar para 4 GB ⚠️ a meio

Criado com 512 MB, já passou para **2 GB / 1 vCPU / 48 GB** — ainda curto: o backend sozinho usa até ~1,4 GB.

No painel: **Power off → Resize → 4 GB / 2 vCPU ("CPU and RAM + disk") → Power on**. Nada do que foi instalado se perde.

### 4. Utilizador `fmacuacua` e fuso horário ✅

```bash
ssh -i ~/.ssh/id_rsa_do root@209.38.194.84

timedatectl set-timezone Africa/Maputo
adduser fmacuacua
usermod -aG sudo,docker fmacuacua
rsync --archive --chown=fmacuacua:fmacuacua ~/.ssh /home/fmacuacua
chown -R fmacuacua:fmacuacua /opt/scorexl-infra
```

Não fechas esta sessão ainda. Noutro terminal, confirma que entras com o novo utilizador:

```bash
ssh -i ~/.ssh/id_rsa_do fmacuacua@209.38.194.84
```

### 5. Endurecer o SSH ✅

```bash
sudo nano /etc/ssh/sshd_config
```

Altera estas duas linhas:

```
PermitRootLogin no
PasswordAuthentication no
```

```bash
sudo systemctl restart ssh
```

A partir daqui, entras sempre como `fmacuacua` (configura já o **Atalho SSH**, abaixo).

### 6. Cloud Firewall

No painel da DigitalOcean: **Networking → Firewalls → Create**, só com as portas **22** e **80** abertas, associada ao droplet `209.38.194.84`.

> ⚠️ O Docker ignora o ufw. Por isso todas as portas no `docker-compose.yml` estão em `127.0.0.1:PORTA:PORTA`. Nunca publiques uma base de dados em `0.0.0.0`.

### 7. Enviar o `.env`

O `.env` de produção está no droplet antigo. Corre no teu PC (de uma máquina que tenha acesso SSH ao antigo):

```bash
scp -3 root@188.166.116.252:<pasta do infra>/.env scorexl:/opt/scorexl-infra/.env
```

No novo, acrescenta uma senha nova para o Postgres único:

```bash
ssh scorexl
echo 'BACKEND_POSTGRES_PASSWORD=<senha nova>' >> /opt/scorexl-infra/.env
```

### 8. GHCR, imagens e nginx

```bash
ssh scorexl
cd /opt/scorexl-infra
grep ^GH_PACKAGES_TOKEN= .env | cut -d= -f2- | docker login ghcr.io -u devmacuacua --password-stdin
docker compose pull
sudo ./scripts/bootstrap.sh
```

Ainda sem downtime — o antigo continua a servir.

### 9. Dump no droplet antigo — ⚠️ início do downtime

```bash
ssh root@188.166.116.252
cd <pasta do infra>
git fetch && git worktree add /opt/scorexl-migrate origin/single-backend
cd /opt/scorexl-migrate
./scripts/migrate-to-single-backend.sh dump
```

Para as 13 APIs antigas (as bases continuam ligadas) e cria `backups/<ts>.tgz` com as 13 bases, o umami e a contagem de linhas de cada tabela. O worktree não mexe no que está a correr.

### 10. Copiar o dump para o novo

No teu PC:

```bash
scp -3 root@188.166.116.252:/opt/scorexl-migrate/backups/<ts>.tgz scorexl:/opt/scorexl-infra/backups/
```

### 11. Restaurar e arrancar

```bash
ssh scorexl
cd /opt/scorexl-infra
tar -C backups -xzf backups/<ts>.tgz
./scripts/migrate-to-single-backend.sh restore backups/<ts>
./scripts/deploy.sh
```

O `restore` confere cada tabela contra a contagem do dump e recusa restaurar por cima de dados.

### 12. Verificar (antes de mudar o DNS)

```bash
docker compose ps
docker stats --no-stream
curl -s -H 'Host: basketball-api.scorexl.com' http://127.0.0.1/api/v1/plan
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: scorexl.com' http://127.0.0.1/
docker logs --tail=100 scorexl-backend
```

### 13. DNS no Cloudflare — ✅ fim do downtime

Muda os registos A de `188.166.116.252` para `209.38.194.84`:

| Tipo | Nome | Valor |
|---|---|---|
| A | `@` | 209.38.194.84 |
| A | `www` | 209.38.194.84 |
| A | `api` | 209.38.194.84 |
| A | `basketball-api`, `nba-api`, `volleyball-api`, `mlb-api`, `afl-api`, `nfl-api`, `nhl-api`, `rugby-api`, `handball-api`, `f1-api`, `mma-api` | 209.38.194.84 |
| A | `analytics` | 209.38.194.84 |

Com o proxy do Cloudflare ligado (nuvem laranja) a mudança é imediata.

```bash
curl -I https://scorexl.com
```

### 14. Planos da API-Sports

Todos os desportos arrancam em **FREE**. Se a conta da API-Sports ainda for Pro, passa os que quiseres para **PAID**:

```bash
curl -X PUT https://basketball-api.scorexl.com/api/v1/plan \
  -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" \
  -d '{"plan":"PAID"}'
```

### Rollback

1. Cloudflare: registos A de volta para `188.166.116.252`.
2. No antigo: `docker start <lista que o dump imprimiu>`.

Só destróis o droplet antigo depois de alguns dias estáveis.

### Atalho SSH (no teu PC)

Adiciona isto ao `~/.ssh/config`:

```
Host scorexl
    HostName 209.38.194.84
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```

Depois basta `ssh scorexl`, e para enviar ficheiros `scp ficheiro scorexl:/opt/scorexl-infra/`.

---

## Variáveis de ambiente (`.env`)

Tudo num só `.env` em `/opt/scorexl-infra` (não versionado; modelo em `.env.example`). O
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

As `<DESPORTO>_POSTGRES_*` e `USER_POSTGRES_PASSWORD` só servem ao stack antigo (`main`) e ao `dump`.
