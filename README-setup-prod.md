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

Cloudflare: `@`, `www`, `api`, `analytics` e `basketball-api` → A `159.89.3.248` (proxy ligado).

## 8. Mudar para o feed de picks (uma vez)

Antes: as branches `feature/scorexl-picks-feed` do `scorexl-backend` e do `scorexl-web` juntas no `main`
e as imagens novas geradas (GitHub → Actions, ambos verdes).

```bash
ssh scorexl
cd ~/projects/scorexl-infra && git fetch && git checkout feature/scorexl-picks-feed && git pull
nano .env
```

No `.env`, acrescenta (o resto fica):

```
GOOGLE_CLIENT_IDS=<GOOGLE_CLIENT_ID>,<client ID Android>,<client ID iOS>
```

`INTERNAL_API_KEY` tem de existir: o site usa-a para falar com o backend (sem ela, login e conta falham).

```bash
sudo ./scripts/bootstrap.sh
./scripts/deploy.sh
```

Verificar:

```bash
docker logs scorexl-backend 2>&1 | grep -E "Started|\[feed\]|ERROR"
curl -s https://api.scorexl.com/picks/api/v1/summary
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://api.scorexl.com/user/api/v1/push/notify   # 401
curl -s -o /dev/null -w "%{http_code}\n" https://scorexl.com/                                     # 200
```

No primeiro arranque o backend importa o feed todo e envia, no máximo, uma push de novos palpites
(só se houver jogo por começar) e uma de resultados por dia dos últimos 2 dias.

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
