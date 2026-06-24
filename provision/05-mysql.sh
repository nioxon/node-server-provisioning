#!/usr/bin/env bash
set -e

echo "📦 Installing and hardening MySQL Server..."

apt install -y mysql-server

# Run mysql_secure_installation non-interactively
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';"
mysql_secure_installation --use-default

systemctl enable mysql
systemctl start mysql

echo "✔ MySQL installation complete."
