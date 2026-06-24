#!/usr/bin/env bash
set -e

echo "🚀 Installing NIOXON CLI"

# Update package index and install basic toolsets
apt-get update -y
apt-get install -y git curl ca-certificates rsync unzip

# Detect if running from a local development folder containing the files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/bin/nioxon" ] && [ -d "$SCRIPT_DIR/provision" ]; then
  echo "📦 Local files detected at $SCRIPT_DIR"
  echo "   Syncing local files to /opt/nioxon..."
  mkdir -p /opt/nioxon
  rsync -a --delete \
    --exclude='.git' \
    --exclude='.idea' \
    --exclude='provision-clean' \
    "$SCRIPT_DIR/" /opt/nioxon/
else
  # Production remote deployment mode
  if [ -d /opt/nioxon/.git ]; then
    current_remote=$(cd /opt/nioxon && git config --get remote.origin.url || echo "")
    if [[ "$current_remote" != *"node-server-provisioning"* ]]; then
      echo "🔄 Stale repository remote detected ($current_remote). Re-cloning..."
      rm -rf /opt/nioxon
    fi
  fi

  if [ ! -d /opt/nioxon/.git ]; then
    rm -rf /opt/nioxon
    git clone https://github.com/nioxon/node-server-provisioning.git /opt/nioxon
  else
    cd /opt/nioxon
    git fetch --all
    git reset --hard origin/main
  fi
fi

# Ensure CLI binary exists
if [ ! -f /opt/nioxon/bin/nioxon ]; then
  echo "❌ bin/nioxon missing in repository structure"
  exit 1
fi

chmod +x /opt/nioxon/bin/nioxon

# Global launcher (PATH-safe launcher in /usr/local/bin)
cat > /usr/local/bin/nioxon <<'EOF'
#!/usr/bin/env bash
exec /opt/nioxon/bin/nioxon "$@"
EOF
chmod +x /usr/local/bin/nioxon

echo "✔ NIOXON CLI successfully installed!"
echo "👉 Run: sudo nioxon setup"
