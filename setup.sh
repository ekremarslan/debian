#!/bin/bash
set -e

# === Gereklilik kontrolü ve kurulum ===
echo "[1/7] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
apt update && apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

# === SSH Anahtarı ===
echo "[2/7] SSH anahtarı oluşturuluyor..."
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

# === SSH Ayarları (önce parolalı erişim açık) ===
echo "[3/7] SSH yapılandırması yapılıyor..."
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
else
  echo "❌ /etc/ssh/sshd_config bulunamadı. openssh-server kurulamamış olabilir."
  exit 1
fi

# === Güvenlik ayarları ===
echo "[4/7] UFW ve Fail2Ban yapılandırılıyor..."
ufw allow OpenSSH
ufw allow "Nginx HTTP"
ufw --force enable
systemctl enable fail2ban

# === SSH erişimi sıkılaştırma ===
echo "[5/7] SSH erişimi sadece anahtar tabanlı hâle getiriliyor..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh

# === Nginx test dosyası ===
echo "[6/7] Nginx test sayfası yazılıyor..."
echo "<h1>Debian Setup Başarılı</h1>" > /var/www/html/index.html

# === Bilgilendirme ===
echo "[7/7] Kurulum tamamlandı:"
echo "🔐 SSH public key:"
cat "$SSH_DIR/id_ed25519.pub"
echo ""
echo "📂 Private key (bu sunucuda): $SSH_DIR/id_ed25519"
echo "🌐 IP adresleri:"
ip -4 a | grep inet | grep -v 127 | awk '{print $2}'
echo ""
echo "✅ Artık yalnızca SSH anahtarıyla erişim mümkün."
