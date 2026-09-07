#!/bin/bash
# Stufe 50 — Sicherung nach Borg.
# *Stage 50 — Borg backup.*
. "$(dirname "$0")/lib.sh"

# Die Ausschlussliste wird IMMER eingesetzt, auch ohne Sicherung. spiel-verwalten
# schreibt bei jeder Installation und Deinstallation einen Block hinein und liest
# sie vorher — fehlt die Datei, bricht die Deinstallation mitten im Ablauf ab und
# laesst Reste stehen. Genau dieser Abbruch ist hier schon einmal passiert, aus
# einem anderen Grund (siehe panel.service, ProtectSystem).
# *The exclusion list is always installed, even without backups: spiel-verwalten
#  reads and writes it on every install and uninstall, and a missing file aborts
#  the uninstall mid-way, leaving remnants behind.*
log "Ausschlussliste"
einsetzen "$REPO/etc/borg-ausschluss.txt" /etc/borg-ausschluss.txt 0644 root:root

log "Zeitplan einsetzen"
for u in spiele-sicherung.service spiele-sicherung.timer \
         spiele-sicherung-voll.service spiele-sicherung-voll.timer; do
  einsetzen "$REPO/systemd/$u" "/etc/systemd/system/$u"
done
systemctl daemon-reload

if [ "$SICHERUNG_AN" = "nein" ]; then
  # BORG_REPO=aus: kein borg, keine Passphrase, keine Timer. Die Einheiten
  # liegen trotzdem auf der Maschine, damit das Einschalten spaeter eine Zeile
  # in konfiguration.env und ein erneuter Lauf dieser Stufe ist.
  # *BORG_REPO=aus: no borg, no passphrase, no timers. The units are installed
  #  anyway so switching on later is one line plus a re-run of this stage.*
  systemctl disable --now spiele-sicherung.timer spiele-sicherung-voll.timer 2>/dev/null || true
  einsetzen "$REPO/bin/spiele-sicherung" /usr/local/bin/spiele-sicherung 0700 root:root
  warn "BORG_REPO=aus — es wird NICHTS gesichert."
  warn "Spielstaende sind dann nur so sicher wie diese eine Platte."
  log "Stufe 50 fertig (Sicherung abgeschaltet)."
  exit 0
fi

apt-get install -y -qq borgbackup

log "Werkzeug"
einsetzen "$REPO/bin/spiele-sicherung" /usr/local/bin/spiele-sicherung 0700 root:root

# --- Passphrase -------------------------------------------------------
# Liegt als Datei, weil die Timer unbeaufsichtigt laufen. Rechte 0600 root:
# der Panel-Nutzer kommt nicht heran, und panel-aktion liest sie nur als root.
# WICHTIG: Diese Passphrase ist der EINZIGE Schluessel zu den Sicherungen. Sie
# gehoert an einen zweiten Ort ausserhalb dieses Servers — geht die Maschine
# verloren, ist ein verschluesseltes Repository ohne sie wertlos.
# *This passphrase is the ONLY key to the backups. Keep a copy somewhere other
#  than this machine: without it an encrypted repository is worthless.*
if [ ! -s /root/.borg-passphrase ]; then
  passwort 32 > /root/.borg-passphrase
  chmod 0600 /root/.borg-passphrase
  warn "Neue Borg-Passphrase erzeugt: /root/.borg-passphrase"
  warn "JETZT ausserhalb dieses Servers sichern! / Store a copy off this host NOW!"
fi

log "Repository anlegen (falls neu)"
export BORG_PASSPHRASE=$(cat /root/.borg-passphrase)
export BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
if borg list "$BORG_REPO" >/dev/null 2>&1; then
  log "Repository vorhanden."
else
  borg init --encryption repokey-blake2 "$BORG_REPO" \
    || warn "borg init fehlgeschlagen — Schluessel auf dem Sicherungsziel hinterlegt? SSH erreichbar?"
fi

log "Zeitplan einschalten"
systemctl enable --now spiele-sicherung.timer spiele-sicherung-voll.timer

# Alarmpfad nachweisen, nicht nur den Gutfall: eine Sicherung, die nie geprueft
# wurde, ist eine Vermutung. Der erste Lauf laeuft deshalb JETZT und sein
# Ergebnis wird angesehen.
# *Prove the failure path, not just the happy one: an unverified backup is a
#  guess. The first run happens now and its result is inspected.*
log "Probelauf"
if /usr/local/bin/spiele-sicherung --alle; then
  log "Archive im Repository:"
  borg list --short "$BORG_REPO" | tail -20
else
  fehler "Der erste Sicherungslauf ist gescheitert — nicht weitermachen, bis das steht."
fi

log "Stufe 50 fertig."
