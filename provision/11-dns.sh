#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "🌐 Configuring DNS and DHCP services..."

apt-get install -y dnsmasq

# Write dnsmasq base configuration
cat > /etc/dnsmasq.d/nioxon.conf <<EOF
interface=${LAN_IFACE}
bind-interfaces
listen-address=${LAN_IP}

domain-needed
bogus-priv

# Upstream servers (optional fallbacks)
server=8.8.8.8
server=1.1.1.1

# Resolve all hostnames to LAN IP (Captive DNS)
address=/#/${LAN_IP}
EOF

# Configure DHCP if enabled
if [ "$ENABLE_DHCP" = "true" ]; then
  echo "📶 Enabling DHCP Server..."
  IP_PREFIX=$(echo "$LAN_IP" | cut -d. -f1-3)
  DHCP_RANGE_START="${IP_PREFIX}.50"
  DHCP_RANGE_END="${IP_PREFIX}.150"
  
  cat >> /etc/dnsmasq.d/nioxon.conf <<EOF
# DHCP server settings
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},12h
dhcp-option=option:router,${LAN_IP}
dhcp-option=option:dns-server,${LAN_IP}
EOF
fi

# Restart and enable service
systemctl restart dnsmasq
systemctl enable dnsmasq

echo "✔ DNS/DHCP configured successfully"
