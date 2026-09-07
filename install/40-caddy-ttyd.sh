#!/bin/bash
# Stufe 40 — Caddy (HTTPS, Zertifikat, Vorschaltung) und das Webterminal ttyd.
# *Stage 40 — Caddy (HTTPS, certificates, reverse proxy) and the ttyd terminal.*
. "$(dirname "$0")/lib.sh"

TTYD_VERSION="1.7.7"

if ! command -v caddy >/dev/null; then
  log "Caddy-Repository eintragen"
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
fi
apt-get install -y -qq caddy

# --- ttyd -------------------------------------------------------------
# Kein Debian-Paket: bookworm liefert ttyd 1.6, dessen --base-path sich anders
# verhaelt. Deshalb das statisch gelinkte Release-Binary.
# *No Debian package: bookworm ships ttyd 1.6 whose --base-path behaves
#  differently. Hence the statically linked release binary.*
if [ "$(/usr/local/bin/ttyd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" != "$TTYD_VERSION" ]; then
  log "ttyd $TTYD_VERSION holen"
  curl -fsSL -o /usr/local/bin/ttyd \
    "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
  chmod 0755 /usr/local/bin/ttyd
fi

log "Konfiguration"
einsetzen "$REPO/etc/caddy/Caddyfile" /etc/caddy/Caddyfile 0644 root:root
einsetzen "$REPO/systemd/ttyd.service" /etc/systemd/system/ttyd.service

# caddy validate prueft die Datei, BEVOR der laufende Dienst sie bekommt. Ohne
# das laesst ein Tippfehler den Reverse Proxy stehen und das Panel ist weg —
# samt Webterminal, ueber das man es reparieren wuerde.
# *Validate before reloading: a typo would take down the proxy, the panel and
#  the very terminal one would use to fix it.*
caddy validate --config /etc/caddy/Caddyfile >/dev/null || fehler "Caddyfile ungueltig"

systemctl daemon-reload
systemctl enable --now caddy ttyd
systemctl reload caddy

log "Stufe 40 fertig. Panel: https://${PANEL_DOMAIN}/"
