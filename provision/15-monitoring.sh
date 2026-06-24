#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "🩺 Setting up API health monitoring..."

MONITOR_DIR="/opt/nioxon/monitoring"
HEALTH_CHECK_SCRIPT="$MONITOR_DIR/check_api_health.sh"
LOG_FILE="/var/log/api-health.log"

mkdir -p "$MONITOR_DIR"

# 1. Create the health check script
cat > "$HEALTH_CHECK_SCRIPT" <<EOF
#!/usr/bin/env bash
HEALTH_ENDPOINT="https://api.${SITE_DOMAIN}/api/v1/health"

while true; do
  TIMESTAMP=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  HTTP_STATUS=\$(curl --insecure --silent --output /dev/null --write-out "%{http_code}" "\$HEALTH_ENDPOINT")

  if [ "\$HTTP_STATUS" -eq 200 ]; then
    echo "[\$TIMESTAMP] STATUS: UP | CODE: \$HTTP_STATUS" >> "$LOG_FILE"
  else
    echo "[\$TIMESTAMP] STATUS: DOWN | CODE: \$HTTP_STATUS" >> "$LOG_FILE"
  fi
  
  sleep 60 # Check every 60 seconds
done
EOF

chmod +x "$HEALTH_CHECK_SCRIPT"
touch "$LOG_FILE"
chown www-data:www-data "$LOG_FILE"

echo "✔ API health monitoring script created."