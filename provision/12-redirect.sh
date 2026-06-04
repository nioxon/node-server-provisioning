#!/usr/bin/env bash
set -e
source /opt/nioxon/config/runtime.env

echo "🔌 Configuring captive portal HTTP redirection..."

mkdir -p /var/www/captive

# Write beautiful redirect HTML
cat > /var/www/captive/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Welcome to NioxPlay</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #0a051b;
      --card-bg: rgba(255, 255, 255, 0.03);
      --card-border: rgba(255, 255, 255, 0.08);
      --accent: linear-gradient(135deg, #7c3aed 0%, #d946ef 100%);
      --text: #f3f4f6;
      --text-muted: #9ca3af;
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
      position: relative;
    }
    /* Background Glows */
    body::before, body::after {
      content: '';
      position: absolute;
      width: 300px;
      height: 300px;
      border-radius: 50%;
      background: var(--accent);
      filter: blur(120px);
      opacity: 0.15;
      z-index: 1;
    }
    body::before { top: -10%; left: -10%; }
    body::after { bottom: -10%; right: -10%; }

    .container {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      padding: 3rem 2rem;
      border-radius: 24px;
      text-align: center;
      max-width: 440px;
      width: 90%;
      box-shadow: 0 20px 40px rgba(0,0,0,0.4);
      z-index: 2;
      animation: fadeIn 0.8s ease-out;
    }

    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .logo {
      font-size: 3.5rem;
      margin-bottom: 1.5rem;
      display: inline-block;
      animation: pulse 2s infinite ease-in-out;
    }

    @keyframes pulse {
      0%, 100% { transform: scale(1); }
      50% { transform: scale(1.05); }
    }

    h1 {
      font-size: 2rem;
      font-weight: 800;
      margin-bottom: 1rem;
      background: var(--accent);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      letter-spacing: -0.5px;
    }

    p {
      color: var(--text-muted);
      font-size: 1.1rem;
      line-height: 1.6;
      margin-bottom: 2.5rem;
    }

    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: var(--accent);
      color: #fff;
      text-decoration: none;
      font-weight: 600;
      font-size: 1.1rem;
      padding: 1rem 2.5rem;
      border-radius: 12px;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      box-shadow: 0 4px 15px rgba(124, 58, 237, 0.4);
      border: none;
      cursor: pointer;
      width: 100%;
    }

    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(124, 58, 237, 0.6);
      opacity: 0.95;
    }

    .btn:active {
      transform: translateY(1px);
    }
  </style>
</head>
<body>
  <div class="container">
    <span class="logo">🎬</span>
    <h1>Welcome to NioxPlay</h1>
    <p>Enjoy blazing fast local high-definition video streaming directly from our server network without any internet connection.</p>
    <a href="http://${SITE_DOMAIN}" class="btn">Connect & Stream</a>
  </div>
</body>
</html>
EOF

# Setup Captive site config in Nginx
cat > /etc/nginx/sites-available/captive <<EOF
server {
  listen 80 default_server;
  server_name _;
  root /var/www/captive;
  index index.html;
  
  # Allow Apple / Android captive portal test requests to load or be redirected
  # (Crucial for auto-triggering the OS login prompt)
  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF

ln -sf /etc/nginx/sites-available/captive /etc/nginx/sites-enabled/captive
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "✔ Captive portal HTTP redirection configured"
