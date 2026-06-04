#!/usr/bin/env bash
set -e

source /opt/nioxon/config/runtime.env

echo "🔒 Configuring UFW security firewall..."

# Install UFW
apt-get install -y ufw

# Set default policies (Deny incoming, Allow outgoing)
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow SSH (Port 22)
ufw allow 22/tcp

# Allow HTTP (Port 80) and HTTPS (Port 443)
ufw allow 80/tcp
ufw allow 443/tcp

# Allow DNS (Port 53) on LAN interface
if [ -n "$LAN_IFACE" ]; then
  ufw allow in on "$LAN_IFACE" to any port 53 proto udp
  ufw allow in on "$LAN_IFACE" to any port 53 proto tcp
  
  # Allow DHCP (Ports 67 & 68) on LAN interface if enabled
  if [ "$ENABLE_DHCP" = "true" ]; then
    ufw allow in on "$LAN_IFACE" to any port 67 proto udp
    ufw allow in on "$LAN_IFACE" to any port 68 proto udp
  fi
fi

# Enable UFW
ufw --force enable

echo "✔ Security firewall configured successfully"
