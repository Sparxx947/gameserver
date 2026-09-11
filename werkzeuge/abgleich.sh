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

# Liest nur - ohne root und ohne sudo -n laeuft es weiter, warnt aber: Dateien,
# die nur root lesen darf (sudoers, DNS-Zugang), erscheinen dann als abweichend.
# *Read-only: without root or sudo it continues, with a warning.*
. "$(dirname "${BASH_SOURCE[0]}")/ziel.sh"
ziel_rechte weich

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


# Repo-Fassung mit eingesetzten Werten erzeugen (wie die Einrichtung es taete).
rendern() {
  local text v; text=$(cat "$1")
  for v in "${VARIABLEN[@]}"; do text=${text//@@${v}@@/${!v}}; done
  printf '%s\n' "$text"
}

# Paare "Repo-Datei : Serverpfad"
PAARE=(
  "bin/dns-pflegen:/usr/local/bin/dns-pflegen"
  "bin/port-ermitteln:/usr/local/bin/port-ermitteln"
  "bin/katalog-vorpruefung:/usr/local/bin/katalog-vorpruefung"
  "bin/katalogbilder-holen:/usr/local/bin/katalogbilder-holen"
  "bin/konfig-datei:/usr/local/bin/konfig-datei"
  "bin/compose-feld:/usr/local/bin/compose-feld"
  "bin/panel-aktion:/usr/local/bin/panel-aktion"
  "bin/spiel-einrichtung:/usr/local/bin/spiel-einrichtung"
  "bin/kanal-verwalten:/usr/local/bin/kanal-verwalten"
  "bin/spiel-verwalten:/usr/local/bin/spiel-verwalten"
  "bin/spiele-sicherung:/usr/local/bin/spiele-sicherung"
  "etc/spiele-katalog.json:/etc/spiele-katalog.json"
  "etc/borg-ausschluss.txt:/etc/borg-ausschluss.txt"
  "etc/caddy/Caddyfile:/etc/caddy/Caddyfile"
  "etc/fail2ban/jail.local:/etc/fail2ban/jail.local"
  "etc/ssh/sshd_config.d/99-gameserver.conf:/etc/ssh/sshd_config.d/99-gameserver.conf"
  "etc/sudoers.d/panel:/etc/sudoers.d/panel"
  "panel/app.py:/opt/panel/app.py"
  "systemd/panel.service:/etc/systemd/system/panel.service"
  "systemd/ttyd.service:/etc/systemd/system/ttyd.service"
  "systemd/spiel-einrichtung.service:/etc/systemd/system/spiel-einrichtung.service"
  "systemd/spiel-einrichtung.timer:/etc/systemd/system/spiel-einrichtung.timer"
  "systemd/kanal-abgleich.service:/etc/systemd/system/kanal-abgleich.service"
  "systemd/kanal-abgleich.timer:/etc/systemd/system/kanal-abgleich.timer"
  "systemd/spiele-sicherung.service:/etc/systemd/system/spiele-sicherung.service"
  "systemd/spiele-sicherung.timer:/etc/systemd/system/spiele-sicherung.timer"
  "systemd/spiele-sicherung-voll.service:/etc/systemd/system/spiele-sicherung-voll.service"
  "systemd/spiele-sicherung-voll.timer:/etc/systemd/system/spiele-sicherung-voll.timer"
  "systemd/palworld-neustart.service:/etc/systemd/system/palworld-neustart.service"
  "systemd/palworld-neustart.timer:/etc/systemd/system/palworld-neustart.timer"
  "systemd/dns-ziel.service:/etc/systemd/system/dns-ziel.service"
  "systemd/dns-ziel.timer:/etc/systemd/system/dns-ziel.timer"
  "bin/spiele-autoupdate:/usr/local/bin/spiele-autoupdate"
  "bin/spiele-wiederanlauf:/usr/local/bin/spiele-wiederanlauf"
  "bin/platzwart-melden:/usr/local/bin/platzwart-melden"
  "bin/platzwart-wache:/usr/local/bin/platzwart-wache"
  "bin/spieler-zaehlen:/usr/local/bin/spieler-zaehlen"
  "bin/platzwart-status:/usr/local/bin/platzwart-status"
  "bin/platzwart-verlauf:/usr/local/bin/platzwart-verlauf"
  "bin/platzwart-schlaf:/usr/local/bin/platzwart-schlaf"
  "bin/mod-verwalten:/usr/local/bin/mod-verwalten"
  "bin/workshop:/usr/local/bin/workshop"
  "bin/sicherung-probe:/usr/local/bin/sicherung-probe"
  "etc/spiele-mods.json:/etc/spiele-mods.json"
  "etc/spiele-workshop.json:/etc/spiele-workshop.json"
  "systemd/spiele-autoupdate.service:/etc/systemd/system/spiele-autoupdate.service"
  "systemd/spiele-autoupdate.timer:/etc/systemd/system/spiele-autoupdate.timer"
  "systemd/spiele-wiederanlauf.service:/etc/systemd/system/spiele-wiederanlauf.service"
  "systemd/platzwart-wache.service:/etc/systemd/system/platzwart-wache.service"
  "systemd/platzwart-wache.timer:/etc/systemd/system/platzwart-wache.timer"
  "systemd/spieler-zaehlen.service:/etc/systemd/system/spieler-zaehlen.service"
  "systemd/spieler-zaehlen.timer:/etc/systemd/system/spieler-zaehlen.timer"
  "systemd/platzwart-status.service:/etc/systemd/system/platzwart-status.service"
  "systemd/platzwart-status.timer:/etc/systemd/system/platzwart-status.timer"
  "systemd/platzwart-verlauf.service:/etc/systemd/system/platzwart-verlauf.service"
  "systemd/platzwart-verlauf.timer:/etc/systemd/system/platzwart-verlauf.timer"
  "systemd/platzwart-schlaf.service:/etc/systemd/system/platzwart-schlaf.service"
  "systemd/platzwart-schlaf.timer:/etc/systemd/system/platzwart-schlaf.timer"
  "systemd/platzwart-wecken@.service:/etc/systemd/system/platzwart-wecken@.service"
  "etc/spiele-adressen.json:/etc/spiele-adressen.json"
)
# Diese Liste wird VON HAND gepflegt, und genau daran ist sie gescheitert: Sie
# wuchs nicht mit, als spiele-autoupdate und spiele-wiederanlauf dazukamen. Neun
# ausgerollte Dateien wurden nie verglichen, und der Lauf meldete trotzdem
# "abweichend: 0" - eine Zahl, die wie "alles stimmt" aussieht und "alles, was
# ich zufaellig ansehe, stimmt" bedeutet.
# vollstaendigkeit.sh prueft seit dem 2026-09-10, dass jede von install/
# ausgerollte Datei hier steht. Wer eine hinzufuegt, laeuft dort auf.
# *Hand-maintained, and that is exactly how it failed: it did not grow when
#  auto-update and restart-recovery arrived. Nine deployed files were never
#  compared while the run still reported zero deviations.*

# Manche Dateien gehoeren nur auf manche Maschinen (#196): die Palworld-
# Neustartzeitgeber nur dorthin, wo Palworld installiert ist, der dns-ziel-
# Zeitgeber nur zu SERVER_IPV4=dynamic. Die Liste kannte nur "muss da sein" -
# "0 fehlend" war damit auf fast jeder Maschine unerreichbar, und eine Zahl,
# die immer "2, wie immer" sagt, uebersieht die dritte. Fehlt eine solche Datei
# dort, wo sie nicht gilt, heisst das "entfaellt"; ist sie trotzdem da, wird
# sie verglichen wie jede andere.
# *Some files belong on some machines only. Absent where they do not apply
#  counts as "not applicable", not "missing"; present, they are compared.*
PALWORLD_DA=$(am_ziel 'test -d /opt/stacks/palworld && echo ja' 2>/dev/null || true)
gilt_hier() {
  case "$1" in
    /etc/systemd/system/palworld-neustart.*) [ "$PALWORLD_DA" = ja ] ;;
    /etc/systemd/system/dns-ziel.*)          [ "$SERVER_IPV4" = dynamic ] ;;
    *)                                       return 0 ;;
  esac
}

