#!/usr/bin/env bash
set -e

# Installs Docker + nginx if missing, then symlinks every nginx/*.conf file
# into /etc/nginx/sites-available (and sites-enabled) under ITS OWN filename.
#
# This deliberately never writes to /etc/nginx/sites-available/default —
# that's the exact bug this repo fixes: the old scorexl-football-infra and
# scorexl-web-infra repos both bootstrapped to .../sites-available/default,
# so whichever one was (re-)bootstrapped last silently clobbered the other's
# site. Every conf here gets a distinct, collision-free filename instead.

echo "Installing dependencies..."
sudo apt update
sudo apt install -y docker.io docker-compose-plugin nginx

echo "Configuring Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Configuring NGINX..."

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_SRC_DIR="$REPO_DIR/nginx"

for conf in "$NGINX_SRC_DIR"/*.conf; do
  name="$(basename "$conf")"
  dest="/etc/nginx/sites-available/$name"

  echo "  -> $name"
  sudo cp "$conf" "$dest"
  sudo chmod 644 "$dest"
  sudo ln -sf "$dest" "/etc/nginx/sites-enabled/$name"
done

echo "Testing NGINX configuration..."
sudo nginx -t

echo "Reloading NGINX..."
sudo systemctl reload nginx

echo "Bootstrap complete."
