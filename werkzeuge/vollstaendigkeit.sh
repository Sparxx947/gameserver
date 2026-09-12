#!/bin/bash
# vollstaendigkeit.sh — prueft, ob das Repositorium alles enthaelt, was die
# Einrichtung anfasst. Aendert nichts.
#
# Warum es das gibt: Eine .gitignore-Regel "*.local" schloss einmal
# etc/fail2ban/jail.local aus — eine Datei, die install/10-basis.sh zwingend
# braucht. Der Push war gruen, die Dateiliste sah vollstaendig aus, und der
# Fehler waere erst bei der naechsten Neueinrichtung aufgefallen: also genau
# dann, wenn man ihn am wenigsten gebrauchen kann.
#
# *Why this exists: a `.gitignore` rule of "*.local" once excluded
#  etc/fail2ban/jail.local, a file install/10-basis.sh requires. The push was
#  green and the file list looked complete; the failure would have surfaced only
#  during the next fresh install — exactly when it is least welcome.*
#
# Exit 0 = vollstaendig, 1 = etwas fehlt.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO"

fehler=0

# --- 1. Jede von den Stufen referenzierte Repo-Datei muss existieren ---------
echo "== Referenzen der Einrichtungsstufen =="
while read -r pfad; do
  # Glob-Ausdruecke (z.B. "$REPO"/panel/bilder/*.svg) auflösen statt zu testen
  if [[ "$pfad" == *"*"* ]]; then
    # shellcheck disable=SC2086
    compgen -G "$pfad" >/dev/null || { echo "  FEHLT (Muster ohne Treffer): $pfad"; fehler=1; }
    continue
  fi
  # konfiguration.env ist Absicht: Sie gehoert NICHT ins Repositorium und
  # entsteht erst beim Einrichten aus der Vorlage - lib.sh sagt das auch so.
  # In einem frischen Klon (und damit in jeder Pruefung ausserhalb dieser
  # Maschine) fehlt sie zu Recht; sie hier zu verlangen machte den Lauf dort
  # unbrauchbar. Dass die VORLAGE vollstaendig ist, prueft Abschnitt 5.
  # *konfiguration.env is deliberately absent from the repository and is created
  #  from the template at setup time, so requiring it here made the check
  #  unusable in a fresh clone. Section 5 checks the template instead.*
  [ "${pfad##*/}" = "konfiguration.env" ] && continue
  [ -e "$pfad" ] || { echo "  FEHLT: ${pfad#$REPO/}"; fehler=1; }
# Das "@" gehoert in die Zeichenklasse: systemd-Vorlagen heissen
# "platzwart-wecken@.service". Ohne es schnitt das Muster am @ ab und meldete
# "FEHLT: systemd/platzwart-wecken" - eine Datei, die es nie geben sollte.
# *The "@" belongs in the class: systemd template units are named foo@.service,
#  and without it the pattern cut at the @ and reported a file that should never
#  exist.*
done < <(grep -rhoE '"\$REPO"[/a-zA-Z0-9_.@-]+|\$REPO/[a-zA-Z0-9_./*@-]+' install/ \
         | sed 's|"\$REPO"|'"$REPO"'|; s|\$REPO|'"$REPO"'|' | sort -u)

# --- 2. Nichts davon darf von .gitignore verschluckt werden -----------------
# Der eigentliche Fehler war nicht die fehlende Datei, sondern dass sie
# UNBEMERKT fehlte: sie lag im Arbeitsverzeichnis und wurde nur nicht verfolgt.
# *The real fault was not the missing file but that it went unnoticed: it sat in
#  the working tree and simply was not tracked.*
echo "== Von git verfolgt? =="
while read -r f; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 \
    || { echo "  NICHT VERFOLGT: $f  ($(git check-ignore -v "$f" 2>/dev/null || echo 'nicht eingecheckt'))"; fehler=1; }
done < <(find bin etc install panel/app.py panel/requirements.txt panel/bilder \
              stacks systemd werkzeuge konfiguration.env.beispiel README.md docs VERSION \
              -type f 2>/dev/null | grep -vE '/katalog/|\.jpg$|__pycache__|\.pyc$')

