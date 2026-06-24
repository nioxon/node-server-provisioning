#!/usr/bin/env bash
set -e

echo "🌐 Installing and enabling Nginx web server..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends nginx
systemctl enable --now nginx
