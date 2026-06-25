#!/usr/bin/env bash
set -e

echo "📦 Installing and hardening MySQL Server..."

export DEBIAN_FRONTEND=noninteractive
apt-get install -y mysql-server

systemctl enable --now mysql

# Ubuntu configures MySQL root with socket authentication. Keep it that way so
# root-run provisioning scripts can administer MySQL without storing a root
# password. Never assign an empty password: validate_password rejects it.
mysql --protocol=socket --user=root <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
DROP USER IF EXISTS ''@'localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db = 'test' OR Db LIKE 'test\_%';
FLUSH PRIVILEGES;
SQL

echo "✔ MySQL installation complete."
