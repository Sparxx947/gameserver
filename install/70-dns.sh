#!/bin/bash
# Stufe 70 — Cloudflare-DNS (optional).
#
# Jedes Spiel bekommt <name>.<zone> als CNAME auf DNS_ZIEL. Damit haengt genau
# EIN Eintrag an der IP-Adresse: zieht der Server um, ist einer zu aendern.
# *One CNAME per game pointing at DNS_ZIEL, so exactly one record carries the
#  IP address: on a move there is a single record to change.*
. "$(dirname "$0")/lib.sh"

KONF=/etc/cloudflare-gameserver.conf
if [ ! -s "$KONF" ]; then
  cat <<TEXT

  Es fehlt $KONF.

  1. Bei Cloudflare ein API-Token anlegen — NICHT den globalen Schluessel:
       Berechtigung : Zone / DNS / Bearbeiten
       Zonenressource: nur ${DNS_ZONE}
     *Create a scoped API token: Zone / DNS / Edit, limited to ${DNS_ZONE}.
      Never the global key.*

  2. Datei anlegen:
       printf 'CF_TOKEN=%s\\n' '<token>' > $KONF
       chmod 600 $KONF

  3. Diese Stufe erneut aufrufen.

TEXT
  exit 1
fi

chmod 600 "$KONF"

log "Zielsatz pruefen"
# Der A-Eintrag DNS_ZIEL muss von Hand existieren — er ist der einzige Ort mit
# der IP-Adresse und wird deshalb bewusst NICHT automatisch angelegt.
# *The A record must exist by hand: it is the only place holding the IP and is
#  therefore deliberately not created automatically.*
cf-dns liste | head -20 || fehler "cf-dns kommt nicht an die API — Token pruefen"

log "Vorhandene Spielserver eintragen"
for d in /opt/stacks/*/; do
  s=$(basename "$d")
  cf-dns setzen "$s" || warn "DNS fuer $s fehlgeschlagen"
done

log "Gegenprobe: nichts darf proxied sein"
cf-dns pruefen

log "Stufe 70 fertig."
