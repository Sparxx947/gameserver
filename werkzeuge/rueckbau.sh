#!/bin/bash
# rueckbau.sh — entfernt von einer Maschine wieder, was dieses Repositorium
# dort einbaut. Das Gegenstueck zu install/einrichten.sh.
#
# Warum es das gibt: Der Rueckweg stand bisher nur als Befehlsliste in
# docs/02-installation.md — und war abgedriftet. Er loeschte keine einzige
# systemd-Einheit, liess Caddyfile, fail2ban-Regel, das Cloudflare-Token und die
# Systembenutzer stehen, und in der Liste der Werkzeuge fehlten zwei. Eine
# Anleitung, die man abtippt und die dabei die Haelfte uebrig laesst, ist
# schlimmer als keine: man haelt die Maschine danach fuer sauber.
#
# Zwei Listen erzeugt dieses Skript deshalb AUS DEM REPOSITORIUM selbst — die
# systemd-Einheiten aus systemd/ und die Werkzeuge aus bin/. Damit koennen genau
# die beiden Kategorien nicht mehr auseinanderlaufen, in denen die Anleitung
# falsch war. Wer eine Einheit hinzufuegt, braucht hier nichts nachzutragen.
#
# *Why this exists: the teardown existed only as a command list in the
#  documentation, and it had drifted — it removed no systemd unit at all, left
#  the Caddyfile, the fail2ban rule, the Cloudflare token and the system users
#  behind, and its tool list was missing two entries. Instructions that leave
#  half of it standing are worse than none: the machine looks clean afterwards.
#  Two of the lists are therefore derived from the repository itself, so the two
#  categories that were wrong cannot drift again.*
#
#   werkzeuge/rueckbau.sh <ssh-ziel> [Stufen] [--wirklich]
#
#     ohne --wirklich    zeigt nur, was geschehen WUERDE. Aendert nichts.
#     --mit-spielstaenden  auch /opt/stacks, /srv/games und /srv/dienste
#     --mit-benutzern      auch die Systembenutzer panel und spiele
#     --mit-dns            auch die CNAMEs bei Cloudflare und das Token
#
# Exit 0 = durch, 1 = einzelne Schritte fehlgeschlagen, 2 = gar nicht erst los.
set -uo pipefail

ZIEL=""; WIRKLICH=0; MIT_SPIEL=0; MIT_NUTZER=0; MIT_DNS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wirklich)          WIRKLICH=1 ;;
    --mit-spielstaenden) MIT_SPIEL=1 ;;
    --mit-benutzern)     MIT_NUTZER=1 ;;
    --mit-dns)           MIT_DNS=1 ;;
    -*) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    *)  [ -z "$ZIEL" ] || { echo "Nur ein Ziel angeben." >&2; exit 2; }; ZIEL="$1" ;;
  esac
  shift
done
[ -n "$ZIEL" ] || { cat >&2 <<TEXT
Aufruf: $0 <ssh-ziel> [--mit-spielstaenden] [--mit-benutzern] [--mit-dns] [--wirklich]

Ohne --wirklich wird nur gezeigt, was geschehen wuerde.
TEXT
exit 2; }

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KONF="$REPO/konfiguration.env"
[ -f "$KONF" ] || { echo "konfiguration.env fehlt — ohne sie ist nicht bekannt, was zu dieser Maschine gehoert."; exit 2; }
set -a; . "$KONF"; set +a

# -n: ssh darf die Standardeingabe NICHT lesen. Sonst frisst der erste Aufruf
# die Antwort weg, die weiter unten als Bestaetigung abgefragt wird.
# *ssh must not consume stdin, or the first call eats the confirmation answer.*
fern() { ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "$@"; }
fern true 2>/dev/null || { echo "Nicht erreichbar: $ZIEL"; exit 2; }

# Die Befehle gehen UNVERPACKT hinueber - "systemctl disable", "rm -rf
# /opt/stacks", "docker compose down". Als gewoehnlicher Benutzer scheitert
# davon fast alles, und das Werkzeug lief bisher trotzdem bis zum Ende durch:
# gemessen 77 von 89 Schritten FEHLGESCHLAGEN, danach eine ordentliche
# Zusammenfassung und eine Gegenprobe. Das liest sich wie ein halber Rueckbau
# und ist in Wirklichkeit eine fehlende Voraussetzung - eine Unterscheidung, die
# man aus 77 gleichlautenden Zeilen nicht herausliest.
#
# Geprueft wird deshalb hier, in einem Satz, bevor irgendetwas passiert. Das
# Vorbild steht in install/lib.sh, das sich mit "Als root ausfuehren" weigert.
#
# *Commands go across unwrapped, so as an ordinary user almost everything fails
#  - measured 77 of 89 steps, after which the tool still printed a tidy summary.
#  That reads like a partial teardown and is actually a missing precondition.
#  Checked here in one sentence, the way install/lib.sh refuses to start.*
if [ "$(fern 'id -u' 2>/dev/null)" != "0" ]; then
  cat >&2 <<TEXT
