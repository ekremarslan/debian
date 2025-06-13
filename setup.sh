#!/bin/bash
set -e

echo "[1/5] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
apt update && apt upgrade -y
apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

echo "[2/5] Güvenlik duvarı yapılandırılıyor..."
ufw allow OpenSSH
ufw allow "Nginx HTTP"
ufw --force enable
systemctl enable fail2ban

echo "[3/5] Public key indiriliyor ve tüm kullanıcılara uygulanıyor..."
PUBKEY_URL="https://raw.githubusercontent.com/ekremarslan/debian/refs/heads/main/ekremarslan.pub"
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

echo "[4/5] SSH yapılandırması güvenli hale getiriliyor..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

echo "[5/5] Kurulum tamamlandı."
echo "Sunucu IP adresleri:"
hostname -I
echo "✅ Tüm kullanıcılar için güvenli SSH erişimi aktif. Şifreli bağlantı kapalı."
