#!/bin/bash
# abgleich.sh — vergleicht das Repositorium mit einer laufenden Maschine.
#
# Warum es das gibt: Eine Dokumentation, die vom System abweicht, ist schlimmer
# als keine — man handelt danach. Dieses Skript findet die Abweichung, statt
# darauf zu hoffen, dass jemand sie bemerkt. Es aendert NICHTS.
#
# *Why this exists: documentation that drifts from the system is worse than none,
#  because people act on it. This finds the drift instead of hoping someone
#  notices. It changes nothing.*
#
#   werkzeuge/abgleich.sh <ssh-ziel>
#
# Exit 0 = deckungsgleich, 1 = Abweichungen, 2 = Maschine nicht erreichbar.
set -uo pipefail

ZIEL="${1:-}"
[ -n "$ZIEL" ] || { echo "Aufruf: $0 <ssh-ziel>   (z.B. gameserver)"; exit 2; }

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KONF="$REPO/konfiguration.env"
[ -f "$KONF" ] || { echo "konfiguration.env fehlt — ohne sie sind die Platzhalter nicht aufloesbar."; exit 2; }
set -a; . "$KONF"; set +a

ssh -o ConnectTimeout=10 -o BatchMode=yes "$ZIEL" true 2>/dev/null \
  || { echo "Nicht erreichbar: $ZIEL"; exit 2; }

VARIABLEN=(DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER
           ADMIN_NETZ ADMIN_IP BORG_REPO BORG_TAILSCALE_IP FREMD_IPV4)

# Repo-Fassung mit eingesetzten Werten erzeugen (wie die Einrichtung es taete).
rendern() {
  local text v; text=$(cat "$1")
  for v in "${VARIABLEN[@]}"; do text=${text//@@${v}@@/${!v}}; done
  printf '%s\n' "$text"
}

# Paare "Repo-Datei : Serverpfad"
PAARE=(
  "bin/cf-dns:/usr/local/bin/cf-dns"
  "bin/katalog-vorpruefung:/usr/local/bin/katalog-vorpruefung"
  "bin/panel-aktion:/usr/local/bin/panel-aktion"
  "bin/spiel-einrichtung:/usr/local/bin/spiel-einrichtung"
  "bin/spiel-verwalten:/usr/local/bin/spiel-verwalten"
  "bin/spiele-sicherung:/usr/local/bin/spiele-sicherung"
  "etc/spiele-katalog.json:/etc/spiele-katalog.json"
  "etc/borg-ausschluss.txt:/etc/borg-ausschluss.txt"
  "etc/caddy/Caddyfile:/etc/caddy/Caddyfile"
  "etc/fail2ban/jail.local:/etc/fail2ban/jail.local"
  "etc/sudoers.d/panel:/etc/sudoers.d/panel"
  "panel/app.py:/opt/panel/app.py"
  "systemd/panel.service:/etc/systemd/system/panel.service"
  "systemd/ttyd.service:/etc/systemd/system/ttyd.service"
  "systemd/spiel-einrichtung.service:/etc/systemd/system/spiel-einrichtung.service"
  "systemd/spiel-einrichtung.timer:/etc/systemd/system/spiel-einrichtung.timer"
  "systemd/spiele-sicherung.service:/etc/systemd/system/spiele-sicherung.service"
  "systemd/spiele-sicherung.timer:/etc/systemd/system/spiele-sicherung.timer"
  "systemd/spiele-sicherung-voll.service:/etc/systemd/system/spiele-sicherung-voll.service"
  "systemd/spiele-sicherung-voll.timer:/etc/systemd/system/spiele-sicherung-voll.timer"
  "systemd/palworld-neustart.service:/etc/systemd/system/palworld-neustart.service"
  "systemd/palworld-neustart.timer:/etc/systemd/system/palworld-neustart.timer"
)

gleich=0; anders=0; fehlt=0
for p in "${PAARE[@]}"; do
  lokal="$REPO/${p%%:*}"; fern="${p#*:}"
  if ! ssh "$ZIEL" "test -f '$fern'" 2>/dev/null; then
    printf '  FEHLT auf dem Server  %s\n' "$fern"; fehlt=$((fehlt+1)); continue
  fi
  if diff -q <(rendern "$lokal") <(ssh "$ZIEL" "cat '$fern'") >/dev/null 2>&1; then
    gleich=$((gleich+1))
  else
    printf '  ABWEICHUNG            %s\n' "$fern"
    diff -u <(rendern "$lokal") <(ssh "$ZIEL" "cat '$fern'") \
      | sed -n '3,23p' | sed 's/^/      /'
    anders=$((anders+1))
  fi
done

echo
printf 'deckungsgleich: %d   abweichend: %d   fehlend: %d\n' "$gleich" "$anders" "$fehlt"
[ $((anders + fehlt)) -eq 0 ] || exit 1