gleich=0; anders=0; fehlt=0; entfaellt=0
for p in "${PAARE[@]}"; do
  lokal="$REPO/${p%%:*}"; fern="${p#*:}"
  if ! am_ziel "test -f '$fern'" 2>/dev/null; then
    if gilt_hier "$fern"; then
      printf '  FEHLT auf dem Server  %s\n' "$fern"; fehlt=$((fehlt+1))
    else
      printf '  entfaellt hier        %s\n' "$fern"; entfaellt=$((entfaellt+1))
    fi
    continue
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
    lv=$(rendern "$lokal" | entblocken); fv=$(am_ziel "cat '$fern'" | entblocken)
    if [ "$lv" = "$fv" ]; then gleich=$((gleich+1)); else
      echo "  ABWEICHUNG            $fern"
      diff -u <(printf '%s\n' "$lv") <(printf '%s\n' "$fv") | sed -n '3,23p' | sed 's/^/      /'
      anders=$((anders+1))
    fi
    continue
  fi
  if diff -q <(rendern "$lokal") <(am_ziel "cat '$fern'") >/dev/null 2>&1; then
    gleich=$((gleich+1))
  else
    printf '  ABWEICHUNG            %s\n' "$fern"
    diff -u <(rendern "$lokal") <(am_ziel "cat '$fern'") \
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
if ! diff -q <(am_ziel '/opt/panel/venv/bin/pip list --format=freeze' 2>/dev/null) \
              "$REPO/panel/requirements.txt" >/dev/null 2>&1; then
  echo "  ABWEICHUNG            panel/requirements.txt <-> venv auf dem Server"
  diff -u "$REPO/panel/requirements.txt" \
          <(am_ziel '/opt/panel/venv/bin/pip list --format=freeze') \
    | sed -n '3,23p' | sed 's/^/      /'
  anders=$((anders+1))
