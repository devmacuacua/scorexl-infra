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

---

# Novo droplet — passo a passo

Estado: passos 1 e 2 feitos (2026-10-14). Próximo: **3**.

## 1. Criar o droplet ✅

No painel da DigitalOcean: Ubuntu 24.04, **4 GB / 2 vCPU**, mesma região do antigo, chave SSH `id_rsa_do`, backups ligados.

## 2. Provisionar ✅

Corre no teu PC, dentro deste repo:

```bash
ssh -i ~/.ssh/id_rsa_do root@209.38.194.84 'bash -s' < scripts/provision-droplet.sh
rsync -a --exclude .env --exclude backups --exclude .git -e "ssh -i ~/.ssh/id_rsa_do" ./ root@209.38.194.84:/opt/scorexl-infra/
```

Instala Docker, nginx, ufw (22 e 80), fail2ban, atualizações automáticas, swap de 2 GB e limita os logs do Docker.

## 3. Redimensionar para 4 GB

O droplet foi criado com 512 MB — não chega para o stack.

No painel: **Power off → Resize → 4 GB / 2 vCPU ("CPU and RAM + disk") → Power on**. Nada do que foi instalado se perde.

## 4. Utilizador `fmacuacua` e fuso horário

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

## 5. Endurecer o SSH

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

A partir daqui, entras sempre como `fmacuacua` (ver **Atalho SSH** no fim).

## 6. Cloud Firewall

No painel da DigitalOcean: **Networking → Firewalls → Create**, só com as portas **22** e **80** abertas, associada ao droplet `209.38.194.84`.

> ⚠️ O Docker ignora o ufw. Por isso todas as portas no `docker-compose.yml` estão em `127.0.0.1:PORTA:PORTA`. Nunca publiques uma base de dados em `0.0.0.0`.

## 7. Enviar o `.env`

O `.env` de produção está no droplet antigo. Corre no teu PC (de uma máquina que tenha acesso SSH ao antigo):

```bash
scp -3 root@188.166.116.252:<pasta do infra>/.env scorexl:/opt/scorexl-infra/.env
```

No novo, acrescenta uma senha nova para o Postgres único:

```bash
ssh scorexl
echo 'BACKEND_POSTGRES_PASSWORD=<senha nova>' >> /opt/scorexl-infra/.env
```

## 8. GHCR, imagens e nginx

```bash
ssh scorexl
cd /opt/scorexl-infra
grep ^GH_PACKAGES_TOKEN= .env | cut -d= -f2- | docker login ghcr.io -u devmacuacua --password-stdin
docker compose pull
sudo ./scripts/bootstrap.sh
```

Ainda sem downtime — o antigo continua a servir.

## 9. Dump no droplet antigo — ⚠️ início do downtime

```bash
ssh root@188.166.116.252
cd <pasta do infra>
git fetch && git worktree add /opt/scorexl-migrate origin/single-backend
cd /opt/scorexl-migrate
./scripts/migrate-to-single-backend.sh dump
```

Para as 13 APIs antigas (as bases continuam ligadas) e cria `backups/<ts>.tgz` com as 13 bases, o umami e a contagem de linhas de cada tabela. O worktree não mexe no que está a correr.

## 10. Copiar o dump para o novo

No teu PC:

```bash
scp -3 root@188.166.116.252:/opt/scorexl-migrate/backups/<ts>.tgz scorexl:/opt/scorexl-infra/backups/
```

## 11. Restaurar e arrancar

```bash
ssh scorexl
cd /opt/scorexl-infra
tar -C backups -xzf backups/<ts>.tgz
./scripts/migrate-to-single-backend.sh restore backups/<ts>
./scripts/deploy.sh
```

O `restore` confere cada tabela contra a contagem do dump e recusa restaurar por cima de dados.

## 12. Verificar (antes de mudar o DNS)

```bash
docker compose ps
docker stats --no-stream
curl -s -H 'Host: basketball-api.scorexl.com' http://127.0.0.1/api/v1/plan
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: scorexl.com' http://127.0.0.1/
docker logs --tail=100 scorexl-backend
```

## 13. DNS no Cloudflare — ✅ fim do downtime

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

## 14. Planos da API-Sports

Todos os desportos arrancam em **FREE**. Se a conta da API-Sports ainda for Pro, passa os que quiseres para **PAID**:

```bash
curl -X PUT https://basketball-api.scorexl.com/api/v1/plan \
  -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" \
  -d '{"plan":"PAID"}'
```

## Rollback

1. Cloudflare: registos A de volta para `188.166.116.252`.
2. No antigo: `docker start <lista que o dump imprimiu>`.

Só destróis o droplet antigo depois de alguns dias estáveis.

---

# Dia a dia

```bash
ssh scorexl
cd /opt/scorexl-infra
./scripts/deploy.sh                      # pull das imagens :latest + up -d
sudo ./scripts/bootstrap.sh              # reaplica nginx/*.conf (o script copia os ficheiros)
docker compose ps
docker logs -f --tail=200 scorexl-backend
```

Base de dados para análise (a porta só existe em 127.0.0.1):

```bash
ssh -L 5440:127.0.0.1:5440 scorexl      # depois liga a localhost:5440
```

## Atalho SSH (no teu PC)

Adiciona isto ao `~/.ssh/config`:

```
Host scorexl
    HostName 209.38.194.84
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```

Depois basta `ssh scorexl`, e para enviar ficheiros `scp ficheiro scorexl:/opt/scorexl-infra/`.

## Scripts

| Script | Faz |
|---|---|
| `provision-droplet.sh` | setup inicial de um Ubuntu 24.04 (pode correr de novo) |
| `bootstrap.sh` | instala nginx, copia `nginx/*.conf`, recarrega |
| `deploy.sh` | `compose pull` + `up -d`; recusa correr sem migração feita |
| `migrate-to-single-backend.sh` | `dump` (antigo) / `restore <dir>` (novo) / `all` (mesmo servidor) |
| `dev.sh` | ambiente local, faz build a partir dos repos ao lado |