FEHLER: $ZIEL meldet sich nicht als root an.

  Dieses Werkzeug schickt systemctl-, rm- und docker-Befehle ohne sudo ueber
  SSH. Ohne root scheitert fast jeder Schritt einzeln, waehrend der Lauf
  weiterlaeuft und am Ende eine Zusammenfassung druckt.

  Ein Ziel mit root-Anmeldung verwenden, zum Beispiel root@<maschine> oder
  einen Eintrag in ~/.ssh/config mit "User root". Auf der Maschine muss dafuer
  PermitRootLogin eine Schluesselanmeldung zulassen (SSH_ROOT_LOGIN, siehe
  docs/06-netz-dns-firewall.md).
TEXT
  exit 2
fi

geplant=0; getan=0; fehlschlaege=0
schritt() {   # schritt <beschreibung> <befehl>
  local text="$1" befehl="$2"
  if [ "$WIRKLICH" -eq 0 ]; then
    printf '  %-46s %s\n' "$text" "$befehl"; geplant=$((geplant+1)); return 0
  fi
  printf '  %-46s ' "$text"
  if fern "$befehl" >/dev/null 2>&1; then echo "ok"; getan=$((getan+1))
  else echo "FEHLGESCHLAGEN"; fehlschlaege=$((fehlschlaege+1)); fi
}

