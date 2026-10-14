# Setup de produção

Servidor `209.38.194.84` · utilizador `fmacuacua` · projeto em `/home/fmacuacua/scorexl`.

Estado (2026-10-14): 1 ✅ 2 ✅ 3 ⚠️ 4 ✅ 5 ✅ 7 ✅ — próximo: **3**, **6**, **8**.

## 1. Criar o droplet ✅

Painel DigitalOcean: Ubuntu 24.04 · 4 GB / 2 vCPU · chave `id_rsa_do` · backups ligados.

## 2. Provisionar ✅

```bash
scp scripts/provision-droplet.sh scorexl:/tmp/
ssh -t scorexl 'sudo bash /tmp/provision-droplet.sh'
rsync -a --exclude .env --exclude backups --exclude .git ./ scorexl:~/scorexl/
```

## 3. Redimensionar ⚠️ (está com 2 GB)

Painel: Power off → Resize → 4 GB / 2 vCPU, "CPU and RAM + disk" → Power on.

## 4. Utilizador ✅

```bash
ssh -i ~/.ssh/id_rsa_do root@209.38.194.84
timedatectl set-timezone Africa/Maputo
adduser fmacuacua
usermod -aG sudo,docker fmacuacua
rsync --archive --chown=fmacuacua:fmacuacua ~/.ssh /home/fmacuacua
```

## 5. SSH ✅

```bash
sudo nano /etc/ssh/sshd_config      # PermitRootLogin no · PasswordAuthentication no
sudo systemctl restart ssh
```

## 6. Cloud Firewall

Painel: Networking → Firewalls → Create · portas 22 e 80 · associar a `209.38.194.84`.

## 7. `.env` ✅

Já criado. Para editar:

```bash
ssh scorexl
nano ~/scorexl/.env
```

## 8. Imagens e nginx

```bash
ssh -t scorexl
cd ~/scorexl
grep ^GH_PACKAGES_TOKEN= .env | cut -d= -f2- | docker login ghcr.io -u devmacuacua --password-stdin
docker compose pull
sudo ./scripts/bootstrap.sh
```

## 9. Arrancar

```bash
ssh scorexl 'cd ~/scorexl && ./scripts/deploy.sh'
```

## 10. Verificar

```bash
docker compose ps
curl -s -H 'Host: basketball-api.scorexl.com' http://127.0.0.1/api/v1/plan
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: scorexl.com' http://127.0.0.1/
```

## 11. DNS

Cloudflare: registos A `@`, `www`, `api`, `analytics` e todos os `*-api` → `209.38.194.84` (proxy ligado).

```bash
curl -I https://scorexl.com
```

## 12. Planos

```bash
curl -X PUT https://basketball-api.scorexl.com/api/v1/plan -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" -d '{"plan":"PAID"}'
```

## Atalho SSH

No teu PC, em `~/.ssh/config`:

```
Host scorexl
    HostName 209.38.194.84
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```
