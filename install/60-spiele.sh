#!/bin/bash
# Stufe 60 — die von Hand gepflegten Serverstacks aus stacks/.
#
# Diese sieben Server sind NICHT ueber den Katalog installiert: sie brauchen je
# ein eigenes Image (Enshrouded, Palworld, Satisfactory, FOUNDRY, StarRupture,
# Windrose) oder sind gar kein Spiel (TeamSpeak). Katalogspiele kommen spaeter
# ueber die Oberflaeche oder "spiel-verwalten installieren <schluessel>".
#
# *These seven are not catalogue installs: each needs its own image, or is not
#  a game at all (TeamSpeak). Catalogue games are added later through the panel
#  or "spiel-verwalten installieren <key>".*
. "$(dirname "$0")/lib.sh"

STACKS=("$@")
[ ${#STACKS[@]} -eq 0 ] && { echo "Aufruf: $0 <stack> [<stack> ...]"; echo "Verfuegbar:"; ls "$REPO"/stacks/ | sed 's/\.yaml$//' | sed 's/^/  /'; exit 0; }

for s in "${STACKS[@]}"; do
  quelle="$REPO/stacks/$s.yaml"
  [ -f "$quelle" ] || fehler "Unbekannter Stack: $s"
  ziel="/opt/stacks/$s"

  if [ -f "$ziel/compose.yaml" ]; then
    warn "$s ist bereits eingerichtet — uebersprungen (Passwoerter blieben unangetastet)."
    continue
  fi

  # Passwoerter JE STACK frisch. Sie stehen im Klartext in der compose-Datei,
  # weil die Spielserver sie so verlangen — deshalb 0600 und root als
  # Eigentuemer. Das Panel zeigt sie an, indem panel-aktion sie als root liest.
  # *Passwords are per stack and freshly generated. They sit in cleartext in the
  #  compose file because the game servers require it — hence 0600 root. The
  #  panel displays them by having panel-aktion read them as root.*
  PW=$(passwort 14); ADMIN=$(passwort 14)

  mkdir -p "$ziel"
  # Erst rendern, DANN ersetzen — nicht in einer Pipe: "fehler" beendet in einer
  # Pipe nur die Subshell, und die compose-Datei entstuende halbfertig.
  # *Not a pipe: "fehler" would only exit the subshell and leave a half-written
  #  compose file behind.*
  vorlage=$(rendern "$quelle" '@@(ADMIN_)?PASSWORT@@') || exit 1
  printf '%s\n' "$vorlage" \
    | sed -e "s|@@PASSWORT@@|$PW|g" -e "s|@@ADMIN_PASSWORT@@|$ADMIN|g" \
    > "$ziel/compose.yaml"
  chmod 0600 "$ziel/compose.yaml"; chown root:root "$ziel/compose.yaml"

  # Datenverzeichnis. UID/GID 4711 = Benutzer "spiele": die Container laufen
  # unter dieser Kennung (PUID/UID im compose), sonst gehoeren die Spielstaende
  # niemandem und der Server kann nicht schreiben.
  # *UID/GID 4711 = user "spiele": the containers run as this id, otherwise the
  #  save files are ownerless and the server cannot write.*
  if grep -q "/srv/dienste/$s" "$ziel/compose.yaml"; then
    install -d -m 0770 -o 4711 -g 4711 "/srv/dienste/$s"
  else
    install -d -m 0770 -o 4711 -g 4711 "/srv/games/$s"
  fi

  log "$s eingerichtet — Beitritt: $PW / Admin: $ADMIN"
done

echo
echo "  Starten mit / start with:"
for s in "${STACKS[@]}"; do echo "    docker compose -f /opt/stacks/$s/compose.yaml up -d"; done
echo
echo "  Die Passwoerter stehen danach im Panel unter \"Zugaenge\"."
echo "  *The passwords are listed in the panel under \"Zugaenge\" afterwards.*"