# --- 3. Skripte muessen syntaktisch heil sein -------------------------------
echo "== Syntax =="
for f in install/*.sh werkzeuge/*.sh; do
  bash -n "$f" 2>/dev/null || { echo "  SYNTAXFEHLER: $f"; fehler=1; }
done
for f in bin/*; do
  head -1 "$f" | grep -q python3 && { python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null \
    || { echo "  SYNTAXFEHLER: $f"; fehler=1; }; }
  head -1 "$f" | grep -q 'bash$' && { bash -n "$f" 2>/dev/null || { echo "  SYNTAXFEHLER: $f"; fehler=1; }; }
done
python3 -c "import ast;ast.parse(open('panel/app.py').read())" 2>/dev/null \
  || { echo "  SYNTAXFEHLER: panel/app.py"; fehler=1; }
python3 -c "import json;json.load(open('etc/spiele-katalog.json'))" 2>/dev/null \
  || { echo "  UNGUELTIGES JSON: etc/spiele-katalog.json"; fehler=1; }

# Geschweifte Klammern in f-Strings: {1,20} in einem HTML-Attribut ist fuer
# Python ein AUSDRUCK und wird zum Tupel "(1, 20)". Die Syntaxpruefung laesst das
# durch, weil "1,20" gueltiges Python ist - im ausgelieferten HTML stand dann
# pattern="[A-Za-z0-9](1, 20)", und ein voellig korrekter Benutzername wurde vom
# Browser abgewiesen (08.09., ein siebenstelliger Name aus Buchstaben und
# Ziffern). Deshalb wird hier das ERGEBNIS geprueft,
# nicht der Quelltext.
# *Braces in f-strings: {1,20} in an HTML attribute is an expression to Python and
#  renders as a tuple. The syntax check passes it, so the rendered output is what
#  gets checked here.*
# Eine Variable, die erst mit "" beginnt, dann mit += gefuellt und danach mit =
# ueberschrieben wird, verliert alles Vorherige. Am 2026-09-09 verschwand so der
# Auto-Update-Schalter von der Karte: gebaut und drei Zeilen spaeter weggeworfen.
# Jeder Block sah fuer sich betrachtet richtig aus.
# *A variable seeded with "", filled with += and then reassigned with = loses
#  everything before it. That is how the auto-update button vanished from the
#  card: built and discarded three lines later.*
echo "== Wird ein aufgebauter HTML-Schnipsel spaeter ueberschrieben? =="
python3 - <<'PRUEF' || fehler=1
import re, sys
t = open("panel/app.py").read()
schlecht = []
for name in set(re.findall(r'^\s*(\w+) = ""\s*$', t, re.M)):
    # Reihenfolge der Zuweisungen an diese Variable einsammeln
    vorkommen = [(m.start(), m.group(1))
                 for m in re.finditer(rf'^\s*{name} (\+?=)', t, re.M)]
    plus_gesehen = False
    for pos, art in vorkommen:
        if art == "+=":
            plus_gesehen = True
        elif plus_gesehen and art == "=":
            zeile = t[:pos].count("\n") + 1
            schlecht.append(f"Zeile {zeile}: {name} wird mit = ueberschrieben, "
                            f"nachdem es mit += gefuellt wurde")
            break
if schlecht:
    print("  " + "\n  ".join(schlecht))
    sys.exit(1)
PRUEF

# Jede Route holt ihre Sitzung ueber angemeldet() oder pruefe(), und beide
# geben None zurueck - ohne Anmeldung, mit falschem CSRF-Merkmal. Wer danach
# s.get(...) oder s["..."] schreibt, ohne vorher auf None zu pruefen, bekommt
# einen AttributeError und damit HTTP 500 statt einer Umleitung. So bei allen
# drei Mod-Routen (#165), waehrend jede andere Route ist_admin(s) oder
# darf_verwalten(s) benutzte, die None abfangen.
# *angemeldet()/pruefe() return None without a session. Touching s before a None
#  check turns that into a 500 - as in all three mod routes (#165).*
echo "== Sitzung erst auf None pruefen, dann benutzen? =="
python3 - <<'PRUEF' || fehler=1
import re, sys
zeilen = open("panel/app.py").read().split("\n")
schlecht, route = [], None
for i, z in enumerate(zeilen, 1):
    m = re.match(r'@app\.(get|post)\("([^"]+)"', z)
    if m:
        route, start = m.group(2), i
        continue
    if route and re.search(r'\bs(\.get\(|\[")', z):
        davor = "\n".join(zeilen[start:i - 1])
        if not re.search(r'if not s\b|if s is None|darf_verwalten\(s\)|ist_admin\(s\)', davor):
            schlecht.append(f"{route} (Zeile {i}): {z.strip()[:60]}")
        route = None
    elif route and i - start > 60:
        route = None
if schlecht:
    print("  Sitzung benutzt, bevor sie auf None geprueft ist - ohne Anmeldung HTTP 500:")
    print("    " + "\n    ".join(schlecht))
    print("    Vorher: if not s: ... oder ist_admin(s)/darf_verwalten(s) benutzen.")
    sys.exit(1)
PRUEF

echo "== Keine ausgewerteten Klammern im HTML? =="
python3 - <<'PRUEF' || fehler=1
import re, sys
t = open("panel/app.py").read()
schlecht = []
for m in re.finditer(r'(?:pattern|minlength|maxlength|size)=("?)([^"\s>]*)\1', t):
    if re.search(r'\(\s*\d+\s*,\s*\d+\s*\)', m.group(0)):
        schlecht.append(m.group(0))
# und der haeufigere Fall: einfache Klammern in einem HTML-Attribut eines f-Strings
for m in re.finditer(r'pattern="[^"]*(?<!\{)\{[0-9]+,[0-9]*\}(?!\})[^"]*"', t):
    zeile = t[:m.start()].count("\n") + 1
    anfang = t.rfind('f"""', 0, m.start())
    if anfang != -1 and t.rfind('"""', anfang + 4, m.start()) == -1:
        schlecht.append(f"Zeile {zeile}: {m.group(0)} steht in einem f-String und muss {{{{...}}}} lauten")
if schlecht:
    print("  " + "\n  ".join(schlecht))
    sys.exit(1)
PRUEF

# --- 3b. Jedes Werkzeug aus bin/ muss auch eingebaut werden -----------------
# Warum es das gibt: bin/konfig-datei stand im Repositorium, wurde von
# panel-aktion aufgerufen und von abgleich.sh verglichen — aber von KEINER
# Einrichtungsstufe nach /usr/local/bin gelegt. Auf einer frisch aufgebauten
# Maschine waere der Konfigdatei-Editor tot gewesen ("exec: not found"), und auf
# der laufenden fiel es nicht auf, weil die Datei einmal von Hand ausgerollt
# worden war. Genau die Sorte Luecke, die erst bei der Neueinrichtung auffaellt.
#
# *Why this exists: bin/konfig-datei sat in the repository, was called by
#  panel-aktion and compared by abgleich.sh — but installed by no stage. On a
#  freshly built machine the config-file editor would simply not exist, while on
#  the running one it went unnoticed because the file had once been rolled out by
#  hand. Exactly the kind of gap that surfaces only during a fresh install.*
echo "== Wird jedes Werkzeug aus bin/ auch eingebaut? =="
eingebaut=$(grep -rhoE 'for w in [a-z0-9 -]+; do|einsetzen "\$REPO/bin/[a-z-]+"' install/*.sh \
            | sed -E 's/for w in //; s/; do//; s|einsetzen "\$REPO/bin/||; s/"//' \
            | tr ' ' '\n' | sort -u)
for f in bin/*; do
  n=$(basename "$f")
  # Here-String, keine Pipe: "grep -q" beendet sich beim ersten Treffer, die
  # schreibende Seite bekaeme SIGPIPE und mit pipefail gaelte die Pipeline als
  # gescheitert.
  grep -qx "$n" <<<"$eingebaut" \
    || { echo "  NICHT EINGEBAUT: bin/$n wird von keiner Stufe nach /usr/local/bin gelegt"; fehler=1; }
done

# --- 4. Kein Geheimnis, keine Standortdaten ---------------------------------
# Die Ausnahmen sind eng gehalten und einzeln begruendet — eine breite
# Ausnahme wuerde die Pruefung stillschweigend entwerten.
# *Exceptions are narrow and individually justified: a broad one would quietly
#  hollow out the check.*
#   vollstaendigkeit.sh          enthaelt die Suchmuster selbst
#   *.beispiel                   Vorlagen mit sichtbaren Platzhaltertexten
echo "== Keine Standortdaten oder Geheimnisse =="
MUSTER='BEGIN [A-Z ]*PRIVATE KEY|\$argon2|CF_TOKEN=[A-Za-z0-9_-]{20,}'
treffer=$(grep -rniE "$MUSTER" --exclude-dir=.git --exclude=konfiguration.env \
            --exclude='vollstaendigkeit.sh' --exclude='*.beispiel' . || true)
if [ -n "$treffer" ]; then
  echo "  TREFFER — bitte pruefen:"; sed 's/^/    /' <<<"$treffer"; fehler=1
fi

# --- 4b. Keine echten IP-Adressen -------------------------------------------
# Am 2026-09-09 stand die oeffentliche IPv4 des Servers in E23 - seit dem
# 08.09., als der Vorfall aufgeschrieben wurde. Die Regel dagegen steht in
# CLAUDE.md; gemerkt hat sie niemand, weil nichts hinsah.
#
# Erlaubt sind genau die Bereiche, die keinen Ort verraten: Loopback, 0.0.0.0,
# die privaten Netze (RFC 1918), der Tailscale-Bereich (RFC 6598), die drei
# Dokumentationsnetze aus RFC 5737, Link-local (169.254/16) und Multicast samt
# reserviertem Rest (224/3) - die letzten beiden nennt install/assistent.sh als
# "nicht oeffentlich", keine davon ist je die Adresse eines Standorts. Alles
# andere ist ein Fund - auch eine fremde Adresse, denn die gehoert genauso wenig
# hierher.
#
# Das "(?<!§)" ist kein Schmuck: "§4.2.1.1" (NIST SP 800-63B-4) und "§3.1.3.1"
# sehen wie IPv4 aus. Ohne diese Ausnahme meldet die Pruefung zwei Abschnitts-
# nummern und wird nach dem zweiten Mal ignoriert.
# *Allowed are exactly the ranges that reveal no location. The negative
#  lookbehind is not decoration: NIST section numbers look like IPv4, and a
#  check that cries wolf twice gets ignored.*
echo "== Keine echten IP-Adressen? =="
treffer=$(grep -rPoh '(?<!§)(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])' \
            --exclude-dir=.git --exclude=konfiguration.env --exclude='vollstaendigkeit.sh' . \
          | sort -u | grep -vE '^(127\.|0\.0\.0\.0$|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|169\.254\.|2(2[4-9]|[3-5][0-9])\.)' || true)
if [ -n "$treffer" ]; then
  echo "  STANDORTDATEN — echte Adressen gehoeren nicht ins Repositorium:"
  sed 's/^/    /' <<<"$treffer"
  echo "    Fuer Beispiele: 192.0.2.x, 198.51.100.x, 203.0.113.x (RFC 5737)."
  fehler=1
fi

# --- 4c. Keine Standortwerte aus konfiguration.env, keine lokal gelisteten Namen
# Muster finden Geheimnisse und IP-Adressen, aber keine Namen. So stand der Name
# der Welt (auch Teil der Zone) in einer Messung und in einem Kommentar, und ein
# echter Kontoname kam mit #248 zurueck, nachdem ihn 013ee7b schon einmal
# entfernt hatte. Geprueft werden deshalb die WERTE der eigenen
# konfiguration.env (Zone, Ziel, Panel-Domain, Weltname) und die Woerter aus
# .standortdaten - einer lokalen, nie eingecheckten Liste fuer Kontonamen und
# Aehnliches. Ohne beide Dateien entfaellt die Pruefung (frischer Klon).
# ADMIN_USER bewusst nicht: der Vorname steht als Entscheider in der Doku.
# *Patterns catch secrets and IPs, not names: the world name sat in a
#  measurement, and a real account name came back with #248 after being removed
#  once. So the VALUES from the local konfiguration.env and the words from the
#  local, never committed .standortdaten are searched for in tracked files.*
echo "== Keine Standortwerte aus konfiguration.env und .standortdaten? =="
woerter=$( { [ -f konfiguration.env ] && sed -nE 's/^(DNS_ZONE|DNS_ZIEL|PANEL_DOMAIN|WELT_NAME)=//p' konfiguration.env
             [ -f .standortdaten ] && grep -vE '^[[:space:]]*(#|$)' .standortdaten; } \
           | tr -d "\"'" | awk 'length($0) >= 4' | LC_ALL=C sort -u)
if [ -z "$woerter" ]; then
  echo "  entfaellt: weder konfiguration.env noch .standortdaten vorhanden"
else
  treffer=$(git ls-files -z | xargs -0 grep -nIiF -f <(printf '%s\n' "$woerter") -- 2>/dev/null || true)
  if [ -n "$treffer" ]; then
    echo "  STANDORTDATEN — ein Wert aus konfiguration.env/.standortdaten steht im Repositorium:"
    sed 's/^/    /' <<<"$treffer"
    echo "    Durch einen Platzhalter oder ein neutrales Beispiel ersetzen (meinserver, beispiel.de)."
    fehler=1
  else
    echo "  ok: $(wc -l <<<"$woerter") Werte gesucht, keiner gefunden"
  fi
fi

# --- 5. Jeder Platzhalter muss in der Vorlage erklaert sein ------------------
echo "== Platzhalter in konfiguration.env.beispiel erklaert? =="
while read -r p; do
  v=${p//@/}
  # PASSWORT/ADMIN_PASSWORT werden je Stack erzeugt und gehoeren nicht in die
  # Vorlage. NAME/PLATZHALTER/PLACEHOLDER sind generische Erwaehnungen in
  # Kommentaren ("ein uebrig gebliebener @@NAME@@ ist ein Fehler"), keine Werte.
  # *The first two are generated per stack; the rest are generic mentions in
  #  comments, not values.*
  case "$v" in PASSWORT|ADMIN_PASSWORT|NAME|PLATZHALTER|PLACEHOLDER) continue ;; esac
  grep -q "^${v}=" konfiguration.env.beispiel \
    || { echo "  $p kommt vor, steht aber nicht in konfiguration.env.beispiel"; fehler=1; }
done < <(grep -rhoE '@@[A-Z_]+@@' bin etc install panel stacks systemd 2>/dev/null | sort -u)

# --- 6. Titelbild fuer jedes Spiel ohne Steam-Eintrag ------------------------
# Die Bilder unter panel/bilder/eigene/ lagen frueher nur im Repositorium, weil
# sie einmal von Hand erzeugt wurden. Kam ein Katalogspiel ohne Steam-Eintrag
# dazu, fehlte sein Bild und niemand sah es - am 2026-09-08 waren es sechs.
# *These images used to exist only because someone made them by hand once; a new
#  catalogue game without a Steam entry silently had no artwork.*
echo "== Titelbild fuer jedes Spiel ohne Steam-Eintrag? =="
if ! python3 werkzeuge/eigene-bilder.py --pruefen 2>&1 | sed 's/^/  /'; then
  echo "  mit: python3 werkzeuge/eigene-bilder.py"
  fehler=1
fi

# --- 7. Stimmt die Doku noch mit dem Katalog ueberein? -----------------------
# Der Katalog wuchs 41 -> 86 -> 154 -> 162 -> 179, die Doku blieb bei 41, an vier
# Stellen, ueber Monate. Von Hand nachzupflegen hat zweimal nicht funktioniert;
# was hilft, ist eine Pruefung, die meckert. Geprueft werden ausdrueckliche
# Stellen und die erzeugte Spieleliste - nicht "irgendeine Zahl vor dem Wort
# Spiele", denn davon stehen mehrere in der Doku, die etwas anderes zaehlen.
# *The catalogue grew while the docs stayed at 41 in four places. Maintaining it
#  by hand failed twice; a check that complains is what helps.*
echo "== Stimmt die Doku zum Spielekatalog? =="
if ! python3 werkzeuge/katalog-doku.py --pruefen 2>&1 | sed 's/^/  /'; then
  fehler=1
fi

# --- 7a. Hat jedes Katalogspiel eine Kategorie? ------------------------------
# Die Generatoren legten 17 Spiele ohne das Feld an; katalog-kategorien.py lief
# nur von Hand. Die Spiele fehlten danach in jedem Kategoriefilter der
# Katalogseite, auch in "Sonstiges" - und nichts sagte es (#251).
# *17 generated entries had no category and vanished from every filter (#251).*
echo "== Hat jedes Katalogspiel eine Kategorie? =="
if ! python3 werkzeuge/katalog-kategorien.py etc/spiele-katalog.json --pruefen 2>&1 | sed 's/^/  /'; then
  fehler=1
fi

# --- 7c. Ist die Dokumentation zweisprachig? ---------------------------------
# Die Regel stand nur als Satz in CLAUDE.md. Am 2026-09-11 fehlte der englische
# Absatz in 83 Abschnitten, und niemand hatte es bemerkt.
# *The rule was only a sentence in CLAUDE.md; 83 sections lacked the English
#  paragraph on 2026-09-11 and nobody had noticed.*
echo "== Hat jeder Doku-Abschnitt seinen englischen Absatz? =="
if ! python3 werkzeuge/doku-englisch.py; then
  fehler=1
fi

# --- 7b. Wird alles Ausgerollte auch verglichen? ----------------------------
# abgleich.sh fuehrt eine Liste von Hand. Am 2026-09-10 fehlten neun Dateien
# darin - darunter spiele-autoupdate, das jede Nacht unbeaufsichtigt laeuft, und
# spiele-wiederanlauf, das nach einem Neustart entscheidet, was zurueckkommt.
# Der Lauf meldete trotzdem "abweichend: 0". Eine Zahl, die "alles stimmt"
# suggeriert und "alles, was ich zufaellig ansehe, stimmt" bedeutet, ist
# schlimmer als gar keine - man hoert auf nachzusehen.
#
# Geprueft wird nur EINE Richtung: Was install/ ausrollt, muss verglichen
# werden. Umgekehrt nicht - in abgleich.sh stehen zu Recht Dateien, die andere
# Stufen auf anderem Weg anlegen (sudoers.d/panel, die dns-ziel- und
# Sicherungs-Einheiten). Die Palworld-Einheiten standen hier auch - als Datei,
# die "anders" angelegt werde. Angelegt hat sie keine Stufe (#252).
# *One direction only: what install/ deploys must be compared. Not the reverse -
#  abgleich.sh rightly lists files other stages create by other means.*
echo "== Wird jede ausgerollte Datei auch verglichen? =="
{
  grep -rhoE 'einsetzen "\$REPO/[^"]+" +/[^ ]+' install/*.sh \
    | sed -E 's|einsetzen "\$REPO/([^"]+)" +(/\S+)|\1|'
  for n in $(grep -oE 'for w in [a-z0-9 -]+' install/30-panel.sh | sed 's/for w in //'); do
    echo "bin/$n"
  done
} | LC_ALL=C sort -u > /tmp/vs-soll.$$
grep -oE '^[[:space:]]*"[^":]+:[^"]+"' werkzeuge/abgleich.sh \
  | tr -d ' "' | cut -d: -f1 | LC_ALL=C sort -u > /tmp/vs-ist.$$
fehlend=$(LC_ALL=C comm -23 /tmp/vs-soll.$$ /tmp/vs-ist.$$)
if [ -n "$fehlend" ]; then
  echo "  install/ rollt aus, abgleich.sh vergleicht NICHT:"
  sed 's/^/    /' <<<"$fehlend"
  echo "    -> Paar in die Liste PAARE in werkzeuge/abgleich.sh eintragen."
  fehler=1
fi

# Dieselbe Tabelle steht ein DRITTES Mal in ausrollen.sh, und auch die wurde
# vergessen: etc/spiele-adressen.json liess sich am 2026-09-10 nicht ausrollen
# ("UNBEKANNT wohin"), waehrend das Panel schon ohne seine Adressdatei lief.
# bin/* und systemd/* fangen dort Mustereintraege ab und brauchen keinen
# eigenen Fall - geprueft wird deshalb nur, was einen braucht.
# *The same table exists a third time in ausrollen.sh and was forgotten too.
#  bin/* and systemd/* are covered by wildcards there, so only the rest is
#  checked.*
nicht_rollbar=$(while read -r p; do
    case "$p" in bin/*|systemd/*) continue ;; esac
    grep -qF "    $p)" werkzeuge/ausrollen.sh || echo "$p"
  done < /tmp/vs-soll.$$)
if [ -n "$nicht_rollbar" ]; then
  echo "  install/ rollt aus, ausrollen.sh kennt das Ziel NICHT:"
  sed 's/^/    /' <<<"$nicht_rollbar"
  echo "    -> Fall in die Funktion wohin() in werkzeuge/ausrollen.sh eintragen."
  fehler=1
fi
rm -f /tmp/vs-soll.$$ /tmp/vs-ist.$$

# --- 8. Entscheidungsnummern: keine doppelt, keine ins Leere ----------------
# Am 2026-09-09 wurde E24 zweimal vergeben. Der Grund ist eine Falle, die beim
# naechsten Mal genauso aussieht: die Ueberschriften in 10-entscheidungen.md
# stehen NICHT in ihrer Reihenfolge - E24 liegt oberhalb von E23, weil sie
# frueher geschrieben wurde und in der Mitte landete. Wer ans Ende anhaengt und
# auf die letzte Ueberschrift sieht, liest E23 und haelt E24 fuer frei.
# Zugleich geprueft: jede aus der Doku heraus genannte Nummer muss es geben -
# ein Verweis auf eine geloeschte oder umnummerierte Entscheidung fuehrt den
# Leser sonst ins Nichts, und genau dafuer sind die Verweise da.
# *E24 was assigned twice: the headings are not in numeric order, so appending
#  at the end and looking at the last one reads E23 and takes E24 for free.
#  Also checked: every E<n> referenced from the docs must exist.*
echo "== Entscheidungsnummern eindeutig und aufloesbar? =="
D=docs/10-entscheidungen.md
doppelt=$(grep -oE '^## E[0-9]+' "$D" | grep -oE 'E[0-9]+' | sort | uniq -d)
if [ -n "$doppelt" ]; then
  echo "  DOPPELT vergeben: $(tr '\n' ' ' <<<"$doppelt")"
  echo "  Achtung: die Ueberschriften stehen nicht in numerischer Reihenfolge —"
  echo "  die naechste freie Nummer ist die hoechste, nicht die letzte."
  fehler=1
fi
vorhanden=$(grep -oE '^## E[0-9]+' "$D" | grep -oE 'E[0-9]+' | sort -u)
# Nur Verweise aus der Doku: im Code steht "E23" auch mal als Teil eines Wortes.
while read -r v; do
  grep -qx "$v" <<<"$vorhanden" \
    || { echo "  Verweis auf $v, aber es gibt keine solche Entscheidung"; fehler=1; }
done < <(grep -rhoE '\bE[0-9]{1,2}\b' docs/*.md CLAUDE.md README.md 2>/dev/null \
         | sort -u)

# --- 8b. Jede Route des Panels steht in der Routentabelle -------------------
# Die Tabelle in docs/03-panel.md kannte am 2026-09-11 22 von 61 Routen und
# fuehrte /konfig und /archive noch als admin-only. Eine Referenz, die nur einen
# Teil kennt, ist die, nach der man die falsche Rolle vergibt (#179).
# *The route table knew 22 of 61 routes and listed two with the wrong role.*
echo "== Steht jede Route des Panels in der Routentabelle? =="
python3 - <<'PRUEF' || fehler=1
import re, sys
code = set(re.findall(r'@app\.(?:get|post)\("([^"]+)"', open("panel/app.py").read()))
doku = open("docs/03-panel.md").read()
abschnitt = doku[doku.index("## Alle Routen"):]
abschnitt = abschnitt[:abschnitt.index("\n## ", 5)] if "\n## " in abschnitt[5:] else abschnitt
genannt = set(re.findall(r"`(/[^`]*)`", abschnitt))
fehlt = sorted(code - genannt)
if fehlt:
    print("  Routen ohne Eintrag in docs/03-panel.md -> 'Alle Routen':")
    print("    " + "\n    ".join(fehlt))
    sys.exit(1)
PRUEF

# --- 9. Ports des Spielekatalogs --------------------------------------------
# Am 2026-09-10 veroeffentlichte der Katalog die gotty-Webkonsole von FiveM und
# RedM (Serverkonsole ohne Anmeldung) und RCON bei gut fuenfzig Spielen - die
# Regel dagegen gab es, sie sah nur die falsche Spalte an. Dazu Beitrittsadressen
# auf Ports, auf denen das Spiel nicht lauscht. Regeln und Ausnahmen stehen im
# Werkzeug selbst (#163).
# *The catalogue published FiveM's console and RCON for some fifty games; the
#  rule against it existed but looked at the wrong column.*
echo "== Ports des Spielekatalogs (Grenze 4, Beitrittsport, Kollisionen) =="
python3 werkzeuge/katalog-ports.py || fehler=1

# --- 9b. Sicherungsausschluesse des Spielekatalogs --------------------------
# Bis 2026-09-12 sicherten alle 167 Katalogeintraege der Bauarten ich777 und
# linuxgsm ihre Spielinstallation mit: Valheims 2,65 GB bestehen zu 85 % aus
# Unity-Daten und Bibliotheken, die jede Neuinstallation zurueckbringt (#221).
# Die Muster stehen im Werkzeug, samt Begruendung, warum keins davon ein
# Spielstand sein kann. Es laesst ausserdem jedes Muster fallen, das ein
# Modverzeichnis aus etc/spiele-mods.json verdecken wuerde - ein selbst
# hochgeladener Mod kommt aus keiner Neuinstallation zurueck.
# *All 167 ich777/linuxgsm catalogue entries backed up their game install. The
#  patterns and the reasoning live in the tool, which also drops any pattern
#  that would cover a mod directory - an uploaded mod returns from no reinstall.*
echo "== Sicherungsausschluesse des Spielekatalogs =="
if [ -n "${PLATZWART_KEIN_AUSSCHLUSS_GATE:-}" ]; then
  echo "  uebersprungen (PLATZWART_KEIN_AUSSCHLUSS_GATE gesetzt)"
else
  python3 werkzeuge/katalog-ausschluesse.py --selbsttest || fehler=1
  if ! python3 werkzeuge/katalog-ausschluesse.py --pruefen; then
    echo "    Vorbei: PLATZWART_KEIN_AUSSCHLUSS_GATE=1"
    fehler=1
  fi
fi

# --- Kennt die Wache jeden Stack? -------------------------------------------
# Die Einrichtungspruefung der Wache lief ueber /opt/stacks/*/panel.json - die
# hat nur, was ueber den Katalog installiert wurde, also einer von sieben
# Servern. Die sechs handgebauten sah niemand an, und das faellt nicht auf: Eine
# Pruefung, die einen Bereich nicht ansieht, meldet ihn als in Ordnung (#289).
# Deshalb braucht jeder Bauplan unter stacks/ eine Regel in SCHUTZ - auch
# "unbestimmt", aber dann mit Grund. Ein neuer Stack erzwingt so eine
# Entscheidung, statt lautlos durchzurutschen.
# *The watchdog's setup check ran over panel.json, which only catalogue installs
#  have - one server of seven. Every blueprint under stacks/ therefore needs a
#  rule in SCHUTZ, "unbestimmt" included but then with a reason, so a new stack
#  forces a decision instead of slipping through.*
echo "== Kennt die Wache jeden Stack? =="
if [ -n "${PLATZWART_KEIN_SCHUTZ_GATE:-}" ]; then
  echo "  uebersprungen (PLATZWART_KEIN_SCHUTZ_GATE gesetzt)"
