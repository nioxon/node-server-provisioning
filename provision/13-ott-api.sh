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
    echo "https://x-access-token:${token}@${clean_url}"
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
  GIT_TERMINAL_PROMPT=0 git clone "$CLONE_URL" "$API_DIR"

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
DB_USER_PASS="Nioxplay@2190!"

DB_NAME="nioxplay"
DB_USER="nioxplay"

perl -pi -e "s|^APP_NAME=.*|APP_NAME=NioxPlay-API|" .env
perl -pi -e "s|^APP_ENV=.*|APP_ENV=local|" .env
perl -pi -e "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
perl -pi -e "s|^APP_URL=.*|APP_URL=https://api.$SITE_DOMAIN|" .env

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
# 3. Storage & Permissions (Ensure www-data ownership before running commands)
# -------------------------
chown -R www-data:www-data "$API_DIR"
chmod -R 775 storage bootstrap/cache

# Determine runner command (support mock macOS environments)
if id "www-data" &>/dev/null; then
  ARTISAN="sudo -u www-data php"
else
  ARTISAN="php"
fi

# Clear any pre-existing cached config so artisan reads fresh .env values
$ARTISAN artisan config:clear 2>/dev/null || true
$ARTISAN artisan cache:clear 2>/dev/null || true
$ARTISAN artisan view:clear 2>/dev/null || true

# -------------------------
# 4. App Key Generation
# -------------------------
$ARTISAN artisan key:generate --force

# -------------------------
# 5. Database Setup
# -------------------------
echo "▶ Creating dedicated MySQL user and privileges..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
mysql -u root -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_USER_PASS';"
mysql -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Verify MySQL user connection directly (not via artisan, to avoid config cache issues)
echo "▶ Verifying MySQL user connection..."
if ! mysql -u"${DB_USER}" -p"${DB_USER_PASS}" -h 127.0.0.1 -P 3306 "${DB_NAME}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "❌ Direct MySQL connection test failed for user '${DB_USER}' on 127.0.0.1:3306"
  echo "   Database: ${DB_NAME}"
  echo "   Check MySQL status: systemctl status mysql"
  echo "   Try manually: mysql -u${DB_USER} -p -h 127.0.0.1 ${DB_NAME}"
  exit 1
fi
echo "✔ MySQL connection verified"

# Reload fresh config now that DB user exists and credentials are confirmed
$ARTISAN artisan config:clear 2>/dev/null || true
$ARTISAN artisan cache:clear 2>/dev/null || true

# -------------------------
# 6. Database Migrations
# -------------------------
if [ -f database/init.sql ]; then
  echo "▶ Importing database schema from SQL..."
  mysql -u"$DB_USER" -p"$DB_USER_PASS" "$DB_NAME" < database/init.sql
  $ARTISAN artisan migrate --force
else
  $ARTISAN artisan migrate --force
  $ARTISAN artisan db:seed --force 2>/dev/null || true
fi

# -------------------------
# 7. Caching & Optimization
# -------------------------
$ARTISAN artisan config:clear
$ARTISAN artisan config:cache
$ARTISAN artisan route:cache || true

# -------------------------
# 8. Nginx Site Config (Resolves api.* and ott-api.test)
# -------------------------
echo "▶ Configuring Nginx Site for API..."
NGINX_API_CONFIG="/etc/nginx/sites-available/ott-api"
cat > "$NGINX_API_CONFIG" <<EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name api.${SITE_DOMAIN} ott-api.test;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.${SITE_DOMAIN} ott-api.test;
    root ${API_DIR}/public;

    index index.php index.html;
    charset utf-8;

    # Support high file size uploads for video files
    client_max_body_size 10G;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/wildcard.${SITE_DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.${SITE_DOMAIN}.key;

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

echo "▶ Configuring Supervisor for API health monitor..."
SUPERVISOR_HEALTH_CONF="/etc/supervisor/conf.d/api-health-monitor.conf"
cat > "$SUPERVISOR_HEALTH_CONF" <<EOF
[program:api-health-monitor]
command=/opt/nioxon/monitoring/check_api_health.sh
autostart=true
autorestart=true
user=root
redirect_stderr=true
stdout_logfile=/dev/null
EOF

supervisorctl reread
supervisorctl update
supervisorctl start api-health-monitor:* || true

echo "✔ NioxPlay OTT API setup completed successfully"
