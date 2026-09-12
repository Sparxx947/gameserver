#!/bin/bash
# Stufe 40 — Caddy (HTTPS, Zertifikat, Vorschaltung) und das Webterminal ttyd.
# *Stage 40 — Caddy (HTTPS, certificates, reverse proxy) and the ttyd terminal.*
. "$(dirname "$0")/lib.sh"

TTYD_VERSION="1.7.7"

if ! command -v caddy >/dev/null; then
  log "Caddy-Repository eintragen"
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
fi
apt-get install -y -qq caddy

# --- ttyd -------------------------------------------------------------
# Kein Debian-Paket: bookworm liefert ttyd 1.6, dessen --base-path sich anders
# verhaelt. Deshalb das statisch gelinkte Release-Binary.
# *No Debian package: bookworm ships ttyd 1.6 whose --base-path behaves
#  differently. Hence the statically linked release binary.*
if [ "$(/usr/local/bin/ttyd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" != "$TTYD_VERSION" ]; then
  log "ttyd $TTYD_VERSION holen"
  curl -fsSL -o /usr/local/bin/ttyd \
    "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
  chmod 0755 /usr/local/bin/ttyd
fi

# --- Zertifikatsweg ---------------------------------------------------
# Beide Dateien werden ERZEUGT und nicht eingesetzt: ihr Inhalt haengt an einem
# Wert, nicht an einer Vorlage - wie /etc/gameserver-version. Verglichen werden
# sie deshalb nicht byteweise, sondern von abgleich.sh gegen ZERTIFIKAT_WEG.
# *Both files are generated rather than installed, because their content depends
#  on a value; the comparison checks them against ZERTIFIKAT_WEG instead.*
ZERT_KONF=/etc/caddy/zertifikat.conf
DROPIN=/etc/systemd/system/caddy.service.d/dns01.conf
CADDY_DNS=/usr/local/bin/caddy

