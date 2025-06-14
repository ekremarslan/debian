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

echo "[1/6] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
apt update && apt upgrade -y
apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

echo "[2/6] Güvenlik duvarı yapılandırılıyor (SSH port: $SSH_PORT)..."
ufw allow "${SSH_PORT}/tcp"
ufw allow "Nginx HTTP"
# Varsayılan 22 numaralı SSH portunu kapat
ufw delete allow 22/tcp 2>/dev/null || true
ufw delete allow 22/tcp (v6) 2>/dev/null || true
ufw --force enable
systemctl enable fail2ban

echo "[3/6] Public key indiriliyor ve tüm kullanıcılara uygulanıyor..."
TEMP_KEY="/tmp/ekremarslan.pub"
curl -Ls "$PUBKEY_URL" -o "$TEMP_KEY"

for dir in /home/* /root; do
  [ -d "$dir" ] || continue
  USERNAME=$(basename "$dir")
  SSH_DIR="$dir/.ssh"
  AUTH_KEYS="$SSH_DIR/authorized_keys"

  echo "→ $USERNAME kullanıcısına ekleniyor..."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  touch "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  grep -qxFf "$TEMP_KEY" "$AUTH_KEYS" || cat "$TEMP_KEY" >> "$AUTH_KEYS"
  chown -R "$USERNAME:$USERNAME" "$SSH_DIR" 2>/dev/null || true
done

rm -f "$TEMP_KEY"

echo "[4/6] SSH yapılandırması güvenli hale getiriliyor..."
grep -q "^Port" /etc/ssh/sshd_config && sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config || echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

echo "[5/6] SSH servisi yeniden başlatılıyor..."
systemctl restart ssh

echo "[6/6] Kurulum tamamlandı."
echo "Sunucu IP adresleri:"
hostname -I
echo "✅ SSH portu: $SSH_PORT | 22 kapalı | Şifreli giriş yok | Yalnızca key ile giriş aktif."
