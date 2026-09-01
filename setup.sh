#!/bin/bash
# =============================================================================
# Debian Standardizasyon / Hardening Scripti
# Bookworm (12) ve Trixie (13) uyumlu — "önce doğrula, sonra kapat" mantığı
# =============================================================================

# --- 0) Önyükleme: güvenli mod + root kontrolü -------------------------------
# NOT: set -u arg parse'tan SONRA devreye girmeli ki ${2:-} vb. ile uğraşmayalım;
#      burada -e ve pipefail'i açıyoruz, -u'yu arg parse sonrası ekliyoruz.
set -eo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "HATA: Bu script root olarak çalıştırılmalı." >&2
  exit 1
fi

# NOT: Çıktı doğrudan terminale yazılır — böylece 'bash <(curl ...)', 'curl | bash'
# ve dosyadan çalıştırma dahil her yöntemde script sorunsuz başlar.
# Log dosyası istersen komutu tee ile sarmalaman yeterli (fd yönlendirmesine gerek yok):
#   bash <(curl -sL URL) 2>&1 | tee /var/log/debian-setup.log

# --- Varsayılan ayarlar ------------------------------------------------------
SSH_PORT=2222
WITH_NGINX=0
PUBKEY_URL="https://raw.githubusercontent.com/ekremarslan/debian/refs/heads/main/ekremarslan.pub"

# --- Argüman ayrıştırma ------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      SSH_PORT="${2:-}"; shift 2 ;;
    --with-nginx)
      WITH_NGINX=1; shift ;;
    --pubkey-url)
      PUBKEY_URL="${2:-}"; shift 2 ;;
    *)
      echo "Bilinmeyen parametre: $1" >&2; exit 1 ;;
  esac
done

# --- Argüman validasyonu -----------------------------------------------------
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "HATA: Geçersiz SSH portu: '$SSH_PORT' (1-65535 arası olmalı)" >&2
  exit 1
fi
if [ -z "$PUBKEY_URL" ]; then
  echo "HATA: PUBKEY_URL boş olamaz." >&2
  exit 1
fi

# Artık -u güvenli
set -u
export DEBIAN_FRONTEND=noninteractive

# Debian sürüm codename'ini dinamik al (bookworm/trixie/...)
# shellcheck source=/dev/null
. /etc/os-release
CODENAME="${VERSION_CODENAME:-}"
if [ -z "$CODENAME" ]; then
  echo "HATA: Debian codename tespit edilemedi (/etc/os-release)." >&2
  exit 1
fi
echo "Tespit edilen dağıtım: ${PRETTY_NAME:-Debian} (codename: $CODENAME)"

# =============================================================================
echo "[0/7] Repository ayarları düzeltiliyor..."
# =============================================================================
# Trixie ve sonrası deb822 formatı kullanır (/etc/apt/sources.list.d/debian.sources).
# Bu dosya kuruluşta genelde doğru yapılandırılır; ona dokunmuyoruz.
# Sadece klasik (legacy) sources.list kullanan sistemlerde cdrom'u temizleyip
# ağ depolarını garanti altına alıyoruz.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  echo "→ deb822 formatı algılandı (debian.sources). Depolar olduğu gibi bırakılıyor."
  # Olası cdrom stanza'sını devre dışı bırak (varsa)
  if grep -qi 'cdrom' /etc/apt/sources.list 2>/dev/null; then
    sed -i '/cdrom/d' /etc/apt/sources.list
  fi
else
  echo "→ Klasik sources.list formatı. cdrom girişleri temizleniyor, ağ depoları ekleniyor."
  touch /etc/apt/sources.list
  sed -i '/cdrom/d' /etc/apt/sources.list
  if ! grep -q "deb.debian.org/debian ${CODENAME} main" /etc/apt/sources.list; then
    cat >> /etc/apt/sources.list << EOF

# Debian ${CODENAME} Repositories (script tarafından eklendi)
deb http://deb.debian.org/debian ${CODENAME} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free non-free-firmware
EOF
  fi
fi

# =============================================================================
echo "[1/7] Sistem güncelleniyor ve gerekli paketler kuruluyor..."
# =============================================================================
apt-get update
apt-get upgrade -y
apt-get install -y \
  sudo curl wget vim gnupg ca-certificates \
  ufw fail2ban openssh-server \
  unattended-upgrades systemd-timesyncd

if [ "$WITH_NGINX" -eq 1 ]; then
  apt-get install -y nginx
fi

# =============================================================================
echo "[2/7] Public key indiriliyor, DOĞRULANIYOR ve kullanıcılara uygulanıyor..."
# =============================================================================
# -f: HTTP hatasında (404 vb.) curl fail versin ki bozuk anahtar eklenmesin.
TEMP_KEY="$(mktemp)"
trap 'rm -f "$TEMP_KEY"' EXIT

if ! curl -fsSL "$PUBKEY_URL" -o "$TEMP_KEY"; then
  echo "HATA: Public key indirilemedi: $PUBKEY_URL" >&2
  exit 1
fi

# İndirilen içerik gerçekten geçerli bir SSH public key mi?
if ! ssh-keygen -l -f "$TEMP_KEY" >/dev/null 2>&1; then
  echo "HATA: İndirilen dosya geçerli bir SSH public key değil. İşlem durduruldu." >&2
  echo "      (Password auth kapatılmadan önce yakalandı — kilitlenme önlendi.)" >&2
  exit 1
