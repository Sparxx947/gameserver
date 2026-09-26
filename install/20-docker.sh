#!/bin/bash
# Stufe 20 — Docker aus dem Hersteller-Repository.
# Debians eigenes docker.io ist zu alt fuer "docker compose" (Plugin-Form);
# die compose-Dateien hier setzen die v2-Syntax voraus.
# *Debian's own docker.io is too old for the "docker compose" plugin; every
#  compose file here assumes v2 syntax.*
. "$(dirname "$0")/lib.sh"

if ! command -v docker >/dev/null; then
  log "Docker-Repository eintragen"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
fi

# daemon.json VOR dem ersten Start (#329): Logrotation und live-restore.
# Ohne max-size wuchs das Log eines einzigen Containers auf 112 MB in 13 Tagen,
# und ohne live-restore hielt jedes Docker-Update ALLE Spielserver an. Die Werte
# gelten nur fuer neu erzeugte Container - deshalb gleich zu Beginn.
# *daemon.json before the first start: log rotation and live-restore. Without
#  max-size one container's log reached 112 MB in 13 days; without live-restore
#  every Docker update stopped all game servers. Only new containers pick up the
#  log options, hence right at the start.*
install -m 0755 -d /etc/docker
if ! cmp -s "$REPO/etc/docker/daemon.json" /etc/docker/daemon.json; then
  install -m 0644 -o root -g root "$REPO/etc/docker/daemon.json" /etc/docker/daemon.json
  DAEMON_NEU=1
fi

log "Docker installieren"
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
# War Docker schon da, liest es die geaenderte daemon.json erst nach einem
# Neustart. Auf einer laufenden Maschine haelt der die Spielserver an - einmal,
# danach verhindert live-restore genau das.
# *An existing Docker reads a changed daemon.json only after a restart, which
#  stops the game servers once - live-restore prevents that from then on.*
[ "${DAEMON_NEU:-0}" = 1 ] && systemctl restart docker

# ACHTUNG: den Menschen NICHT in die Gruppe "docker" aufnehmen. Wer mit Docker
# sprechen darf, kann sich mit einem Einzeiler root verschaffen
# (docker run -v /:/host). Fuer die Weboberflaeche gibt es deshalb die enge
# sudo-Bruecke panel-aktion, nicht den Socket.
# *Deliberately NOT adding anyone to the "docker" group: socket access is
#  equivalent to root (docker run -v /:/host). The panel uses the narrow
#  panel-aktion sudo bridge instead.*

log "Stufe 20 fertig. Docker: $(docker --version)"