else
  python3 - <<'PRUEF' || fehler=1
import pathlib, sys
quelle = pathlib.Path("bin/platzwart-wache").read_text()
raum = {}
exec(compile(quelle.split("def sh(")[0], "wache", "exec"), raum)
schutz = raum.get("SCHUTZ")
if not schutz:
    print("  SCHUTZ steht nicht mehr in bin/platzwart-wache"); sys.exit(1)
staecke = sorted(p.stem for p in pathlib.Path("stacks").glob("*.yaml"))
fehlt = [s for s in staecke if s not in schutz]
ohne_grund = [s for s, r in schutz.items()
              if r.get("art") == "unbestimmt" and not r.get("grund")]
if fehlt:
    print(f"  {len(fehlt)} Stack(s) ohne Regel in SCHUTZ: {', '.join(fehlt)}")
    print("    Eintrag in bin/platzwart-wache ergaenzen - 'umgebung', 'konfig'")
    print("    oder 'unbestimmt' mit Grund. Vorbei: PLATZWART_KEIN_SCHUTZ_GATE=1")
if ohne_grund:
    print(f"  'unbestimmt' ohne Grund: {', '.join(ohne_grund)}")
if fehlt or ohne_grund:
    sys.exit(1)
print(f"  {len(staecke)} Bauplaene, {len(schutz)} Regeln - jeder Stack hat eine.")
PRUEF
fi

