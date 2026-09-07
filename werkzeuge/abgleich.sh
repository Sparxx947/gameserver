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
  "bin/katalogbilder-holen:/usr/local/bin/katalogbilder-holen"
  "bin/konfig-datei:/usr/local/bin/konfig-datei"
  "bin/compose-feld:/usr/local/bin/compose-feld"
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
  "systemd/dns-ziel.service:/etc/systemd/system/dns-ziel.service"
  "systemd/dns-ziel.timer:/etc/systemd/system/dns-ziel.timer"
)

gleich=0; anders=0; fehlt=0
for p in "${PAARE[@]}"; do
  lokal="$REPO/${p%%:*}"; fern="${p#*:}"
  if ! ssh "$ZIEL" "test -f '$fern'" 2>/dev/null; then
    printf '  FEHLT auf dem Server  %s\n' "$fern"; fehlt=$((fehlt+1)); continue
  fi
  # Die Ausschlussliste traegt zur Laufzeit angehaengte Bloecke je installiertem
  # Spiel ("# >>> panel:<name> ... # <<< panel:<name>"). Sie beschreiben den
  # Bestand DIESER Maschine, nicht den Bauplan — beim Vergleich also ausblenden,
  # sonst schlaegt der Abgleich nach jeder Installation an und man gewoehnt sich
  # daran, ihn zu uebergehen.
  # *The exclusion list gains runtime blocks per installed game. They describe
  #  this machine's inventory, not the blueprint — filtered out here, otherwise
  #  the comparison fires after every install and people learn to ignore it.*
  entblocken() { sed '/^# >>> panel:/,/^# <<< panel:/d'; }
  if [ "$fern" = "/etc/borg-ausschluss.txt" ]; then
    lv=$(rendern "$lokal" | entblocken); fv=$(ssh "$ZIEL" "cat '$fern'" | entblocken)
    if [ "$lv" = "$fv" ]; then gleich=$((gleich+1)); else
      echo "  ABWEICHUNG            $fern"
      diff -u <(printf '%s\n' "$lv") <(printf '%s\n' "$fv") | sed -n '3,23p' | sed 's/^/      /'
      anders=$((anders+1))
    fi
    continue
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

# --- Was kein einfacher Dateivergleich ist -----------------------------------
# Mehrere Dinge gehoeren zur Reproduktion, liegen auf dem Server aber nicht als
# Datei gleichen Inhalts vor. Sie fehlten hier zunaechst — aufgefallen ist das
# erst, als ein Dependabot-PR requirements.txt aenderte und ich den Abgleich von
# Hand nachziehen musste. Eine Pruefung, die einen Bereich gar nicht ansieht,
# meldet ihn als in Ordnung.
# *Several things belong to the reproduction but do not exist as identical files on
#  the server. They were missing here at first, and it only showed when a
#  Dependabot PR changed requirements.txt and the comparison had to be done by
#  hand. A check that never looks at an area reports it as fine.*
echo
echo "-- Weiteres --"

# 1. Python-Umgebung des Panels
if ! diff -q <(ssh "$ZIEL" '/opt/panel/venv/bin/pip list --format=freeze' 2>/dev/null) \
              "$REPO/panel/requirements.txt" >/dev/null 2>&1; then
  echo "  ABWEICHUNG            panel/requirements.txt <-> venv auf dem Server"
  diff -u "$REPO/panel/requirements.txt" \
          <(ssh "$ZIEL" '/opt/panel/venv/bin/pip list --format=freeze') \
    | sed -n '3,23p' | sed 's/^/      /'
  anders=$((anders+1))
else
  gleich=$((gleich+1))
fi

# 2. ttyd — die Version ist in Stufe 40 festgeschrieben, das Binary kommt aber
#    von GitHub und nicht aus diesem Repositorium.
SOLL=$(grep -oE 'TTYD_VERSION="[0-9.]+"' "$REPO/install/40-caddy-ttyd.sh" | grep -oE '[0-9.]+')
IST=$(ssh "$ZIEL" '/usr/local/bin/ttyd --version 2>/dev/null' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ "$SOLL" != "$IST" ]; then
  echo "  ABWEICHUNG            ttyd: Repo verlangt $SOLL, Server hat ${IST:-nichts}"
  anders=$((anders+1))
else
  gleich=$((gleich+1))
fi

# 3. Die selbst erzeugten Symbole und Titelbilder. Die Steam-Header unter
#    bilder/katalog werden bewusst NICHT verglichen: sie sind Werke Dritter,
#    liegen nicht im Repositorium und werden zur Laufzeit geholt.
# *The self-made icons and artwork. Steam headers under bilder/katalog are
#  deliberately not compared: third-party works, fetched at runtime.*
for bild in favicon.svg favicon.ico apple-touch-icon.png; do
  if ! ssh "$ZIEL" "cat /opt/panel/bilder/$bild" 2>/dev/null | cmp -s - "$REPO/panel/bilder/$bild"; then
    echo "  ABWEICHUNG            panel/bilder/$bild"
    anders=$((anders+1))
  else
    gleich=$((gleich+1))
  fi
