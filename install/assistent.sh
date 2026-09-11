#!/bin/bash
# ======================================================================
#  assistent.sh — gefuehrte Einrichtung von Grund auf
#  *assistent.sh — guided setup from scratch*
#
#    sudo install/assistent.sh                      fragen, pruefen, einrichten
#    sudo install/assistent.sh --nur-konfiguration  nur konfiguration.env und die
#                                                   Zugangsdateien schreiben
#    install/assistent.sh --selbsttest              die Pruefregeln mit Beispielen
#
#  Drei Wege: Neueinrichtung, Wiederaufbau aus einer vorhandenen Sicherung,
#  oder nur die Konfiguration. Bis zur Bestaetigung am Ende der Fragen richtet
#  der Assistent nichts ein. Vorher geschieht nur, was die Pruefungen brauchen:
#  auf Nachfrage fehlende Werkzeuge (curl, borg ...) und Tailscale installieren;
#  ohne Nachfrage einen SSH-Schluessel fuer root anlegen, wenn keiner da ist, und
#  den Host-Schluessel des Sicherungsservers merken. Danach laufen die bekannten
#  Stufen (install/einrichten.sh, 60-spiele.sh, 70-dns.sh) unveraendert; der
#  Assistent ersetzt sie nicht, er bereitet sie vor und haelt sie zusammen (E34).
#
#  *Three paths: new install, rebuild from an existing backup, or configuration
#   only. Nothing is set up before the confirmation. Before it, only what the
#   checks need: on request missing tools and Tailscale; without asking a root SSH
#   key if none exists, and the backup server's host key. Afterwards the known
#   stages run unchanged; the assistant prepares and sequences them (E34).*
#
#  Warum es ihn gibt (#258): Jede der folgenden Fallen hat eine Neueinrichtung
#  spaet und hart scheitern lassen oder haette es getan, und keine meldet sich
#  vorher von selbst:
#    * Stufe 10 schaltet die Passwortanmeldung ab - ohne hinterlegten Schluessel
#      ist die naechste SSH-Anmeldung ausgesperrt.
#    * Stufe 10 erlaubt SSH nur von ADMIN_IP - sitzt man woanders, kommt man
#      nach dem Abmelden nicht wieder herein.
#    * Stufe 50 spricht den Sicherungsserver mit BatchMode an - auf einer frischen
#      Maschine ist dessen Host-Schluessel unbekannt, borg init scheitert.
#    * Der Admin-Benutzer entsteht ohne Passwort - sudo im Webterminal geht nicht.
#    * Die Erstanmeldung steht einmal mitten in der Ausgabe von Stufe 30 und
#      scrollt weg.
#  *Every one of these traps made or would have made a fresh install fail late
#   and hard, and none announces itself in advance.*
# ======================================================================
set -uo pipefail
umask 077

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Pfade ueber die Umgebung umlenkbar - fuer den Selbsttest und die Probe mit
# Wegwerfdateien, nie im Ernstfall noetig.
# *Overridable for the self-test and dry probes only.*
KONF="${ASSISTENT_KONF:-$REPO/konfiguration.env}"
VORLAGE="$REPO/konfiguration.env.beispiel"
DNS_KONF="${ASSISTENT_DNS_KONF:-/etc/dns-gameserver.conf}"
MELDEN_KONF="${ASSISTENT_MELDEN_KONF:-/etc/platzwart-melden.conf}"
PASSPHRASE=/root/.borg-passphrase
KATALOG="$REPO/etc/spiele-katalog.json"
BEGINN=$(date +%Y%m%d-%H%M%S)
PROTOKOLL="/root/platzwart-einrichtung-$BEGINN.log"

if [ -t 1 ]; then
  ROT=$'\e[31m'; GRUEN=$'\e[32m'; GELB=$'\e[33m'; FETT=$'\e[1m'; AUS=$'\e[0m'
else
  ROT=""; GRUEN=""; GELB=""; FETT=""; AUS=""
fi
log()    { echo "${GRUEN}==>${AUS} $*"; }
warn()   { echo "${GELB}!! ${AUS} $*" >&2; }
fehler() { echo "${ROT}FEHLER:${AUS} $*" >&2; exit 1; }
titel()  { printf '\n%s== %s ==%s\n' "$FETT" "$*" "$AUS"; }
text()   { local z; for z in "$@"; do printf '   %s\n' "$z"; done; }

# ======================================================================
#  Eingabe
# ======================================================================
# Jede Eingabe landet in ANTWORT (global) und nicht in einer
# Befehlsersetzung: "fehler" beendete in $(...) nur die Unterschale, und der
# Aufrufer liefe mit einem leeren Wert weiter. Dateiende (kein Terminal mehr,
# Eingabe zu Ende) bricht ab, statt eine Frage endlos zu wiederholen.
# *Input goes into a global rather than a command substitution, where "fehler"
#  would only exit the subshell. End of input aborts instead of looping.*
ANTWORT=""
lies() {
  if ! IFS= read -r ANTWORT; then
    echo; fehler "Eingabe beendet - abgebrochen. Bis zur Bestaetigung wurde nichts geaendert."
  fi
  ANTWORT="${ANTWORT#"${ANTWORT%%[![:space:]]*}"}"
  ANTWORT="${ANTWORT%"${ANTWORT##*[![:space:]]}"}"
}

# frage <variable> <text> <vorgabe> [pruefer] [meldung]
frage() {
  local var="$1" txt="$2" vorgabe="$3" pruef="${4:-}" meld="${5:-Ungueltiger Wert.}"
  while true; do
    if [ -n "$vorgabe" ]; then printf '  %s [%s]: ' "$txt" "$vorgabe"; else printf '  %s: ' "$txt"; fi
    lies
    [ -n "$ANTWORT" ] || ANTWORT="$vorgabe"
    if [ -z "$ANTWORT" ]; then warn "Bitte einen Wert eingeben."; continue; fi
    if [ -n "$pruef" ] && ! "$pruef" "$ANTWORT"; then warn "$meld"; continue; fi
    printf -v "$var" '%s' "$ANTWORT"
    return 0
  done
}

# wahl <variable> <text> <vorgabe-nummer> "wert|beschreibung" ...
wahl() {
  local var="$1" txt="$2" vorgabe="$3"; shift 3
  local i=1 o
  printf '  %s\n' "$txt"
  for o in "$@"; do printf '    %d) %s\n' "$i" "${o#*|}"; i=$((i + 1)); done
  while true; do
    printf '  Auswahl [%s]: ' "$vorgabe"
    lies
    [ -n "$ANTWORT" ] || ANTWORT="$vorgabe"
    if [[ "$ANTWORT" =~ ^[0-9]+$ ]] && [ "$ANTWORT" -ge 1 ] && [ "$ANTWORT" -le $# ]; then
      o="${!ANTWORT}"
      printf -v "$var" '%s' "${o%%|*}"
      return 0
    fi
    warn "Bitte eine Zahl von 1 bis $# eingeben."
  done
}

# janein <text> <j|n>  -> Rueckgabe 0 = ja
janein() {
  local vorgabe="$2" z
  if [ "$vorgabe" = j ]; then z="J/n"; else z="j/N"; fi
  while true; do
    printf '  %s [%s]: ' "$1" "$z"
    lies
    case "${ANTWORT:-$vorgabe}" in
      j|J|ja|Ja|y|Y|yes) return 0 ;;
      n|N|nein|Nein|no)  return 1 ;;
    esac
    warn "Bitte j oder n."
  done
}

# geheim <variable> <text> [pruefer] [meldung] - ohne Echo, nie in argv.
geheim() {
  local var="$1" txt="$2" pruef="${3:-}" meld="${4:-Ungueltiger Wert.}"
  while true; do
    printf '  %s (Eingabe bleibt unsichtbar): ' "$txt"
    if ! IFS= read -r -s ANTWORT; then echo; fehler "Eingabe beendet - abgebrochen."; fi
    echo
    ANTWORT="${ANTWORT//[[:space:]]/}"
    if [ -z "$ANTWORT" ]; then warn "Leer - bitte eingeben."; continue; fi
    if [ -n "$pruef" ] && ! "$pruef" "$ANTWORT"; then warn "$meld"; continue; fi
    printf -v "$var" '%s' "$ANTWORT"
    ANTWORT=""
    return 0
  done
}

weiter() { printf '  Weiter mit Eingabe ... '; lies; }

