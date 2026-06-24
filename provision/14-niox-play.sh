#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "▶ Setting up NioxPlay Frontend (Vue/Vite)..."

FRONTEND_DIR="/var/www/nioxplay/frontend"
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
# 0. Fetch Frontend codebase
# -------------------------
if [ "$APP_SOURCE_TYPE" = "git" ]; then
  echo "▶ Cloning Frontend from Git..."
  rm -rf "$FRONTEND_DIR"
  CLONE_URL=$(get_git_clone_url "$FRONTEND_SOURCE_VALUE" "$GITHUB_PAT")
  GIT_TERMINAL_PROMPT=0 git clone "$CLONE_URL" "$FRONTEND_DIR"

elif [ "$APP_SOURCE_TYPE" = "local" ]; then
  if [ -z "$FRONTEND_SOURCE_VALUE" ] || [ ! -d "$FRONTEND_SOURCE_VALUE" ]; then
    echo "❌ Local Frontend source directory not found: $FRONTEND_SOURCE_VALUE"
    exit 1
  fi
  echo "▶ Copying Frontend from local path..."
  rsync -a --delete "$FRONTEND_SOURCE_VALUE/" "$FRONTEND_DIR/"

else
  # USB Mode
  echo "▶ Scanning USB for Frontend zip/folder..."
  USB_BASE="/media"
  USB_FRONT_PATH=""
  for d in $USB_BASE/*; do
    if [ -d "$d/$FRONTEND_SOURCE_VALUE" ] || [ -f "$d/${FRONTEND_SOURCE_VALUE}.zip" ]; then
      USB_FRONT_PATH="$d"
      break
    fi
  done

  if [ -z "$USB_FRONT_PATH" ]; then
    echo "❌ Frontend files not found on USB (Expected folder '$FRONTEND_SOURCE_VALUE' or zip '${FRONTEND_SOURCE_VALUE}.zip')"
    exit 1
  fi

  if [ -d "$USB_FRONT_PATH/$FRONTEND_SOURCE_VALUE" ]; then
    rsync -a --delete "$USB_FRONT_PATH/$FRONTEND_SOURCE_VALUE/" "$FRONTEND_DIR/"
  else
    rm -rf "$FRONTEND_DIR"
    mkdir -p "$FRONTEND_DIR"
    unzip "$USB_FRONT_PATH/${FRONTEND_SOURCE_VALUE}.zip" -d "$FRONTEND_DIR"
  fi
fi

cd "$FRONTEND_DIR"

# -------------------------
# 1. Install Node modules
# -------------------------
if [ ! -d "node_modules" ]; then
  echo "▶ Installing Node modules..."
  npm install --no-audit --no-fund --loglevel=error
fi

# -------------------------
# 2. Configure Dynamic API Endpoints
# -------------------------
echo "▶ Configuring frontend environment variables..."
echo "VITE_API_BASE_URL=http://api.${SITE_DOMAIN}/api/v1" > .env

# Resilient inline patching to support repositories that don't have dynamic endpoint code yet
if [ -f "src/store/api.js" ]; then
  perl -pi -e "s|'https://nioxplay.nioxon.cloud/api/v1'|import.meta.env.VITE_API_BASE_URL \|\| 'https://nioxplay.nioxon.cloud/api/v1'|g" src/store/api.js
fi
if [ -f "src/pages/movies/MovieLists.vue" ]; then
  perl -pi -e "s|'https://nioxplay.nioxon.cloud'|(import.meta.env.VITE_API_BASE_URL \|\| 'https://nioxplay.nioxon.cloud').replace\(\/\\\\\/api\\\\\/v1\\\\\/\?\\\$\/, ''\)|g" src/pages/movies/MovieLists.vue
fi

# -------------------------
# 3. Build Frontend
# -------------------------
echo "▶ Compiling frontend static assets (Vite)..."
npm run build

# -------------------------
# 3. Nginx Site Config (Serves main SITE_DOMAIN)
# -------------------------
echo "▶ Configuring Nginx Site for Frontend..."
NGINX_FRONTEND_CONFIG="/etc/nginx/sites-available/niox-play"
cat > "$NGINX_FRONTEND_CONFIG" <<EOF
server {
    listen 80;
    server_name ${SITE_DOMAIN};
    root ${FRONTEND_DIR}/dist;

    index index.html;
    charset utf-8;

    location / {
        # Fallback to index.html for Single Page Application (SPA) routing
        try_files \$uri \$uri/ /index.html;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

ln -sf "$NGINX_FRONTEND_CONFIG" /etc/nginx/sites-enabled/niox-play
nginx -t
systemctl reload nginx

# -------------------------
# 4. Permissions
# -------------------------
chown -R www-data:www-data "$FRONTEND_DIR"

echo "✔ NioxPlay Frontend setup completed successfully"
