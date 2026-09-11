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

# Geschrieben wird nach /etc und /usr/local/bin - als root oder ueber sudo -n
# (#214). Ohne beides scheiterte frueher jede Datei einzeln mit "Permission
# denied", ohne zu sagen, dass es an der Anmeldung liegt (#192). ziel.sh prueft
# das einmal vorab und nennt beide Wege.
# *Writes as root or through sudo -n; ziel.sh checks once and names both ways.*
. "$(dirname "${BASH_SOURCE[0]}")/ziel.sh"
ziel_rechte

# Ziele, bei denen eine kaputte Datei SPAETER und hart zuschlaegt: Caddy liest
# die Caddyfile erst beim naechsten Neustart (Panel weg), sshd die Haertung
# ebenso (Aussperrung), sudo die Panel-Regel beim naechsten Aufruf (das Panel
# verliert seine Bruecke). Nach dem Tausch wird der Dienst gefragt, ob er die
# Datei annimmt; wenn nicht, kommt die gerade angelegte Sicherung zurueck (#204).
# Anlass: Die Caddyfile aus #202 importiert eine Datei, die nur Stufe 40 anlegt -
# allein ausgerollt, haette "caddy validate" sie abgelehnt, bemerkt erst nach dem
# naechsten Neustart.
# *Targets where a bad file bites later and hard. After the swap the service is
#  asked whether it accepts the file; if not, the just-made backup comes back.*
pruefbefehl() {
  case "$1" in
    /etc/caddy/Caddyfile)         echo "caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile" ;;
    /etc/ssh/sshd_config.d/*)     echo "sshd -t" ;;
    /etc/sudoers.d/*)             echo "visudo -cf '$1'" ;;
    *)                            echo "" ;;
  esac
}

VARIABLEN=(DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER
           ADMIN_NETZ ADMIN_IP BORG_REPO FREMD_IPV4
           SSH_PASSWORT_AUTH SSH_ROOT_LOGIN ZERTIFIKAT_WEG)

# Jeder Wert muss in konfiguration.env stehen. Fehlt einer, bricht ${!v} unter
# "set -u" ab, und JEDE Datei erschien als abweichend - nach #187 geschehen,
# weil zwei neue Werte in einer aelteren konfiguration.env fehlten (#189).
# *Every value must be set; a missing one made every file look different.*
for v in "${VARIABLEN[@]}"; do
  [ -n "${!v+x}" ] || { echo "konfiguration.env: $v fehlt - Vorlage: konfiguration.env.beispiel"; exit 2; }
done


# Repo-Pfad -> Serverpfad, Rechte, Eigentuemer
wohin() {
  case "$1" in
    bin/*)               echo "/usr/local/bin/${1#bin/} 0755 root:root" ;;
    panel/app.py)        echo "/opt/panel/app.py 0644 root:root" ;;
    etc/spiele-katalog.json) echo "/etc/spiele-katalog.json 0644 root:root" ;;
    etc/spiele-adressen.json) echo "/etc/spiele-adressen.json 0644 root:root" ;;
    etc/spiele-mods.json) echo "/etc/spiele-mods.json 0644 root:root" ;;
    etc/spiele-workshop.json) echo "/etc/spiele-workshop.json 0644 root:root" ;;
    # Die Symbole erzeugt werkzeuge/logo.py; sie gehoeren dem Panelnutzer,
    # weil bilder/ das einzige beschreibbare Verzeichnis des Panels ist.
    panel/bilder/*) echo "/opt/panel/bilder/${1#panel/bilder/} 0644 panel:panel" ;;
    etc/borg-ausschluss.txt) echo "/etc/borg-ausschluss.txt 0644 root:root" ;;
    etc/caddy/Caddyfile) echo "/etc/caddy/Caddyfile 0644 root:root" ;;
    etc/fail2ban/jail.local) echo "/etc/fail2ban/jail.local 0644 root:root" ;;
    etc/ssh/sshd_config.d/99-gameserver.conf) echo "/etc/ssh/sshd_config.d/99-gameserver.conf 0644 root:root" ;;
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

  # Binaerdateien gehen UNVERAENDERT hinueber. Der Weg darunter laeuft ueber
  # eine Kommandosubstitution, und die verwirft NULL-Bytes stillschweigend:
  # Am 2026-09-10 kam icon-192.png mit 11275 statt 11409 Byte an, "file" sagte
  # "data" statt "PNG image", und ausgerollt: stand daneben. Eine Warnung der
  # Shell gab es, aber der Rueckgabewert war 0.
  #
  # Ein Werkzeug, das stillschweigend beschaedigt, ist schlimmer als eins, das
  # abbricht. Geprueft wird trotzdem auf Platzhalter - mit "grep -a", denn die
  # Annahme "in einer Binaerdatei steht kein Platzhalter" soll eine gepruefte
  # Aussage sein und keine Vermutung.
  #
  # *Binary files are transferred verbatim: the path below goes through command
  #  substitution, which drops NUL bytes silently - a PNG arrived 134 bytes
  #  short and "file" called it data, while the tool printed success. A tool
  #  that corrupts silently is worse than one that refuses. Placeholders are
  #  still checked, with grep -a, so that "a binary holds no placeholder" is a
  #  measured statement rather than an assumption.*
  if LC_ALL=C grep -qI . "$quelle" 2>/dev/null; then
    binaer=0
  else
    binaer=1
  fi

  if [ $binaer -eq 1 ]; then
    if LC_ALL=C grep -aqE '@@[A-Z_]+@@' "$quelle"; then
      echo "ABBRUCH: $datei ist binaer und enthaelt einen Platzhalter."
      fehler=1; continue
    fi
    am_ziel_mit_eingabe "
      [ -f '$pfad' ] && cp -a '$pfad' '$pfad.vor-$(date +%Y%m%d-%H%M%S)'
      cat > '$pfad.neu' && chmod $modus '$pfad.neu' && chown $eigner '$pfad.neu' \
        && mv '$pfad.neu' '$pfad'" < "$quelle" \
      && { echo "ausgerollt: $datei -> $pfad (binaer, unveraendert)"; ausgerollt=1; } \
      || { echo "FEHLGESCHLAGEN: $datei"; fehler=1; }
    continue
  fi

  text=$(cat "$quelle")
  for v in "${VARIABLEN[@]}"; do text=${text//@@${v}@@/${!v}}; done
  # Ein uebrig gebliebener Platzhalter bricht ab. Genau das ist der Zweck.
  if grep -qE '@@[A-Z_]+@@' <<<"$text"; then
    echo "ABBRUCH: unersetzte Platzhalter in $datei:"
    grep -oE '@@[A-Z_]+@@' <<<"$text" | sort -u | sed 's/^/    /'
    fehler=1; continue
  fi

  # Sicherung auf der Maschine, dann atomar ersetzen - und wo es einen
  # Pruefbefehl gibt, den Dienst fragen; lehnt er ab, die Sicherung zurueck.
  pruef=$(pruefbefehl "$pfad")
  sicherung="$pfad.vor-$(date +%Y%m%d-%H%M%S)"
  printf '%s\n' "$text" | am_ziel_mit_eingabe "
    [ -f '$pfad' ] && cp -a '$pfad' '$sicherung'
    cat > '$pfad.neu' && chmod $modus '$pfad.neu' && chown $eigner '$pfad.neu' \
      && mv '$pfad.neu' '$pfad' || exit 1
    if [ -n \"$pruef\" ] && ! $pruef >/tmp/ausrollen-pruefung.txt 2>&1; then
      if [ -f '$sicherung' ]; then cp -a '$sicherung' '$pfad'; else rm -f '$pfad'; fi
      echo '  abgelehnt von: $pruef'; sed 's/^/    /' /tmp/ausrollen-pruefung.txt | tail -5
      rm -f /tmp/ausrollen-pruefung.txt; exit 3
    fi
    rm -f /tmp/ausrollen-pruefung.txt" \
    && { echo "ausgerollt: $datei -> $pfad${pruef:+ (geprueft: ${pruef%% *})}"; ausgerollt=1; } \
    || { echo "FEHLGESCHLAGEN: $datei - vorige Fassung bleibt bzw. ist zurueck"; fehler=1; }
done

# Ein neuer Katalog muss auch die schon installierten Spiele erreichen -
# Sicherungsausschluesse (#221) und fehlende Umgebungsvariablen (#153), dieselbe
# Angleichung wie Stufe 30.
# *A new catalogue must reach installed games' backup exclusions too.*
case " $* " in
  *" etc/spiele-katalog.json "*)
    am_ziel "[ -x /usr/local/bin/spiel-verwalten ] && /usr/local/bin/spiel-verwalten katalog-abgleich" \
      || { echo "FEHLGESCHLAGEN: Ausschluesse nicht angeglichen"; fehler=1; } ;;
esac

# Wurde etwas von Hand nachgerollt, stimmt der Versionsstempel nicht mehr genau:
# die Fassung ist noch dieselbe, aber einzelne Dateien sind neuer. Genau das ist
# spaeter die interessante Auskunft - "Version 1.0.0, aber da wurde noch
# nachgearbeitet" ist etwas anderes als "Version 1.0.0".
# *A hand-rolled file leaves the release name correct but individual files
#  newer. "1.0.0, but touched since" is a different answer from "1.0.0".*
if [ "${ausgerollt:-0}" -eq 1 ]; then
  am_ziel "[ -f /etc/gameserver-version ] && sed -i 's/^STAND=.*/STAND=geaendert/' /etc/gameserver-version" \
    || echo "Hinweis: kein Versionsstempel auf $ZIEL — Einrichtung lief vor der Versionierung."
fi

exit $fehler