# ======================================================================
#  Pruefregeln - rein, ohne Datei und Netz, deshalb im Selbsttest pruefbar
# ======================================================================
ist_ipv4() {
  local a b c d o
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$1"
  for o in "$a" "$b" "$c" "$d"; do [ "$o" -le 255 ] || return 1; done
}
ip_zahl() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
ist_cidr() {
  [[ "$1" == */* ]] || return 1
  local ip="${1%/*}" m="${1#*/}"
  ist_ipv4 "$ip" && [[ "$m" =~ ^[0-9]{1,2}$ ]] && [ "$m" -le 32 ]
}
ist_ip_oder_cidr() { ist_ipv4 "$1" || ist_cidr "$1"; }
# in_netz <ip> <ip-oder-cidr>
in_netz() {
  local ip="$1" netz="$2" m=32 n
  ist_ipv4 "$ip" || return 1
  if ist_cidr "$netz"; then m="${netz#*/}"; netz="${netz%/*}"; fi
  ist_ipv4 "$netz" || return 1
  [ "$m" -eq 0 ] && return 0
  n=$(( (0xFFFFFFFF << (32 - m)) & 0xFFFFFFFF ))
  [ $(( $(ip_zahl "$ip") & n )) -eq $(( $(ip_zahl "$netz") & n )) ]
}
ist_oeffentlich() {
  ist_ipv4 "$1" || return 1
  local n
  for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
           172.16.0.0/12 192.168.0.0/16 192.0.2.0/24 198.51.100.0/24 \
           203.0.113.0/24 224.0.0.0/3; do
    in_netz "$1" "$n" && return 1
  done
  return 0
}
ist_domain() {
  [ ${#1} -le 253 ] && [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}
ist_in_zone() { ist_domain "$1" && [[ "$1" == *".${DNS_ZONE}" ]]; }
ist_benutzer() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  case "$1" in root|panel|spiele|daemon|bin|sys|sync|nobody|www-data|borg) return 1 ;; esac
}
# WELT_NAME landet in compose-Werten, INI-Dateien und Spieltiteln: nur, was in
# allen dreien ohne Anfuehrungszeichen unversehrt bleibt.
# *Ends up in compose values, INI files and game titles: only what survives all
#  three without quoting.*
ist_weltname() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$ ]]; }
ist_borg_repo() {
  [[ "$1" =~ ^ssh://[A-Za-z0-9._-]+@[A-Za-z0-9.-]+(:[0-9]{1,5})?/[^[:space:]]+$ ]] \
    || [[ "$1" =~ ^/[^[:space:]]+$ ]]
}
ist_webhook() { [[ "$1" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$ ]]; }
ist_token() { [[ "$1" =~ ^[A-Za-z0-9_-]{20,200}$ ]]; }
ist_passphrase() { [ ${#1} -ge 8 ]; }
ist_schluessel() {
  [[ "$1" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/=]{40,}(\ .*)?$ ]]
}
ist_passwort() { [ ${#1} -ge 10 ]; }

# Archivname zum Praefix, der juenger ist als nichts und aelter als BEGINN.
# Archive heissen <praefix>-JJJJMMTT-HHMMSS (spiele-sicherung). "Aelter als der
# Beginn" ist kein Zierat: Stufe 50 fuehrt einen Probelauf aus und legt dabei
# frische, leere config-/panel-Archive an - das "neueste" waere dann genau das
# falsche.
# *Newest archive for a prefix that is older than this run: stage 50's test run
#  creates fresh, empty config/panel archives, and "newest" would pick those.*
# neuestes_vor <praefix> <grenze JJJJMMTT-HHMMSS>   (Archivliste auf stdin)
neuestes_vor() {
  local p="$1" g="${2//-/}" name ts beste="" bestts=""
  while IFS= read -r name; do
    [[ "$name" =~ ^(.+)-([0-9]{8})-([0-9]{6})$ ]] || continue
    [ "${BASH_REMATCH[1]}" = "$p" ] || continue
    ts="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    [ "$ts" \< "$g" ] || continue
    if [ -z "$bestts" ] || [ "$bestts" \< "$ts" ]; then beste="$name"; bestts="$ts"; fi
  done
  printf '%s' "$beste"
}

# ======================================================================
#  konfiguration.env aus der Vorlage erzeugen
# ======================================================================
# Die Vorlage bleibt mit allen Erklaerungen erhalten; nur die Wertzeilen werden
# ersetzt. So steht in der erzeugten Datei, was jede Zeile bedeutet, und
# abgleich-/ausrollen-Werkzeuge lesen sie wie immer.
# *The template keeps all its explanations; only the value lines are replaced.*
declare -A WERTE=()
VARIABLEN=(DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER
           ADMIN_NETZ ADMIN_IP SSH_PASSWORT_AUTH SSH_ROOT_LOGIN ZERTIFIKAT_WEG
           BORG_REPO FREMD_IPV4)

konfiguration_schreiben() {   # konfiguration_schreiben <ziel>
  local ziel="$1" tmp z k n v
  tmp=$(mktemp "${ziel}.neu.XXXXXX") || return 1
  {
    printf '# Erzeugt von install/assistent.sh am %s.\n' "$(date -Is)"
    printf '# *Generated by install/assistent.sh.*\n'
    while IFS= read -r z || [ -n "$z" ]; do
      if [[ "$z" =~ ^([A-Z0-9_]+)= ]] && [ -n "${WERTE[${BASH_REMATCH[1]}]+x}" ]; then
        k="${BASH_REMATCH[1]}"
        printf '%s=%s\n' "$k" "${WERTE[$k]}"
      else
        printf '%s\n' "$z"
      fi
    done < "$VORLAGE"
  } > "$tmp"
  # Gegenprobe: jede Variable genau einmal und mit dem gewaehlten Wert.
  # *Cross-check: every variable exactly once, with the chosen value.*
  for k in "${VARIABLEN[@]}"; do
    # Ohne Wert gar nicht erst vergleichen: unter "set -u" beendete schon das
    # Lesen eines fehlenden Schluessels das ganze Skript (Selbsttest).
    # *A missing key would end the whole script under "set -u".*
    if [ -z "${WERTE[$k]+x}" ]; then
      rm -f "$tmp"; warn "konfiguration.env: kein Wert fuer $k"; return 1
    fi
    n=$(grep -c "^${k}=" "$tmp")
    v=$(sed -n "s/^${k}=//p" "$tmp")
    if [ "$n" -ne 1 ] || [ "$v" != "${WERTE[$k]}" ]; then
      rm -f "$tmp"; warn "konfiguration.env: $k fehlt oder stimmt nicht"; return 1
    fi
  done
  chmod 600 "$tmp"
  [ -f "$ziel" ] && cp -a "$ziel" "$ziel.vor-$BEGINN"
  mv "$tmp" "$ziel"
}

# ======================================================================
#  Selbsttest
# ======================================================================
selbsttest() {
  local schlecht=0 f
  pruefe() {   # pruefe <erwartet 0|1> <beschreibung> <befehl...>
    local soll="$1" was="$2"; shift 2
    if "$@" >/dev/null 2>&1; then ist=0; else ist=1; fi
    if [ "$ist" = "$soll" ]; then echo "  ok     $was"; else echo "  FEHLER $was (erwartet $soll, bekam $ist)"; schlecht=$((schlecht + 1)); fi
  }
  DNS_ZONE=beispiel.de
  pruefe 0 "IPv4 gueltig"                ist_ipv4 203.0.113.10
  pruefe 1 "IPv4 mit 256"                ist_ipv4 203.0.113.256
  pruefe 1 "Name statt IPv4"             ist_ipv4 gs.beispiel.de
  pruefe 0 "CIDR gueltig"                ist_cidr 203.0.113.0/30
  pruefe 1 "CIDR /33"                    ist_cidr 203.0.113.0/33
  pruefe 0 "in_netz /30"                 in_netz 203.0.113.2 203.0.113.0/30
  pruefe 1 "nicht in_netz /30"           in_netz 203.0.113.5 203.0.113.0/30
  pruefe 0 "in_netz Einzeladresse"       in_netz 203.0.113.5 203.0.113.5
  pruefe 0 "in_netz 0.0.0.0/0"           in_netz 203.0.113.9 0.0.0.0/0
  # Eine oeffentliche Adresse zusammengesetzt statt woertlich: vollstaendigkeit.sh
  # meldet jede echte Adresse im Repositorium, und ein Beispielnetz (RFC 5737)
  # ist gerade NICHT oeffentlich.
  # *Built at run time: the completeness check flags every real address, and the
  #  documentation ranges are exactly the ones that are not public.*
  f=$(printf '%d.%d.%d.%d' 9 9 9 9)
  pruefe 0 "oeffentlich"                 ist_oeffentlich "$f"
  pruefe 1 "privat ist nicht oeffentlich" ist_oeffentlich 192.168.1.10
  pruefe 1 "Tailscale ist nicht oeffentlich" ist_oeffentlich 100.101.102.103
  pruefe 1 "Dokunetz ist nicht oeffentlich" ist_oeffentlich 203.0.113.10
  pruefe 0 "Domain"                      ist_domain panel.beispiel.de
  pruefe 1 "Domain gross"                ist_domain Panel.Beispiel.de
  pruefe 1 "Domain ohne Punkt"           ist_domain localhost
  pruefe 0 "in der Zone"                 ist_in_zone gs.beispiel.de
  pruefe 1 "ausserhalb der Zone"         ist_in_zone gs.anderes.de
  pruefe 1 "Zone selbst ist kein Name darin" ist_in_zone beispiel.de
  pruefe 0 "Benutzer"                    ist_benutzer admin
  pruefe 1 "Benutzer root"               ist_benutzer root
  pruefe 1 "Benutzer panel"              ist_benutzer panel
  pruefe 1 "Benutzer gross"              ist_benutzer Admin
  pruefe 0 "Weltname"                    ist_weltname meinserver
  pruefe 1 "Weltname mit Leerzeichen"    ist_weltname "mein server"
  pruefe 1 "Weltname mit Anfuehrung"     ist_weltname 'mein"server'
  pruefe 0 "Borg ssh://"                 ist_borg_repo ssh://borg@100.100.1.2/backup/x.borg
  pruefe 0 "Borg ssh:// mit Port"        ist_borg_repo ssh://u@host.beispiel.de:23/./x
  pruefe 0 "Borg lokaler Pfad"           ist_borg_repo /mnt/sicherung/x.borg
  pruefe 1 "Borg ohne Benutzer"          ist_borg_repo ssh://host/x
  pruefe 0 "Webhook"                     ist_webhook https://discord.com/api/webhooks/123456/abcDEF_-9
  pruefe 1 "Webhook fremder Wirt"        ist_webhook https://example.com/api/webhooks/1/x
  pruefe 0 "Token"                       ist_token AbCdEfGhIjKlMnOpQrStUvWxYz0123456789
  pruefe 1 "Token zu kurz"               ist_token abc
  pruefe 0 "Schluessel ed25519"          ist_schluessel "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGl5c2lzbm90YXJlYWxrZXlidXRsb25nZW5vdWdo jens@pc"
  pruefe 1 "Dateiname statt Schluessel"  ist_schluessel "id_ed25519.pub"
  pruefe 1 "Schluessel ohne Inhalt"      ist_schluessel "ssh-ed25519 AAAA"
  # Archivwahl: juengstes VOR dem Beginn, nicht das des Probelaufs.
  f=$(printf '%s\n' valheim-20260910-120000 valheim-20260911-090000 valheim-20260911-230000 \
                   valheim2-20260911-100000 config-20260911-080000 | neuestes_vor valheim 20260911-220000)
  pruefe 0 "Archivwahl vor Beginn"       test "$f" = valheim-20260911-090000
  f=$(printf '%s\n' config-20260911-230000 | neuestes_vor config 20260911-220000)
  pruefe 0 "nur Probelauf-Archiv -> keins" test -z "$f"
  # Konfiguration aus der Vorlage: jede Variable genau einmal, Kommentare bleiben.
  local tmpd; tmpd=$(mktemp -d)
  WERTE=([DNS_ZONE]=beispiel.de [DNS_ZIEL]=gs.beispiel.de [PANEL_DOMAIN]=panel.beispiel.de
         [SERVER_IPV4]=dynamic [WELT_NAME]=probe [ADMIN_USER]=admin [ADMIN_NETZ]=203.0.113.7/32
         [ADMIN_IP]=203.0.113.7 [SSH_PASSWORT_AUTH]=no [SSH_ROOT_LOGIN]=prohibit-password
         [ZERTIFIKAT_WEG]=http-01 [BORG_REPO]=aus [FREMD_IPV4]=198.51.100.10)
  pruefe 0 "Konfiguration schreiben"     konfiguration_schreiben "$tmpd/k.env"
  pruefe 0 "Wert eingesetzt"             grep -qx "SERVER_IPV4=dynamic" "$tmpd/k.env"
  pruefe 0 "Erklaerungen bleiben"        grep -q "Oeffentliche IPv4 des Servers" "$tmpd/k.env"
  pruefe 0 "Rechte 600"                  test "$(stat -c %a "$tmpd/k.env")" = 600
  unset 'WERTE[FREMD_IPV4]'
  pruefe 1 "fehlender Wert bricht ab"    konfiguration_schreiben "$tmpd/k2.env"
  rm -rf "$tmpd"
  echo
  if [ "$schlecht" -eq 0 ]; then echo "alles gruen."; return 0; fi
  echo "$schlecht FEHLER"; return 1
}

# ======================================================================
#  Messungen und Pruefungen mit Netz
# ======================================================================
oeffentliche_ip() {
  local u ip
  for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip=$(curl -4 -fsS --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]')
    if ist_oeffentlich "$ip"; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

# Den Token nie in argv: curl liest die Kopfzeile aus einer 0600-Datei (-H @datei).
# *Never in argv: curl reads the header from a 0600 file.*
dns_token_pruefen() {   # dns_token_pruefen <anbieter> <token> <zone>
  local kopf antwort
  kopf=$(mktemp); chmod 600 "$kopf"
  case "$1" in
    cloudflare)
      printf 'Authorization: Bearer %s\n' "$2" > "$kopf"
      antwort=$(curl -4 -sS --max-time 15 -H @"$kopf" "https://api.cloudflare.com/client/v4/zones?name=$3" 2>&1) ;;
    hetzner)
      printf 'Auth-API-Token: %s\n' "$2" > "$kopf"
      antwort=$(curl -4 -sS --max-time 15 -H @"$kopf" "https://dns.hetzner.com/api/v1/zones?name=$3" 2>&1) ;;
  esac
  rm -f "$kopf"
  grep -q "\"name\":\"$3\"" <<<"$antwort"
}

# Webhook-URL ebenfalls nicht in argv: curl -K liest die URL aus einer Datei.
webhook_testen() {   # webhook_testen <url> <titel>
  local k; k=$(mktemp); chmod 600 "$k"
  printf 'url = "%s?wait=true"\n' "$1" > "$k"
  curl -4 -fsS --max-time 15 -K "$k" -H 'Content-Type: application/json' \
       -d "{\"content\":\"$2\"}" >/dev/null 2>&1
  local rc=$?; rm -f "$k"; return $rc
}

schluessel_zahl() {   # schluessel_zahl <home> -> Zahl brauchbarer Zeilen in authorized_keys
  local d="$1/.ssh/authorized_keys"
  [ -f "$d" ] || { echo 0; return; }
  grep -cE '^(ssh-|ecdsa-|sk-)' "$d"
}

borg_verbindung() {   # borg_verbindung <repo> -> Ausgabe: neu | vorhanden | fehler:<text>
  local aus
  aus=$(BORG_PASSPHRASE="${BORG_PRUEF_PASS:-platzwart-probe}" \
        BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new" \
        timeout 60 borg info --lock-wait 30 "$1" 2>&1)
  local rc=$?
  if [ $rc -eq 0 ]; then echo vorhanden
  elif grep -qiE "does not exist|is not a valid repository" <<<"$aus"; then echo neu
  elif grep -qiE "passphrase supplied.*incorrect|passphrase.*wrong" <<<"$aus"; then echo vorhanden-andere-passphrase
  else echo "fehler:$(tail -2 <<<"$aus" | tr '\n' ' ')"
  fi
}

# ======================================================================
#  Ablauf
# ======================================================================
MODUS=""
NUR_KONF=""
case "${1:-}" in
  --selbsttest) selbsttest; exit $? ;;
  --nur-konfiguration) NUR_KONF=ja; MODUS=konfiguration ;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) fehler "Unbekannter Schalter: $1 (erlaubt: --nur-konfiguration, --selbsttest)" ;;
esac

BESTAETIGT=""
trap 'echo; if [ -z "$BESTAETIGT" ]; then warn "Abgebrochen - bis zur Bestaetigung wurde nichts geaendert."; else warn "Abgebrochen waehrend der Einrichtung. Die Stufen sind wiederholbar: den Assistenten erneut starten, die Antworten stehen als Vorgaben bereit."; fi; exit 130' INT

[ -f "$VORLAGE" ] || fehler "Vorlage fehlt: $VORLAGE - der Assistent muss aus einem vollstaendigen Klon laufen."
for s in 10-basis 20-docker 25-dns-grundgeruest 30-panel 40-caddy-ttyd 50-sicherung 60-spiele 70-dns einrichten; do
  [ -f "$REPO/install/$s.sh" ] || fehler "install/$s.sh fehlt - der Klon ist unvollstaendig."
done

[ -t 1 ] && clear 2>/dev/null
cat <<TEXT
${FETT}
  ==================================================================
   Platzwart - gefuehrte Einrichtung
   *guided setup*
  ==================================================================${AUS}

   Der Assistent fragt alles ab, was die Einrichtung braucht, prueft
   Zugaenge und Voraussetzungen und zeigt am Ende eine Zusammenfassung.
   Eingerichtet wird erst nach deiner Bestaetigung.

   Eckige Klammern zeigen die Vorgabe - Eingabe uebernimmt sie.
   Abbrechen jederzeit mit Strg+C.

   Ausfuehrliche Anleitung: docs/11-neueinrichtung.md
TEXT

# --- Vorhandene Antworten als Vorgaben ------------------------------------
declare -A ALT=()
if [ -f "$KONF" ]; then
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"
    ALT[$k]="$v"
  # Ziffern im Namen mitnehmen: mit [A-Z_]+ fielen SERVER_IPV4 und FREMD_IPV4
  # still heraus, und die Vorgabe sprang von "dynamic" auf die gemessene Adresse.
  # *Allow digits: [A-Z_]+ silently dropped SERVER_IPV4 and FREMD_IPV4.*
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$KONF")
  echo
  log "Vorhandene konfiguration.env gefunden - ihre Werte sind die Vorgaben."
fi
alt() { printf '%s' "${ALT[$1]:-${2:-}}"; }

# --- Modus ------------------------------------------------------------------
if [ -z "$MODUS" ]; then
  titel "Was soll geschehen?"
  wahl MODUS "Modus:" 1 \
    "neu|Neueinrichtung - eine leere Maschine wird zum Spieleserver" \
    "wiederaufbau|Wiederaufbau aus einer vorhandenen Borg-Sicherung (verlorene Maschine)" \
    "konfiguration|nur konfiguration.env und Zugangsdateien schreiben, nichts einrichten"
  [ "$MODUS" = konfiguration ] && NUR_KONF=ja
fi

IST_ROOT=""; [ "$(id -u)" -eq 0 ] && IST_ROOT=ja
if [ -z "$IST_ROOT" ]; then
  [ -n "$NUR_KONF" ] || fehler "Einrichten geht nur als root: sudo install/assistent.sh"
  warn "Nicht root: es entsteht nur konfiguration.env; Zugangsdateien unter /etc und /root werden uebersprungen."
fi

# --- Vorabpruefung ------------------------------------------------------------
if [ -z "$NUR_KONF" ]; then
  titel "Vorabpruefung"
  . /etc/os-release 2>/dev/null || true
  if [ "${VERSION_CODENAME:-}" = bookworm ]; then
    log "System: ${PRETTY_NAME:-Debian 12}"
  else
    warn "System: ${PRETTY_NAME:-unbekannt} - gebaut und geprueft ist die Einrichtung fuer Debian 12 (bookworm)."
    janein "Trotzdem weitermachen?" n || fehler "Abgebrochen."
  fi
  ram_mb=$(awk '/^MemTotal/ {print int($2/1024)}' /proc/meminfo)
  frei_gb=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
  kerne=$(nproc)
  log "Maschine: ${kerne} Kerne, $(( ram_mb / 1024 )) GB Arbeitsspeicher, ${frei_gb} GB frei auf /"
  [ "$ram_mb" -ge 7500 ] || warn "Unter 8 GB Arbeitsspeicher: ein bis zwei kleine Server, mehr nicht."
  if [ "$frei_gb" -lt 30 ]; then
    fehler "Nur ${frei_gb} GB frei. Spiele sind gross, und jede Installation haelt 10 GB Reserve - mindestens 50 GB."
  elif [ "$frei_gb" -lt 50 ]; then
    warn "Nur ${frei_gb} GB frei - fuer mehr als zwei, drei Spiele zu wenig (Empfehlung: 100 GB)."
  fi
  if [ -f /etc/gameserver-version ]; then
    warn "Diese Maschine ist bereits eingerichtet ($(tr '\n' ' ' < /etc/gameserver-version))."
    text "Die Stufen sind wiederholbar: vorhandene Dateien werden gesichert, Geheimnisse" \
         "(Panel-Zugang, Borg-Passphrase, Spielpasswoerter) bleiben unangetastet."
    janein "Trotzdem weitermachen?" n || fehler "Abgebrochen."
  fi
  fehlt=()
  command -v curl >/dev/null || fehlt+=(curl ca-certificates)
  command -v python3 >/dev/null || fehlt+=(python3)
  command -v ssh-keygen >/dev/null || fehlt+=(openssh-client)
  command -v borg >/dev/null || fehlt+=(borgbackup)
  if [ ${#fehlt[@]} -gt 0 ]; then
    text "Fuer die Pruefungen fehlen: ${fehlt[*]} (installiert Stufe 10 ohnehin)."
    if janein "Jetzt installieren?" j; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${fehlt[@]}" >/dev/null \
        || fehler "apt-get install ${fehlt[*]} gescheitert"
      log "installiert: ${fehlt[*]}"
    else
      warn "Ohne diese Werkzeuge bleiben Adress-, Token- und Sicherungspruefung aus."
    fi
  fi
  # Eine abreissende SSH-Verbindung beendet die Einrichtung mittendrin. Die
  # Stufen sind wiederholbar, aber ein halber Lauf ist unnoetig.
  # *A dropped SSH connection ends the run midway; tmux avoids that.*
  if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ]; then
    warn "Du bist per SSH verbunden und nicht in tmux/screen: reisst die Verbindung ab,"
    warn "bricht die Einrichtung mittendrin ab. Empfehlung: apt install tmux; tmux new -s einrichtung"
    janein "Trotzdem ohne tmux weitermachen?" j || fehler "Abgebrochen - in tmux neu starten."
  fi
  if command -v curl >/dev/null && curl -4 -fsS --max-time 8 -o /dev/null https://deb.debian.org/; then
    log "Internet erreichbar"
  else
    warn "deb.debian.org nicht erreichbar - ohne Internet scheitern die Stufen."
  fi
fi

# ======================================================================
#  Fragen
# ======================================================================
# --- Sicherung zuerst im Wiederaufbau: aus ihr kommen DNS-Token und Webhooks ---
BORG_REPO_WERT=""; BORG_PASS_NEU=""; BORG_ZUSTAND=""
declare -A ARCHIV=()
ETC_ARCHIV=""

sicherung_fragen() {
  titel "Sicherung"
  text "Borg sichert jeden Spielstand alle 15 Minuten auf einen zweiten Rechner." \
       "Empfohlen ist ein Ziel ueber ein privates Netz (Tailscale), dann braucht der" \
       "Sicherungsserver keinen offenen Port. Beispiel:" \
       "  ssh://borg@100.64.0.10/backup/platzwart/platzwart.borg" \
       "Ohne Sicherungsziel geht es auch - dann liegt jeder Spielstand nur hier."
  local art
  if [ "$MODUS" = wiederaufbau ]; then
    art=repo
  else
    local vorgabe=1; [ "$(alt BORG_REPO)" = aus ] && vorgabe=2
    wahl art "Sichern?" "$vorgabe" "repo|ja, auf ein Borg-Ziel" "aus|nein, vorerst ohne Sicherung (BORG_REPO=aus)"
  fi
  if [ "$art" = aus ]; then BORG_REPO_WERT=aus; return 0; fi
  local av; av=$(alt BORG_REPO); [ "$av" = aus ] && av=""
  frage BORG_REPO_WERT "Borg-Repository" "$av" ist_borg_repo \
        "Form: ssh://benutzer@wirt[:port]/pfad oder ein lokaler Pfad /mnt/..."
  [ -n "$IST_ROOT" ] || return 0
  [ -n "$NUR_KONF" ] && return 0

  local wirt=""
  if [[ "$BORG_REPO_WERT" =~ ^ssh://[^@]+@([^:/]+) ]]; then wirt="${BASH_REMATCH[1]}"; fi
  # Tailscale, wenn das Ziel im Tailnet liegt.
  if [ -n "$wirt" ] && { in_netz "$wirt" 100.64.0.0/10 2>/dev/null || [[ "$wirt" == *.ts.net ]]; }; then
    if ! command -v tailscale >/dev/null; then
      warn "Das Ziel liegt im Tailnet, Tailscale ist hier aber nicht installiert."
      if janein "Tailscale jetzt installieren und anmelden (Anmeldelink folgt)?" j; then
        curl -fsSL https://tailscale.com/install.sh | sh || fehler "Tailscale-Installation gescheitert"
        tailscale up || fehler "tailscale up gescheitert"
      else
        warn "Ohne Tailnet ist das Ziel nicht erreichbar - Stufe 50 wird scheitern."
      fi
    elif ! tailscale status >/dev/null 2>&1; then
      warn "Tailscale ist installiert, aber nicht verbunden."
      janein "Jetzt 'tailscale up' (Anmeldelink folgt)?" j && { tailscale up || warn "tailscale up gescheitert"; }
    else
      log "Tailscale verbunden"
    fi
  fi
  # SSH-Schluessel von root fuer den Sicherungsserver.
  if [ -n "$wirt" ]; then
    if [ ! -s /root/.ssh/id_ed25519 ] && [ ! -s /root/.ssh/id_rsa ]; then
      log "root hat noch keinen SSH-Schluessel - lege einen an (ed25519, ohne Passphrase: die Sicherung laeuft unbeaufsichtigt)."
      install -d -m 700 /root/.ssh
      ssh-keygen -q -t ed25519 -N "" -C "platzwart-borg@$(hostname)" -f /root/.ssh/id_ed25519 \
        || fehler "ssh-keygen gescheitert"
    fi
    local pub; pub=$(cat /root/.ssh/id_ed25519.pub 2>/dev/null || cat /root/.ssh/id_rsa.pub)
    text "" "Dieser oeffentliche Schluessel muss auf dem Sicherungsserver hinterlegt sein" \
         "(authorized_keys des Borg-Benutzers, am besten mit command=\"borg serve ...\"):" ""
    printf '     %s\n\n' "$pub"
  fi
  if command -v borg >/dev/null; then
    while true; do
      if [ "$MODUS" = wiederaufbau ]; then
        geheim BORG_PASS_NEU "Passphrase des vorhandenen Repositorys" ist_passphrase "mindestens 8 Zeichen"
        BORG_PRUEF_PASS="$BORG_PASS_NEU"
      elif [ -s "$PASSPHRASE" ]; then
        BORG_PRUEF_PASS=$(cat "$PASSPHRASE")
      fi
      log "Pruefe die Verbindung zum Repository (bestaetigt dabei den Host-Schluessel des Servers) ..."
      BORG_ZUSTAND=$(BORG_PRUEF_PASS="${BORG_PRUEF_PASS:-}" borg_verbindung "$BORG_REPO_WERT")
      case "$BORG_ZUSTAND" in
        neu)
          if [ "$MODUS" = wiederaufbau ]; then
            warn "Unter dieser Adresse liegt kein Repository - Wiederaufbau unmoeglich."
          else
            log "erreichbar, noch kein Repository - Stufe 50 legt es an."; break
          fi ;;
        vorhanden)
          if [ "$MODUS" = wiederaufbau ]; then log "Repository erreichbar, Passphrase stimmt."; break; fi
          log "Repository vorhanden und mit der Passphrase dieser Maschine lesbar."; break ;;
        vorhanden-andere-passphrase)
          if [ "$MODUS" = wiederaufbau ]; then
            warn "Die Passphrase passt nicht zu diesem Repository."
          else
            warn "Unter dieser Adresse liegt schon ein Repository mit einer anderen Passphrase."
            text "Soll eine verlorene Maschine zurueckkommen, ist das der Wiederaufbau-Modus."
            janein "Trotzdem weiter (Stufe 50 wird scheitern)?" n && break
          fi ;;
        fehler:*)
          warn "Nicht erreichbar: ${BORG_ZUSTAND#fehler:}"
          text "Haeufig: Schluessel oben noch nicht hinterlegt, Tailnet nicht verbunden, Pfad falsch." ;;
      esac
      janein "Noch einmal pruefen?" j || { [ "$MODUS" = wiederaufbau ] && fehler "Ohne Zugriff auf die Sicherung kein Wiederaufbau."; warn "Weiter ohne bestaetigte Verbindung - Stufe 50 wird es zeigen."; break; }
    done
  fi
  if [ "$MODUS" = wiederaufbau ]; then
    local liste
    liste=$(BORG_PASSPHRASE="$BORG_PASS_NEU" BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15" \
            borg list --short --lock-wait 300 "$BORG_REPO_WERT" 2>/dev/null) \
      || fehler "Archivliste nicht lesbar."
    local p a
    for p in config panel etc; do
      a=$(neuestes_vor "$p" "$BEGINN" <<<"$liste")
      ARCHIV[$p]="$a"
    done
    [ -n "${ARCHIV[config]}" ] || fehler "Kein config-Archiv (compose-Dateien) im Repository - der Wiederaufbau braucht es."
    ETC_ARCHIV="${ARCHIV[etc]}"
    log "Archive: config ${ARCHIV[config]}, panel ${ARCHIV[panel]:-FEHLT}, etc ${ARCHIV[etc]:-FEHLT}"
    WIEDER_STACKS=$(BORG_PASSPHRASE="$BORG_PASS_NEU" BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15" \
      borg list --short "$BORG_REPO_WERT::${ARCHIV[config]}" 2>/dev/null \
      | sed -nE 's#^opt/stacks/([a-z0-9-]+)/compose\.yaml$#\1#p' | sort -u | tr '\n' ' ')
    log "Server in der Sicherung: ${WIEDER_STACKS:-keine}"
    for p in $WIEDER_STACKS; do
      ARCHIV[$p]=$(neuestes_vor "$p" "$BEGINN" <<<"$liste")
      text "  $p: ${ARCHIV[$p]:-KEIN Spielstand-Archiv}"
    done
    janein "Diese Staende zurueckspielen?" j || fehler "Abgebrochen."
  fi
}

# Datei aus dem etc-Archiv lesen, ohne sie irgendwo abzulegen.
aus_etc_archiv() {   # aus_etc_archiv <pfad ohne fuehrenden />
  [ -n "$ETC_ARCHIV" ] || return 1
  BORG_PASSPHRASE="$BORG_PASS_NEU" BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15" \
    borg extract --stdout "$BORG_REPO_WERT::$ETC_ARCHIV" "$1" 2>/dev/null
}

WIEDER_STACKS=""
if [ "$MODUS" = wiederaufbau ]; then sicherung_fragen; fi

# --- Namen ------------------------------------------------------------------
titel "Namen"
text "Die Zone ist deine Domain bei Cloudflare (oder Hetzner). Darin entstehen:" \
     "  <ziel>   ein A-Eintrag mit der Adresse dieser Maschine" \
     "  <panel>  der Name der Weboberflaeche" \
     "  <spiel>  je Spielserver ein CNAME auf <ziel>"
frage DNS_ZONE "DNS-Zone" "$(alt DNS_ZONE)" ist_domain "Form: beispiel.de (klein, mit Punkt)"
frage DNS_ZIEL "Name, der die Adresse traegt" "$(alt DNS_ZIEL "gs.$DNS_ZONE")" ist_in_zone \
      "muss innerhalb von $DNS_ZONE liegen, z. B. gs.$DNS_ZONE"
frage PANEL_DOMAIN "Name der Weboberflaeche" "$(alt PANEL_DOMAIN "panel.$DNS_ZONE")" ist_domain \
      "Form: panel.$DNS_ZONE"
ist_in_zone "$PANEL_DOMAIN" || warn "$PANEL_DOMAIN liegt ausserhalb der Zone - diesen Namen pflegst du von Hand."
frage WELT_NAME "Name der Welt (erscheint in Spielen und im Panel)" "$(alt WELT_NAME platzwart)" ist_weltname \
      "2-32 Zeichen: Buchstaben, Ziffern, . _ - (keine Leerzeichen)"

# --- Adresse ------------------------------------------------------------------
titel "Oeffentliche Adresse"
GEMESSEN=""
command -v curl >/dev/null && GEMESSEN=$(oeffentliche_ip || true)
if [ -n "$GEMESSEN" ]; then log "Gemessen: $GEMESSEN"; else warn "Oeffentliche IPv4 nicht messbar (kein Netz oder hinter CGNAT)."; fi
text "Fest: der A-Eintrag bleibt, wie er ist. Dynamisch: die Maschine misst alle" \
     "fuenf Minuten ihre Adresse und traegt sie selbst ein."
av=$(alt SERVER_IPV4)
if [ "$av" = dynamic ]; then v=3; elif [ -n "$GEMESSEN" ]; then v=1; else v=2; fi
wahl ip_art "Adresse:" "$v" \
  "gemessen|fest, die gemessene: ${GEMESSEN:-(nicht gemessen)}" \
  "eigene|fest, eine andere Adresse eingeben" \
  "dynamic|wechselnd (dynamic)"
case "$ip_art" in
  gemessen) [ -n "$GEMESSEN" ] || fehler "Keine gemessene Adresse - bitte 2 oder 3 waehlen und neu starten."; SERVER_IPV4="$GEMESSEN" ;;
  eigene)   frage SERVER_IPV4 "Oeffentliche IPv4" "$( [ "$av" != dynamic ] && echo "$av")" ist_ipv4 "Form: 203.0.113.10" ;;
  dynamic)  SERVER_IPV4=dynamic ;;
esac
if [ "$SERVER_IPV4" != dynamic ] && [ -n "$GEMESSEN" ] && [ "$SERVER_IPV4" != "$GEMESSEN" ]; then
  warn "$SERVER_IPV4 ist nicht die gemessene Adresse $GEMESSEN - richtig, wenn eine Weiterleitung davorsteht."
fi

# --- DNS-Zugang ----------------------------------------------------------------
titel "DNS-Zugang"
text "Mit einem API-Token legt die Einrichtung die Namen selbst an - vor dem" \
     "Zertifikat. Cloudflare: Profil -> API-Tokens -> Token erstellen, Vorlage" \
     "'Edit zone DNS', Zonenressource NUR $DNS_ZONE. Nie den globalen Schluessel."
DNS_ANBIETER=""; DNS_TOKEN=""
if [ "$MODUS" = wiederaufbau ] && [ -n "$ETC_ARCHIV" ]; then
  inhalt=$(aus_etc_archiv etc/dns-gameserver.conf || true)
  if [ -n "$inhalt" ]; then
    DNS_ANBIETER=$(sed -n 's/^[[:space:]]*ANBIETER[[:space:]]*=[[:space:]]*//p' <<<"$inhalt" | head -1)
    DNS_TOKEN=$(sed -n 's/^[[:space:]]*TOKEN[[:space:]]*=[[:space:]]*//p' <<<"$inhalt" | head -1)
    DNS_ANBIETER="${DNS_ANBIETER:-cloudflare}"
    log "DNS-Zugang aus der Sicherung (${ETC_ARCHIV}): $DNS_ANBIETER"
    janein "Diesen Zugang uebernehmen?" j || { DNS_ANBIETER=""; DNS_TOKEN=""; }
  fi
  inhalt=""
fi
if [ -z "$DNS_TOKEN" ] && [ -s "$DNS_KONF" ] && [ -n "$IST_ROOT" ]; then
  log "Vorhandener DNS-Zugang: $DNS_KONF"
  if janein "Behalten?" j; then DNS_ANBIETER=behalten; fi
fi
if [ -z "$DNS_TOKEN" ] && [ "$DNS_ANBIETER" != behalten ]; then
  wahl DNS_ANBIETER "DNS-Anbieter:" 1 \
    "cloudflare|Cloudflare (im Betrieb erprobt)" \
    "hetzner|Hetzner DNS (nach Dokumentation, noch nicht gegen eine echte Zone gelaufen)" \
    "keiner|keiner - die Namen pflege ich von Hand"
  if [ "$DNS_ANBIETER" != keiner ]; then
    while true; do
      geheim DNS_TOKEN "API-Token" ist_token "Ein Token besteht aus 20-200 Zeichen A-Z a-z 0-9 _ -"
      if ! command -v curl >/dev/null; then warn "curl fehlt - Token ungeprueft."; break; fi
      if dns_token_pruefen "$DNS_ANBIETER" "$DNS_TOKEN" "$DNS_ZONE"; then
        log "Token gueltig, Zone $DNS_ZONE sichtbar."; break
      fi
      warn "Der Token sieht die Zone $DNS_ZONE nicht (falscher Token, falsche Berechtigung oder Zone)."
      janein "Anderen Token eingeben?" j || { janein "Diesen trotzdem verwenden?" n && break; DNS_ANBIETER=keiner; DNS_TOKEN=""; break; }
    done
  fi
fi
if [ "$DNS_ANBIETER" = keiner ]; then
  text "Ohne Token muessen $DNS_ZIEL und $PANEL_DOMAIN VOR der Einrichtung auf diese" \
       "Maschine zeigen, sonst scheitert das Zertifikat."
  if command -v getent >/dev/null && [ "$SERVER_IPV4" != dynamic ]; then
    for n in "$DNS_ZIEL" "$PANEL_DOMAIN"; do
      ist=$(getent ahostsv4 "$n" 2>/dev/null | awk 'NR==1 {print $1}')
      if [ "$ist" = "$SERVER_IPV4" ]; then log "$n -> $ist"; else warn "$n loest auf '${ist:-nichts}' auf, nicht $SERVER_IPV4."; fi
    done
  fi
fi
text "" "Ein Wildcard-Eintrag (*.$DNS_ZONE) beantwortet jeden erfundenen Namen."
v=n; [ -n "$(alt FREMD_IPV4)" ] && [ "$(alt FREMD_IPV4)" != 198.51.100.10 ] && v=j
if janein "Hat die Zone einen Wildcard-Eintrag?" "$v"; then
  frage FREMD_IPV4 "Adresse, auf die er zeigt" "$(alt FREMD_IPV4)" ist_ipv4 "Form: 198.51.100.10"
else
  FREMD_IPV4=198.51.100.10
fi

# --- Zertifikat ----------------------------------------------------------------
titel "Zertifikat"
text "http-01: Let's Encrypt ruft die Maschine auf Port 80 - der muss hier ankommen." \
     "dns-01:  ueber einen TXT-Eintrag, ganz ohne eingehenden Port (hinter CGNAT," \
     "         oder wenn Port 80 schon woanders hin weitergeleitet ist); nur Cloudflare."
if [ "$DNS_ANBIETER" = cloudflare ] || { [ "$DNS_ANBIETER" = behalten ] && grep -qi 'ANBIETER=cloudflare' "$DNS_KONF" 2>/dev/null; }; then
  v=1; [ "$(alt ZERTIFIKAT_WEG)" = dns-01 ] && v=2
  wahl ZERTIFIKAT_WEG "Weg:" "$v" "http-01|http-01 ueber Port 80 (Vorgabe)" "dns-01|dns-01 ueber die DNS-API (eigener Caddy-Bau, einige Minuten)"
else
  ZERTIFIKAT_WEG=http-01
  log "http-01 (dns-01 geht nur mit einem Cloudflare-Token)"
fi

# --- Zugang ----------------------------------------------------------------------
titel "Zugang zur Maschine"
v=$(alt ADMIN_USER "${SUDO_USER:-}")
[ "$v" = root ] && v=""
[ -n "$v" ] || v=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
frage ADMIN_USER "Benutzer fuer den Menschen (Webterminal, sudo)" "${v:-admin}" ist_benutzer \
      "Kleinbuchstaben, Ziffern, _ -; nicht root, panel oder spiele"

KLIENT="${SSH_CONNECTION:-}"; KLIENT="${KLIENT%% *}"; ist_ipv4 "$KLIENT" || KLIENT=""
text "SSH nimmt ufw nur von einer Adresse (oder einem Netz) an; fail2ban sperrt" \
     "Angreifer 48 Stunden, ausser Adressen aus dem Admin-Netz."
[ -n "$KLIENT" ] && log "Du bist gerade verbunden von: $KLIENT"
av=$(alt ADMIN_IP)
if [ -n "$KLIENT" ]; then v=1; elif [ -n "$av" ] && [ "$av" != 0.0.0.0/0 ]; then v=2; else v=2; fi
wahl ssh_art "SSH erlauben von:" "$v" \
  "klient|nur dieser Adresse: ${KLIENT:-(nicht erkannt)}" \
  "eigene|einer anderen festen Adresse oder einem Netz" \
  "ueberall|ueberall (fuer wechselnde Heimadressen; dann traegt die Schluesselanmeldung)"
case "$ssh_art" in
  klient)
    [ -n "$KLIENT" ] || fehler "Keine Verbindungsadresse erkannt - bitte 2 waehlen."
    ADMIN_IP="$KLIENT"; ADMIN_NETZ="$KLIENT/32" ;;
  eigene)
    frage ADMIN_IP "Adresse oder Netz (CIDR)" "$( [ "$av" != 0.0.0.0/0 ] && echo "$av")" ist_ip_oder_cidr "Form: 203.0.113.7 oder 203.0.113.0/29"
    if ist_cidr "$ADMIN_IP"; then ADMIN_NETZ="$ADMIN_IP"; else ADMIN_NETZ="$ADMIN_IP/32"; fi ;;
  ueberall)
    ADMIN_IP=0.0.0.0/0
    # NICHT 0.0.0.0/0 fuer fail2ban - das hiesse, niemand wird je gesperrt (#259).
    # *Never 0.0.0.0/0 for fail2ban: nobody would ever be banned (#259).*
    ADMIN_NETZ=127.0.0.1/32
    text "fail2ban sperrt dann jeden, der sich dreimal vertut - auch dich. Rueckweg: Tailnet." ;;
