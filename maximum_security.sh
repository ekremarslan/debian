#!/bin/bash
set -e

# Varsayılan: tüm önlemler pasif
ENABLE_FAIL2BAN=true
ENABLE_ICMP_BLOCK=false
ENABLE_SSH_IP_LIMIT=false
ENABLE_AUDITD=false
ENABLE_SYSCTL_HARDENING=false

SSH_PORT=2222
SSH_ALLOW_IP=""  # örnek: 192.168.1.0/24

# Argümanları oku
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --fail2ban) ENABLE_FAIL2BAN=true ;;
    --block-icmp) ENABLE_ICMP_BLOCK=true ;;
    --ssh-allow-ip) SSH_ALLOW_IP="$2"; ENABLE_SSH_IP_LIMIT=true; shift ;;
    --enable-auditd) ENABLE_AUDITD=true ;;
    --harden-sysctl) ENABLE_SYSCTL_HARDENING=true ;;
    --port) SSH_PORT="$2"; shift ;;
    *) echo "Bilinmeyen parametre: $1"; exit 1 ;;
  esac
  shift
done

# Fail2Ban yapılandırması
if [ "$ENABLE_FAIL2BAN" = true ]; then
  echo "[✓] Fail2Ban yapılandırılıyor..."
  apt install -y fail2ban
  cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
bantime = 86400
findtime = 600
EOF
  systemctl restart fail2ban
fi

# ICMP (ping) engelleme
if [ "$ENABLE_ICMP_BLOCK" = true ]; then
  echo "[✓] ICMP engelleniyor..."
  sysctl -w net.ipv4.icmp_echo_ignore_all=1
  echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.conf
fi

# SSH bağlantısına IP sınırlaması
if [ "$ENABLE_SSH_IP_LIMIT" = true ] && [ -n "$SSH_ALLOW_IP" ]; then
  echo "[✓] UFW üzerinden SSH IP sınırlaması uygulanıyor..."
  ufw delete allow $SSH_PORT/tcp || true
  ufw allow from $SSH_ALLOW_IP to any port $SSH_PORT proto tcp
fi

# AuditD kurulumu
if [ "$ENABLE_AUDITD" = true ]; then
  echo "[✓] Auditd kuruluyor ve izleme kuralları uygulanıyor..."
  apt install -y auditd
  auditctl -w /etc/passwd -p war -k passwd_changes
  auditctl -w /etc/ssh/sshd_config -p war -k ssh_config_changes
fi

# sysctl ile çekirdek güvenlik ayarları
if [ "$ENABLE_SYSCTL_HARDENING" = true ]; then
  echo "[✓] Ağ güvenlik ayarları sysctl ile uygulanıyor..."
  cat >> /etc/sysctl.conf <<EOF

# IPv4 güvenliği
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0

# IPv6 devre dışı
net.ipv6.conf.all.disable_ipv6 = 1

# SYN flood koruması
net.ipv4.tcp_syncookies=1
EOF
  sysctl -p
fi

echo "✅ maximum_security.sh tamamlandı."
