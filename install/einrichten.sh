#!/bin/bash
# ======================================================================
#  gameserver — Einrichtung von Grund auf
#  *gameserver — set up from scratch*
#
#  Fuehrt die Stufen der Reihe nach aus. Jede Stufe ist einzeln aufrufbar
#  und mehrfach ausfuehrbar (idempotent): vorhandene Dateien werden vor
#  dem Ueberschreiben nach <datei>.vor-<datum> gesichert, vorhandene
#  Geheimnisse (Panel-Zugang, Borg-Passphrase, Stack-Passwoerter) bleiben
#  unangetastet.
#
#  *Runs the stages in order. Each is idempotent and can be run on its own:
#   existing files are backed up to <file>.vor-<date> before being replaced,
#   and existing secrets are never regenerated.*
#
#  Voraussetzungen / prerequisites:
#    * Debian 12 (bookworm), root
#    * konfiguration.env ausgefuellt (Vorlage: konfiguration.env.beispiel)
#    * PANEL_DOMAIN zeigt oeffentlich auf SERVER_IPV4 (sonst kein Zertifikat)
#    * Tailscale ist verbunden, wenn ueber das Tailnet gesichert wird
# ======================================================================
. "$(dirname "$0")/lib.sh"

# 25 steht vor 40, weil Caddy dort das Zertifikat fuer PANEL_DOMAIN holt und
# der Name dafuer schon aufloesen muss. Ohne Cloudflare-Token ueberspringt sich
# die Stufe von selbst.
# *25 precedes 40 because the panel certificate needs the name to resolve
#  already. Without a Cloudflare token the stage skips itself.*
STUFEN=(10-basis 20-docker 25-dns-grundgeruest 30-panel 40-caddy-ttyd 50-sicherung)

if [ $# -gt 0 ]; then
  STUFEN=("$@")
fi

# --- Der DNS-Zugang gehoert VOR die Rueckfrage -------------------------------
#
# Der Token steht nicht in konfiguration.env, sondern in einer eigenen Datei mit
# 0600 — er ist ein Geheimnis, und die Werte aus konfiguration.env werden in
# Dateien eingesetzt, die 0755 auf der Maschine liegen. Diese Trennung ist
# richtig, hat aber eine Kante: es ist eine ZWEITE Datei, die von Hand angelegt
# werden muss, und wer das nicht weiss, merkt es erst spaet.
#
# Der Hinweis darauf stand bisher in Stufe 25 und kam damit zu spaet: da laeuft
# die Einrichtung schon, die Zeilen scrollen vorbei, und was daran haengt faellt
# erst in Stufe 40 auf — nachdem ACME einen Fehlversuch verbucht hat. Dessen
# Sperrfristen zaehlen in Stunden, ein zweiter Anlauf ist also nicht umsonst.
#
# Deshalb hier, vor der Rueckfrage: wer den Token vergessen hat, bricht mit
# einem Tastendruck ab, legt die Datei an und startet EINMAL sauber durch.
#
# *The token lives in its own 0600 file rather than in konfiguration.env,
#  because values from there get substituted into 0755 files. That split is
#  right, but it means a second file to create by hand. The hint used to live in
#  stage 25, which was too late: by then the run is under way and the
#  consequence only surfaces in stage 40, after ACME has booked a failed attempt
#  whose rate limits count in hours. Shown before the prompt instead, so a
#  forgotten token costs one keystroke and not one run.*
dns_fehlt=""
if printf '%s\n' "${STUFEN[@]}" | grep -qx 25-dns-grundgeruest; then
  if [ -s "$DNS_KONF" ]; then
    dns_anbieter=$(sed -n 's/^[[:space:]]*ANBIETER[[:space:]]*=[[:space:]]*//p' "$DNS_KONF" | head -1)
    dns_zeile="${dns_anbieter:-cloudflare} — $DNS_KONF"
  elif [ -s "$DNS_KONF_ALT" ]; then
    dns_zeile="cloudflare — $DNS_KONF_ALT (wird uebernommen)"
  else
    dns_zeile="KEIN TOKEN — $DNS_KONF fehlt"
    dns_fehlt=ja
  fi
else
  dns_zeile="Stufe 25 ist nicht dabei"
fi

echo
echo "  Einrichtung auf:  $(hostname) / $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  Panel:            https://${PANEL_DOMAIN}/"
echo "  Zone:             ${DNS_ZONE}   Ziel: ${DNS_ZIEL}"
echo "  DNS-Zugang:       ${dns_zeile}"
echo "  Sicherung:        ${BORG_REPO}"
echo "  Stufen:           ${STUFEN[*]}"
if [ -n "$dns_fehlt" ]; then
  echo
  warn "Stufe 25 wird sich ueberspringen. Dann muessen ${DNS_ZIEL} und"
  warn "${PANEL_DOMAIN} BEREITS oeffentlich auf diese Maschine zeigen —"
  warn "sonst scheitert in Stufe 40 das Zertifikat, und Let's Encrypt sperrt"
  warn "eine Wiederholung fuer Stunden."
  warn ""
  warn "Jetzt anlegen und neu starten, dann laeuft es in einem Zug durch:"
  warn "  printf 'ANBIETER=cloudflare\\nTOKEN=%s\\n' '<token>' > $DNS_KONF"
  warn "  chmod 600 $DNS_KONF"
  warn ""
  warn "Token: Cloudflare-Dashboard, Zone / DNS / Bearbeiten, nur ${DNS_ZONE}."
fi
echo
read -r -p "  Fortfahren? / continue? [j/N] " a
case "$a" in j|J|y|Y) ;; *) echo "Abgebrochen."; exit 0 ;; esac
echo

for s in "${STUFEN[@]}"; do
  skript="$REPO/install/${s}.sh"
  [ -f "$skript" ] || fehler "Unbekannte Stufe: $s"
  echo
  echo "############ $s ############"
  bash "$skript" || fehler "Stufe $s ist gescheitert — hier anhalten und die Ursache klaeren."
done

# Erst nach ALLEN Stufen: vorher haette jede einzelne Stufe den Stempel schon
# wieder auf "geaendert" gesetzt.
# *After all stages: any single stage would have marked it "geaendert" again.*
version_stempeln sauber
log "Stand: $(tr '\n' ' ' < "$VERSIONSDATEI")"

cat <<TEXT

  ====================================================================
   Grundgeruest steht. / Base system is up.

   Weiter mit / next:

     install/60-spiele.sh <stack> [...]   die handgepflegten Server
                                          *hand-maintained servers*
       verfuegbar: $(ls "$REPO"/stacks/ | sed 's/\.yaml$//' | tr '\n' ' ')

     install/70-dns.sh                    Cloudflare-Namen (optional)
                                          *Cloudflare records (optional)*

   Katalogspiele danach im Panel unter "Spiele" oder mit
     spiel-verwalten installieren <schluessel>
   *Catalogue games via the panel's "Spiele" page or the command above.*
  ====================================================================

TEXT