if [ "$ZERTIFIKAT_WEG" = "dns-01" ]; then
  anbieter=$(sed -n 's/^[[:space:]]*ANBIETER[[:space:]]*=[[:space:]]*//p' "$DNS_KONF" | head -1)
  # Nur geprueften Anbietercode ausliefern. Es gibt caddy-dns-Module fuer viele
  # Anbieter, aber ein Modul, das nie gegen die echte Zone lief, sieht aus als
  # liefe es - dieselbe Regel wie fuer dns-pflegen selbst (#60, #66).
  # *Only ship provider code that has been run: a module that never talked to
  #  the real zone looks like it works.*
  [ "$anbieter" = "cloudflare" ] || fehler \
    "ZERTIFIKAT_WEG=dns-01 ist bisher nur mit ANBIETER=cloudflare geprueft," \
    "$DNS_KONF nennt \"$anbieter\". Siehe docs/06-netz-dns-firewall.md."

  # Der Caddy aus dem Paket kennt keine DNS-Module - "acme_dns cloudflare" wird
  # von einem Binary ohne caddy-dns/cloudflare abgewiesen. Deshalb ein eigener
  # Bau mit xcaddy.
  #
  # Er landet unter /usr/local/bin und ERSETZT NICHT /usr/bin/caddy. Das Paket
  # bleibt damit verwaltet und bekommt weiter Sicherheitsaktualisierungen;
  # unattended-upgrades laeuft hier scharf und wuerde eine ueberschriebene
  # Paketdatei beim naechsten Caddy-Update wortlos zuruecksetzen - auf einen
  # Caddy, der sein eigenes Zertifikat nicht mehr erneuern kann. Bemerkt haette
  # man das 60 Tage spaeter.
  # *The built binary goes to /usr/local/bin and does not replace the packaged
  #  one: unattended-upgrades would silently restore a Caddy that cannot renew
  #  its own certificate, and that would surface 60 days later.*
  paketstand=$(/usr/bin/caddy version 2>/dev/null | grep -oE '^v[0-9.]+')
  eigen=$(/usr/local/bin/caddy version 2>/dev/null | grep -oE '^v[0-9.]+')
  hat_modul=$(/usr/local/bin/caddy list-modules 2>/dev/null | grep -c "^dns.providers.$anbieter$")
  if [ "$eigen" != "$paketstand" ] || [ "${hat_modul:-0}" -eq 0 ]; then
    log "Caddy mit DNS-Modul bauen (xcaddy, $paketstand)"
    apt-get install -y -qq golang-go
    export GOPATH=/root/go GOCACHE=/root/.cache/go-build
    PATH="/root/go/bin:$PATH"
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
      || fehler "xcaddy liess sich nicht holen"
    # Auf denselben Stand bauen wie das Paket: zwei Caddy-Fassungen auf einer
    # Maschine, die sich in der Version unterscheiden, sind genau die Sorte
    # Abweichung, die niemand sucht.
    # *Build the same version the package has: two Caddy versions on one machine
    #  is the kind of drift nobody goes looking for.*
    /root/go/bin/xcaddy build "$paketstand" \
      --with "github.com/caddy-dns/$anbieter" --output "$CADDY_DNS.neu" \
      || fehler "xcaddy-Bau fehlgeschlagen"
    chmod 0755 "$CADDY_DNS.neu"; mv "$CADDY_DNS.neu" "$CADDY_DNS"
    "$CADDY_DNS" list-modules | grep -qx "dns.providers.$anbieter" \
      || fehler "gebauter Caddy kennt dns.providers.$anbieter nicht"
  fi

  # --environ MUSS weg. Debians Einheit startet mit "caddy run --environ", und
  # das schreibt die VOLLSTAENDIGE Umgebung ins Journal - gemessen: ein
  # Testwert stand danach im Klartext in "journalctl -u". Zusammen mit dem
  # EnvironmentFile unten stuende dort der DNS-Token, der in seiner eigenen
  # Datei mit 0600 liegt. Ein Geheimnis, das ueber einen Umweg im Protokoll
  # landet, ist kein Geheimnis mehr.
  # *--environ must go: Debian's unit starts Caddy with it, and it writes the
  #  entire environment to the journal (measured). Together with the
  #  EnvironmentFile below the 0600 DNS token would stand there in clear.*
  #
  # EnvironmentFile zeigt auf DIESELBE Datei, die dns-pflegen liest. Kein
  # zweites Exemplar des Tokens: zwei Orte fuer ein Geheimnis laufen
  # auseinander, und dann entscheidet ein Vorrang, welches gilt.
  # systemd liest die Datei als root, bevor es auf den Benutzer caddy
  # wechselt - 0600 root:root bleibt also richtig.
  # *Same file dns-pflegen reads, no second copy. systemd reads it as root
  #  before dropping to the caddy user, so 0600 root:root stays correct.*
  mkdir -p "$(dirname "$DROPIN")"
  cat > "$DROPIN" <<EOF
[Service]
ExecStart=
ExecStart=$CADDY_DNS run --config /etc/caddy/Caddyfile
ExecReload=
ExecReload=$CADDY_DNS reload --config /etc/caddy/Caddyfile --force
EnvironmentFile=$DNS_KONF
EOF
  chmod 0644 "$DROPIN"
  printf 'acme_dns %s {env.TOKEN}\n' "$anbieter" > "$ZERT_KONF"
  log "Zertifikat ueber dns-01 ($anbieter) - kein eingehender Port noetig"
else
  # Leer, nicht fehlend: die Caddyfile importiert die Datei unbedingt, und ein
  # fehlender Import ist ein Abbruch. Leer heisst "Caddy macht, was es von sich
  # aus tut" - also http-01 beziehungsweise tls-alpn-01.
  # *Empty, not absent: the Caddyfile imports it unconditionally and a missing
  #  file aborts. Empty means "whatever Caddy does by itself".*
  : > "$ZERT_KONF"
  rm -f "$DROPIN"
