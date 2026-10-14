#!/usr/bin/env bash
set -euo pipefail

# One-time setup of a fresh DigitalOcean droplet (Ubuntu 24.04, 4 GB) for the
# single-backend stack. Runs as root (via sudo), from your machine:
#
#   scp scripts/provision-droplet.sh scorexl:/tmp/
#   ssh -t scorexl 'sudo bash /tmp/provision-droplet.sh'
#
# (first run on a fresh droplet, before root login is disabled:
#   ssh root@<new-ip> 'bash -s' < scripts/provision-droplet.sh)
#
# Idempotent: safe to run again. Installs Docker (Docker's own apt repo), nginx,
# ufw (22 + 80 only), fail2ban, unattended security upgrades, Docker log rotation
# and a 2 GB swapfile, and creates /opt/scorexl-infra for the repo checkout.
#
# Every container port is published on 127.0.0.1 only (docker-compose.yml) — Docker
# writes its own iptables rules and would bypass ufw for anything bound to 0.0.0.0.

export DEBIAN_FRONTEND=noninteractive

echo ">> packages"
apt-get update -q
apt-get upgrade -yq
apt-get install -yq ca-certificates curl git gnupg ufw nginx fail2ban unattended-upgrades rsync

echo ">> docker (official repo)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# bounded container logs: the old droplet's json logs grew without limit
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" }
}
JSON
  systemctl restart docker
fi
systemctl enable --now docker

echo ">> swap (2G)"
if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -q vm.swappiness=10
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
fi

echo ">> firewall (ssh + http)"
ufw allow OpenSSH >/dev/null
ufw allow 'Nginx HTTP' >/dev/null
ufw --force enable >/dev/null
ufw status | head -8

echo ">> unattended security upgrades + fail2ban"
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now fail2ban

# nginx's stock default site would answer for any unknown Host header
rm -f /etc/nginx/sites-enabled/default
systemctl enable --now nginx

mkdir -p /opt/scorexl-infra/backups

echo
echo "Provisioned. Docker $(docker --version | awk '{print $3}' | tr -d ,), $(docker compose version --short) compose, $(nginx -v 2>&1 | cut -d/ -f2) nginx."
echo "Next: copy the infra repo + .env to /opt/scorexl-infra (README: \"New droplet\")."
