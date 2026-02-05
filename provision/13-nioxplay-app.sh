#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "▶ Setting up NioxPlay Laravel App (USB mode)"

APP_DIR="/var/www/nioxplay/current"
USB_BASE="/media"
USB_APP_PATH=""

DB_NAME="nioxplay"
DB_USER="root"
DB_PASS=""

# -------------------------
# 0. Detect USB automatically
# -------------------------
for d in $USB_BASE/*; do
  if [ -d "$d/nioxplay" ] || [ -f "$d/nioxplay.zip" ]; then
    USB_APP_PATH="$d"
    break
  fi
done

if [ -z "$USB_APP_PATH" ]; then
  echo "❌ NioxPlay app not found on USB"
  echo "Expected:"
  echo "  /media/USB_NAME/nioxplay/"
  echo "  or /media/USB_NAME/nioxplay.zip"
  exit 1
fi

echo "✔ USB detected at $USB_APP_PATH"

# -------------------------
# 1. Copy app from USB
# -------------------------
mkdir -p /var/www/nioxplay

if [ -d "$USB_APP_PATH/nioxplay" ]; then
  echo "▶ Copying Laravel app directory"
  rsync -a --delete "$USB_APP_PATH/nioxplay/" "$APP_DIR/"
elif [ -f "$USB_APP_PATH/nioxplay.zip" ]; then
  echo "▶ Extracting Laravel app zip"
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR"
  unzip "$USB_APP_PATH/nioxplay.zip" -d "$APP_DIR"
fi

cd "$APP_DIR"

# -------------------------
# 2. ENV setup
# -------------------------
[ ! -f .env ] && cp .env.example .env

sed -i "s|^APP_NAME=.*|APP_NAME=NioxPlay|" .env
sed -i "s|^APP_ENV=.*|APP_ENV=local|" .env
sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
sed -i "s|^APP_URL=.*|APP_URL=http://$SITE_DOMAIN|" .env

sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" .env
sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env

grep -q APP_MODE .env || echo "APP_MODE=local" >> .env

# -------------------------
# 3. App key
# -------------------------
php artisan key:generate --force

# -------------------------
# 4. Storage & permissions
# -------------------------
chown -R www-data:www-data /var/www/nioxplay
chmod -R 775 storage bootstrap/cache

# -------------------------
# 5. Database setup
# -------------------------
mysql -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

php artisan migrate:status >/dev/null 2>&1 || {
  echo "❌ Database connection failed"
  exit 1
}

# -------------------------
# 6. Migrate / Seed / SQL
# -------------------------
if [ -f database/init.sql ]; then
  echo "▶ Importing SQL"
  mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < database/init.sql
else
  php artisan migrate --force
  php artisan db:seed --force 2>/dev/null || true
fi

# -------------------------
# 7. Optimize
# -------------------------
php artisan config:clear
php artisan config:cache
php artisan route:cache || true

# -------------------------
# 8. PM2
# -------------------------
pm2 delete nioxplay-worker 2>/dev/null || true

pm2 start "php artisan queue:work --sleep=3 --tries=3" \
  --name nioxplay-worker

pm2 save

echo "✔ NioxPlay app setup completed (USB)"
