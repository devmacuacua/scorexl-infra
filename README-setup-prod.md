# Setup de produção

Servidor `159.89.3.248` · utilizador `fmacuacua` · projeto em `~/projects/scorexl-infra`.

## 1. Droplet ✅

Painel: Ubuntu 24.04 · 4 GB / 2 vCPU · chave `id_rsa_do` · backups ligados.
Networking → Firewalls: portas 22 e 80.

## 2. Utilizador ✅

```bash
ssh root@159.89.3.248
adduser fmacuacua && usermod -aG sudo fmacuacua
rsync -a --chown=fmacuacua:fmacuacua ~/.ssh /home/fmacuacua
```

Noutro terminal, confirma que `ssh scorexl` entra antes de continuar.

### Bloquear root e login por senha ✅

Ainda como root:

```bash
nano /etc/ssh/sshd_config
```

Muda estas duas linhas (tira o `#` se estiverem comentadas):

```
PermitRootLogin no
PasswordAuthentication no
```

Grava (`Ctrl+O`, `Enter`) e sai (`Ctrl+X`), depois:

```bash
systemctl restart ssh
```

Verificar:

```bash
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'   # ambos "no"
```

No teu PC: `ssh root@159.89.3.248` → `Permission denied (publickey)`.

## 3. Chave do GitHub ✅

Cada servidor tem a sua chave: num droplet novo, gera e adiciona outra.

```bash
ssh scorexl
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
nano ~/.ssh/id_ed25519.pub
```

Copia a linha toda e sai (`Ctrl+X`).

GitHub → `devmacuacua/scorexl-infra` → Settings → Deploy keys → Add deploy key: cola a chave, "Allow write access" desligado. Apaga a deploy key de servidores antigos.

Testar:

```bash
ssh -T git@github.com   # "Hi devmacuacua/scorexl-infra! You've successfully authenticated"
```

Se der `Permission denied (publickey)`: a chave não está nas Deploy keys, ou estás com outro utilizador (`root`/`sudo` usa outro `~/.ssh`).

## 4. Clonar e provisionar ✅

```bash
mkdir -p ~/projects && cd ~/projects
git clone git@github.com:devmacuacua/scorexl-infra.git
cd scorexl-infra && git checkout single-backend
sudo bash scripts/provision-droplet.sh
sudo usermod -aG docker fmacuacua
```

O script instala Docker, nginx, firewall, fail2ban e swap; no fim mostra `Provisioned. Docker …`.

Sai e volta a entrar (`exit`, `ssh scorexl`) para o grupo `docker` ficar ativo. Verificar:

```bash
docker ps   # sem "permission denied"
```

Se o `deploy.sh` der `docker: command not found`, este passo não correu.

## 5. `.env` ✅

```bash
cd ~/projects/scorexl-infra && cp .env.example .env && nano .env
```

## 6. Arrancar ✅ (2026-10-28)

```bash
cd ~/projects/scorexl-infra && ./scripts/deploy.sh
```

## 7. DNS

Cloudflare: `@`, `www`, `api`, `analytics` e todos os `*-api` → A `159.89.3.248` (proxy ligado).

## 8. Carregar histórico (base nova)

A base nova só tem os próximos jogos (o full sync corre de 2 em 2 h e traz hoje + 2 dias). Sem jogos passados e estatísticas, não há stats nem picks (`picksGenerated=0`).

```bash
cd ~/projects/scorexl-infra
K=$(grep -E '^INTERNAL_API_KEY=' .env | cut -d= -f2-)
API=https://api.scorexl.com/api/v1/sync
```

Por ordem, cada um só depois do anterior estar `SUCCESS` em `curl -s $API/status`:

```bash
# 1. resultados passados (~1 pedido por dia)
curl -s -X POST -H "Authorization: Bearer $K" "$API/history?daysBack=60"

# 2. estatísticas (cantos, cartões, remates, faltas) dos jogos passados
curl -s -X POST -H "Authorization: Bearer $K" "$API/statistics/backfill?days=30"

# 3. gerar picks (não gasta quota)
curl -s -X POST -H "Authorization: Bearer $K" "$API/pipeline?days=2"
```

O backfill só trata jogos que já estão na base (por isso o `history` primeiro) e gasta **1 pedido por jogo**, com 3 s entre pedidos. Corre em background: `docker logs -f scorexl-backend | grep -i backfill`.

Quota do football: 7500/dia, reinicia às 00:00 UTC. Ver antes de correr o backfill:

```bash
A=$(grep -E '^API_SPORTS_KEY=' .env | cut -d= -f2-)
curl -s -H "x-apisports-key: $A" https://v3.football.api-sports.io/status | grep -o '"requests":{[^}]*}'
```

Se faltar quota, faz `days=30` num dia e `days=60` no seguinte (os já preenchidos são saltados).

## Atalho SSH (no teu PC)

```bash
nano ~/.ssh/config
```

```
Host scorexl
    HostName 159.89.3.248
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```