esac
if [ -n "$KLIENT" ] && ! in_netz "$KLIENT" "$ADMIN_IP" && ! in_netz "$KLIENT" 100.64.0.0/10; then
  warn "Deine jetzige Adresse $KLIENT ist NICHT in $ADMIN_IP."
  warn "Nach Stufe 10 kommst du so nicht mehr per SSH herein (die laufende Sitzung bleibt)."
  janein "Wirklich so?" n || fehler "Abgebrochen - bitte neu starten und die Adresse anpassen."
fi

v=1; [ "$(alt SSH_PASSWORT_AUTH)" = yes ] && v=2
wahl SSH_PASSWORT_AUTH "Anmeldung per SSH:" "$v" \
  "no|nur mit Schluessel (Vorgabe, empfohlen)" \
  "yes|auch mit Passwort (davor stehen dann nur ufw und fail2ban)"
if [ "$SSH_PASSWORT_AUTH" = yes ]; then
  wahl SSH_ROOT_LOGIN "root per SSH:" 1 \
    "prohibit-password|nur mit Schluessel (Vorgabe)" "no|gar nicht (nur ueber $ADMIN_USER und sudo)" \
    "forced-commands-only|nur Schluessel mit festem Befehl" "yes|auch mit Passwort"
else
  wahl SSH_ROOT_LOGIN "root per SSH:" 1 \
    "prohibit-password|nur mit Schluessel (Vorgabe)" "no|gar nicht (nur ueber $ADMIN_USER und sudo)" \
    "forced-commands-only|nur Schluessel mit festem Befehl"
