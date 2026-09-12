#!/bin/bash
# Startet den SCUM-Server: erst aktualisieren, dann unter Wine fahren.
#
# Geordnetes Anhalten ist hier kein Luxus: SCUM schreibt seinen Spielstand beim
# Herunterfahren, und ein SIGKILL mitten hinein kostet die Datenbank. Deshalb
# geht SIGTERM als SIGINT an den Serverprozess und wir warten auf ihn.
#
# *Graceful shutdown matters: SCUM writes its save on exit, and a SIGKILL in the
#  middle costs the database. SIGTERM is forwarded as SIGINT and we wait.*
set -u

GAMEPORT="${GAMEPORT:-7777}"
QUERYPORT="${QUERYPORT:-27015}"
MAXPLAYERS="${MAXPLAYERS:-4}"
ADDITIONALFLAGS="${ADDITIONALFLAGS:-}"
APPID=3792580          # "SCUM Server", nur als Windows-Programm zu haben
EXE="$SERVERDIR/SCUM/Binaries/Win64/SCUMServer.exe"

melde() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }

if [ "$(id -u)" = "0" ]; then
  melde "FEHLER: laeuft als root. Dieses Abbild ist fuer 4711 gebaut."
  exit 1
fi

melde "Serverdateien aktualisieren (App $APPID, Windows-Zweig) ..."
"$STEAMCMD/steamcmd.sh" +@sSteamCmdForcePlatformType windows \
  +force_install_dir "$SERVERDIR" +login anonymous +app_update "$APPID" validate +quit \
  || { melde "FEHLER: SteamCMD fehlgeschlagen - es wird nichts gestartet."; exit 1; }

if [ ! -f "$EXE" ]; then
  melde "FEHLER: $EXE fehlt nach dem Aktualisieren."
  exit 1
fi

# Ohne crypt32 verweigert die Steam-Anbindung den Dienst. Im Bau versucht, hier
# noch einmal nachgesehen - eine fehlende Wine-Komponente sieht sonst aus wie
# ein kaputter Server.
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/crypt32.dll" ]; then
  melde "HINWEIS: crypt32 fehlt im Wine-Prefix - der Server kann sich bei Steam nicht melden."
fi

kind=""
aufraeumen() {
  [ -n "$kind" ] || exit 0
  melde "Anhalten angefordert - SIGINT an den Server (PID $kind)."
  kill -INT "$kind" 2>/dev/null
  for _ in $(seq 1 90); do
    kill -0 "$kind" 2>/dev/null || { melde "Server sauber beendet."; exit 0; }
    sleep 1
  done
  melde "Server reagiert nicht - SIGKILL."
  kill -KILL "$kind" 2>/dev/null
  exit 0
}
trap aufraeumen TERM INT

melde "Server starten: Port $GAMEPORT, Abfrage $QUERYPORT, bis $MAXPLAYERS Spieler."
# shellcheck disable=SC2086
xvfb-run --auto-servernum --server-args="-screen 0 1024x768x24" \
  wine "$EXE" -log -port="$GAMEPORT" -QueryPort="$QUERYPORT" -MaxPlayers="$MAXPLAYERS" \
  $ADDITIONALFLAGS &
huelle=$!

# Wine startet das Programm in einem eigenen Prozess; fuer das geordnete
# Anhalten brauchen wir DESSEN Nummer, nicht die der Huelle.
for _ in $(seq 1 60); do
  kind=$(pgrep -f "SCUMServer.exe" | head -1)
  [ -n "$kind" ] && break
  sleep 1
done
[ -n "$kind" ] && melde "SCUMServer.exe laeuft als PID $kind." \
               || melde "HINWEIS: SCUMServer.exe nicht gefunden - Anhalten trifft nur die Huelle."

wait "$huelle"
