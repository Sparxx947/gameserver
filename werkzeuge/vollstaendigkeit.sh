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
  [ -e "$pfad" ] || { echo "  FEHLT: ${pfad#$REPO/}"; fehler=1; }
done < <(grep -rhoE '"\$REPO"[/a-zA-Z0-9_.-]+|\$REPO/[a-zA-Z0-9_./*-]+' install/ \
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
# Browser abgewiesen (08.09., "ropax85"). Deshalb wird hier das ERGEBNIS geprueft,
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

echo
[ $fehler -eq 0 ] && echo "vollstaendig." || echo "UNVOLLSTAENDIG — siehe oben."
exit $fehler
