#!/bin/bash
set -e

# === SSH Anahtarı ===
SSH_DIR="/root/.ssh"
PUB_KEY_COMMENT="root@setup"
SSH_PORT=22

# === SSH Anahtarı oluştur ===
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
  ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "$PUB_KEY_COMMENT"
fi
cat "$SSH_DIR/id_ed25519.pub" > "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

# === SSH Ayarları (ilk erişim için parola da açık) ===
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# === Sistem güncelleme ve araçlar ===
apt update && apt upgrade -y
apt install -y sudo curl wget vim gnupg ufw fail2ban openssh-server nginx

# === Güvenlik ayarları ===
ufw allow OpenSSH
ufw allow "Nginx HTTP"
ufw --force enable
systemctl enable fail2ban

# === SSH Sıkılaştırma: sadece anahtarla erişim ===
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh

# === Bilgi çıktısı ===
echo ""
echo "Kurulum tamamlandı."
echo "SSH public key (başka cihaza aktarılacak):"
echo ""
cat "$SSH_DIR/id_ed25519"
echo ""
echo "SSH portu: $SSH_PORT"
ip -4 a | grep inet
