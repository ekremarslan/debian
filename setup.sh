#!/bin/bash
# =============================================================================
# Debian Standardizasyon / Hardening Scripti
# Bookworm (12) ve Trixie (13) uyumlu — "önce doğrula, sonra kapat" mantığı
#
# Kullanım:
#   bash <(curl -sL URL) [--port 2222] [--with-nginx] [--pubkey-url URL]
# Log istersen:
#   bash <(curl -sL URL) 2>&1 | tee /var/log/debian-setup.log
# =============================================================================

# --- 0) Önyükleme: güvenli mod + root kontrolü -------------------------------
# set -u arg parse'tan SONRA açılıyor.
set -eo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "HATA: Bu script root olarak çalıştırılmalı." >&2
  exit 1
fi

# 'su' (tiresiz) ile root olunduğunda Debian /usr/sbin ve /sbin'i PATH'e eklemez;
# ufw, sshd, iptables vb. bulunamaz. PATH'i garanti altına alıyoruz.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# --- Varsayılan ayarlar ------------------------------------------------------
SSH_PORT=2222
WITH_NGINX=0
PUBKEY_URL="https://raw.githubusercontent.com/ekremarslan/debian/refs/heads/main/ekremarslan.pub"

# --- Argüman ayrıştırma ------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      SSH_PORT="${2:-}"; shift 2 || shift ;;
    --with-nginx)
      WITH_NGINX=1; shift ;;
    --pubkey-url)
      PUBKEY_URL="${2:-}"; shift 2 || shift ;;
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
# O dosyaya dokunmuyoruz; sadece legacy sources.list'teki cdrom satırlarını temizliyoruz.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  echo "→ deb822 formatı algılandı (debian.sources). Depolar olduğu gibi bırakılıyor."
  if [ -f /etc/apt/sources.list ] && grep -qi 'cdrom' /etc/apt/sources.list; then
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
# python3-systemd: fail2ban'in systemd backend'i için gerekli
# (Debian 12'de rsyslog/auth.log olmadığından fail2ban journal'dan okumalı).
# iproute2: 'ss' komutu için.
apt-get install -y \
  sudo curl wget vim gnupg ca-certificates iproute2 \
  ufw fail2ban python3-systemd openssh-server \
  unattended-upgrades systemd-timesyncd

if [ "$WITH_NGINX" -eq 1 ]; then
  apt-get install -y nginx
fi

# Kritik komutlar gerçekten erişilebilir mi?
for cmd in ufw sshd ss ssh-keygen fail2ban-client; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "HATA: '$cmd' bulunamadı (PATH: $PATH). İşlem durduruldu." >&2
    exit 1
  fi
done

# =============================================================================
echo "[2/7] Public key indiriliyor, DOĞRULANIYOR ve kullanıcılara uygulanıyor..."
# =============================================================================
TEMP_KEY="$(mktemp)"
trap 'rm -f "$TEMP_KEY"' EXIT

# -f: HTTP hatasında (404 vb.) curl fail versin ki bozuk anahtar eklenmesin.
if ! curl -fsSL "$PUBKEY_URL" -o "$TEMP_KEY"; then
  echo "HATA: Public key indirilemedi: $PUBKEY_URL" >&2
  exit 1
fi

# Normalize: CRLF → LF, boş satırları at, dosya sonu newline garanti.
sed -i 's/\r$//; /^[[:space:]]*$/d' "$TEMP_KEY"
if [ -s "$TEMP_KEY" ] && [ -n "$(tail -c1 "$TEMP_KEY")" ]; then
  echo >> "$TEMP_KEY"
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

  # /home altında sistemde karşılığı olmayan klasörleri atla
  if [ "$dir" != "/root" ] && ! id "$USERNAME" >/dev/null 2>&1; then
    echo "→ $dir için kullanıcı yok, atlanıyor."
    continue
  fi

  echo "→ $USERNAME kullanıcısına ekleniyor..."
  mkdir -p "$SSH_DIR"
  touch "$AUTH_KEYS"

  # Önceki çalıştırmalardan kalmış olabilecek CRLF'leri temizle
  sed -i 's/\r$//' "$AUTH_KEYS"
  # Mevcut dosya newline ile bitmiyorsa ekle (anahtarlar aynı satıra yapışmasın)
  if [ -s "$AUTH_KEYS" ] && [ -n "$(tail -c1 "$AUTH_KEYS")" ]; then
    echo >> "$AUTH_KEYS"
  fi

  # Her anahtar satırını ayrı ayrı kontrol edip yoksa ekle
  while IFS= read -r keyline; do
    [ -n "$keyline" ] || continue
    grep -qxF -- "$keyline" "$AUTH_KEYS" || printf '%s\n' "$keyline" >> "$AUTH_KEYS"
  done < "$TEMP_KEY"

  chmod 700 "$SSH_DIR"
  chmod 600 "$AUTH_KEYS"
  if [ "$dir" = "/root" ]; then
    chown -R root:root "$SSH_DIR"
  else
    USERGROUP="$(id -gn "$USERNAME")"
    chown -R "$USERNAME:$USERGROUP" "$SSH_DIR"
  fi
