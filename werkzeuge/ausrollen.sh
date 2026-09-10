#!/bin/bash
# ausrollen.sh — bringt Repo-Dateien mit eingesetzten Platzhaltern auf die Maschine.
#
# Warum es das gibt: Zweimal an einem Tag habe ich eine Datei mit scp direkt
# kopiert und dabei die @@PLATZHALTER@@ mitgeschickt — einmal den Spielekatalog
# (der Weltname stand danach als "@@WELT_NAME@@" auf dem Server), einmal
# panel-aktion (das Borg-Repository war weg). Beide Male hat abgleich.sh es
# gefunden, beide Male war es vermeidbar: Die Ersetzung von Hand zu tippen ist
# der Fehler, nicht das Vergessen.
#
# *Why this exists: twice in one day a file was scp'd straight across with its
#  @@PLACEHOLDERS@@ intact. Both times the comparison tool caught it; both times
#  it was avoidable. Retyping the substitution by hand is the mistake, not
#  forgetting it.*
#
#   werkzeuge/ausrollen.sh <ssh-ziel> <repo-datei> [<repo-datei> ...]
#   werkzeuge/ausrollen.sh gameserver bin/panel-aktion panel/app.py
#
# Das Ziel auf der Maschine und die Rechte stehen in derselben Tabelle, die
# abgleich.sh benutzt — es gibt nur EINE Wahrheit darueber, wohin was gehoert.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KONF="$REPO/konfiguration.env"
[ -f "$KONF" ] || { echo "konfiguration.env fehlt"; exit 2; }
set -a; . "$KONF"; set +a

ZIEL="${1:-}"; shift || true
[ -n "$ZIEL" ] && [ $# -gt 0 ] || { echo "Aufruf: $0 <ssh-ziel> <repo-datei> [...]"; exit 2; }

VARIABLEN=(DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER
           ADMIN_NETZ ADMIN_IP BORG_REPO BORG_TAILSCALE_IP FREMD_IPV4)

# Repo-Pfad -> Serverpfad, Rechte, Eigentuemer
wohin() {
  case "$1" in
    bin/*)               echo "/usr/local/bin/${1#bin/} 0755 root:root" ;;
    panel/app.py)        echo "/opt/panel/app.py 0644 root:root" ;;
    etc/spiele-katalog.json) echo "/etc/spiele-katalog.json 0644 root:root" ;;
    etc/spiele-adressen.json) echo "/etc/spiele-adressen.json 0644 root:root" ;;
    etc/borg-ausschluss.txt) echo "/etc/borg-ausschluss.txt 0644 root:root" ;;
    etc/caddy/Caddyfile) echo "/etc/caddy/Caddyfile 0644 root:root" ;;
    etc/fail2ban/jail.local) echo "/etc/fail2ban/jail.local 0644 root:root" ;;
    etc/sudoers.d/panel) echo "/etc/sudoers.d/panel 0440 root:root" ;;
    systemd/*)           echo "/etc/systemd/system/${1#systemd/} 0644 root:root" ;;
    *) return 1 ;;
  esac
}

fehler=0
for datei in "$@"; do
  quelle="$REPO/$datei"
  [ -f "$quelle" ] || { echo "FEHLT: $datei"; fehler=1; continue; }
  if ! read -r pfad modus eigner < <(wohin "$datei"); then
    echo "UNBEKANNT wohin: $datei"; fehler=1; continue
  fi

  text=$(cat "$quelle")
  for v in "${VARIABLEN[@]}"; do text=${text//@@${v}@@/${!v}}; done
  # Ein uebrig gebliebener Platzhalter bricht ab. Genau das ist der Zweck.
  if grep -qE '@@[A-Z_]+@@' <<<"$text"; then
    echo "ABBRUCH: unersetzte Platzhalter in $datei:"
    grep -oE '@@[A-Z_]+@@' <<<"$text" | sort -u | sed 's/^/    /'
    fehler=1; continue
  fi

  # Sicherung auf der Maschine, dann atomar ersetzen.
  printf '%s\n' "$text" | ssh "$ZIEL" "
    [ -f '$pfad' ] && cp -a '$pfad' '$pfad.vor-$(date +%Y%m%d-%H%M%S)'
    cat > '$pfad.neu' && chmod $modus '$pfad.neu' && chown $eigner '$pfad.neu' \
      && mv '$pfad.neu' '$pfad'" \
    && { echo "ausgerollt: $datei -> $pfad"; ausgerollt=1; } \
    || { echo "FEHLGESCHLAGEN: $datei"; fehler=1; }
done

# Wurde etwas von Hand nachgerollt, stimmt der Versionsstempel nicht mehr genau:
# die Fassung ist noch dieselbe, aber einzelne Dateien sind neuer. Genau das ist
# spaeter die interessante Auskunft - "Version 1.0.0, aber da wurde noch
# nachgearbeitet" ist etwas anderes als "Version 1.0.0".
# *A hand-rolled file leaves the release name correct but individual files
#  newer. "1.0.0, but touched since" is a different answer from "1.0.0".*
if [ "${ausgerollt:-0}" -eq 1 ]; then
  ssh "$ZIEL" "[ -f /etc/gameserver-version ] && sed -i 's/^STAND=.*/STAND=geaendert/' /etc/gameserver-version" \
    || echo "Hinweis: kein Versionsstempel auf $ZIEL — Einrichtung lief vor der Versionierung."
fi

exit $fehler
