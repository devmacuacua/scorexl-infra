# Setup de produção

Servidor `188.166.60.166` · utilizador `fmacuacua` · projeto em `~/projects/scorexl-infra`.

## 1. Droplet

Painel: Ubuntu 24.04 · 2 GB · região Amsterdam ou Londres (Frankfurt se houver) · chave `id_rsa_do` · backups ligados.
Networking → Firewalls: portas 22 e 80.

## 2. Utilizador

```bash
ssh root@188.166.60.166
adduser fmacuacua && usermod -aG sudo fmacuacua
rsync -a --chown=fmacuacua:fmacuacua ~/.ssh /home/fmacuacua
```

Noutro terminal, confirma que `ssh scorexl` entra antes de continuar.

### Bloquear root e login por senha

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

No teu PC: `ssh root@188.166.60.166` → `Permission denied (publickey)`.

## 3. Chave do GitHub

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

## 4. Clonar e provisionar

```bash
mkdir -p ~/projects && cd ~/projects
git clone git@github.com:devmacuacua/scorexl-infra.git
cd scorexl-infra && git checkout main
sudo bash scripts/provision-droplet.sh
sudo usermod -aG docker fmacuacua
```

O script instala Docker, nginx, firewall, fail2ban e swap; no fim mostra `Provisioned. Docker …`.

Sai e volta a entrar (`exit`, `ssh scorexl`) para o grupo `docker` ficar ativo. Verificar:

```bash
docker ps   # sem "permission denied"
```

Se o `deploy.sh` der `docker: command not found`, este passo não correu.

## 5. `.env`

O `.env.prod` do teu PC já é o `.env` de produção completo (mesma estrutura do `.env.example`). No teu PC:

```bash
cd ~/workspace-scorexl/scorexl-infra
scp .env.prod fmacuacua@188.166.60.166:~/projects/scorexl-infra/.env
ssh fmacuacua@188.166.60.166 'chmod 600 ~/projects/scorexl-infra/.env'
```

Traz as **mesmas** `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` de antes: os browsers que já tinham alertas
voltam a registar-se sozinhos. Com chaves novas, perdem os alertas.

Sem o `.env.prod`: `cp .env.example .env && nano .env` no servidor e preenche os `<...>`.

Se mudares o `.env` no servidor, copia-o de volta para o `.env.prod` (`scp` ao contrário), para os dois não divergirem.

## 6. Arrancar

```bash
cd ~/projects/scorexl-infra && ./scripts/deploy.sh
```

## 7. DNS

Cloudflare: `@`, `www`, `api`, `analytics` e `basketball-api` → A `188.166.60.166` (proxy ligado).

## 8. Verificar

```bash
docker logs scorexl-backend 2>&1 | grep -E "Started|\[feed\]|ERROR"
curl -s https://api.scorexl.com/picks/api/v1/summary
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://api.scorexl.com/user/api/v1/push/notify   # 401
curl -s -o /dev/null -w "%{http_code}\n" https://scorexl.com/                                     # 200
```

Base nova: no arranque o backend importa o histórico todo do feed (sem push dos dias antigos).

## Atalho SSH (no teu PC)

```bash
nano ~/.ssh/config
```

```
Host scorexl
    HostName 188.166.60.166
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```