# --- Selbsttests duerfen das System nicht anfassen --------------------------
#
# bin/modul-verwalten setzte in seinem Selbsttest ein echtes
# "systemctl daemon-reload" ab. Auf dem Server als root harmlos, auf einem
# Arbeitsplatzrechner eine Anfrage an den System-Manager: Polkit stellte sie als
# Passwortdialog auf den Schirm, immer wieder, bis eine andere Sitzung den Weg
# nachvollzogen hat (2026-09-12).
#
# Eine blosse Messung "heute ruft keiner systemctl" haelt das nicht zu: Genau
# dieser Aufruf war jahrelang unerreichbar und wurde es erst, als ein Testfall
# erweitert wurde. Deshalb wird hier gemessen, nicht gelesen: ein Schein-
# systemctl im PATH, jeder Aufruf ist ein Fehler.
#
# *A self-test must touch nothing: modul-verwalten's issued a real
#  daemon-reload, harmless as root on the server and a Polkit password prompt on
#  a workstation. Measuring "nobody calls it today" does not close the case -
#  that call became reachable only when a test case grew. Hence a fake systemctl
#  in PATH, and any call is a failure.*
echo "== Fassen die Selbsttests das System an? =="
if [ -n "${PLATZWART_KEIN_SYSTEMCTL_GATE:-}" ]; then
  echo "  uebersprungen (PLATZWART_KEIN_SYSTEMCTL_GATE gesetzt)"
