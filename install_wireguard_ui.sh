#!/bin/bash
set -e

echo -e "\n📂 wireguard-ui kurulumu başlatılıyor..."
mkdir -p /etc/wireguard
echo "[Interface]" > /etc/wireguard/wg0.conf
chmod 755 /etc/wireguard
chmod 644 /etc/wireguard/wg0.conf

mkdir -p /opt/wireguard-ui
cd /opt/wireguard-ui

cat > docker compose.yml <<EOF
version: '3'
services:
  wireguard-ui:
    image: embarkstudios/wireguard-ui:latest
    container_name: wireguard-ui
    restart: unless-stopped
    ports:
      - "51822:5000"
    volumes:
      - /etc/wireguard:/etc/wireguard
    environment:
      - WGUI_AUTO_GENERATE=true
      - WGUI_ENDPOINT_ADDRESS=192.168.10.24:51820
EOF

docker compose up -d

mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

echo -e "\n🌐 Nginx yapılandırması yapılıyor..."
cat > /etc/nginx/sites-available/wg-ui <<EOF
server {
    listen 80;
    server_name vpn.local;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/wg-ui /etc/nginx/sites-enabled/wg-ui
nginx -t && systemctl reload nginx

echo -e "\n✅ Kurulum tamamlandı!"
echo -e "🌍 Web Arayüz: http://vpn.local"
echo -e "📌 /etc/hosts dosyanıza şu satırı ekleyin:"
echo -e "192.168.10.24    vpn.local"
