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
              stacks systemd werkzeuge konfiguration.env.beispiel README.md docs \
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

echo
[ $fehler -eq 0 ] && echo "vollstaendig." || echo "UNVOLLSTAENDIG — siehe oben."
exit $fehler
