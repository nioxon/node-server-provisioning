#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

# -------------------------
# Validate required values
# -------------------------
if [ -z "$LAN_IFACE" ] || [ -z "$LAN_IP" ] || [ -z "$LAN_NETMASK" ]; then
  echo "❌ LAN configuration missing in runtime.env"
  echo "   LAN_IFACE=$LAN_IFACE"
  echo "   LAN_IP=$LAN_IP"
  echo "   LAN_NETMASK=$LAN_NETMASK"
  exit 1
fi

NETPLAN_FILE="/etc/netplan/50-nioxon-lan.yaml"

# -------------------------
# Write netplan safely (using NetworkManager renderer)
# -------------------------
cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ${LAN_IFACE}:
      dhcp4: false
      addresses:
        - ${LAN_IP}/${LAN_NETMASK}
EOF

# -------------------------
# Fix permissions (CRITICAL)
# -------------------------
chmod 600 "$NETPLAN_FILE"
chown root:root "$NETPLAN_FILE"

# -------------------------
# Apply netplan
# -------------------------
netplan generate
netplan apply