else
  schein=$(mktemp -d)
  export SCHEIN_LOG="$schein/aufrufe"
  : > "$SCHEIN_LOG"
  cat > "$schein/systemctl" <<'SCHEINENDE'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$SCHEIN_LOG"
exit 0
SCHEINENDE
  chmod +x "$schein/systemctl"
  # Auch werkzeuge/ - dort stehen ebenfalls Selbsttests, und die Schleife sah
  # sie bis 2026-09-12 nicht an. Nur nicht diese Datei selbst: sie riefe sich
  # sonst selbst wieder auf.
  for w in $(grep -l -- "--selbsttest" bin/* werkzeuge/* 2>/dev/null); do
    case "$w" in */vollstaendigkeit.sh) continue ;; esac
    PATH="$schein:$PATH" timeout 300 "$w" --selbsttest >/dev/null 2>&1
  done
  anzahl=$(wc -l < "$SCHEIN_LOG")
  if [ "$anzahl" -gt 0 ]; then
    echo "  $anzahl Aufruf(e) an das System aus einem Selbsttest:"
    sort -u "$SCHEIN_LOG" | sed "s/^/    /"
    echo "    Regel: Ein Selbsttest laeuft auch auf einem Arbeitsplatzrechner und"
    echo "    darf dort nichts anfassen - als nicht-root ueberspringen oder die"
    echo "    Ausfuehrung im Test umbiegen. Vorbei: PLATZWART_KEIN_SYSTEMCTL_GATE=1"
    fehler=1
  else
    echo "  kein Selbsttest ruft systemctl."
  fi
  unset SCHEIN_LOG
  rm -rf "$schein"
