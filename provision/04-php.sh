#!/usr/bin/env bash
  set -e

  echo "🐘 Installing PHP 8.3 and required extensions..."

  # Add Ondrej Sury PHP repository if running on Ubuntu/Debian
  if [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
    if ! command -v add-apt-repository >/dev/null; then
      apt-get install -y software-properties-common
    fi
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
  fi

  # Install PHP 8.3 and extensions
  apt-get install -y php8.3 php8.3-fpm php8.3-cli php8.3-mysql php8.3-curl php8.3-mbstring php8.3-xml php8.3-zip php8.3-sqlite3 php8.3-bcmath php8.3-gd php8.3-redis

  # Install Composer globally
  if ! command -v composer >/dev/null; then
    echo "📦 Installing Composer..."
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
  fi

  # Configure PHP FPM and CLI upload limits for video streaming (10GB max)
  echo "⚙️ Tuning PHP-FPM and PHP-CLI limits for video uploads..."
  
  for ini in /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini; do
    if [ -f "$ini" ]; then
      perl -pi -e "s|^upload_max_filesize =.*|upload_max_filesize = 10G|" "$ini"
      perl -pi -e "s|^post_max_size =.*|post_max_size = 10G|" "$ini"
      perl -pi -e "s|^memory_limit =.*|memory_limit = 512M|" "$ini"
      perl -pi -e "s|^max_execution_time =.*|max_execution_time = 600|" "$ini"
    fi
  done

  # Enable and restart php8.3-fpm
  systemctl enable php8.3-fpm
  systemctl restart php8.3-fpm

  echo "✔ PHP 8.3 installation complete"
