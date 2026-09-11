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

# Der Zeitgeber gehoert hierher, die CNAMEs der Spiele nicht: Hier steht, was VOR
# dem Zertifikat da sein muss - und bei SERVER_IPV4=dynamic ist der gepflegte
# A-Eintrag genau das, naemlich etwas, das da sein UND bleiben muss. Die CNAMEs
# duerfen warten, bis es Spiele gibt, und bleiben in der optionalen Stufe 70.
#
# Bis #195 stand der Zeitgeber ebenfalls in Stufe 70 - die nicht in der
# Vorgabeliste von einrichten.sh steht. Eine vollstaendig durchgelaufene
# Einrichtung liess damit genau den Automatismus aus, den konfiguration.env
# zusagt.
#
# Eingesetzt und geschaltet wird er von dns_ziel_zeitgeber() in lib.sh, damit es
# EINE Fassung gibt: Stufe 70 ruft dieselbe Funktion.
#
# *The timer belongs here, the game CNAMEs do not: this stage holds what must
#  exist before the certificate, and with a changing address the maintained A
#  record is exactly that - something that must exist and keep existing. Until
#  #195 it sat in stage 70, which is not in the default stage list, so a complete
#  installation omitted the automation konfiguration.env promises. Installed and
#  switched by dns_ziel_zeitgeber() in lib.sh so there is one implementation;
#  stage 70 calls the same function.*
log "Zeitgeber fuer den A-Eintrag"
dns_ziel_zeitgeber
log "Stufe 25 fertig. Spiel-CNAMEs (optional): install/70-dns.sh"