else
  gleich=$((gleich+1))
fi

# 2. ttyd — die Version ist in Stufe 40 festgeschrieben, das Binary kommt aber
#    von GitHub und nicht aus diesem Repositorium.
SOLL=$(grep -oE 'TTYD_VERSION="[0-9.]+"' "$REPO/install/40-caddy-ttyd.sh" | grep -oE '[0-9.]+')
IST=$(am_ziel '/usr/local/bin/ttyd --version 2>/dev/null' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ "$SOLL" != "$IST" ]; then
  echo "  ABWEICHUNG            ttyd: Repo verlangt $SOLL, Server hat ${IST:-nichts}"
  anders=$((anders+1))
else
  gleich=$((gleich+1))
fi

# 2b. Der Zertifikatsweg. /etc/caddy/zertifikat.conf und das systemd-Drop-in
#     werden von Stufe 40 ERZEUGT, nicht eingesetzt - ein byteweiser Vergleich
#     gegen eine Repo-Datei gibt es also nicht. Verglichen wird stattdessen, ob
#     die Maschine den Weg faehrt, den ZERTIFIKAT_WEG nennt.
#
#     Das ist hier kein Formalismus: Faellt eine Maschine von dns-01 auf http-01
#     zurueck - weil das Drop-in fehlt, weil ein Paket-Update den Dienst wieder
#     auf /usr/bin/caddy zeigen laesst -, dann laeuft alles weiter und sieht
#     richtig aus. Bemerkt wird es, wenn das Zertifikat nach 60 Tagen nicht
#     erneuert wird.
# *Both files are generated, so there is no byte comparison; what is compared is
#  whether the machine runs the path ZERTIFIKAT_WEG names. A machine that falls
#  back to http-01 keeps working and looks right - until renewal fails 60 days
#  later.*
zert_ist=$(am_ziel 'cat /etc/caddy/zertifikat.conf 2>/dev/null' || true)
if [ "$ZERTIFIKAT_WEG" = "dns-01" ]; then
  zert_anbieter=$(am_ziel "sed -n 's/^[[:space:]]*ANBIETER[[:space:]]*=[[:space:]]*//p' /etc/dns-gameserver.conf 2>/dev/null" | head -1)
  laeuft=$(am_ziel 'systemctl show caddy -p ExecStart --value' 2>/dev/null)
  if ! grep -q "^acme_dns ${zert_anbieter} " <<<"$zert_ist"; then
    echo "  ABWEICHUNG            zertifikat.conf nennt kein \"acme_dns $zert_anbieter\" — Caddy holt ueber Port 80"
    anders=$((anders+1))
  elif ! grep -q "/usr/local/bin/caddy" <<<"$laeuft"; then
    echo "  ABWEICHUNG            caddy laeuft aus dem Paket, nicht der Bau mit DNS-Modul — acme_dns wirkt nicht"
    anders=$((anders+1))
  elif grep -q -- "--environ" <<<"$laeuft"; then
    echo "  ABWEICHUNG            caddy laeuft mit --environ — der DNS-Token landet im Journal"
    anders=$((anders+1))
  else
    gleich=$((gleich+1))
  fi
elif [ -n "$zert_ist" ]; then
  echo "  ABWEICHUNG            ZERTIFIKAT_WEG=http-01, aber zertifikat.conf ist nicht leer"
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
  if ! am_ziel "cat /opt/panel/bilder/$bild" 2>/dev/null | cmp -s - "$REPO/panel/bilder/$bild"; then
    echo "  ABWEICHUNG            panel/bilder/$bild"
    anders=$((anders+1))
  else
    gleich=$((gleich+1))
  fi
