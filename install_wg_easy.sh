#!/bin/bash
set -e

echo -e "\n🌐 Locale ayarları yapılıyor..."
apt install -y locales
sed -i 's/^# *tr_TR.UTF-8 UTF-8/tr_TR.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=tr_TR.UTF-8
echo -e 'LANG=tr_TR.UTF-8\nLC_ALL=tr_TR.UTF-8' > /etc/default/locale
export LANG=tr_TR.UTF-8
export LC_ALL=tr_TR.UTF-8

echo -e "\n🧱 [0/6] UFW güvenlik duvarı ayarlanıyor..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 51820/udp
yes | ufw enable

echo -e "\n🛠️ [1/6] Docker ve Gerekli Paketler Kuruluyor..."
apt update -y
apt install -y docker.io docker-compose nginx curl

systemctl enable docker
systemctl start docker


echo -e "\n🌐 [5/6] Nginx yapılandırması ekleniyor..."
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

echo -e "\n✅ [6/6] Kurulum başarıyla tamamlandı!"
echo -e "\n🔑 Web Arayüz Giriş Şifresi: \e[1;32madmin123\e[0m"
echo -e "🌍 Giriş Adresi: \e[1;34mhttp://vpn.local\e[0m"
echo -e "📌 Not: Kendi bilgisayarınızda /etc/hosts dosyasına şu satırı ekleyin:"
echo -e "    \e[1;33m192.168.10.24    vpn.local\e[0m\n"

echo -e "\n📦 [Ek] wireguard-ui kuruluyor (EmbarkStudios/wireguard-ui)..."
mkdir -p /opt/wireguard-ui
cd /opt/wireguard-ui

cat > docker-compose.yml <<EOF
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

docker-compose up -d
cd -

echo -e "\n✅ Kurulum tamamlandı!"
echo -e "\n🌍 Web Arayüz (WireGuard UI): \e[1;34mhttp://vpn.local\e[0m"
echo -e "📌 Not: /etc/hosts dosyanıza şunu eklemeyi unutmayın:"
echo -e "    \e[1;33m192.168.10.24    vpn.local\e[0m\n"
