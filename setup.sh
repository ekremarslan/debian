#!/bin/bash
set -e

# Varsayılan ayarlar
SSH_PORT=2222
PUBKEY_URL="https://raw.githubusercontent.com/ekremarslan/debian/refs/heads/main/ekremarslan.pub"

# Argümanlardan özel port seçimi
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --port) SSH_PORT="$2"; shift ;;
    *) echo "Bilinmeyen parametre: $1"; exit 1 ;;
  esac
  shift
done

echo "[0/6] Repository ayarları düzeltiliyor..."

# CD-ROM satırlarını kaldır ve düzgün repository'leri ekle
sed -i '/cdrom/d' /etc/apt/sources.list

# Bookworm repository'lerini ekle (varsa tekrar eklenmemesi için kontrol)
if ! grep -q "deb.debian.org/debian bookworm main" /etc/apt/sources.list; then
  cat >> /etc/apt/sources.list << 'EOF'

# Debian Bookworm Repositories
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
fi

echo "[1/6] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
apt update && apt upgrade -y
apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

echo "[2/6] Güvenlik duvarı yapılandırılıyor (SSH port: $SSH_PORT)..."
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp

# 22 numaralı SSH portunu sil (varsa)
ufw delete allow 22/tcp 2>/dev/null || true
ufw delete allow OpenSSH 2>/dev/null || true
ufw delete allow 22 2>/dev/null || true

ufw --force enable
systemctl enable fail2ban

echo "[3/6] Public key indiriliyor ve tüm kullanıcılara uygulanıyor..."
TEMP_KEY="/tmp/ekremarslan.pub"
curl -Ls "$PUBKEY_URL" -o "$TEMP_KEY"

for dir in /root /home/*; do
  [ -d "$dir" ] || continue
  USERNAME=$(basename "$dir")
  SSH_DIR="$dir/.ssh"
  AUTH_KEYS="$SSH_DIR/authorized_keys"
  
  echo "→ $USERNAME kullanıcısına ekleniyor..."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  touch "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  
  grep -qxFf "$TEMP_KEY" "$AUTH_KEYS" 2>/dev/null || cat "$TEMP_KEY" >> "$AUTH_KEYS"
  
  if [ "$dir" = "/root" ]; then
    chown -R root:root "$SSH_DIR"
  else
    chown -R "$USERNAME:$USERNAME" "$SSH_DIR" 2>/dev/null || true
  fi
done

rm -f "$TEMP_KEY"

echo "[4/6] SSH yapılandırması güvenli hale getiriliyor..."
SSHD_CONFIG="/etc/ssh/sshd_config"

# Port ayarı
if grep -q "^Port" "$SSHD_CONFIG"; then
  sed -i "s/^Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
else
  echo "Port $SSH_PORT" >> "$SSHD_CONFIG"
fi

# Güvenlik ayarları
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"

echo "[5/6] SSH servisi yeniden başlatılıyor..."
systemctl restart ssh

echo "[6/6] Nginx yapılandırması kontrol ediliyor..."
systemctl enable nginx
systemctl start nginx

echo ""
echo "✅ Kurulum tamamlandı!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sunucu IP: $(hostname -I)"
echo "SSH portu: $SSH_PORT"
echo "Güvenlik: Port 22 kapalı | Şifre girişi kapalı | Sadece SSH key erişimi"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
