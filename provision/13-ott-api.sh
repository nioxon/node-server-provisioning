#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "▶ Setting up NioxPlay OTT API (Laravel Backend)..."

API_DIR="/var/www/nioxplay/api"
mkdir -p /var/www/nioxplay

# Helper to format private git clone URL with GitHub Token if provided
get_git_clone_url() {
  local raw_url="$1"
  local token="$2"
  if [ -n "$token" ]; then
    local clean_url="${raw_url#https://}"
    echo "https://${token}@${clean_url}"
  else
    echo "$raw_url"
  fi
}

# -------------------------
# 0. Fetch API codebase
# -------------------------
if [ "$APP_SOURCE_TYPE" = "git" ]; then
  echo "▶ Cloning API from Git..."
  rm -rf "$API_DIR"
  CLONE_URL=$(get_git_clone_url "$API_SOURCE_VALUE" "$GITHUB_PAT")
  git clone "$CLONE_URL" "$API_DIR"

elif [ "$APP_SOURCE_TYPE" = "local" ]; then
  if [ -z "$API_SOURCE_VALUE" ] || [ ! -d "$API_SOURCE_VALUE" ]; then
    echo "❌ Local API source directory not found: $API_SOURCE_VALUE"
    exit 1
  fi
  echo "▶ Copying API from local path..."
  rsync -a --delete "$API_SOURCE_VALUE/" "$API_DIR/"

else
  # USB Mode
  echo "▶ Scanning USB for API zip/folder..."
  USB_BASE="/media"
  USB_API_PATH=""
  for d in $USB_BASE/*; do
    if [ -d "$d/$API_SOURCE_VALUE" ] || [ -f "$d/${API_SOURCE_VALUE}.zip" ]; then
      USB_API_PATH="$d"
      break
    fi
  done

  if [ -z "$USB_API_PATH" ]; then
    echo "❌ API files not found on USB (Expected folder '$API_SOURCE_VALUE' or zip '${API_SOURCE_VALUE}.zip')"
    exit 1
  fi

  if [ -d "$USB_API_PATH/$API_SOURCE_VALUE" ]; then
    rsync -a --delete "$USB_API_PATH/$API_SOURCE_VALUE/" "$API_DIR/"
  else
    rm -rf "$API_DIR"
    mkdir -p "$API_DIR"
    unzip "$USB_API_PATH/${API_SOURCE_VALUE}.zip" -d "$API_DIR"
  fi
fi

cd "$API_DIR"

# -------------------------
# 1. ENV Setup
# -------------------------
[ ! -f .env ] && cp .env.example .env

# Generate secure DB credentials
DB_PASS_FILE="/opt/nioxon/config/db.pass"
if [ ! -f "$DB_PASS_FILE" ]; then
  DB_USER_PASS=$(openssl rand -hex 16)
  echo "$DB_USER_PASS" > "$DB_PASS_FILE"
  chmod 600 "$DB_PASS_FILE"
else
  DB_USER_PASS=$(cat "$DB_PASS_FILE")
fi

DB_NAME="nioxplay"
DB_USER="nioxplay"

perl -pi -e "s|^APP_NAME=.*|APP_NAME=NioxPlay-API|" .env
perl -pi -e "s|^APP_ENV=.*|APP_ENV=local|" .env
perl -pi -e "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
perl -pi -e "s|^APP_URL=.*|APP_URL=http://api.$SITE_DOMAIN|" .env

perl -pi -e "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" .env
perl -pi -e "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
perl -pi -e "s|^DB_PORT=.*|DB_PORT=3306|" .env
perl -pi -e "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
perl -pi -e "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
perl -pi -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_USER_PASS|" .env

# -------------------------
# 2. Composer dependencies
# -------------------------
if [ ! -d "vendor" ]; then
  echo "▶ Installing Composer dependencies..."
  composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# -------------------------
# 3. App Key Generation
# -------------------------
php artisan key:generate --force

# -------------------------
# 4. Storage & Permissions
# -------------------------
chown -R www-data:www-data "$API_DIR"
chmod -R 775 storage bootstrap/cache

# -------------------------
# 5. Database Setup
# -------------------------
echo "▶ Creating dedicated MySQL user and privileges..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Verify connection
php artisan migrate:status >/dev/null 2>&1 || {
  echo "❌ Database connection failed for user '$DB_USER'"
  exit 1
}

# -------------------------
# 6. Database Migrations
# -------------------------
if [ -f database/init.sql ]; then
  echo "▶ Importing database schema from SQL..."
  mysql -u"$DB_USER" -p"$DB_USER_PASS" "$DB_NAME" < database/init.sql
else
  php artisan migrate --force
  php artisan db:seed --force 2>/dev/null || true
fi

# -------------------------
# 7. Caching & Optimization
# -------------------------
php artisan config:clear
php artisan config:cache
php artisan route:cache || true

# -------------------------
# 8. Nginx Site Config (Resolves api.* and ott-api.test)
# -------------------------
echo "▶ Configuring Nginx Site for API..."
NGINX_API_CONFIG="/etc/nginx/sites-available/ott-api"
cat > "$NGINX_API_CONFIG" <<EOF
server {
    listen 80;
    server_name api.${SITE_DOMAIN} ott-api.test;
    root ${API_DIR}/public;

    index index.php index.html;
    charset utf-8;

    # Support high file size uploads for video files
    client_max_body_size 10G;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 600;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

ln -sf "$NGINX_API_CONFIG" /etc/nginx/sites-enabled/ott-api
nginx -t
systemctl reload nginx

# -------------------------
# 9. Supervisor worker setup
# -------------------------
echo "▶ Configuring Supervisor background worker for API..."
SUPERVISOR_CONF="/etc/supervisor/conf.d/ott-api-worker.conf"
cat > "$SUPERVISOR_CONF" <<EOF
[program:ott-api-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${API_DIR}/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=/var/log/ott-api-worker.log
stopwaitsecs=3600
EOF

supervisorctl reread
supervisorctl update
supervisorctl start ott-api-worker:* || true

echo "✔ NioxPlay OTT API setup completed successfully"
