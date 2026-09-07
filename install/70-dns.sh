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

log "Zeitgeber fuer den A-Eintrag einsetzen"
for u in dns-ziel.service dns-ziel.timer; do
  einsetzen "$REPO/systemd/$u" "/etc/systemd/system/$u"
done
systemctl daemon-reload

if [ "$IP_DYNAMISCH" = "ja" ]; then
  # SERVER_IPV4=dynamic: der A-Eintrag gehoert ab hier diesem Programm. Deshalb
  # wird er auch angelegt, wenn er fehlt — anders als im festen Betrieb, wo er
  # der einzige haendisch gepflegte Ort mit der Adresse ist und bewusst nicht
  # automatisch entsteht. Wer beides gleich behandelt, hat entweder einen
  # Automatismus, der fremde Eintraege ueberschreibt, oder einen dynamischen
  # Betrieb, der beim ersten Lauf an einem fehlenden Eintrag scheitert.
  # *With SERVER_IPV4=dynamic this program owns the record and therefore creates
  #  it; in fixed mode it stays hand-made. Treating both alike would either
  #  overwrite foreign records or fail on the first run.*
  log "Adresse messen und A-Eintrag setzen"
  cf-dns ziel-setzen || fehler "A-Eintrag ${DNS_ZIEL} konnte nicht gesetzt werden"
  systemctl enable --now dns-ziel.timer
else
  # Feste Adresse: der Zeitgeber bleibt aus. Er liegt trotzdem auf der Maschine,
  # damit ein Wechsel auf "dynamic" nur eine Zeile in konfiguration.env ist.
  # *Fixed address: the timer stays off but is installed, so switching to
  #  "dynamic" is one line in konfiguration.env.*
  systemctl disable --now dns-ziel.timer 2>/dev/null || true
  log "SERVER_IPV4 ist fest (${SERVER_IPV4}) — Zeitgeber bleibt aus"
  log "Zielsatz pruefen"
  # Im festen Betrieb muss der A-Eintrag DNS_ZIEL von Hand existieren — er ist
  # der einzige Ort mit der IP-Adresse und wird deshalb bewusst NICHT
  # automatisch angelegt.
  # *In fixed mode the A record must exist by hand: it is the only place holding
  #  the IP and is therefore deliberately not created automatically.*
  cf-dns liste | head -20 || fehler "cf-dns kommt nicht an die API — Token pruefen"
fi

log "Vorhandene Spielserver eintragen"
for d in /opt/stacks/*/; do
  s=$(basename "$d")
  cf-dns setzen "$s" || warn "DNS fuer $s fehlgeschlagen"
done

log "Gegenprobe: nichts darf proxied sein"
cf-dns pruefen

log "Stufe 70 fertig."
