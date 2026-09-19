#!/usr/bin/env bash
set -e

echo "🚀 Configuring In-Bus High-Throughput Local HLS CDN & Zero-Buffering Kernel..."

# 1. Install FFmpeg for video HLS chunking & packaging
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends ffmpeg

# 2. Setup Local NVMe Storage Paths for Zero-Buffering HLS Video Chunks
MEDIA_BASE="/opt/nioxon/media"
mkdir -p "$MEDIA_BASE/hls/movies"
mkdir -p "$MEDIA_BASE/hls/shows"
mkdir -p "$MEDIA_BASE/hls/masala"
mkdir -p "$MEDIA_BASE/hls/ads"
mkdir -p "$MEDIA_BASE/hls/creators"

# Ensure web server ownership
chown -R www-data:www-data "$MEDIA_BASE"
chmod -R 775 "$MEDIA_BASE"

# 3. Kernel System Tuning (sysctl) for High Concurrent Passenger WiFi Streaming
SYSCTL_CONF="/etc/sysctl.d/99-nioxon-cdn.conf"
cat > "$SYSCTL_CONF" <<'EOF'
# NIOXON In-Bus Local CDN Kernel Optimizations
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
EOF

# Apply sysctl settings (suppress error if running inside container)
sysctl -p "$SYSCTL_CONF" 2>/dev/null || true

# 4. Enhance Nginx Core Configuration for Zero-Copy AIO Streaming
NGINX_CONF="/etc/nginx/nginx.conf"
if [ -f "$NGINX_CONF" ]; then
  # Ensure worker_rlimit_nofile exists
  if ! grep -q "worker_rlimit_nofile" "$NGINX_CONF"; then
    sed -i '/worker_processes/a worker_rlimit_nofile 65535;' "$NGINX_CONF"
  fi
  # Ensure aio threads is enabled in http block if not present
  if ! grep -q "aio threads;" "$NGINX_CONF"; then
    sed -i '/http {/a \    aio threads;\n    directio 8m;\n    open_file_cache max=10000 inactive=1d;\n    open_file_cache_valid 5m;\n    open_file_cache_min_uses 1;' "$NGINX_CONF"
  fi
fi

nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

echo "✔ In-Bus Local CDN & Zero-Buffering engine configured successfully"
