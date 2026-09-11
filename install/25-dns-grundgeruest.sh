#!/bin/bash
# Stufe 25 — DNS-Grundgeruest bei Cloudflare (nur mit Token).
#
# Warum diese Stufe VOR Stufe 40 steht: Caddy holt dort ueber ACME das
# Zertifikat fuer PANEL_DOMAIN, und dafuer muss der Name oeffentlich auf diese
# Maschine zeigen. Die DNS-Stufe war aber Nummer 70 und lief erst hinterher — auf
# einer frischen Zone gab es damit genau einen Moment, in dem der einzige
# Automatismus, der den Namen haette anlegen koennen, noch nicht dran war.
#
# Kaputt ging dabei nichts: Caddy versucht es von selbst weiter, sobald der Name
# aufloest. Aber das Panel war bis zum ersten Handgriff nicht per HTTPS da, und
# im Journal stand als Grund nur ein gescheiterter ACME-Versuch — nicht, dass
# ein DNS-Eintrag fehlt, den man gleich haette anlegen koennen.
#
# *Why this runs before stage 40: Caddy fetches the panel certificate there via
#  ACME, which needs PANEL_DOMAIN to resolve to this machine publicly. The DNS
#  stage was number 70 and ran afterwards, so on a fresh zone there was exactly
#  one moment where the only automation that could have created the name had not
#  run yet. Nothing broke — Caddy keeps retrying — but the panel had no HTTPS
#  until someone intervened, and the journal blamed ACME, not the missing
#  record.*
#
# Ohne Token wird die Stufe UEBERSPRUNGEN, nicht abgebrochen: DNS von Hand zu
# pflegen ist ein zulaessiger Betrieb, und eine Einrichtung, die daran scheitert,
# waere schlimmer als eine, die es nur deutlich sagt.
# *Without a token the stage is skipped, not failed: hand-maintained DNS is a
#  legitimate way to run this, and an install that dies on it would be worse
#  than one that says so plainly.*
. "$(dirname "$0")/lib.sh"

KONF="$DNS_KONF"

# Aeltere Installationen tragen den Zugang noch unter dem alten Dateinamen.
# ZUERST uebernehmen, dann pruefen: umgekehrt wuerde die Stufe sich auf einer
# Maschine ueberspringen, die sehr wohl einen Token hat - nur eben den alten.
# *Migrate first, check second: the other order would skip the stage on a
#  machine that does have a token, just under the former name.*
dns_konf_uebernehmen

if [ ! -s "$KONF" ]; then
  warn "kein $KONF — das DNS bleibt Handarbeit."
  warn "Vor Stufe 40 muessen ${DNS_ZIEL} und ${PANEL_DOMAIN} oeffentlich auf"
  warn "diese Maschine zeigen, sonst bekommt das Panel kein Zertifikat."
  warn "Anbieter und Token anlegen, dann diese Stufe einzeln nachholen:"
  warn "  printf 'ANBIETER=cloudflare\\nTOKEN=%s\\n' '<token>' > $KONF"
  warn "  chmod 600 $KONF"
  warn "  install/einrichten.sh 25-dns-grundgeruest"
  log "Stufe 25 uebersprungen (kein DNS-Token)."
  exit 0
fi

chmod 600 "$KONF"

# dns-pflegen wird sonst erst in Stufe 30 eingebaut, hier aber schon gebraucht.
# einsetzen() ist idempotent und legt bei gleichem Inhalt keine zweite Kopie an —
# Stufe 30 setzt es danach wortlos noch einmal ein.
# *dns-pflegen is normally installed in stage 30 but needed here already. einsetzen()
#  is idempotent, so stage 30 simply installs it again without a second copy.*
log "dns-pflegen einbauen"
einsetzen "$REPO/bin/dns-pflegen" /usr/local/bin/dns-pflegen 0755 root:root

log "Anbieter"
dns-pflegen anbieter || fehler "Anbieter oder Token nicht brauchbar — $KONF pruefen"

log "Fehlende Eintraege anlegen"
dns-pflegen grundgeruest || fehler "DNS-Grundgeruest fehlgeschlagen — Token, Zone und DNS_ZIEL pruefen"

