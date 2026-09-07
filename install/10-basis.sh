#!/bin/bash
# Stufe 10 — Grundsystem: Pakete, Benutzer, SSH, Firewall, fail2ban.
# *Stage 10 — base system: packages, users, SSH, firewall, fail2ban.*
. "$(dirname "$0")/lib.sh"

log "Paketquellen aktualisieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

log "Grundpakete"
apt-get install -y -qq \
  borgbackup bash-completion bind9-host ca-certificates curl ethtool fail2ban \
  gnupg htop iputils-ping nano openssh-server python3-pip python3-systemd \
  python3-venv qemu-guest-agent screen socat sudo tcpdump traceroute ufw \
  unattended-upgrades vim

# --- Benutzer ---------------------------------------------------------
# ADMIN_USER: Mensch am Webterminal, mit sudo.
# panel:      Systemnutzer der Weboberflaeche, ohne Shell.
# spiele:     feste UID 4711 fuer alle Spieldaten. Die Container laufen unter
#             dieser UID (PUID/UID im compose); ohne festen Wert gehoeren die
#             Spielstaende nach einem Neuaufbau plötzlich niemandem mehr.
# *Fixed UID 4711 for all game data: containers run as this UID, and without a
#  fixed value the save files end up ownerless after a rebuild.*
id -u "$ADMIN_USER" >/dev/null 2>&1 || { adduser --disabled-password --gecos "" "$ADMIN_USER"; usermod -aG sudo "$ADMIN_USER"; }
getent group panel  >/dev/null || groupadd --system panel
id -u panel >/dev/null 2>&1 || useradd --system --gid panel --home-dir /opt/panel --shell /usr/sbin/nologin panel
# Der Mensch muss die Panel-Daten lesen koennen (Fehlersuche im Terminal).
usermod -aG panel "$ADMIN_USER"
getent group  spiele >/dev/null || groupadd --gid 4711 spiele
id -u spiele >/dev/null 2>&1 || useradd --uid 4711 --gid 4711 --no-create-home --shell /usr/sbin/nologin spiele

log "Verzeichnisse"
install -d -m 0755 -o root -g root /srv/games /srv/dienste /opt/stacks

# --- SSH --------------------------------------------------------------
# Passwortanmeldung aus, root nur mit Schluessel. Beides ist auf einem Server
# mit oeffentlicher IP nicht verhandelbar: die Protokolle zeigen binnen Stunden
# die ersten Anmeldeversuche.
# *Password auth off, root key-only. Non-negotiable on a public IP — the logs
#  show the first login attempts within hours.*
cat > /etc/ssh/sshd_config.d/99-gameserver.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
X11Forwarding no
EOF
sshd -t && systemctl reload ssh

# --- Firewall ---------------------------------------------------------
# Grundregel: alles zu. Spielports macht Docker spaeter selbst auf (DNAT vor
# den ufw-Ketten) — sie stehen deshalb bewusst NICHT hier drin.
# *Default deny. Docker opens game ports itself via DNAT ahead of the ufw
#  chains, which is why no game port is listed here.*
log "ufw"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
ufw allow in on tailscale0 comment 'Tailnet: Notzugang und Sicherungen'
ufw allow from "$ADMIN_IP" to any port 22 proto tcp comment 'SSH nur von zuhause'
ufw allow 80/tcp  comment 'Caddy: Zertifikatsausstellung'
ufw allow 443/tcp comment 'Panel (HTTPS)'
ufw --force enable

log "fail2ban"
einsetzen "$REPO/etc/fail2ban/jail.local" /etc/fail2ban/jail.local
systemctl enable --now fail2ban
systemctl restart fail2ban

# --- Automatische Sicherheitsaktualisierungen -------------------------
log "unattended-upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

log "Stufe 10 fertig."