fi
echo "→ Public key doğrulandı: $(ssh-keygen -l -f "$TEMP_KEY")"

for dir in /root /home/*; do
  [ -d "$dir" ] || continue
  USERNAME="$(basename "$dir")"
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

# =============================================================================
echo "[3/7] Güvenlik duvarı (UFW) yapılandırılıyor — port 22 HENÜZ kapatılmıyor..."
# =============================================================================
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
# NOT: 22'yi burada kapatmıyoruz. Yeni portun dinlediğini teyit ETTİKTEN sonra kapatacağız.

# =============================================================================
echo "[4/7] SSH güvenli hale getiriliyor (drop-in config)..."
# =============================================================================
# Ana sshd_config'e sed atmak yerine drop-in kullanıyoruz. Sebep: cloud image'larda
# /etc/ssh/sshd_config.d/50-cloud-init.conf gibi dosyalar ana gövdeden ÖNCE okunur
# ve sshd çoğu direktif için İLK değeri kullanır; ana dosyadaki değişiklik geçersiz kalır.
# 00- öneki ile bizim ayarlarımız en önce okunur.
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
mkdir -p "$SSHD_DROPIN_DIR"
cat > "$SSHD_DROPIN_DIR/00-hardening.conf" << EOF
# Bu dosya standardizasyon scripti tarafından üretildi. Elle düzenlemeyin.
Port $SSH_PORT
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
ChallengeResponseAuthentication no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# ssh.socket (socket-activation) aktifse, 'Port' direktifi YOK SAYILIR; dinlenen portu
# socket birimi belirler. Bunu önlemek için socket'i devre dışı bırakıp ssh.service'e geçiyoruz.
if systemctl is-enabled ssh.socket >/dev/null 2>&1 || systemctl is-active ssh.socket >/dev/null 2>&1; then
  echo "→ ssh.socket tespit edildi; devre dışı bırakılıp ssh.service'e geçiliyor (Port direktifi geçerli olsun diye)."
  systemctl disable --now ssh.socket || true
  systemctl enable ssh.service || true
fi

# Config'i restart'tan ÖNCE test et — hatalıysa SSH'ı öldürme.
echo "→ sshd yapılandırması test ediliyor (sshd -t)..."
if ! sshd -t; then
  echo "HATA: sshd yapılandırması geçersiz. Restart YAPILMADI, mevcut oturum korundu." >&2
  echo "      $SSHD_DROPIN_DIR/00-hardening.conf dosyasını kontrol edin." >&2
  exit 1
fi

# =============================================================================
echo "[5/7] SSH servisi yeniden başlatılıyor ve yeni port doğrulanıyor..."
# =============================================================================
systemctl restart ssh
sleep 2

# Yeni portu gerçekten dinliyor muyuz?
if ss -tlnH "sport = :$SSH_PORT" 2>/dev/null | grep -q ":$SSH_PORT"; then
  echo "→ Doğrulandı: sshd ${SSH_PORT} portunu dinliyor."
else
  echo "HATA: sshd yeni portu ($SSH_PORT) dinlemiyor! Port 22 kapatılmayacak." >&2
  echo "      Mevcut oturumunuz güvende. Sorunu çözmeden çıkış yapmayın." >&2
  echo "      Kontrol: 'ss -tlnp | grep ssh' ve 'journalctl -u ssh -n 50'" >&2
  exit 1
fi

# --- Yalnızca doğrulama başarılıysa 22'yi kapat ------------------------------
echo "→ Yeni port çalışıyor. Port 22 kapatılıyor..."
ufw delete allow 22/tcp        2>/dev/null || true
ufw delete allow OpenSSH       2>/dev/null || true
ufw delete allow 22            2>/dev/null || true

# =============================================================================
echo "[6/7] fail2ban etkinleştiriliyor (özel port jail'i ile)..."
# =============================================================================
# Not: Varsayılan sshd jail'i 22'yi izler. Özel port için jail.local şart.
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban

# =============================================================================
echo "[7/7] Otomatik güvenlik güncellemeleri ve zaman senkronu..."
# =============================================================================
# unattended-upgrades: güvenlik yamalarını otomatik uygula (standardizasyonun kalbi)
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades || true
systemctl enable --now systemd-timesyncd  || true

if [ "$WITH_NGINX" -eq 1 ]; then
  systemctl enable --now nginx
fi

# =============================================================================
echo ""
echo "✅ Kurulum tamamlandı!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dağıtım    : ${PRETTY_NAME:-Debian} ($CODENAME)"
echo "Sunucu IP  : $(hostname -I | xargs)"
echo "SSH portu  : $SSH_PORT"
echo "Nginx      : $([ "$WITH_NGINX" -eq 1 ] && echo 'kuruldu' || echo 'atlandı (--with-nginx ile ekleyebilirsiniz)')"
echo "Güvenlik   : Port 22 kapalı | Şifre girişi kapalı | Sadece SSH key | fail2ban aktif | oto-güncelleme açık"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  ÇIKIŞ YAPMADAN ÖNCE: Yeni bir terminalden 'ssh -p $SSH_PORT kullanici@ip'"
echo "    ile bağlanabildiğinizi doğrulayın. Bu oturumu açık tutun!"

# stdout/stderr'i kapat ve tee'nin log'a yazmayı bitirmesini bekle
exec >&- 2>&-
wait "$LOG_TEE_PID" 2>/dev/null || true
