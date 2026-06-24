#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "🔐 Generating self-signed SSL certificate..."

if [ -z "$SITE_DOMAIN" ]; then
  echo "❌ SITE_DOMAIN is not set in runtime.env. Cannot generate SSL certificate."
  exit 1
fi

SSL_DIR="/etc/nginx/ssl"
CA_KEY="$SSL_DIR/NioxonCA.key"
CA_CERT="$SSL_DIR/NioxonCA.pem"

mkdir -p "$SSL_DIR"

# --- Generate Local Certificate Authority (CA) ---
if [ ! -f "$CA_CERT" ]; then
  echo "▶ Creating new local Certificate Authority..."
  # Generate CA private key
  openssl genrsa -out "$CA_KEY" 2048
  # Generate CA root certificate
  openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
    -out "$CA_CERT" \
    -subj "/C=US/ST=Local/L=Local/O=Nioxon/CN=Nioxon Local CA"
  chmod 600 "$CA_KEY"
  
  # --- Trust the CA on the server ---
  echo "▶ Installing CA certificate into system trust store..."
  cp "$CA_CERT" /usr/local/share/ca-certificates/NioxonCA.crt
  update-ca-certificates
else
  echo "✔ Local Certificate Authority already exists. Skipping generation."
fi

# --- Generate Wildcard Certificate for *.${SITE_DOMAIN} ---
WILDCARD_KEY="$SSL_DIR/wildcard.${SITE_DOMAIN}.key"
WILDCARD_CERT="$SSL_DIR/wildcard.${SITE_DOMAIN}.crt"
WILDCARD_CSR="$SSL_DIR/wildcard.${SITE_DOMAIN}.csr"
WILDCARD_EXT_CONF="$SSL_DIR/wildcard_ext.cnf"

if [ ! -f "$WILDCARD_CERT" ]; then
  echo "▶ Generating CA-signed wildcard certificate for *.${SITE_DOMAIN}..."

  # Generate private key
  openssl genrsa -out "$WILDCARD_KEY" 2048

  # Create a temporary config file for Subject Alternative Name (SAN)
  cat > "$WILDCARD_EXT_CONF" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${SITE_DOMAIN}
DNS.2 = *.${SITE_DOMAIN}
EOF

  # Create Certificate Signing Request (CSR) and the final certificate in one step
  openssl req -new -key "$WILDCARD_KEY" \
    -subj "/C=US/ST=Local/L=Local/O=Nioxon/CN=*.${SITE_DOMAIN}" | \
    openssl x509 -req -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$WILDCARD_CERT" -days 3650 -sha256 -extfile "$WILDCARD_EXT_CONF"

  chmod 600 "$WILDCARD_KEY"
  rm "$WILDCARD_EXT_CONF" # Clean up temp config
else
  echo "✔ Wildcard certificate for *.${SITE_DOMAIN} already exists."
fi

echo "✔ SSL setup complete."