fi

# Aussperrschutz: Nach Stufe 10 muss es einen Weg hinein geben. Nur, wenn hier
# auch eingerichtet wird - sonst fragte der Assistent nach Schluessel und
# Passwort, die er gar nicht setzt.
# *Lockout guard: after stage 10 there must be a way in. Only when setting up
#  here - otherwise it would ask for a key and password it never applies.*
ADMIN_SCHLUESSEL=""; ADMIN_PASSWORT=""
if [ -n "$NUR_KONF" ]; then
  text "" "Vor der Einrichtung auf der Zielmaschine: ein oeffentlicher Schluessel fuer" \
       "$ADMIN_USER oder root muss hinterlegt sein - Stufe 10 schaltet die Passwortanmeldung" \
       "ab, wenn SSH_PASSWORT_AUTH=no. Der Assistent prueft das dort, wenn er einrichtet."
else
adm_home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
adm_keys=0; [ -n "$adm_home" ] && adm_keys=$(schluessel_zahl "$adm_home")
root_keys=$(schluessel_zahl /root 2>/dev/null || echo 0)
weg=""
[ "$SSH_PASSWORT_AUTH" = yes ] && weg="Passwort"
[ "$adm_keys" -gt 0 ] && weg="${weg:+$weg, }Schluessel von $ADMIN_USER"
case "$SSH_ROOT_LOGIN" in prohibit-password|yes) [ "$root_keys" -gt 0 ] && weg="${weg:+$weg, }Schluessel von root" ;; esac
if [ -n "$weg" ]; then
  log "Anmeldung nach Stufe 10 moeglich ueber: $weg"
  janein "Zusaetzlich einen oeffentlichen Schluessel fuer $ADMIN_USER hinterlegen?" n \
    && frage ADMIN_SCHLUESSEL "Oeffentlicher Schluessel (eine Zeile, ssh-ed25519 ...)" "" ist_schluessel "Das ist kein oeffentlicher SSH-Schluessel."
