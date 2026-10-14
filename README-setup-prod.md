# Setup de produção

Servidor novo `209.38.194.84` · antigo `188.166.116.252` · projeto em `/home/fmacuacua/scorexl`.

Estado (2026-10-14): 1 ✅ 2 ✅ 3 ⚠️ 4 ✅ 5 ✅ — próximo: **3**, **6**, **7**.

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

## 7. `.env`

```bash
scp -3 root@188.166.116.252:<pasta do infra>/.env scorexl:~/scorexl/.env
ssh scorexl "echo 'BACKEND_POSTGRES_PASSWORD=<senha nova>' >> ~/scorexl/.env"
```

## 8. Imagens e nginx

```bash
ssh -t scorexl
cd ~/scorexl
grep ^GH_PACKAGES_TOKEN= .env | cut -d= -f2- | docker login ghcr.io -u devmacuacua --password-stdin
docker compose pull
sudo ./scripts/bootstrap.sh
```

## 9. Dump no antigo ⚠️ começa o downtime

```bash
ssh root@188.166.116.252
cd <pasta do infra> && git fetch && git worktree add /opt/scorexl-migrate origin/single-backend
cd /opt/scorexl-migrate && ./scripts/migrate-to-single-backend.sh dump
```

## 10. Copiar o dump

```bash
scp -3 root@188.166.116.252:/opt/scorexl-migrate/backups/<ts>.tgz scorexl:~/scorexl/backups/
```

## 11. Restaurar e arrancar

```bash
ssh scorexl
cd ~/scorexl
tar -C backups -xzf backups/<ts>.tgz
./scripts/migrate-to-single-backend.sh restore backups/<ts>
./scripts/deploy.sh
```

## 12. Verificar

```bash
docker compose ps
curl -s -H 'Host: basketball-api.scorexl.com' http://127.0.0.1/api/v1/plan
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: scorexl.com' http://127.0.0.1/
```

## 13. DNS ✅ acaba o downtime

Cloudflare: todos os registos A de `188.166.116.252` → `209.38.194.84`.

```bash
curl -I https://scorexl.com
```

## 14. Planos

```bash
curl -X PUT https://basketball-api.scorexl.com/api/v1/plan -H "Authorization: Bearer $INTERNAL_API_KEY" -H "Content-Type: application/json" -d '{"plan":"PAID"}'
```

## Rollback

1. Cloudflare: registos A de volta para `188.166.116.252`.
2. `ssh root@188.166.116.252 'docker start <containers que o dump listou>'`

## Atalho SSH

No teu PC, em `~/.ssh/config`:

```
Host scorexl
    HostName 209.38.194.84
    User fmacuacua
    IdentityFile ~/.ssh/id_rsa_do
```