fi
chmod 0644 "$ZERT_KONF"

# Die Routendatei der Zusatzmodule. Leer, aber vorhanden: Die Caddyfile bindet
# sie unbedingt ein, ein fehlender Import bricht "caddy validate" ab - und
# vorhandene Routen darf diese Stufe nicht wegwerfen, deshalb nur anlegen,
# wenn sie fehlt.
# *Empty but present: the Caddyfile imports it unconditionally. Only created
#  when missing, so an existing module route survives a re-run of this stage.*
MODUL_KONF=/etc/caddy/module.conf
if [ ! -f "$MODUL_KONF" ]; then
  printf '# Erzeugt von modul-verwalten. Ohne Modul leer.\n' > "$MODUL_KONF"
fi
chmod 0644 "$MODUL_KONF"

log "Konfiguration"
einsetzen "$REPO/etc/caddy/Caddyfile" /etc/caddy/Caddyfile 0644 root:root
einsetzen "$REPO/systemd/ttyd.service" /etc/systemd/system/ttyd.service

# caddy validate prueft die Datei, BEVOR der laufende Dienst sie bekommt. Ohne
# das laesst ein Tippfehler den Reverse Proxy stehen und das Panel ist weg —
# samt Webterminal, ueber das man es reparieren wuerde.
# *Validate before reloading: a typo would take down the proxy, the panel and
#  the very terminal one would use to fix it.*
#
# Geprueft wird mit DEM Binary, das den Dienst spaeter faehrt. Mit dem Caddy aus
# dem Paket scheitert die Pruefung bei ZERTIFIKAT_WEG=dns-01 an "acme_dns" -
# einer Zeile, die richtig ist und nur von diesem Binary nicht verstanden wird.
# *Validated with the binary that will actually run the service: the packaged
#  Caddy rejects "acme_dns", a line that is correct and merely unknown to it.*
#
# Bei dns-01 muss der Token beim PRUEFEN in der Umgebung stehen. Das
# EnvironmentFile gilt nur fuer die systemd-Einheit, in der Shell dieser Stufe
# ist {env.TOKEN} leer - und das Cloudflare-Modul prueft den Token schon beim
# Einlesen der Konfiguration ("API token '' appears invalid"). Ohne das scheitert
# eine voellig richtige Caddyfile an einer Umgebung, die nur der Pruefung fehlt.
#
# Gelesen wird er in einer Subshell aus derselben 0600-Datei und NICHT als
# Argument uebergeben: in argv stuende er in der Prozessliste, die jeder Nutzer
# der Maschine lesen kann.
# *At validation time the token must be in the environment: the EnvironmentFile
#  applies to the unit only, and the Cloudflare module checks the token while
#  loading the config. Read in a subshell from the same 0600 file, never passed
#  as an argument - argv is visible in the process list to every user.*
if [ "$ZERTIFIKAT_WEG" = "dns-01" ]; then PRUEFER="$CADDY_DNS"; else PRUEFER=caddy; fi
( set -a; . "$DNS_KONF"; set +a
  "$PRUEFER" validate --config /etc/caddy/Caddyfile >/dev/null ) \
  || fehler "Caddyfile ungueltig"

systemctl daemon-reload
systemctl enable --now caddy ttyd
# restart, nicht reload: Das Drop-in aendert ExecStart, und ein Reload laesst den
# alten Prozess mit dem alten Befehl weiterlaufen - Caddy liefe dann ohne
# EnvironmentFile und ohne DNS-Modul weiter, waehrend die Stufe Erfolg meldet.
# *restart, not reload: the drop-in changes ExecStart, and a reload would leave
#  the old process running the old command while the stage reports success.*
systemctl restart caddy

log "Stufe 40 fertig. Panel: https://${PANEL_DOMAIN}/"
