#!/bin/bash
# Stufe 30 — Weboberflaeche (FastAPI/uvicorn) und die sudo-Bruecke.
# *Stage 30 — web panel (FastAPI/uvicorn) and its sudo bridge.*
. "$(dirname "$0")/lib.sh"

log "Verzeichnisse und Rechte"
# /opt/panel gehoert root: die App darf ihren EIGENEN Code nicht ueberschreiben
# koennen. Schreibbar ist ausschliesslich daten/ und bilder/.
# *Owned by root so the app cannot overwrite its own code; only daten/ and
#  bilder/ are writable.*
install -d -m 0755 -o root  -g root  /opt/panel
install -d -m 0755 -o panel -g panel /opt/panel/daten /opt/panel/bilder /opt/panel/bilder/katalog

einsetzen "$REPO/panel/app.py" /opt/panel/app.py 0644 root:root
cp "$REPO"/panel/bilder/favicon.svg "$REPO"/panel/bilder/favicon.ico \
   "$REPO"/panel/bilder/apple-touch-icon.png /opt/panel/bilder/
# Selbst gezeichnete Titelbilder fuer Spiele ohne Steam-Eintrag (appid 0).
# spiel-verwalten greift darauf zurueck, wenn Steam nichts liefert.
# *Self-drawn artwork for games with no Steam entry; the installer falls back
#  to these.*
install -d -m 0755 -o panel -g panel /opt/panel/bilder/eigene
cp "$REPO"/panel/bilder/eigene/*.jpg /opt/panel/bilder/eigene/ 2>/dev/null || true
chown -R panel:panel /opt/panel/bilder

log "Python-Umgebung"
[ -d /opt/panel/venv ] || python3 -m venv /opt/panel/venv
/opt/panel/venv/bin/pip install -q --upgrade pip
/opt/panel/venv/bin/pip install -q -r "$REPO/panel/requirements.txt"

log "Werkzeuge nach /usr/local/bin"
for w in cf-dns compose-feld katalog-vorpruefung katalogbilder-holen konfig-datei panel-aktion spiel-einrichtung spiel-verwalten; do
  einsetzen "$REPO/bin/$w" "/usr/local/bin/$w" 0755 root:root
done
einsetzen "$REPO/etc/spiele-katalog.json" /etc/spiele-katalog.json 0644 root:root

# Die sudo-Regel ist die einzige Rechteerweiterung der Oberflaeche. visudo -c
# prueft sie VOR dem Einbau: eine kaputte Datei in /etc/sudoers.d legt sudo
# systemweit lahm — auch fuer den Menschen, der sie reparieren muesste.
# *visudo -c checks before install: a broken file in /etc/sudoers.d disables
#  sudo system-wide, including for whoever would have to fix it.*
log "sudo-Bruecke"
rendern "$REPO/etc/sudoers.d/panel" > /tmp/sudoers-panel.$$
if visudo -cf /tmp/sudoers-panel.$$ >/dev/null; then
  install -m 0440 -o root -g root /tmp/sudoers-panel.$$ /etc/sudoers.d/panel
else
  rm -f /tmp/sudoers-panel.$$; fehler "sudoers-Regel ist ungueltig — nicht eingebaut"
fi
rm -f /tmp/sudoers-panel.$$

log "Dienste"
einsetzen "$REPO/systemd/panel.service" /etc/systemd/system/panel.service
einsetzen "$REPO/systemd/spiel-einrichtung.service" /etc/systemd/system/spiel-einrichtung.service
einsetzen "$REPO/systemd/spiel-einrichtung.timer"   /etc/systemd/system/spiel-einrichtung.timer
systemctl daemon-reload
systemctl enable --now panel.service spiel-einrichtung.timer

# --- Erster Zugang ----------------------------------------------------
# Wird NUR beim ersten Lauf angelegt. Das Passwort steht danach einmal auf dem
# Bildschirm und nirgends sonst; gespeichert wird ausschliesslich der
# Argon2id-Hash. Das TOTP-Geheimnis entsteht hier, wird aber NICHT ausgegeben —
# der Benutzer bekommt es bei der ersten Anmeldung als QR-Code. Ein hier
# gedrucktes Geheimnis stuende im Sitzungsprotokoll und waere damit kein
# zweiter Faktor mehr.
# *Created on first run only. The password appears once on screen and nowhere
#  else; only the Argon2id hash is stored. The TOTP secret is generated here but
#  never printed — printing it would put it in the session log and stop it from
#  being a second factor.*
if [ ! -s /opt/panel/daten/nutzer.json ]; then
  START=$(passwort 16)
  /opt/panel/venv/bin/python - "$ADMIN_USER" "$START" <<'PYEOF'
import json, os, sys
import pyotp
from argon2 import PasswordHasher

name, passwort = sys.argv[1], sys.argv[2]
# Struktur exakt wie in app.py: laden()/speichern() erwarten {"secret", "nutzer"}.
# "totp_bestaetigt": False ist der Schalter, der die erste Anmeldung auf die
# QR-Einrichtung umleitet statt eine Sitzung zu vergeben.
# *Structure matches app.py: laden()/speichern() expect {"secret", "nutzer"}.
#  totp_bestaetigt False routes the first login to QR enrolment instead of
#  handing out a session.*
daten = {
    "secret": os.urandom(48).hex(),
    "nutzer": {name: {"passwort_hash": PasswordHasher().hash(passwort),
                      "totp": pyotp.random_base32(),
                      "rolle": "admin",
                      "totp_bestaetigt": False}},
}
pfad = "/opt/panel/daten/nutzer.json"
with open(pfad, "w") as fh:
    json.dump(daten, fh, indent=2)
os.chmod(pfad, 0o600)
PYEOF
  chown panel:panel /opt/panel/daten/nutzer.json
  echo
  echo "  ================================================================"
  echo "   Erstanmeldung / initial login"
  echo "     https://${PANEL_DOMAIN}/"
  echo "     Benutzer / user:  ${ADMIN_USER}"
  echo "     Passwort / pass:  ${START}"
  echo
  echo "   Das Passwort steht nur hier. Beim ersten Anmelden wird der"
  echo "   zweite Faktor als QR-Code eingerichtet."
  echo "   *Shown here only; the second factor is enrolled on first login.*"
  echo "  ================================================================"
  echo
  systemctl restart panel.service    # neue Nutzerdatei einlesen
fi

# Selbst gepflegte Zugangsdaten: Server, deren Passwort sich nicht auslesen
# laesst (Hash oder verschluesselt abgelegt), werden hier von Hand gefuehrt.
# *Manually kept credentials for servers whose password cannot be read back
#  (stored hashed or encrypted).*
if [ ! -s /opt/panel/daten/zugangsdaten.json ]; then
  echo '[]' > /opt/panel/daten/zugangsdaten.json
  chown panel:panel /opt/panel/daten/zugangsdaten.json
  chmod 0600 /opt/panel/daten/zugangsdaten.json
fi

# Titelbilder der Katalogseite. Ohne diesen Aufruf blieb das Verzeichnis nach
# einem Neuaufbau leer - die Bilder waren nur deshalb da, weil sie einmal von
# Hand geholt worden waren. Der Aufruf darf fehlschlagen (kein Netz, Steam
# nicht erreichbar): die Kacheln sind dann blass, alles andere funktioniert.
# *Without this the directory stayed empty after a rebuild; the images were
#  there only because someone had fetched them by hand once. Allowed to fail:
#  the tiles go pale, nothing else breaks.*
log "Titelbilder der Katalogseite"
/usr/local/bin/katalogbilder-holen || warn "Titelbilder unvollstaendig - spaeter mit katalogbilder-holen nachziehen"

log "Stufe 30 fertig."
