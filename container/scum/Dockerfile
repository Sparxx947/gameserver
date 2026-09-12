# SCUM-Server als unser eigenes Abbild.
#
# Warum ueberhaupt ein eigenes: Das verbreitete Fremdabbild laeuft als root und
# legt seine Dateien als root in /srv/games an - als einziger Server dieser
# Maschine. Hier laeuft der Serverprozess als 4711 ("spiele"), wie jeder andere.
# Uebernommen ist davon nichts: Das Fremdprojekt steht ohne Lizenz im Netz
# ("all rights reserved"), sein Dockerfile darf man nicht kopieren. Was hier
# steht, sind die technischen Notwendigkeiten - SCUM ist ein Windows-Programm,
# also Wine; es will einen X-Server, also Xvfb; Wine braucht winbind fuer
# ntlm_auth und crypt32 aus winetricks fuer die Steam-Anbindung.
#
# *Why our own image: the common third-party one runs as root and writes
#  root-owned files into /srv/games, alone among the servers here. This one runs
#  as 4711 like every other. Nothing was copied - that project carries no
#  licence. What follows are the technical necessities: SCUM is a Windows
#  program (Wine), it wants an X server (Xvfb), and Wine needs winbind plus
#  crypt32 for Steam.*
FROM debian:trixie-slim

LABEL org.opencontainers.image.title="Platzwart SCUM-Server"
LABEL org.opencontainers.image.description="SCUM dedicated server under Wine, running as an unprivileged user (uid 4711)"
LABEL org.opencontainers.image.source="https://github.com/Sparxx947/gameserver"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    WINEARCH=win64 \
    WINEPREFIX=/opt/wine \
    WINEDEBUG=-all \
    XDG_RUNTIME_DIR=/tmp \
    STEAMCMD=/opt/steamcmd \
    SERVERDIR=/opt/scumserver

# 1. Grundwerkzeug. cabextract braucht winetricks, xauth braucht xvfb-run.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget gnupg locales procps psmisc unzip cabextract \
        xvfb xauth x11-utils xfonts-base tini \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# 2. Wine aus der Quelle des Wine-Projekts, nicht aus Debian: SCUM braucht eine
#    neuere Fassung, als die Distribution mitbringt.
RUN mkdir -p /etc/apt/keyrings \
    && wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
       | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key - \
    && wget -qNP /etc/apt/sources.list.d/ \
       https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable winbind \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Der Benutzer, unter dem alles laeuft. 4711 ist projektweit "spiele" - so
#    gehoeren die Spielstaende auf dem Wirt demselben Eigentuemer wie bei jedem
#    anderen Server, und ein Ausbruch aus dem Container waere nicht root.
RUN groupadd -g 4711 spiele && useradd -u 4711 -g 4711 -m -d /home/spiele spiele \
    && mkdir -p "$WINEPREFIX" "$STEAMCMD" "$SERVERDIR" \
    && chown -R 4711:4711 "$WINEPREFIX" "$STEAMCMD" "$SERVERDIR"

USER 4711:4711

# 4. Wine-Umgebung und SteamCMD als DERSELBE Benutzer anlegen, der sie spaeter
#    benutzt: Ein Wine-Prefix gehoert einem Benutzer, ein fremder ist unbrauchbar.
RUN wineboot --init > /dev/null 2>&1 && wineserver -w
# winetricks auf eine Fassung festgenagelt, nicht "master": Eine Werkzeugkette,
# die sich unter einem weg aendert, macht jeden Fehlschlag unerklaerbar.
# *Pinned rather than master: a toolchain that shifts underfoot makes every
#  failure unexplainable.*
RUN wget -qO /tmp/winetricks \
      https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20260125/src/winetricks \
    && chmod +x /tmp/winetricks \
    && (/tmp/winetricks -q crypt32 > /tmp/winetricks.log 2>&1 \
        || echo "HINWEIS: winetricks crypt32 fehlgeschlagen - Start prueft es erneut") \
    && rm -f /tmp/winetricks
RUN wget -qO /tmp/steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    && tar -xzf /tmp/steamcmd.tar.gz -C "$STEAMCMD" \
    && rm -f /tmp/steamcmd.tar.gz

COPY --chown=4711:4711 start.sh /opt/start.sh

VOLUME ["/opt/scumserver"]
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/start.sh"]
