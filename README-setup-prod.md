# Setup de produção

Servidor `209.38.194.84` · utilizador `fmacuacua` · projeto em `~/projects/scorexl-infra`.

## 1. Droplet ✅

Painel: Ubuntu 24.04 · 4 GB / 2 vCPU · chave `id_rsa_do` · backups ligados.
Networking → Firewalls: portas 22 e 80.

## 2. Utilizador ✅

```bash
ssh root@209.38.194.84
adduser fmacuacua && usermod -aG sudo fmacuacua
rsync -a --chown=fmacuacua:fmacuacua ~/.ssh /home/fmacuacua
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/; s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart ssh
```

## 3. Chave do GitHub

```bash
ssh scorexl
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub
```

GitHub → `scorexl-infra` → Settings → Deploy keys → Add (só leitura).

## 4. Clonar e provisionar

```bash
mkdir -p ~/projects && cd ~/projects
git clone git@github.com:devmacuacua/scorexl-infra.git
cd scorexl-infra && git checkout single-backend
sudo ./scripts/provision-droplet.sh && sudo usermod -aG docker fmacuacua
```

Sai e volta a entrar (grupo `docker`).

## 5. `.env`

```bash
cd ~/projects/scorexl-infra && cp .env.example .env && nano .env
```

## 6. Arrancar

```bash
cd ~/projects/scorexl-infra && ./scripts/deploy.sh
```

## 7. DNS

Cloudflare: `@`, `www`, `api`, `analytics` e todos os `*-api` → A `209.38.194.84` (proxy ligado).

## Atalho SSH (no teu PC, `~/.ssh/config`)

```
Host scorexl
    HostName 209.38.194.84
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```
