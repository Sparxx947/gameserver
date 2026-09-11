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

# Einsetzen und Ein-/Ausschalten macht dns_ziel_zeitgeber() (lib.sh), dieselbe
# Funktion wie in Stufe 25 (#195). Hier laeuft sie NACH ziel-setzen bzw. der
# Zielpruefung weiter unten, damit der Zeitgeber erst startet, wenn der Eintrag
# steht.
# *Installing and switching is dns_ziel_zeitgeber(), shared with stage 25.*


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
  dns-pflegen ziel-setzen || fehler "A-Eintrag ${DNS_ZIEL} konnte nicht gesetzt werden"
  dns_ziel_zeitgeber
else
  # Feste Adresse: der Zeitgeber bleibt aus. Er liegt trotzdem auf der Maschine,
  # damit ein Wechsel auf "dynamic" nur eine Zeile in konfiguration.env ist.
  # *Fixed address: the timer stays off but is installed, so switching to
  #  "dynamic" is one line in konfiguration.env.*
  dns_ziel_zeitgeber
  log "Zielsatz pruefen"
  # Im festen Betrieb muss der A-Eintrag DNS_ZIEL von Hand existieren — er ist
  # der einzige Ort mit der IP-Adresse und wird deshalb bewusst NICHT
  # automatisch angelegt.
  # *In fixed mode the A record must exist by hand: it is the only place holding
  #  the IP and is therefore deliberately not created automatically.*
  dns-pflegen liste | head -20 || fehler "dns-pflegen kommt nicht an die API — Token pruefen"
fi

# Der alte Name des Werkzeugs. Entfernt wird er ERST HIER und nicht in Stufe 25
# oder 30 - und erst NACH dns_ziel_zeitgeber oben: bis die Einheit neu eingesetzt ist, ruft dns-ziel.service noch
# /usr/local/bin/cf-dns. Wer ihn frueher wegnimmt, bricht den Zeitgeber fuer die
# Dauer der Aktualisierung - und zwar an einer Stelle, an der niemand sucht.
# *Removed here and not earlier: until the unit above is replaced,
#  dns-ziel.service still calls the old path. Removing it sooner breaks the
#  timer for the duration of the upgrade, somewhere nobody would look.*
rm -f /usr/local/bin/cf-dns

log "Vorhandene Spielserver eintragen"
for d in /opt/stacks/*/; do
  s=$(basename "$d")
  dns-pflegen setzen "$s" || warn "DNS fuer $s fehlgeschlagen"
done

log "Gegenprobe: nichts darf proxied sein"
dns-pflegen pruefen

log "Stufe 70 fertig."