fi

# --- Module: Ports und Dashboards -------------------------------------------
#
# Dieselbe Regel wie fuer den Spielekatalog, an einer zweiten Stelle: Ein Modul
# ist ein Dienst fuer Menschen, nicht fuer Spieler - JEDER seiner Ports gehoert
# auf 127.0.0.1, davor steht Caddy mit der Anmeldung des Panels. Bis #163 stand
# die Portregel nur als Kopie im Generator und griff nie; eine zweite Liste ohne
# eigene Pruefung waere derselbe Fehler noch einmal.
# *The same rule as for the game catalogue, at a second place: every port of a
#  module belongs on localhost. A second list without its own check would repeat
#  the mistake of #163.*
echo "== Ports der Module (alle auf 127.0.0.1) =="
if [ -f etc/module-katalog.json ]; then
  python3 - <<'PY' || fehler=1
import json, pathlib, re, sys
schlecht = 0
for m in json.load(open("etc/module-katalog.json")).get("module", []):
    for p in m.get("ports", []):
        if not p.startswith("127.0.0.1:"):
            print(f"  {m['schluessel']}: {p} bindet nicht auf 127.0.0.1")
            schlecht += 1
    for f in ("route", "ziel", "rolle", "daten"):
        if not m.get(f):
            print(f"  {m['schluessel']}: Feld '{f}' fehlt")
            schlecht += 1
    if m.get("ziel") and not m["ziel"].startswith("127.0.0.1:"):
        print(f"  {m['schluessel']}: Ziel {m['ziel']} liegt nicht auf 127.0.0.1")
        schlecht += 1
    # Die Einhaengepunkte der compose-Datei muessen zum Katalog passen. Beim
    # Umzug der Daten nach /srv/module blieb die compose-Datei auf dem alten
    # Pfad stehen (#268): Docker legte den fehlenden Ordner als root an, der
    # vorbereitete Ordner blieb unbenutzt, und Grafana lief in eine
    # Neustartschleife - waehrend die Installation Erfolg meldete. Eine
    # Uebereinstimmung, die man sich merken muss, merkt sich irgendwann niemand.
    # *Mount sources must match the catalogue: after moving the data the compose
    #  file kept the old path, docker created it as root, and Grafana
    #  restart-looped while the install reported success.*
    cyaml = pathlib.Path("etc/module") / m["schluessel"] / "compose.yaml"
    if cyaml.exists():
        erlaubt = (m["daten"] + "/", f"/etc/module/{m['schluessel']}/", "/var/lib/", "./")
        # Nur SCHREIBBARE Einhaengepunkte. Ein Exporter lebt davon, /proc, /sys
        # oder den Docker-Ordner LESEND zu sehen - das ist sein Zweck und keine
        # Abweichung. Geprueft wird, wohin ein Modul schreiben kann.
        # *Read-only mounts are an exporter's purpose; only writable ones matter.*
        for mm in re.finditer(r"^\s+- (/[^:]+|\./[^:]+):([^:\s]+)(:(\S+))?\s*$",
                              cyaml.read_text(), re.M):
            quelle, optionen = mm.group(1), (mm.group(4) or "")
            if "ro" in optionen.split(","):
                continue
            if not quelle.startswith(erlaubt):
                print(f"  {m['schluessel']}: Einhaengepunkt {quelle} steht weder unter "
                      f"{m['daten']} noch /etc/module/{m['schluessel']} noch /var/lib")
                schlecht += 1
    for s in m.get("schalter", []):
        if s.get("art") not in ("profil", "sammler", "grafana"):
            print(f"  {m['schluessel']}/{s.get('name')}: unbekannte Art {s.get('art')!r}")
            schlecht += 1
    for e in m.get("einstellungen", []):
        if e.get("vorgabe") not in e.get("werte", []):
            print(f"  {m['schluessel']}/{e.get('name')}: Vorgabe steht nicht in den Werten")
            schlecht += 1
print(f"  {len(json.load(open('etc/module-katalog.json')).get('module', []))} Modul(e) - Ports in Ordnung."
      if not schlecht else f"  {schlecht} Beanstandung(en)")
sys.exit(1 if schlecht else 0)
PY
fi

# Dashboards sind erzeugt (werkzeuge/statistik-dashboards.py). Von Hand
# nachgebessert weichen sie vom Generator ab, und der naechste Lauf wirft die
# Handarbeit weg - lieber hier melden.
# *Dashboards are generated; hand edits drift and the next run discards them.*
echo "== Stimmen die Grafana-Dashboards mit ihrem Generator? =="
if [ -f werkzeuge/statistik-dashboards.py ]; then
  python3 werkzeuge/statistik-dashboards.py --pruefen || fehler=1
fi

echo
[ $fehler -eq 0 ] && echo "vollstaendig." || echo "UNVOLLSTAENDIG — siehe oben."
exit $fehler