done
for bild in "$REPO"/panel/bilder/eigene/*.jpg; do
  [ -e "$bild" ] || continue
  name=$(basename "$bild")
  if ! ssh "$ZIEL" "cat /opt/panel/bilder/eigene/$name" 2>/dev/null | cmp -s - "$bild"; then
    echo "  ABWEICHUNG            panel/bilder/eigene/$name"
    anders=$((anders+1))
  else
    gleich=$((gleich+1))
  fi
done

# 4. Vollstaendigkeit der Katalogbilder. Nicht Datei fuer Datei - die Bilder
#    kommen von Steam und stehen nicht im Repositorium. Geprueft wird nur, ob
#    zu JEDEM Katalogeintrag eines vorliegt: genau das fehlte, und es fiel erst
#    auf, als bei Minecraft die Kachel leer blieb.
# *Not file by file - the images are not in the repository. Only whether every
#  catalogue entry has one: exactly that was missing, and it surfaced only when
#  Minecraft's tile stayed blank.*
if ssh "$ZIEL" "/usr/local/bin/katalogbilder-holen --pruefen" 2>/dev/null | grep -q "0 fehlen"; then
  gleich=$((gleich+1))
else
  echo "  ABWEICHUNG            Katalogbilder: $(ssh "$ZIEL" '/usr/local/bin/katalogbilder-holen --pruefen' 2>/dev/null)"
  anders=$((anders+1))
fi

# 5. Die ausgerollte Fassung. Erzeugt, nicht kopiert - deshalb keine Zeile in
#    PAARE, sondern eine eigene Pruefung wie bei ttyd.
#
#    STAND=geaendert zaehlt BEWUSST NICHT als Abweichung. Einzelne Dateien mit
#    ausrollen.sh nachzuziehen ist der vorgesehene Arbeitsweg; das jedes Mal als
#    Abweichung zu melden hiesse, eine Meldung zu erzeugen, die man sich
#    abgewoehnt zu lesen. Was tatsaechlich abweicht, findet der Dateivergleich
#    oben ohnehin genau.
# *Generated, not copied, so it gets its own check. STAND=geaendert deliberately
#  does not count as a deviation: rolling out single files is the intended
#  workflow, and reporting it every time would train people to ignore the
#  message. Actual drift is found precisely by the file comparison above.*
SOLL_V=$(cat "$REPO/VERSION" 2>/dev/null || echo unbekannt)
STEMPEL=$(ssh "$ZIEL" 'cat /etc/gameserver-version 2>/dev/null' || true)
IST_V=$(grep -m1 '^VERSION=' <<<"$STEMPEL" | cut -d= -f2)
IST_STAND=$(grep -m1 '^STAND=' <<<"$STEMPEL" | cut -d= -f2)
IST_COMMIT=$(grep -m1 '^COMMIT=' <<<"$STEMPEL" | cut -d= -f2)
if [ -z "$STEMPEL" ]; then
  echo "  ABWEICHUNG            /etc/gameserver-version fehlt — Einrichtung lief vor der Versionierung"
  anders=$((anders+1))
elif [ "$SOLL_V" != "$IST_V" ]; then
  echo "  ABWEICHUNG            Fassung: Repo hat $SOLL_V, Server hat ${IST_V:-nichts}"
  anders=$((anders+1))
else
  gleich=$((gleich+1))
  printf '  Fassung %s (Commit %s, Stand: %s)\n' "$IST_V" "${IST_COMMIT:-?}" "${IST_STAND:-?}"
  [ "$IST_STAND" = "geaendert" ] && echo "    seit der letzten vollen Einrichtung wurden einzelne Dateien nachgerollt"
fi

# 6. Der Zeitgeber fuer den A-Eintrag. Die Datei allein sagt nichts darueber,
#    ob er auch laeuft — und genau das ist der Unterschied zwischen fester und
#    wechselnder Adresse. Ein eingesetzter, aber abgeschalteter Zeitgeber sieht
#    im Dateivergleich tadellos aus und laesst die Adresse trotzdem veralten.
# *The file alone says nothing about whether the timer runs, and that is exactly
#  what separates fixed from dynamic mode. An installed but disabled timer looks
#  perfect in a file comparison while the address goes stale.*
if [ "$SERVER_IPV4" = "dynamic" ]; then SOLL_ZG=enabled; else SOLL_ZG=disabled; fi
IST_ZG=$(ssh "$ZIEL" 'systemctl is-enabled dns-ziel.timer 2>/dev/null' || true)
if [ "$IST_ZG" != "$SOLL_ZG" ]; then
  echo "  ABWEICHUNG            dns-ziel.timer: SERVER_IPV4=$SERVER_IPV4 verlangt $SOLL_ZG, Server meldet ${IST_ZG:-nichts}"
  anders=$((anders+1))
else
  gleich=$((gleich+1))
fi

# 7. Bei wechselnder Adresse: stimmt der A-Eintrag noch mit der tatsaechlichen
#    Adresse ueberein? Gemessen wird auf dem Server, weil nur dort die richtige
#    Leitung nach draussen liegt — von hier aus misst man die eigene.
# *In dynamic mode, does the A record still match the real address? Measured on
#  the server: from here one would measure this machine's address instead.*
if [ "$SERVER_IPV4" = "dynamic" ]; then
  if ausgabe=$(ssh "$ZIEL" '/usr/local/bin/cf-dns ziel-zeigen' 2>&1); then
    gleich=$((gleich+1))
  else
    echo "  ABWEICHUNG            A-Eintrag und gemessene Adresse gehen auseinander"
    sed 's/^/      /' <<<"$ausgabe"
    anders=$((anders+1))
  fi
fi

echo
printf 'deckungsgleich: %d   abweichend: %d   fehlend: %d\n' "$gleich" "$anders" "$fehlt"
[ $((anders + fehlt)) -eq 0 ] || exit 1
