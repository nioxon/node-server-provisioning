#!/usr/bin/env bash
set -e

source /opt/nioxon/config/runtime.env

echo "🔒 Configuring SSH access and UFW firewall..."

export DEBIAN_FRONTEND=noninteractive
apt-get install -y ufw openssh-server

# Enable SSH password login for the installer-created administrator account.
# Root login remains disabled; SSH keys continue to work as well.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-nioxon-password-auth.conf <<'EOF'
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
UsePAM yes
EOF

sshd -t
systemctl enable --now ssh

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

echo "✔ SSH access and firewall configured successfully"