else
  warn "Nach Stufe 10 gaebe es KEINEN Weg per SSH herein: keine Passwortanmeldung, kein Schluessel."
  text "Deinen OEFFENTLICHEN Schluessel einfuegen (auf deinem Rechner: cat ~/.ssh/id_ed25519.pub)."
  frage ADMIN_SCHLUESSEL "Oeffentlicher Schluessel fuer $ADMIN_USER" "" ist_schluessel "Das ist kein oeffentlicher SSH-Schluessel."
fi
text "" "$ADMIN_USER braucht ein Passwort fuer sudo (Webterminal)."
if [ -n "$adm_home" ] && passwd -S "$ADMIN_USER" 2>/dev/null | awk '{exit !($2=="P")}'; then
  log "$ADMIN_USER hat bereits ein Passwort."
elif janein "Jetzt ein Passwort fuer $ADMIN_USER festlegen?" j; then
  while true; do
    geheim ADMIN_PASSWORT "Passwort (mindestens 10 Zeichen)" ist_passwort "mindestens 10 Zeichen"
    geheim p2 "Wiederholen"
    [ "$ADMIN_PASSWORT" = "$p2" ] && break
    warn "Die beiden Eingaben unterscheiden sich."
  done
  p2=""
fi
fi

# --- Sicherung (Neueinrichtung) ----------------------------------------------------
[ "$MODUS" = wiederaufbau ] || sicherung_fragen

