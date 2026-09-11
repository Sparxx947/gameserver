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
# Passwortanmeldung aus, root nur mit Schluessel - das ist der VORGABEWERT und
# bleibt die Empfehlung: die Protokolle zeigen auf einer oeffentlichen IP binnen
# Stunden die ersten Anmeldeversuche. Was sich geaendert hat, ist nur, dass es
# ein Wert in konfiguration.env ist statt einer Zeile hier. Der Grund ist nicht
# Bequemlichkeit: Wer die Vorgabe braucht, muss sie sonst nach jedem Lauf von
# Hand wieder eintragen, und zwar in einer Datei, die keine Einrichtungsstufe
# schreibt und die abgleich.sh nie verglichen hat. Eine solche Aenderung
# ueberlebt die naechste Einrichtung nicht und faellt dabei niemandem auf. Was
# konfigurierbar ist, ist sichtbar und wird verglichen (E28).
#
# *Password auth off and root key-only remain the default and the
#  recommendation; what changed is that it is a value rather than a line here.
#  Not for convenience: otherwise the deviation has to be re-entered by hand
#  after every run, in a file no stage writes and no comparison covered - it
#  does not survive the next install and nobody notices.*
SSH_KONF=/etc/ssh/sshd_config.d/99-gameserver.conf
# Die Sicherung von einsetzen() heisst "<datei>.vor-<datum>" und endet damit
# NICHT auf ".conf". Das ist hier keine Nebensache: sshd liest
# "Include /etc/ssh/sshd_config.d/*.conf" und nimmt bei mehrfach gesetzten
# Schluesseln den ERSTEN Wert - eine mitgelesene Sicherung wuerde die neue
# Einstellung also nicht nur ergaenzen, sondern schlagen. Debians sshd_config
# bindet genau "*.conf" ein - der Suffix der Sicherung ist deshalb Teil des
# Entwurfs und keine Kosmetik.
# *The backup does not end in ".conf", which matters: sshd includes only
#  "*.conf" and takes the FIRST value for a repeated key, so a backup that was
#  read along would beat the new setting rather than merely add to it.*
# Eigene Sicherung, VOR einsetzen und unabhaengig davon. einsetzen legt seine
# ".vor-<datum>" nur an, wenn sich der Inhalt aendert - bei gleichem Inhalt gibt
# es keine. Ein "nimm die neueste .vor-Datei" griffe dann auf eine beliebig alte
# zurueck und stellte stillschweigend eine aeltere Konfiguration her. Beim Test
# am 2026-09-11 fiel genau das auf: der Rueckweg muss den Stand von JETZT
# kennen, nicht den letzten, der zufaellig herumliegt.
# *Own backup, taken before einsetzen and independent of it: einsetzen only
#  creates its ".vor-<date>" when the content changes, so "take the newest one"
#  could silently restore an arbitrarily old config.*
SSH_VORHER=$(mktemp)
[ -f "$SSH_KONF" ] && cp -a "$SSH_KONF" "$SSH_VORHER"

einsetzen "$REPO/etc/ssh/sshd_config.d/99-gameserver.conf" "$SSH_KONF"

# "sshd -t" MUSS den Lauf anhalten. Vorher stand hier "sshd -t && systemctl
# reload ssh": schlug die Pruefung fehl, blieb der Neustart aus, die Stufe lief
# weiter und meldete am Ende "fertig" - mit einer kaputten Datei auf der Platte,
# die beim naechsten Neustart des Dienstes greift. Genau dann ist niemand dabei.
# Deshalb: zurueck auf den vorigen Stand (Sicherung, sonst Datei weg) und
# abbrechen, solange die laufende Sitzung noch steht.
# *"sshd -t" must stop the run. It used to be "sshd -t && systemctl reload ssh":
#  a failed check simply skipped the reload, the stage reported success, and the
#  broken file waited for the next restart of the daemon - when nobody is
#  watching. Roll back and abort while the current session still holds.*
if ! sshd -t 2>&1; then
  if [ -s "$SSH_VORHER" ]; then cp -a "$SSH_VORHER" "$SSH_KONF"; else rm -f "$SSH_KONF"; fi
  rm -f "$SSH_VORHER"
  fehler "sshd lehnt $SSH_KONF ab - zurueckgenommen, SSH unveraendert." \
         "SSH_PASSWORT_AUTH und SSH_ROOT_LOGIN in konfiguration.env pruefen."
fi
rm -f "$SSH_VORHER"
systemctl reload ssh || fehler "sshd -t war in Ordnung, der Neustart scheiterte trotzdem"

# Der gefaehrliche Zustand ist nicht "Passwoerter an", sondern "Passwoerter an,
# und keiner weiss es" - dieselbe Ueberlegung wie bei BORG_REPO=aus. Deshalb
# steht es hier im Protokoll und nicht nur in konfiguration.env.
# *The dangerous state is not "passwords on" but "passwords on and nobody
#  knows".*
if [ "$SSH_PASSWORT_AUTH" = "yes" ]; then
  warn "SSH: Passwortanmeldung ist EINGESCHALTET (SSH_PASSWORT_AUTH=yes)."
  warn "     Davor stehen dann nur noch die ufw-Regel auf $ADMIN_IP und fail2ban."
fi
[ "$SSH_ROOT_LOGIN" = "prohibit-password" ] \
  || warn "SSH: PermitRootLogin $SSH_ROOT_LOGIN (Vorgabe waere prohibit-password)."

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
