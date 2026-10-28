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

## 6. Arrancar ✅ (2026-10-14)

```bash
cd ~/projects/scorexl-infra && ./scripts/deploy.sh
```

## 7. DNS

Cloudflare: `@`, `www`, `api`, `analytics` e todos os `*-api` → A `159.89.3.248` (proxy ligado).

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
