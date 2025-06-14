#!/bin/bash
set -e

echo -e "\n🚀 WireGuard UI kurulum başlatılıyor..."

# Sistem güncellemesi ve temel araçlar
apt update -y
apt install -y curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common

# Docker kurulumu (eğer yoksa)
if ! command -v docker >/dev/null 2>&1; then
    echo -e "\n📦 Docker kuruluyor..."
    apt install -y docker.io
    systemctl enable docker
    systemctl start docker
else
    echo -e "\n✅ Docker zaten kurulu."
fi

# docker compose plugin (v2) kurulumu
if ! docker compose version >/dev/null 2>&1; then
    echo -e "\n🔧 docker-compose-plugin kuruluyor..."
    apt install -y docker-compose-plugin
fi

# Nginx kurulumu (eğer yoksa)
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "\n🌐 Nginx kuruluyor..."
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
else
    echo -e "\n✅ Nginx zaten kurulu."
fi

# wireguard-ui kurulumu
mkdir -p /opt/wireguard-ui
cd /opt/wireguard-ui

cat <<EOF > docker-compose.yml
version: '3.8'

services:
  wireguard-ui:
    image: ngoduykhanh/wireguard-ui:latest
    container_name: wireguard-ui
    restart: unless-stopped
    environment:
      - TZ=Europe/Istanbul
      - WGUI_USERNAME=admin
      - WGUI_PASSWORD=admin123
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - ./data:/etc/wireguard
EOF

docker compose up -d

# Nginx reverse proxy yapılandırması
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

cat <<EOF > /etc/nginx/sites-available/wg-ui
server {
    listen 80;
    server_name vpn.local;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/wg-ui /etc/nginx/sites-enabled/wg-ui
nginx -t && systemctl reload nginx

# Bilgilendirme
echo -e "\n✅ Kurulum tamamlandı!"
echo -e "🌍 Web arayüzü: http://vpn.local"
echo -e "👤 Giriş: admin / admin123"
echo -e "📌 Not: /etc/hosts dosyanıza aşağıdakini eklemeyi unutmayın:"
echo -e "192.168.10.24    vpn.local"