# --- Zeitgeber fuer den A-Eintrag ------------------------------------
# Der Zeitgeber stand frueher in Stufe 70 - und Stufe 70 steht NICHT in der
# Vorgabeliste von einrichten.sh. Eine vollstaendig und dokumentiert
# durchgelaufene Einrichtung liess bei SERVER_IPV4=dynamic also genau den
# Automatismus aus, den konfiguration.env zusagt ("misst seine oeffentliche
# IPv4 alle fuenf Minuten und traegt sie selbst ein"). Jede Stufe meldete
# Erfolg, der Abschlusstext bot 70-dns als eine von mehreren Zugaben an, und
# niemand hatte einen Grund nachzusehen. Bemerkt haette man es, wenn die
# Adresse wechselt: A-Eintrag veraltet, Spiel-CNAMEs zeigen mit, und das
# Zertifikat des Panels erneuert sich nicht mehr - vier Schritte entfernt von
# der Ursache.
#
# Er gehoert hierher und nicht in eine Zugabe: Bei einer wechselnden Adresse
# ist der gepflegte A-Eintrag genau das, was diese Stufe laut ihrer eigenen
# Beschreibung sicherstellt - naemlich das, was VOR dem Zertifikat stehen muss
# und stehen BLEIBEN muss.
#
# *The timer used to live in stage 70, which is not in the default stage list,
#  so a complete documented installation silently omitted the automation
#  konfiguration.env promises for SERVER_IPV4=dynamic. Every stage reported
#  success and nobody had a reason to look; it surfaces only when the address
#  changes, four steps away from the cause. With a changing address the
#  maintained A record is exactly what this stage exists to guarantee.*
log "Zeitgeber fuer den A-Eintrag einsetzen"
for u in dns-ziel.service dns-ziel.timer; do
  einsetzen "$REPO/systemd/$u" "/etc/systemd/system/$u"
done
systemctl daemon-reload

# Der alte Name des Werkzeugs. Entfernt wird er ERST NACH dem Einsetzen der
# Einheit: bis dahin ruft dns-ziel.service noch /usr/local/bin/cf-dns. Wer ihn
# frueher wegnimmt, bricht den Zeitgeber fuer die Dauer der Aktualisierung -
# an einer Stelle, an der niemand sucht.
# *Removed after the unit is in place: until then dns-ziel.service still calls
#  the old path, and removing it sooner breaks the timer mid-upgrade.*
rm -f /usr/local/bin/cf-dns

if [ "$IP_DYNAMISCH" = "ja" ]; then
  # SERVER_IPV4=dynamic: der A-Eintrag gehoert ab hier diesem Programm. Deshalb
  # wird er auch angelegt, wenn er fehlt - anders als im festen Betrieb, wo er
  # der einzige haendisch gepflegte Ort mit der Adresse ist und bewusst nicht
  # automatisch entsteht.
  # *With dynamic this program owns the record and creates it; in fixed mode it
  #  stays hand-made.*
  log "Adresse messen und A-Eintrag setzen"
  dns-pflegen ziel-setzen || fehler "A-Eintrag ${DNS_ZIEL} konnte nicht gesetzt werden"
  systemctl enable --now dns-ziel.timer
else
  # Feste Adresse: der Zeitgeber bleibt aus. Er liegt trotzdem auf der Maschine,
  # damit ein Wechsel auf "dynamic" nur eine Zeile in konfiguration.env ist.
  # *Fixed address: timer off but installed, so switching is one line.*
  systemctl disable --now dns-ziel.timer 2>/dev/null || true
  log "SERVER_IPV4 ist fest (${SERVER_IPV4}) — Zeitgeber bleibt aus"
fi

# Die CNAMEs der Spiele bleiben in Stufe 70: die duerfen warten, bis es Spiele
# gibt. Der Zeitgeber darf das nicht.
# *Game CNAMEs stay in stage 70 - those may wait until there are games. The
#  timer may not.*
log "Stufe 25 fertig. Spiel-CNAMEs: install/70-dns.sh"
