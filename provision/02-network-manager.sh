#!/usr/bin/env bash
set -e

echo "🔌 Installing and enabling NetworkManager..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends network-manager
systemctl enable --now NetworkManager
