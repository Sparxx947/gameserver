#!/bin/bash
# Stufe 70 — Cloudflare-DNS (optional).
#
# Jedes Spiel bekommt <name>.<zone> als CNAME auf DNS_ZIEL. Damit haengt genau
# EIN Eintrag an der IP-Adresse: zieht der Server um, ist einer zu aendern.
# *One CNAME per game pointing at DNS_ZIEL, so exactly one record carries the
#  IP address: on a move there is a single record to change.*
. "$(dirname "$0")/lib.sh"

KONF="$DNS_KONF"
dns_konf_uebernehmen
if [ ! -s "$KONF" ]; then
  cat <<TEXT

  Es fehlt $KONF.

  1. Bei Cloudflare ein API-Token anlegen — NICHT den globalen Schluessel:
       Berechtigung : Zone / DNS / Bearbeiten
       Zonenressource: nur ${DNS_ZONE}
     *Create a scoped API token: Zone / DNS / Edit, limited to ${DNS_ZONE}.
      Never the global key.*

  2. Datei anlegen:
       printf 'ANBIETER=cloudflare\\nTOKEN=%s\\n' '<token>' > $KONF
       chmod 600 $KONF

  3. Diese Stufe erneut aufrufen.

TEXT
  exit 1
fi

chmod 600 "$KONF"

# Der Zeitgeber fuer den A-Eintrag steht seit #195 in Stufe 25 und NICHT mehr
# hier. Der Anlass ist zugleich der Grund: Stufe 70 steht nicht in der
# Vorgabeliste von einrichten.sh, und bei SERVER_IPV4=dynamic fehlte damit nach
# einer vollstaendig durchgelaufenen Einrichtung genau der Automatismus, den
# konfiguration.env zusagt.
#
# Es hier ZUSAETZLICH zu tun waere schlimmer als der urspruengliche Fehler: zwei
# Stellen, die dieselbe Einheit einsetzen und ein- oder ausschalten, geraten
# irgendwann auseinander, und dann entscheidet die Reihenfolge der Aufrufe
# darueber, ob der Zeitgeber laeuft. Das ist die Sorte Frage, die man im
# Stoerungsfall nicht beantworten will.
#
# *The A-record timer lives in stage 25 since #195 and no longer here: stage 70
#  is not in the default list, so a complete installation omitted the automation
#  konfiguration.env promises. Doing it here as well would be worse than the
#  original fault - two places installing and toggling one unit drift apart, and
#  then call order decides whether the timer runs.*

if [ "$IP_DYNAMISCH" != "ja" ]; then
  log "Zielsatz pruefen"
  # Im festen Betrieb muss der A-Eintrag DNS_ZIEL von Hand existieren — er ist
  # der einzige Ort mit der IP-Adresse und wird deshalb bewusst NICHT
  # automatisch angelegt.
  # *In fixed mode the A record must exist by hand: it is the only place holding
  #  the IP and is therefore deliberately not created automatically.*
  dns-pflegen liste | head -20 || fehler "dns-pflegen kommt nicht an die API — Token pruefen"
fi

log "Vorhandene Spielserver eintragen"
for d in /opt/stacks/*/; do
  s=$(basename "$d")
  dns-pflegen setzen "$s" || warn "DNS fuer $s fehlgeschlagen"
done

log "Gegenprobe: nichts darf proxied sein"
dns-pflegen pruefen

log "Stufe 70 fertig."