# --- Was gehoert zu dieser Einrichtung? --------------------------------------
# Aus dem Repositorium abgeleitet, nicht von Hand gepflegt.
EINHEITEN=(); for u in "$REPO"/systemd/*; do EINHEITEN+=("$(basename "$u")"); done
# ttyd kommt von GitHub und nicht aus bin/, liegt aber am selben Ort.
WERKZEUGE=(ttyd); for w in "$REPO"/bin/*; do WERKZEUGE+=("$(basename "$w")"); done
# Namen, die frueher einmal eingebaut wurden und heute nicht mehr in bin/ stehen.
# Die Liste oben wird aus dem Repositorium abgeleitet - ein umbenanntes Werkzeug
# steht dort nicht mehr und ueberlebte deshalb jeden Rueckbau. Das ist genau die
# Drift, gegen die dieses Skript gebaut wurde, nur eine Ebene tiefer: die
# Ableitung kennt die Gegenwart, nicht die Geschichte.
# *Tools that were installed under a former name: the derived list above knows
#  the present, not the history, so a renamed tool would survive every teardown -
#  the very drift this script exists to prevent, one level down.*
ALTLASTEN=(cf-dns)          # heisst seit dem Anbieter-Umbau dns-pflegen
WERKZEUGE+=("${ALTLASTEN[@]}")

echo "== Bestandsaufnahme auf $ZIEL =="
STACKS=$(fern "ls -1 /opt/stacks 2>/dev/null" || true)
printf '  %-46s %s\n' "Stacks" "${STACKS//$'\n'/ }"
printf '  %-46s %s\n' "systemd-Einheiten" "${#EINHEITEN[@]}"
printf '  %-46s %s\n' "Werkzeuge in /usr/local/bin" "${#WERKZEUGE[@]}"
printf '  %-46s %s\n' "Sicherung" "$([ "$BORG_REPO" = "aus" ] && echo "abgeschaltet" || echo "$BORG_REPO")"
echo

# --- Was ausdruecklich stehen bleibt -----------------------------------------
cat <<'TEXT'
== Wird NICHT angefasst ==
  Das Borg-Repository            die Spielstaende bleiben wiederherstellbar
  /root/.borg-passphrase         der EINZIGE Schluessel dazu - wer sie loescht,
                                 macht jedes vorhandene Archiv wertlos
  ufw-Regeln                     ein Zuruecksetzen koennte den SSH-Zugang kappen
  /etc/ssh/sshd_config.d/        dasselbe Risiko
  Pakete (docker, caddy, borg)   Entscheidungen ueber das Grundsystem
  Der Benutzer ADMIN_USER        das ist der Zugang, ueber den gerade
                                 gearbeitet wird

TEXT

# --- Rueckfrage --------------------------------------------------------------
# Erst nach der Bestandsaufnahme, damit sichtbar ist, was auf dem Spiel steht.
# Abgefragt wird der NAME des Ziels und nicht "ja": ein "ja" tippt man auch dann,
# wenn man versehentlich die falsche Maschine erwischt hat.
#
# Ohne Terminal wird abgebrochen statt durchgelaufen. Ein Rueckbau, der
# unbeaufsichtigt aus einem Skript heraus startet, ist genau der Fall, den man
# hinterher nicht mehr rueckgaengig machen kann.
# *Confirmation asks for the target name, not for "yes": people type "yes" even
#  when they grabbed the wrong machine. Without a terminal it aborts rather than
#  proceeding - an unattended teardown is exactly what cannot be undone.*
if [ "$WIRKLICH" -eq 1 ]; then
  echo "== Rueckfrage =="
  if [ "$MIT_SPIEL" -eq 1 ]; then
    echo "  Es werden SPIELSTAENDE GELOESCHT (/srv/games, /srv/dienste)."
    [ "$BORG_REPO" = "aus" ] \
      && echo "  Die Sicherung ist abgeschaltet - danach sind sie WEG." \
      || echo "  Vorher laeuft eine letzte Vollsicherung nach $BORG_REPO."
  else
    echo "  Spielstaende bleiben stehen (ohne --mit-spielstaenden)."
  fi
  if [ ! -t 0 ]; then
    echo "FEHLER: --wirklich braucht ein Terminal fuer die Rueckfrage." >&2
    exit 2
  fi
  printf '  Zum Bestaetigen den Namen des Ziels eintippen (%s): ' "$ZIEL"
  read -r antwort
  # Wagenruecklauf und Leerraum abschneiden: manche Terminals und jedes
  # Einfuegen aus der Zwischenablage liefern ihn mit, und dann scheitert die
  # Bestaetigung an etwas, das auf dem Bildschirm richtig aussieht.
  # *Strip CR and whitespace: some terminals and every clipboard paste deliver
  #  them, and the confirmation would fail on something that looks correct.*
  antwort="${antwort%$'\r'}"; antwort="${antwort#"${antwort%%[![:space:]]*}"}"
  antwort="${antwort%"${antwort##*[![:space:]]}"}"
  [ "$antwort" = "$ZIEL" ] || { echo "  Abgebrochen — nichts geaendert."; exit 2; }
  echo
fi

echo "== Rueckbau =="
[ "$WIRKLICH" -eq 0 ] && echo "  (Planlauf — es wird nichts geaendert)"

# 1. DNS zuerst: danach ist die Stackliste weg, aus der die Namen kommen.
if [ "$MIT_DNS" -eq 1 ]; then
  while read -r s; do
    [ -n "$s" ] || continue
    schritt "DNS-Name entfernen: $s" "/usr/local/bin/dns-pflegen entfernen '$s'"
  done <<<"$STACKS"
  schritt "DNS-Token entfernen" "rm -f /etc/dns-gameserver.conf /etc/cloudflare-gameserver.conf"
fi

# 2. Letzte Sicherung, BEVOR Spielstaende verschwinden. Schlaegt sie fehl, wird
#    hier nicht abgebrochen - anders als beim Entfernen eines einzelnen Spiels:
#    wer einen ganzen Server zurueckbaut, hat das entschieden, und ein Abbruch
#    mitten im Rueckbau liesse die Maschine in einem Zustand, den niemand
#    beschreiben kann. Gemeldet wird der Fehlschlag aber deutlich.
# *A failed final backup does not abort here: aborting mid-teardown would leave
#  the machine in a state nobody can describe. It is reported loudly instead.*
if [ "$MIT_SPIEL" -eq 1 ] && [ "$BORG_REPO" != "aus" ]; then
  schritt "letzte Vollsicherung" "/usr/local/bin/spiele-sicherung --alle"
fi

# 3. Container anhalten, solange die compose-Dateien noch da sind.
while read -r s; do
  [ -n "$s" ] || continue
  schritt "Container anhalten: $s" "cd /opt/stacks/'$s' && docker compose down"
done <<<"$STACKS"

# 4. Dienste aus, Einheiten weg. Erst abschalten, dann loeschen: eine geloeschte
#    Unit-Datei laesst sich nicht mehr sauber stoppen, der Dienst liefe weiter.
# *Disable first, delete second: a deleted unit file can no longer be stopped
#  cleanly and the service would keep running.*
# "systemctl disable --now" auf einer Einheit, die es auf dieser Maschine nie
# gab, scheitert - der gewuenschte Zustand ist aber bereits erreicht. Als
# Fehlschlag gezaehlt hiess das: sechs von 89 Schritten "FEHLGESCHLAGEN" auf
# einem Rueckbau, der vollstaendig und richtig war (dns-ziel, palworld-neustart
# und ttyd waren dort schlicht nie installiert). Eine Endzahl, die man erst
# Zeile fuer Zeile nachlesen muss, spart genau die Arbeit nicht, fuer die es sie
# gibt - und ein echter Fehlschlag zwischen fuenf erwarteten faellt nicht auf.
# *Disabling a unit this machine never had fails, yet the desired state is
#  already reached. Counted as failures, six of 89 steps were red on a teardown
#  that was complete and correct - and a real failure among five expected ones
#  is the case this makes harder.*
for u in "${EINHEITEN[@]}"; do
  if [ "$WIRKLICH" -eq 1 ] && ! fern "systemctl cat '$u'" >/dev/null 2>&1; then
    printf '  %-46s %s\n' "abschalten: $u" "gab es hier nicht"
    continue
  fi
  schritt "abschalten: $u" "systemctl disable --now '$u'"
done
for u in "${EINHEITEN[@]}"; do
  schritt "Einheit entfernen: $u" "rm -f '/etc/systemd/system/$u'"
done
schritt "systemd neu einlesen" "systemctl daemon-reload"

# 5. Werkzeuge und Oberflaeche
for w in "${WERKZEUGE[@]}"; do
  schritt "Werkzeug entfernen: $w" "rm -f '/usr/local/bin/$w'"
done
schritt "Weboberflaeche entfernen" "rm -rf /opt/panel"

# 6. Dateien in /etc. Caddyfile und jail.local ersetzen Dateien, die es vorher
#    schon gab - deshalb wird die juengste .vor-<datum>-Sicherung
#    zurueckgeholt statt geloescht. Genau dafuer legt einsetzen() sie an.
# *Those two replace pre-existing files, so the newest .vor-<date> backup is
#  restored rather than deleted - that is what einsetzen() creates it for.*
for d in /etc/caddy/Caddyfile /etc/fail2ban/jail.local; do
  schritt "zuruecknehmen: $d" \
    "v=\$(ls -1t $d.vor-* 2>/dev/null | head -1); if [ -n \"\$v\" ]; then cp -a \"\$v\" $d; else rm -f $d; fi"
done
for d in /etc/sudoers.d/panel /etc/spiele-katalog.json /etc/borg-ausschluss.txt; do
  schritt "entfernen: $d" "rm -f $d"
done

# 7. Spielstaende
if [ "$MIT_SPIEL" -eq 1 ]; then
  schritt "Stacks entfernen" "rm -rf /opt/stacks"
  schritt "Spieldaten entfernen" "rm -rf /srv/games /srv/dienste"
fi

# 8. Systembenutzer. ADMIN_USER bleibt - ueber den laeuft diese Sitzung.
if [ "$MIT_NUTZER" -eq 1 ]; then
  schritt "Benutzer panel entfernen" "userdel panel 2>/dev/null; groupdel panel 2>/dev/null; true"
  schritt "Benutzer spiele entfernen" "userdel spiele 2>/dev/null; groupdel spiele 2>/dev/null; true"
fi

echo
if [ "$WIRKLICH" -eq 0 ]; then
  echo "Planlauf: $geplant Schritte. Nichts geaendert."
  echo "Ausfuehren mit: $0 $ZIEL $([ $MIT_SPIEL -eq 1 ] && echo --mit-spielstaenden) $([ $MIT_NUTZER -eq 1 ] && echo --mit-benutzern) $([ $MIT_DNS -eq 1 ] && echo --mit-dns) --wirklich"
  exit 0
fi

# --- Gegenprobe --------------------------------------------------------------
# Der Vollzug allein beweist nichts: "rm -f" meldet auch Erfolg, wenn es die
# Datei gar nicht gab, und ein Dienst kann nach systemctl disable noch laufen.
# Nachgesehen wird deshalb, was TATSAECHLICH noch da ist.
#
# Und ein KONTROLLWERT: geprueft wird gleichzeitig etwas, das stehen bleiben
# MUSS. Ohne ihn ist "nichts mehr gefunden" nicht von "die Maschine antwortet
# gar nicht mehr" zu unterscheiden - man untersucht dann den Messpunkt statt
# das Ziel.
# *Verifying removal alone proves nothing: rm -f succeeds on a file that never
#  existed. A control value is measured alongside - something that MUST remain -
#  because otherwise "found nothing" is indistinguishable from "the machine no
#  longer answers".*
echo
echo "== Gegenprobe: was ist noch da? =="
uebrig=0
for u in "${EINHEITEN[@]}"; do
  fern "test -f '/etc/systemd/system/$u'" 2>/dev/null && { echo "  UEBRIG: /etc/systemd/system/$u"; uebrig=$((uebrig+1)); }
done
for w in "${WERKZEUGE[@]}"; do
  fern "test -e '/usr/local/bin/$w'" 2>/dev/null && { echo "  UEBRIG: /usr/local/bin/$w"; uebrig=$((uebrig+1)); }
done
for d in /opt/panel /etc/sudoers.d/panel /etc/spiele-katalog.json; do
  fern "test -e '$d'" 2>/dev/null && { echo "  UEBRIG: $d"; uebrig=$((uebrig+1)); }
done
if [ "$MIT_SPIEL" -eq 1 ]; then
  for d in /opt/stacks /srv/games /srv/dienste; do
    fern "test -e '$d'" 2>/dev/null && { echo "  UEBRIG: $d"; uebrig=$((uebrig+1)); }
  done
fi
laeuft=$(fern "systemctl list-units --state=running --no-legend 'panel*' 'ttyd*' 'spiele-sicherung*' 2>/dev/null" || true)
[ -n "$laeuft" ] && { echo "  LAEUFT NOCH:"; sed 's/^/    /' <<<"$laeuft"; uebrig=$((uebrig+1)); }
[ "$uebrig" -eq 0 ] && echo "  nichts."

echo
# Die Passphrase gehoert nur dann zum Kontrollwert, wenn es ueberhaupt eine
# geben kann. Bei BORG_REPO=aus legt Stufe 50 keine an - der Rueckbau meldete
# dort "Passphrase FEHLT — das ist zu viel weggeraeumt" fuer einen Zustand, den
# E22 ausdruecklich vorsieht, und sechs Zeilen weiter stand das Gegenteil
# ("liegt weiterhin unter ..."). Ein Kontrollwert, der ohne Not Alarm schlaegt,
# wird beim naechsten Mal ueberlesen - und dann taugt er an dem Tag nichts, an
# dem die Passphrase wirklich fehlt und jedes Archiv wertlos wird.
# *The passphrase belongs to the control value only where one can exist. With
#  backups off, stage 50 creates none, and the teardown called a documented,
#  supported state damage - while the prose six lines later claimed the opposite.
#  A control value that cries wolf is read once and then ignored.*
PRUEFUNGEN=("docker: command -v docker" "ADMIN_USER: id -u $ADMIN_USER")
[ "$BORG_REPO" != "aus" ] && PRUEFUNGEN+=("Passphrase: test -s /root/.borg-passphrase")

echo "== Kontrollwert: was stehen bleiben MUSS =="
for pruef in "${PRUEFUNGEN[@]}"; do
  name="${pruef%%:*}"; befehl="${pruef#*: }"
  if fern "$befehl" >/dev/null 2>&1; then printf '  %-30s da\n' "$name"
  else printf '  %-30s FEHLT — das ist zu viel weggeraeumt\n' "$name"; fehlschlaege=$((fehlschlaege+1)); fi
done

echo
if [ "$BORG_REPO" != "aus" ]; then
  echo "Die Borg-Passphrase liegt weiterhin unter /root/.borg-passphrase."
  echo "Wird die Maschine abgegeben, gehoert sie vorher an einen zweiten Ort —"
  echo "ohne sie ist jedes vorhandene Archiv wertlos."
else
  echo "BORG_REPO=aus: es gibt keine Passphrase und keine Archive."
fi
echo
printf 'ausgefuehrt: %d   fehlgeschlagen: %d   uebrig: %d\n' "$getan" "$fehlschlaege" "$uebrig"
[ $((fehlschlaege + uebrig)) -eq 0 ] || exit 1