done

# =============================================================================
echo "[3/7] Güvenlik duvarı (UFW) yapılandırılıyor — port 22 HENÜZ kapatılmıyor..."
# =============================================================================
# 22'yi enable'dan ÖNCE geçici olarak açıyoruz; yeni port doğrulanamazsa
# 22 üzerinden tekrar bağlanabilmek için.
ufw allow 22/tcp
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# =============================================================================
echo "[4/7] SSH güvenli hale getiriliyor (drop-in config)..."
# =============================================================================
# Drop-in kullanıyoruz: cloud image'lardaki 50-cloud-init.conf gibi dosyalar ana
# gövdeden ÖNCE okunur ve sshd çoğu direktif için İLK değeri kullanır.
# 00- öneki ile bizim ayarlarımız en önce okunur.
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
mkdir -p "$SSHD_DROPIN_DIR"

# Ana sshd_config drop-in klasörünü include ediyor mu? (Debian 12/13'te varsayılan evet)
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
  echo "→ sshd_config'e Include satırı ekleniyor."
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

cat > "$SSHD_DROPIN_DIR/00-hardening.conf" << EOF
# Bu dosya standardizasyon scripti tarafından üretildi. Elle düzenlemeyin.
Port $SSH_PORT
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# ssh.socket (socket-activation) aktifse 'Port' direktifi YOK SAYILIR.
if systemctl is-enabled ssh.socket >/dev/null 2>&1 || systemctl is-active ssh.socket >/dev/null 2>&1; then
  echo "→ ssh.socket tespit edildi; devre dışı bırakılıp ssh.service'e geçiliyor."
  systemctl disable --now ssh.socket || true
fi
systemctl enable ssh.service >/dev/null 2>&1 || true

# sshd -t, privilege separation dizini yoksa hata verir
mkdir -p /run/sshd
chmod 0755 /run/sshd

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

PORT_OK=0
for _ in 1 2 3 4 5; do
  sleep 1
  if ss -tlnH "sport = :$SSH_PORT" 2>/dev/null | grep -q ":$SSH_PORT"; then
    PORT_OK=1
    break
  fi
done

if [ "$PORT_OK" -eq 1 ]; then
  echo "→ Doğrulandı: sshd ${SSH_PORT} portunu dinliyor."
else
  echo "HATA: sshd yeni portu ($SSH_PORT) dinlemiyor! Port 22 kapatılmayacak." >&2
  echo "      Mevcut oturumunuz güvende. Sorunu çözmeden çıkış yapmayın." >&2
  echo "      Kontrol: 'ss -tlnp | grep ssh' ve 'journalctl -u ssh -n 50'" >&2
  exit 1
fi

# --- Yalnızca doğrulama başarılıysa 22'yi kapat ------------------------------
if [ "$SSH_PORT" -ne 22 ]; then
  echo "→ Yeni port çalışıyor. Port 22 firewall'da kapatılıyor..."
  ufw delete allow 22/tcp   >/dev/null 2>&1 || true
  ufw delete allow OpenSSH  >/dev/null 2>&1 || true
  ufw delete allow 22       >/dev/null 2>&1 || true
fi

# =============================================================================
echo "[6/7] fail2ban etkinleştiriliyor (özel port jail'i ile)..."
# =============================================================================
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
EOF

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 2
if fail2ban-client status sshd >/dev/null 2>&1; then
  echo "→ fail2ban sshd jail'i aktif."
else
  echo "UYARI: fail2ban sshd jail'i doğrulanamadı. 'journalctl -u fail2ban -n 50' ile kontrol edin." >&2
fi

# =============================================================================
echo "[7/7] Otomatik güvenlik güncellemeleri ve zaman senkronu..."
# =============================================================================
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
systemctl enable --now systemd-timesyncd  >/dev/null 2>&1 || true

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