# --- Meldungen --------------------------------------------------------------------
titel "Meldungen nach Discord (optional)"
text "Stoerungen (Absturz, Sicherung, Platte ...) und Mitteilungen (Updates, Entwarnung)" \
     "gehen ueber zwei Webhooks in zwei Kanaele: Kanal bearbeiten -> Integrationen -> Webhooks."
WEBHOOK_STOERUNG=""; WEBHOOK_MELDUNG=""; MELDEN=""
if [ "$MODUS" = wiederaufbau ] && [ -n "$ETC_ARCHIV" ]; then
  inhalt=$(aus_etc_archiv etc/platzwart-melden.conf || true)
  if [ -n "$inhalt" ] && janein "Webhooks aus der Sicherung uebernehmen?" j; then
    WEBHOOK_STOERUNG=$(sed -n 's/^WEBHOOK_STOERUNG=//p' <<<"$inhalt"); WEBHOOK_MELDUNG=$(sed -n 's/^WEBHOOK_MELDUNG=//p' <<<"$inhalt")
    MELDEN=ja
  fi
  inhalt=""
fi
if [ -z "$MELDEN" ] && [ -n "$IST_ROOT" ]; then
  if [ -s "$MELDEN_KONF" ]; then
    log "Vorhanden: $MELDEN_KONF"; janein "Behalten?" j && MELDEN=behalten
  fi
  if [ -z "$MELDEN" ] && janein "Webhooks jetzt eintragen?" n; then
    geheim WEBHOOK_STOERUNG "Webhook fuer Stoerungen" ist_webhook "Form: https://discord.com/api/webhooks/<zahl>/<token>"
    geheim WEBHOOK_MELDUNG  "Webhook fuer Mitteilungen" ist_webhook "Form: https://discord.com/api/webhooks/<zahl>/<token>"
    MELDEN=ja
    if command -v curl >/dev/null && janein "Je eine Testnachricht schicken?" n; then
      webhook_testen "$WEBHOOK_STOERUNG" "Platzwart-Einrichtung: Test Stoerungskanal" && log "Stoerungskanal: angekommen" || warn "Stoerungskanal: nicht angekommen"
      webhook_testen "$WEBHOOK_MELDUNG" "Platzwart-Einrichtung: Test Mitteilungskanal" && log "Mitteilungskanal: angekommen" || warn "Mitteilungskanal: nicht angekommen"
    fi
  fi
fi

