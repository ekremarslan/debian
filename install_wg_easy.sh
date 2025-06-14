#!/bin/bash
set -e

# Türkçe karakter desteği (UTF-8)
export LANG="tr_TR.UTF-8"

# === Otomatik kendine çalıştırılabilir izin ver (eğer dosya olarak çalıştırıldıysa) ===
SCRIPT_PATH=$(readlink -f "$0")
if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
fi

echo -e "\n🛠️ [1/6] Docker ve Gerekli Paketler Kuruluyor..."
apt update -y
apt install -y docker.io docker-compose nginx curl

systemctl enable docker
systemctl start docker

echo -e "\n📁 [2/6] /opt/wg-easy dizini oluşturuluyor..."
mkdir -p /opt/wg-easy
cd /opt/wg-easy

echo -e "\n📄 [3/6] docker-compose.yml dosyası yazılıyor..."
cat > docker-compose.yml <<EOF
version: "3.8"
services:
  wg-easy:
    image: weejewel/wg-easy
    container_name: wg-easy
    ports:
      - "51820:51820/udp"
      - "127.0.0.1:51821:51821/tcp"
    environment:
      - WG_HOST=192.168.10.24
      - PASSWORD=admin123
    volumes:
      - ./wg-data:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
EOF

echo -e "\n🚀 [4/6] WireGuard Web Arayüzü (wg-easy) başlatılıyor..."
docker-compose up -d

echo -e "\n🌐 [5/6] Nginx yapılandırması ekleniyor..."
cat > /etc/nginx/sites-available/wg-ui <<EOF
server {
    listen 80;
    server_name vpn.local;

    location / {
        proxy_pass http://127.0.0.1:51821;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/wg-ui /etc/nginx/sites-enabled/wg-ui
nginx -t && systemctl reload nginx

echo -e "\n✅ [6/6] Kurulum başarıyla tamamlandı!"

echo -e "\n🔑 Web Arayüz Giriş Şifresi: \e[1;32madmin123\e[0m"
echo -e "🌍 Giriş Adresi: \e[1;34mhttp://vpn.local\e[0m"
echo -e "📌 Not: Kendi bilgisayarınızda /etc/hosts dosyasına şu satırı ekleyin:"
echo -e "    \e[1;33m192.168.10.24    vpn.local\e[0m\n"