done
for bild in "$REPO"/panel/bilder/eigene/*.jpg; do
  [ -e "$bild" ] || continue
  name=$(basename "$bild")
  if ! am_ziel "cat /opt/panel/bilder/eigene/$name" 2>/dev/null | cmp -s - "$bild"; then
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
if am_ziel "/usr/local/bin/katalogbilder-holen --pruefen" 2>/dev/null | grep -q "0 fehlen"; then
  gleich=$((gleich+1))
else
  echo "  ABWEICHUNG            Katalogbilder: $(am_ziel '/usr/local/bin/katalogbilder-holen --pruefen' 2>/dev/null)"
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
STEMPEL=$(am_ziel 'cat /etc/gameserver-version 2>/dev/null' || true)
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
IST_ZG=$(am_ziel 'systemctl is-enabled dns-ziel.timer 2>/dev/null' || true)
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
  if ausgabe=$(am_ziel '/usr/local/bin/dns-pflegen ziel-zeigen' 2>&1); then
    gleich=$((gleich+1))
  else
    echo "  ABWEICHUNG            A-Eintrag und gemessene Adresse gehen auseinander"
    sed 's/^/      /' <<<"$ausgabe"
    anders=$((anders+1))
  fi
fi

# 8. Zustand der Sicherungs-Timer. Die Einheiten liegen auch bei abgeschalteter
#    Sicherung auf der Maschine — der Dateivergleich sieht dann tadellos aus,
#    waehrend nichts gesichert wird. Was zaehlt, ist ob sie LAUFEN.
# *The units are installed even with backups off, so the file comparison looks
#  perfect while nothing is backed up. What counts is whether they run.*
if [ "$BORG_REPO" = "aus" ]; then SOLL_SI=disabled; else SOLL_SI=enabled; fi
for u in spiele-sicherung.timer spiele-sicherung-voll.timer; do
  IST_SI=$(am_ziel "systemctl is-enabled $u 2>/dev/null" || true)
  if [ "$IST_SI" != "$SOLL_SI" ]; then
    echo "  ABWEICHUNG            $u: BORG_REPO=$BORG_REPO verlangt $SOLL_SI, Server meldet ${IST_SI:-nichts}"
    anders=$((anders+1))
  else
    gleich=$((gleich+1))
  fi
done

# 9. Die Gegenrichtung: was liegt in /usr/local/bin, das hier niemand kennt?
#
#    Alles bisher Gepruefte geht von der Tabelle aus und fragt, ob es auf der
#    Maschine steht. Eine Datei, die dort liegt und in der Tabelle GAR NICHT
#    mehr vorkommt, sieht dabei nie jemand an. Nach einer Umbenennung bleibt der
#    alte Name deshalb liegen, ist lauffuehrbar, wird von niemandem mehr
#    gepflegt — und der Abgleich meldet "alles in Ordnung". Dieselbe Luecke, die
#    rueckbau.sh mit ALTLASTEN schliessen musste: eine Ableitung aus dem
#    Repositorium kennt nur die Gegenwart.
#
#    Gemeldet wird das als HINWEIS und nicht als Abweichung: auf der Maschine
#    darf es Werkzeuge geben, die mit diesem Repositorium nichts zu tun haben.
#    Eine Abweichung waere hier eine Meldung, die man sich abgewoehnt zu lesen.
#
# *The other direction: everything so far starts from the table and asks whether
#  it exists on the machine. A file that lies there and appears nowhere in the
#  table is never looked at, so a renamed tool stays behind, runnable and
#  unmaintained, while the comparison reports "fine". Reported as a hint, not a
#  deviation: the machine may legitimately carry foreign tools.*
erwartet=$(mktemp)
{ printf '%s\n' "${PAARE[@]}" | sed -n 's|.*:/usr/local/bin/||p'
  echo ttyd            # kommt von GitHub, liegt aber am selben Ort
} | LC_ALL=C sort -u > "$erwartet"
# LC_ALL=C (#196): Die deutsche Sortierung uebergeht Bindestriche, die C-Sortierung
# nicht - und die Werkzeugnamen stecken voller Bindestriche. comm warnte bei jedem
# Lauf, und sein Ergebnis war damit undefiniert. vollstaendigkeit.sh macht es an
# derselben Stelle schon so.
# *Pinned collation: German sorting ignores hyphens, comm then warns and its
#  result is undefined.*
fremd=$(am_ziel 'ls -1 /usr/local/bin 2>/dev/null' | LC_ALL=C sort | LC_ALL=C comm -23 - "$erwartet")
rm -f "$erwartet"
if [ -n "$fremd" ]; then
  echo
  echo "-- In /usr/local/bin, aber in keiner Stufe --"
  while read -r f; do
    [ -n "$f" ] || continue
    printf '  HINWEIS               /usr/local/bin/%s\n' "$f"
  done <<<"$fremd"
  echo "  (kein Fehler — aber nach einer Umbenennung steht der alte Name hier)"
fi

echo
printf 'deckungsgleich: %d   abweichend: %d   fehlend: %d' "$gleich" "$anders" "$fehlt"
# "entfaellt" nur, wenn es etwas gibt - die Zeile bleibt fuer alles, was sie
# liest, dieselbe (#196).
[ "$entfaellt" -gt 0 ] && printf '   entfaellt hier: %d' "$entfaellt"
printf '\n'
[ $((anders + fehlt)) -eq 0 ] || exit 1
