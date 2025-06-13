#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_result() {
  if [ "$1" -eq 0 ]; then
    echo -e "${GREEN}[✓]${NC} $2"
  else
    echo -e "${RED}[✗]${NC} $2"
  fi
}

echo "===== SSH Ayarları Kontrolü ====="
grep -Eq "^PermitRootLogin prohibit-password" /etc/ssh/sshd_config
print_result $? "PermitRootLogin prohibit-password"

grep -Eq "^PasswordAuthentication no" /etc/ssh/sshd_config
print_result $? "PasswordAuthentication no"

grep -Eq "^PubkeyAuthentication yes" /etc/ssh/sshd_config
print_result $? "PubkeyAuthentication yes"

echo -e "\n===== authorized_keys Dosyaları ====="
for dir in /root /home/*; do
  [ -d "$dir" ] || continue
  user=$(basename "$dir")
  file="$dir/.ssh/authorized_keys"
  if [ -f "$file" ]; then
    echo "[+] $user kullanıcısında authorized_keys mevcut:"
    head -n 1 "$file"
  else
    echo -e "${RED}[✗]${NC} $user kullanıcısında authorized_keys bulunamadı."
  fi
done

echo -e "\n===== UFW Durumu ====="
ufw status verbose

echo -e "\n===== Fail2Ban Durumu ====="
systemctl is-active --quiet fail2ban
print_result $? "Fail2Ban aktif"

echo -e "\n===== Açık Portlar ====="
ss -tulpen | grep -v LISTEN | head -n 20

echo -e "\n===== Sudo Yetkisi Olan Kullanıcılar ====="
getent group sudo

echo -e "\n===== Sunucuda Private Key Var mı? ====="
find / -name "id_ed25519" 2>/dev/null | grep -v "/.ssh/id_ed25519.pub" || echo -e "${GREEN}[✓]${NC} Private key bulunamadı."

echo -e "\n✅ Güvenlik kontrolü tamamlandı."
