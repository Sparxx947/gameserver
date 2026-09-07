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

STUFEN=(10-basis 20-docker 30-panel 40-caddy-ttyd 50-sicherung)

if [ $# -gt 0 ]; then
  STUFEN=("$@")
fi

echo
echo "  Einrichtung auf:  $(hostname) / $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  Panel:            https://${PANEL_DOMAIN}/"
echo "  Zone:             ${DNS_ZONE}   Ziel: ${DNS_ZIEL}"
echo "  Sicherung:        ${BORG_REPO}"
echo "  Stufen:           ${STUFEN[*]}"
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