# --- Server -----------------------------------------------------------------------
STACKS_WAHL=""; KATALOG_WAHL=""; STUFE70=""
if [ -z "$NUR_KONF" ]; then
  titel "Server"
  if [ "$MODUS" = wiederaufbau ]; then
    text "Die Server kommen aus der Sicherung: ${WIEDER_STACKS:-keine}."
  else
    text "Handgepflegte Server (eigene Images, Vorlagen in stacks/):"
    i=1; declare -a SL=()
    for f in "$REPO"/stacks/*.yaml; do
      n=$(basename "$f" .yaml); SL+=("$n")
      mem=$(grep -m1 -oE 'mem_limit: ?[0-9]+g' "$f" | grep -oE '[0-9]+')
      printf '    %d) %-13s bis %s GB Arbeitsspeicher\n' "$i" "$n" "${mem:-?}"
      i=$((i + 1))
    done
    while true; do
      printf '  Nummern, durch Leerzeichen getrennt (leer = keine) []: '
      lies
      STACKS_WAHL=""; ok=ja
      for z in $ANTWORT; do
        if [[ "$z" =~ ^[0-9]+$ ]] && [ "$z" -ge 1 ] && [ "$z" -le ${#SL[@]} ]; then
          STACKS_WAHL="$STACKS_WAHL ${SL[$((z - 1))]}"
        else ok=""; fi
      done
      [ -n "$ok" ] && break
      warn "Nur Nummern von 1 bis ${#SL[@]}."
    done
    STACKS_WAHL="${STACKS_WAHL# }"
    text "" "Katalogspiele (179, ein Klick im Panel) lassen sich auch jetzt schon installieren." \
         "Schluessel eingeben, z. B. 'valheim terraria'; '?wort' sucht im Katalog."
    while true; do
      printf '  Katalogspiele (leer = keine) []: '
      lies
      if [[ "$ANTWORT" == \?* ]]; then
        if command -v python3 >/dev/null; then
          python3 - "$KATALOG" "${ANTWORT#\?}" <<'PY'
import json, sys
k = json.load(open(sys.argv[1]))["spiele"]; w = sys.argv[2].lower()
t = [g for g in k if w in (g["schluessel"] + " " + g["name"] + " " + g.get("kurz", "")).lower()]
for g in t[:25]:
    print(f"     {g['schluessel']:<22} {g['name'][:34]:<34} {g['mem_gb']:>2} GB RAM, {g['platte_gb']:>3} GB Platte")
print(f"     ({len(t)} Treffer)")
PY
        else warn "python3 fehlt - keine Suche."; fi
        continue
      fi
      KATALOG_WAHL="$ANTWORT"; ok=ja
      if [ -n "$KATALOG_WAHL" ] && command -v python3 >/dev/null; then
        unbekannt=$(python3 -c "import json,sys;k={g['schluessel'] for g in json.load(open(sys.argv[1]))['spiele']};print(' '.join(s for s in sys.argv[2:] if s not in k))" "$KATALOG" $KATALOG_WAHL)
        [ -z "$unbekannt" ] || { warn "Nicht im Katalog: $unbekannt"; ok=""; }
      fi
      [ -n "$ok" ] && break
    done
  fi
  if [ "$DNS_ANBIETER" != keiner ]; then
    janein "DNS-Namen je Server anlegen (Stufe 70)?" j && STUFE70=ja
  fi
fi

# ======================================================================
#  Zusammenfassung
# ======================================================================
for k in DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER ADMIN_NETZ \
         ADMIN_IP SSH_PASSWORT_AUTH SSH_ROOT_LOGIN ZERTIFIKAT_WEG FREMD_IPV4; do
  WERTE[$k]="${!k}"
done
WERTE[BORG_REPO]="$BORG_REPO_WERT"

titel "Zusammenfassung"
printf '   %-22s %s\n' "Modus" "$MODUS"
for k in "${VARIABLEN[@]}"; do printf '   %-22s %s\n' "$k" "${WERTE[$k]}"; done
case "$DNS_ANBIETER" in
  keiner)   printf '   %-22s %s\n' "DNS-Zugang" "keiner (Namen von Hand)" ;;
  behalten) printf '   %-22s %s\n' "DNS-Zugang" "vorhandener ($DNS_KONF)" ;;
  *)        printf '   %-22s %s\n' "DNS-Zugang" "$DNS_ANBIETER, Token ...${DNS_TOKEN: -4}" ;;
esac
printf '   %-22s %s\n' "Discord-Meldungen" "${MELDEN:-nein}"
[ -n "$ADMIN_SCHLUESSEL" ] && printf '   %-22s %s\n' "Schluessel fuer $ADMIN_USER" "${ADMIN_SCHLUESSEL:0:24}..."
[ -n "$ADMIN_PASSWORT" ] && printf '   %-22s %s\n' "Passwort fuer $ADMIN_USER" "wird gesetzt"
if [ -z "$NUR_KONF" ]; then
  if [ "$MODUS" = wiederaufbau ]; then
    printf '   %-22s %s\n' "Zurueckspielen" "config ${ARCHIV[config]}, panel ${ARCHIV[panel]:-keins}, Server: ${WIEDER_STACKS:-keine}"
  else
    printf '   %-22s %s\n' "Handgepflegte Server" "${STACKS_WAHL:-keine}"
    printf '   %-22s %s\n' "Katalogspiele" "${KATALOG_WAHL:-keine}"
  fi
  printf '   %-22s %s\n' "DNS-Namen je Server" "${STUFE70:-nein}"
  # Stufe 25 laeuft nur mit DNS-Zugang (einrichten.sh prueft die Datei).
  # *Stage 25 only runs with DNS credentials.*
  st="10 20"; [ "$DNS_ANBIETER" != keiner ] && st="$st 25"
  printf '   %-22s %s\n' "Stufen" "$st 30 40 50${STACKS_WAHL:+ 60}${WIEDER_STACKS:+ 60}${STUFE70:+ 70}"
fi
echo
if [ -n "$NUR_KONF" ]; then
  janein "konfiguration.env so schreiben?" j || fehler "Abgebrochen - nichts geschrieben."
else
  text "Die Einrichtung laedt Pakete, Docker und Images - das dauert, je nach Leitung." \
       "Spiele laden danach im Hintergrund weiter. Protokoll: $PROTOKOLL"
  janein "Jetzt einrichten?" n || fehler "Abgebrochen - bis hierher wurde nichts veraendert."
fi
BESTAETIGT=ja

# ======================================================================
#  Ausfuehren
# ======================================================================
titel "Dateien schreiben"
konfiguration_schreiben "$KONF" || fehler "konfiguration.env liess sich nicht schreiben."
log "$KONF"
if [ -n "$IST_ROOT" ]; then
  if [ -n "$DNS_TOKEN" ] && [ "$DNS_ANBIETER" != keiner ] && [ "$DNS_ANBIETER" != behalten ]; then
    [ -f "$DNS_KONF" ] && cp -a "$DNS_KONF" "$DNS_KONF.vor-$BEGINN"
    ( umask 077; printf 'ANBIETER=%s\nTOKEN=%s\n' "$DNS_ANBIETER" "$DNS_TOKEN" > "$DNS_KONF" )
    chmod 600 "$DNS_KONF"; chown root:root "$DNS_KONF"
    log "$DNS_KONF (0600)"
  fi
  if [ "$MELDEN" = ja ]; then
    [ -f "$MELDEN_KONF" ] && cp -a "$MELDEN_KONF" "$MELDEN_KONF.vor-$BEGINN"
    ( umask 077; printf '# Erzeugt von install/assistent.sh\nWEBHOOK_STOERUNG=%s\nWEBHOOK_MELDUNG=%s\n' \
        "$WEBHOOK_STOERUNG" "$WEBHOOK_MELDUNG" > "$MELDEN_KONF" )
    chmod 600 "$MELDEN_KONF"; chown root:root "$MELDEN_KONF"
    log "$MELDEN_KONF (0600)"
  fi
fi
DNS_TOKEN=""; WEBHOOK_STOERUNG=""; WEBHOOK_MELDUNG=""

if [ -n "$NUR_KONF" ]; then
  log "Fertig. Einrichten spaeter mit: sudo install/assistent.sh  (die Antworten stehen dann als Vorgaben bereit)"
  exit 0
fi

# Admin-Benutzer VOR Stufe 10 - genau so, wie Stufe 10 ihn anlegen wuerde - damit
# Schluessel und Passwort stehen, bevor die SSH-Haertung greift.
# *Create the admin user before stage 10, exactly as stage 10 would, so key and
#  password are in place before the SSH hardening applies.*
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$ADMIN_USER" >/dev/null || fehler "adduser $ADMIN_USER gescheitert"
  usermod -aG sudo "$ADMIN_USER"
  log "Benutzer $ADMIN_USER angelegt (Gruppe sudo)"
fi
adm_home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
if [ -n "$ADMIN_SCHLUESSEL" ]; then
  install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$adm_home/.ssh"
  touch "$adm_home/.ssh/authorized_keys"
  grep -qxF "$ADMIN_SCHLUESSEL" "$adm_home/.ssh/authorized_keys" || printf '%s\n' "$ADMIN_SCHLUESSEL" >> "$adm_home/.ssh/authorized_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "$adm_home/.ssh/authorized_keys"; chmod 600 "$adm_home/.ssh/authorized_keys"
  log "Schluessel fuer $ADMIN_USER hinterlegt"
fi
if [ -n "$ADMIN_PASSWORT" ]; then
  # chpasswd liest von stdin - das Passwort steht nie in der Prozessliste.
  printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_PASSWORT" | chpasswd || fehler "Passwort fuer $ADMIN_USER liess sich nicht setzen"
  ADMIN_PASSWORT=""
  log "Passwort fuer $ADMIN_USER gesetzt"
fi
if [ "$MODUS" = wiederaufbau ]; then
  if [ -s "$PASSPHRASE" ] && [ "$(cat "$PASSPHRASE")" != "$BORG_PASS_NEU" ]; then
    cp -a "$PASSPHRASE" "$PASSPHRASE.vor-$BEGINN"
  fi
  ( umask 077; printf '%s' "$BORG_PASS_NEU" > "$PASSPHRASE" )
  chmod 600 "$PASSPHRASE"
  log "Borg-Passphrase aus der Eingabe nach $PASSPHRASE (Stufe 50 behaelt sie)"
fi

# Die Stufen. Die Ausgabe geht zusaetzlich in eine Protokolldatei - aber
# geschwaerzt: Stufe 30 zeigt das Erstpasswort, Stufe 60 die Spielpasswoerter.
# Das Erstpasswort merkt sich der Lauf, denn es steht genau einmal mitten in der
# Ausgabe und scrollt in einem langen Lauf weg; am Ende kommt es noch einmal.
# lastpipe, damit die Leseschleife in dieser Shell laeuft und ERSTPASS behaelt
# (in einer Pipe-Unterschale waere er danach leer).
# *Stage output also goes to a log file - redacted: stage 30 prints the initial
#  password, stage 60 the game passwords. The initial password is remembered and
#  repeated at the end because it scrolls away. lastpipe keeps the read loop in
#  this shell so ERSTPASS survives.*
titel "Einrichtung"
( umask 077; : > "$PROTOKOLL" )
ERSTPASS=""
shopt -s lastpipe
lauf() {
  local z
  bash "$@" 2>&1 | while IFS= read -r z || [ -n "$z" ]; do
    printf '%s\n' "$z"
    case "$z" in
      *"Passwort / pass:"*) ERSTPASS="${z##*pass:}"; ERSTPASS="${ERSTPASS//[[:space:]]/}"
                            z="${z%%pass:*}pass:  <geschwaerzt>" ;;
      *"Beitritt: "*)       z="${z%%Beitritt: *}Beitritt: <geschwaerzt>" ;;
    esac
    printf '%s\n' "$z" >> "$PROTOKOLL"
  done
  return "${PIPESTATUS[0]}"
}
GRUNDSTUFEN=(10-basis 20-docker 25-dns-grundgeruest 30-panel 40-caddy-ttyd 50-sicherung)
# Im Wiederaufbau kommt Stufe 50 erst NACH dem Zurueckspielen: ihr Probelauf
# sichert sonst eine leere Maschine - fast leere config-/panel-Archive, die die
# Einbruchpruefung meldet und die beim naechsten Zurueckspielen als "neueste"
# obenauf laegen. Danach sichert er gleich den zurueckgeholten Stand.
# *When rebuilding, stage 50 runs AFTER the restore: its test run would otherwise
#  back up an empty machine - near-empty archives that trip the drop check and
#  would sit on top as "newest". Afterwards it backs up the restored state.*
[ "$MODUS" = wiederaufbau ] && unset 'GRUNDSTUFEN[5]'
if ! lauf "$REPO/install/einrichten.sh" --ja "${GRUNDSTUFEN[@]}"; then
  fehler "Eine Stufe ist gescheitert - Ausgabe oben und in $PROTOKOLL. Nach dem Beheben den Assistenten erneut starten (die Stufen sind wiederholbar)."
fi

borg_env() {
  export BORG_PASSPHRASE; BORG_PASSPHRASE=$(cat "$PASSPHRASE")
  export BORG_RSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
}

if [ "$MODUS" = wiederaufbau ]; then
  titel "Zurueckspielen"
  borg_env
  log "compose-Dateien aus ${ARCHIV[config]}"
  ( cd / && borg extract --lock-wait 600 "$BORG_REPO_WERT::${ARCHIV[config]}" ) || fehler "config-Archiv liess sich nicht auspacken"
  if [ -n "${ARCHIV[panel]}" ]; then
    log "Panel-Daten aus ${ARCHIV[panel]} (Benutzer, zweite Faktoren, Passkeys, Protokoll, Integrationen)"
    systemctl stop panel
    ( cd / && borg extract --lock-wait 600 "$BORG_REPO_WERT::${ARCHIV[panel]}" ) || warn "panel-Archiv liess sich nicht auspacken"
    systemctl start panel
  fi
  for s in $WIEDER_STACKS; do
    a="${ARCHIV[$s]:-}"
    if [ -z "$a" ]; then warn "$s: kein Spielstand-Archiv - der Server startet leer"; continue; fi
    log "$s aus $a"
    # --numeric-ids: borg stellt Eigentuemer sonst nach NAMEN her. Traegt die neue
    # Maschine denselben Namen unter anderer UID (Cloud-Images belegen 1000 gern
    # mit "debian"), gehoert der Spielstand danach der falschen UID - und ein
    # Container mit fester UID (FOUNDRY laeuft als 1000) kann nicht mehr
    # schreiben. Container kennen nur Nummern (im Container nachgestellt:
    # ohne den Schalter kam 1000 als 1001 zurueck). config und panel bleiben bei
    # Namen: dort zaehlen root und der Benutzer "panel", dessen UID neu vergeben
    # wird.
    # *Numeric ids for saves: by name, a same-named user with another uid on the
    #  new machine would take over the files and a fixed-uid container could no
    #  longer write (reproduced: 1000 came back as 1001). config and panel stay by
    #  name - there root and the freshly numbered "panel" user matter.*
    ( cd / && borg extract --numeric-ids --lock-wait 600 "$BORG_REPO_WERT::$a" ) || warn "$s: Auspacken gescheitert"
  done
  unset BORG_PASSPHRASE
  /usr/local/bin/spiel-verwalten katalog-abgleich || warn "katalog-abgleich gescheitert"
  hand=""
  # Nur Stacks mit Vorlage in stacks/: Stufe 60 bricht bei einem unbekannten ab,
  # und bei vorhandener compose.yaml setzt sie nur noch den Palworld-Zeitgeber ein.
  # *Only stacks with a template; stage 60 aborts on unknown ones and, with an
  #  existing compose file, only installs the Palworld timer.*
  for s in $WIEDER_STACKS; do
    [ -f "/opt/stacks/$s/panel.json" ] && continue
    [ -f "$REPO/stacks/$s.yaml" ] && hand="$hand $s"
  done
  [ -n "${hand# }" ] && { lauf "$REPO/install/60-spiele.sh" $hand || warn "Stufe 60 meldete einen Fehler"; }
  titel "Sicherung einschalten"
  if ! lauf "$REPO/install/einrichten.sh" --ja 50-sicherung; then
    warn "Stufe 50 ist gescheitert - die Staende sind zurueck, aber es wird NICHT gesichert."
    warn "Ursache beheben, dann: sudo install/einrichten.sh 50-sicherung"
  fi
  if janein "Die zurueckgespielten Server jetzt starten (Images werden geladen)?" j; then
    for s in $WIEDER_STACKS; do
      ( cd "/opt/stacks/$s" && docker compose up -d >/dev/null 2>&1 ) && log "$s gestartet" || warn "$s: Start gescheitert"
    done
  fi
elif [ -n "$STACKS_WAHL" ]; then
  titel "Handgepflegte Server"
  lauf "$REPO/install/60-spiele.sh" $STACKS_WAHL || warn "Stufe 60 meldete einen Fehler"
  if janein "Diese Server jetzt starten?" j; then
    for s in $STACKS_WAHL; do
      ( cd "/opt/stacks/$s" && docker compose up -d >/dev/null 2>&1 ) && log "$s gestartet" || warn "$s: Start gescheitert"
    done
  fi
fi

if [ -n "$STUFE70" ]; then
  titel "DNS-Namen"
  lauf "$REPO/install/70-dns.sh" || warn "Stufe 70 meldete einen Fehler"
fi

if [ -n "$KATALOG_WAHL" ]; then
  titel "Katalogspiele"
  for s in $KATALOG_WAHL; do
    log "installiere $s"
    # Ausgabe: ok <Name> <Startzustand> <Passwort> <Adminpasswort> - die beiden
    # letzten nicht auf den Bildschirm, sie stehen im Panel unter Zugangsdaten.
    # *The last two fields are passwords; they stay in the panel.*
    if aus=$(/usr/local/bin/panel-aktion installieren "$s" 2>&1); then
      IFS=$'\t' read -r _ name zustand _ <<<"$(head -1 <<<"$aus")"
      log "$name: $zustand (Passwoerter im Panel unter Zugangsdaten)"
    else
      warn "$s: $(tail -1 <<<"$aus")"
    fi
    aus=""
  done
fi

titel "Fertig"
if [ "$MODUS" = wiederaufbau ] && [ -n "${ARCHIV[panel]:-}" ]; then
  # Das Erstpasswort aus Stufe 30 gilt nicht mehr: nutzer.json kam aus der Sicherung.
  text "Die Benutzer kommen aus der Sicherung - Anmeldung, zweiter Faktor und Passkeys" \
       "wie vor dem Verlust. (Passkeys nur, wenn $PANEL_DOMAIN derselbe Name ist wie vorher.)"
elif [ -n "$ERSTPASS" ]; then
  text "Erstanmeldung:" "  https://$PANEL_DOMAIN/" "  Benutzer: $ADMIN_USER" "  Passwort: $ERSTPASS" \
       "" "Dieses Passwort steht nur hier - jetzt notieren. Beim ersten Anmelden richtest du" \
       "den zweiten Faktor per QR-Code ein; danach zeigt das Panel einmal zehn" \
       "Wiederherstellungscodes."
  ERSTPASS=""
else
  text "Die Erstanmeldung wurde schon bei einem frueheren Lauf ausgegeben (nutzer.json war vorhanden)."
fi
cat <<TEXT

   Panel:        https://${PANEL_DOMAIN}/
   Statusseite:  https://${PANEL_DOMAIN}/status
   Protokoll:    $PROTOKOLL (Passwoerter geschwaerzt)

   Noch zu tun (Einzelheiten: docs/11-neueinrichtung.md):
TEXT
if [ "$MODUS" = wiederaufbau ]; then
  # Auto-Update- und Leerlauf-Liste liegen unter /var/lib und stehen in keinem
  # Archiv; Benutzer, Integrationen und Freigaben kamen mit panel/config zurueck.
  # *The auto-update and idle lists live in /var/lib and are in no archive.*
  text "  1. anmelden und nachsehen, ob alle Server laufen und ihre Welt haben" \
       "  2. je Server Auto-Update und Leerlauf wieder einschalten (nicht in der Sicherung)" \
       "  3. DNS: zeigen die Namen auf die neue Adresse? (Stufe 70 bzw. dns-pflegen)" \
       "  4. vom Arbeitsrechner: werkzeuge/abgleich.sh <ziel>  - muss 0 Abweichungen melden"
else
  text "  1. anmelden, zweiten Faktor einrichten, Wiederherstellungscodes aufheben" \
       "  2. Integrationen im Panel: Steam-Schluessel, TeamSpeak-Zugang, Discord-Bot" \
       "  3. je Server: Auto-Update, Leerlauf; Minecraft/TeamSpeak freigeben" \
       "  4. $( [ "$BORG_REPO_WERT" = aus ] && echo "Sicherung spaeter einschalten: BORG_REPO setzen, Stufe 50" || echo "Kopie von $PASSPHRASE ausser Haus ablegen" )" \
       "  5. vom Arbeitsrechner: werkzeuge/abgleich.sh <ziel>  - muss 0 Abweichungen melden"
fi
if [ "$MODUS" = neu ] && [ "$BORG_REPO_WERT" != aus ] && [ -s "$PASSPHRASE" ]; then
  echo
  if janein "Die Borg-Passphrase jetzt einmal anzeigen (zum Abschreiben in den Passwortmanager)?" n; then
    printf '\n     %s\n\n' "$(cat "$PASSPHRASE")"
    text "Ohne sie ist jede Sicherung wertlos, wenn diese Maschine verloren geht."
  fi
fi
[ "$MELDEN" = ja ] && command -v platzwart-melden >/dev/null && text "" "Meldungen pruefen: platzwart-melden --test"
exit 0
