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
   "$REPO"/panel/bilder/apple-touch-icon.png \
   "$REPO"/panel/bilder/icon-192.png "$REPO"/panel/bilder/icon-512.png \
   /opt/panel/bilder/
# Selbst gezeichnete Titelbilder fuer Spiele ohne Steam-Eintrag (appid 0).
# spiel-verwalten greift darauf zurueck, wenn Steam nichts liefert.
# *Self-drawn artwork for games with no Steam entry; the installer falls back
#  to these.*
# Das einzige JavaScript des Panels (Passkeys). Gehoert root, nicht panel:
# der Dienst darf seinen eigenen ausgelieferten Code nicht ueberschreiben
# koennen - dieselbe Ueberlegung wie bei /opt/panel/app.py.
# *The panel's only JavaScript. Owned by root so the service cannot overwrite
#  code it serves - the same reasoning as for app.py.*
install -d -m 0755 -o root -g root /opt/panel/statisch
install -m 0644 -o root -g root "$REPO/panel/statisch/passkey.js" /opt/panel/statisch/passkey.js

install -d -m 0755 -o panel -g panel /opt/panel/bilder/eigene
cp "$REPO"/panel/bilder/eigene/*.jpg /opt/panel/bilder/eigene/ 2>/dev/null || true
chown -R panel:panel /opt/panel/bilder

log "Python-Umgebung"
[ -d /opt/panel/venv ] || python3 -m venv /opt/panel/venv
/opt/panel/venv/bin/pip install -q --upgrade pip
/opt/panel/venv/bin/pip install -q -r "$REPO/panel/requirements.txt"

log "Werkzeuge nach /usr/local/bin"
# platzwart-melden steht hier mit in der Liste, obwohl es nichts mit dem
# Panel zu tun hat: Es wird von spiele-autoupdate (Stufe 30) UND von
# spiele-sicherung (Stufe 50) gerufen, muss also vor beiden liegen.
# *Installed here although it is not part of the panel: both stage 30 and
#  stage 50 call it, so it has to exist before either.*
for w in dns-pflegen compose-feld katalog-vorpruefung katalogbilder-holen konfig-datei panel-aktion platzwart-melden platzwart-wache platzwart-status port-ermitteln spieler-zaehlen spiel-einrichtung spiel-verwalten spiele-wiederanlauf spiele-autoupdate; do
  einsetzen "$REPO/bin/$w" "/usr/local/bin/$w" 0755 root:root
done
einsetzen "$REPO/etc/spiele-katalog.json" /etc/spiele-katalog.json 0644 root:root
# Die Beitrittsadressen lesen ZWEI Programme: das Panel und platzwart-status.
# Deshalb eine Datei und nicht eine Tabelle im Quelltext.
einsetzen "$REPO/etc/spiele-adressen.json" /etc/spiele-adressen.json 0644 root:root

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

# Die Ausschlussliste gehoert der Sache nach zur Sicherung und wird in Stufe 50
# eingesetzt - panel.service braucht sie aber JETZT: die Einheit gibt genau diese
# eine Datei ueber ReadWritePaths frei, und systemd verweigert den Start, wenn
# der Pfad nicht existiert ("Failed to set up mount namespacing", 226/NAMESPACE).
# Mit Restart=on-failure wurde daraus eine Neustartschleife, die erst Stufe 50
# beendet haette - bei einer Neuinstallation stand der Zaehler fuenfstellig, und
# im Journal steht als Ursache nur der fehlende Namensraum, nicht die Datei.
# Angelegt wird sie nur, wenn sie fehlt: eine vorhandene traegt die
# Ausschlussbloecke der bereits installierten Spiele.
# *panel.service opens this one file via ReadWritePaths, and systemd refuses to
#  start when the path is missing (226/NAMESPACE). With Restart=on-failure that
#  became a restart loop lasting until stage 50 created the file. Only created
#  when absent: an existing one carries the installed games' exclusion blocks.*
[ -f /etc/borg-ausschluss.txt ] \
  || einsetzen "$REPO/etc/borg-ausschluss.txt" /etc/borg-ausschluss.txt 0644 root:root

log "Dienste"
einsetzen "$REPO/systemd/panel.service" /etc/systemd/system/panel.service
einsetzen "$REPO/systemd/spiel-einrichtung.service" /etc/systemd/system/spiel-einrichtung.service
einsetzen "$REPO/systemd/spiel-einrichtung.timer"   /etc/systemd/system/spiel-einrichtung.timer
einsetzen "$REPO/systemd/spiele-wiederanlauf.service" /etc/systemd/system/spiele-wiederanlauf.service
einsetzen "$REPO/systemd/platzwart-status.service" /etc/systemd/system/platzwart-status.service
einsetzen "$REPO/systemd/platzwart-status.timer"   /etc/systemd/system/platzwart-status.timer
einsetzen "$REPO/systemd/spieler-zaehlen.service"  /etc/systemd/system/spieler-zaehlen.service
einsetzen "$REPO/systemd/spieler-zaehlen.timer"    /etc/systemd/system/spieler-zaehlen.timer
einsetzen "$REPO/systemd/platzwart-wache.service"  /etc/systemd/system/platzwart-wache.service
einsetzen "$REPO/systemd/platzwart-wache.timer"    /etc/systemd/system/platzwart-wache.timer
einsetzen "$REPO/systemd/spiele-autoupdate.service" /etc/systemd/system/spiele-autoupdate.service
einsetzen "$REPO/systemd/spiele-autoupdate.timer"   /etc/systemd/system/spiele-autoupdate.timer
systemctl daemon-reload
systemctl enable --now panel.service spiel-einrichtung.timer
# Nur "enable", nicht "--now": Die Einheit soll beim naechsten HOCHFAHREN laufen,
# nicht jetzt. Sie ist ohnehin an eine Liste gebunden, die es gerade nicht gibt.
# *enable without --now: it belongs to the next boot, and it is bound to a list
#  that does not exist right now anyway.*
systemctl enable spiele-wiederanlauf.service
# Der Timer laeuft, die Automatik ist trotzdem aus: er findet nur Server, die in
# ihrer panel.json ausdruecklich freigeschaltet sind. Ohne Freischaltung
# passiert nichts.
# *The timer runs but the automation is off: it only finds servers explicitly
#  enabled in their panel.json.*
systemctl enable --now platzwart-status.timer
systemctl enable --now spieler-zaehlen.timer
systemctl enable --now platzwart-wache.timer
systemctl enable --now spiele-autoupdate.timer

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
