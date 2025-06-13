#!/bin/bash
set -e

# === 1. Gerekli paketler kurulsun ===
echo "[1/8] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
apt update && apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

# === 2. SSH Anahtarı oluşturulsun ===
echo "[2/8] SSH anahtarı oluşturuluyor..."
SSH_DIR="/root/.ssh"
PUB_KEY_COMMENT="root@setup"
SSH_PORT=22

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
  ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "$PUB_KEY_COMMENT"
fi
cat "$SSH_DIR/id_ed25519.pub" > "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

# === 3. SSH ayarları başlangıçta parola + anahtar erişimli ===
echo "[3/8] SSH yapılandırması yapılıyor..."
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
else
  echo "❌ /etc/ssh/sshd_config bulunamadı."
  exit 1
fi

# === 4. Güvenlik uygulamaları kuruluyor ===
echo "[4/8] UFW ve Fail2Ban yapılandırılıyor..."
ufw allow OpenSSH
ufw allow "Nginx HTTP"
ufw --force enable
systemctl enable fail2ban

# === 5. Nginx test sayfası ===
echo "[5/8] Nginx test sayfası yazılıyor..."
echo "<h1>Debian Setup Başarılı</h1>" > /var/www/html/index.html

# === 6. SSH public key gösterilir ===
echo "[6/8] SSH erişimi için public key aşağıdadır:"
echo "----------------- BEGIN PUBLIC KEY -----------------"
cat "$SSH_DIR/id_ed25519.pub"
echo "------------------ END PUBLIC KEY ------------------"
echo ""
echo "🌐 IP adresleriniz:"
ip -4 a | grep inet | grep -v 127 | awk '{print $2}'
echo ""
echo "ℹ️ Bu noktada Windows cihazınızla SSH bağlantısı kurabilirsiniz."
echo "🔒 Bağlantıyı test ettikten sonra devam etmek için ENTER'a basın..."
read -p ""

# === 7. SSH erişimini sıkılaştır ===
echo "[7/8] SSH artık sadece anahtar ile erişilebilir hale getiriliyor..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh

# === 8. Tamamlandı ===
echo "[8/8] Kurulum tamamlandı. SSH sadece anahtarla çalışmaktadır. Güvenli bağlantı aktiftir."
