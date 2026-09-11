#!/bin/bash
# Gemeinsame Funktionen der Einrichtungsstufen.
# *Shared helpers for all installation stages.*

set -o pipefail

ROT=$'\e[31m'; GRUEN=$'\e[32m'; GELB=$'\e[33m'; AUS=$'\e[0m'
log()  { echo "${GRUEN}==>${AUS} $*"; }
warn() { echo "${GELB}!! ${AUS} $*" >&2; }
fehler() { echo "${ROT}FEHLER:${AUS} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fehler "Als root ausfuehren. / Run as root."

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KONF="$REPO/konfiguration.env"
[ -f "$KONF" ] || fehler "konfiguration.env fehlt. Vorlage: konfiguration.env.beispiel"
# shellcheck disable=SC1090
set -a; . "$KONF"; set +a

# Alle Variablen, die in Platzhaltern vorkommen duerfen.
VARIABLEN=(DNS_ZONE DNS_ZIEL PANEL_DOMAIN SERVER_IPV4 WELT_NAME ADMIN_USER
           ADMIN_NETZ ADMIN_IP BORG_REPO FREMD_IPV4
           SSH_PASSWORT_AUTH SSH_ROOT_LOGIN ZERTIFIKAT_WEG)

for v in "${VARIABLEN[@]}"; do
  [ -n "${!v}" ] || fehler "konfiguration.env: \$$v ist leer"
done

# SERVER_IPV4 traegt zwei zulaessige Bedeutungen: eine feste oeffentliche
# Adresse, oder das Wort "dynamic" fuer eine wechselnde. Alles andere ist ein
# Tippfehler oder ein Missverstaendnis - insbesondere ein DDNS-Name. Der wurde
# hier bis dahin klaglos angenommen und wirkte nirgends: die Adresse traegt
# allein der A-Eintrag DNS_ZIEL bei Cloudflare. Ein Wert, der still nichts tut,
# ist schlimmer als ein Fehler, weil man ihn fuer erledigt haelt.
# *SERVER_IPV4 accepts a fixed public address or the word "dynamic". Anything
#  else - a DDNS hostname in particular - used to be accepted silently and did
#  nothing at all, because only the DNS_ZIEL A record carries the address. A
#  value that quietly does nothing is worse than an error: it looks handled.*
ist_ipv4() {
  local ip="$1" o a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip"
  for o in "$a" "$b" "$c" "$d"; do [ "$o" -le 255 ] || return 1; done
  return 0
}
if [ "$SERVER_IPV4" = "dynamic" ]; then
  IP_DYNAMISCH=ja
elif ist_ipv4 "$SERVER_IPV4"; then
  IP_DYNAMISCH=nein
else
  fehler "konfiguration.env: SERVER_IPV4=\"$SERVER_IPV4\" ist weder eine IPv4" \
         "noch das Wort \"dynamic\". Ein DNS-Name gehoert hier nicht hin - bei" \
         "wechselnder Adresse \"dynamic\" eintragen, dann pflegt der Server den" \
         "A-Eintrag $DNS_ZIEL selbst (siehe docs/06-netz-dns-firewall.md)."
fi
# --- SSH ---------------------------------------------------------------------
# SSH_PASSWORT_AUTH und SSH_ROOT_LOGIN tragen die Werte, die sshd selbst
# versteht, und werden unveraendert nach /etc/ssh/sshd_config.d/99-gameserver.conf
# durchgereicht. Eine eigene Sprache ("ja"/"nur-schluessel") waere eine
# Uebersetzungsschicht, die genau einmal auseinanderlaeuft und dann eine
# Konfiguration erzeugt, die anders heisst als das, was sshd tut.
#
# Geprueft wird gegen eine Positivliste, nicht gegen "ist nicht leer": ein
# Tippfehler wie "prohibit_password" ergibt eine Datei, an der "sshd -t"
# scheitert - und ein Dienst, der die neue Datei nicht laedt, bleibt bei der
# alten Fassung und laeuft scheinbar richtig weiter.
#
# *Both carry sshd's own vocabulary and are passed through verbatim; a private
#  spelling would be a translation layer that drifts exactly once. Checked
#  against an allow-list rather than "not empty": a typo yields a file sshd
#  refuses, and a daemon that fails to load it keeps the old one and looks fine.*
case "$SSH_PASSWORT_AUTH" in
  yes|no) ;;
  *) fehler "konfiguration.env: SSH_PASSWORT_AUTH=\"$SSH_PASSWORT_AUTH\" ist" \
            "weder \"no\" noch \"yes\". Der Wert geht unveraendert an sshd." ;;
esac
case "$SSH_ROOT_LOGIN" in
  prohibit-password|no|yes|forced-commands-only) ;;
  *) fehler "konfiguration.env: SSH_ROOT_LOGIN=\"$SSH_ROOT_LOGIN\" ist keiner der" \
            "Werte, die PermitRootLogin kennt: prohibit-password, no, yes," \
            "forced-commands-only." ;;
esac
# "PermitRootLogin yes" ohne Passwortanmeldung ist genau "prohibit-password":
# root kommt so oder so nur mit Schluessel herein. Das ist dieselbe Falle wie ein
# DDNS-Name in SERVER_IPV4 - ein Wert, der still nichts tut, sieht erledigt aus.
# Wer root wirklich mit Passwort hereinlassen will, braucht beide Zeilen.
# *"PermitRootLogin yes" without password auth IS prohibit-password. A value
#  that quietly does nothing looks handled.*
if [ "$SSH_ROOT_LOGIN" = "yes" ] && [ "$SSH_PASSWORT_AUTH" = "no" ]; then
  fehler "konfiguration.env: SSH_ROOT_LOGIN=yes wirkt nicht, solange" \
         "SSH_PASSWORT_AUTH=no ist - root kaeme weiterhin nur mit Schluessel" \
         "herein, also genau das, was prohibit-password bedeutet." \
         "Entweder SSH_PASSWORT_AUTH=yes dazu, oder SSH_ROOT_LOGIN=prohibit-password."
fi

# BORG_REPO=aus schaltet die Sicherung vollstaendig ab: kein borg, keine
# Passphrase, keine Timer, keine Archivliste in der Oberflaeche.
#
# Der Schalter ist bewusst der WERT von BORG_REPO und keine zweite Variable.
# Zwei Variablen koennen sich widersprechen ("Sicherung an, aber wohin?"), eine
# nicht. Und der gefaehrliche Zustand ist nicht "abgeschaltet", sondern
# "abgeschaltet, und keiner weiss es": deshalb sagt es die Oberflaeche auf jeder
# Seite, und deshalb sagt es die Loeschbestaetigung eines Spielservers.
# *BORG_REPO=aus disables backups entirely. Deliberately the VALUE of BORG_REPO
#  rather than a second variable: two variables can contradict each other, one
#  cannot. The dangerous state is not "off" but "off and nobody knows", so the
#  panel says so on every page and the uninstall confirmation says so too.*
if [ "$BORG_REPO" = "aus" ]; then SICHERUNG_AN=nein; else SICHERUNG_AN=ja; fi

# --- Version ----------------------------------------------------------------
# Bis hierher liess sich die Frage "welcher Stand laeuft da eigentlich?" nur
# ueber einen Dateivergleich beantworten. Das sagt zwar genau, WAS abweicht,
# aber nicht, WELCHE Fassung dort ausgerollt wurde - und beim Nachsehen in einem
# Fehlerfall ist genau das die erste Frage.
#
# Der Stempel nennt die Fassung, den Commit und ob seither einzelne Dateien von
# Hand nachgerollt wurden. Er wird ERZEUGT und nicht kopiert, steht deshalb
# nicht in der Dateiliste von abgleich.sh, sondern hat dort eine eigene
# Pruefung - wie die ttyd-Version.
#
# *Until now "which state is actually running?" could only be answered by
#  comparing files: that says exactly WHAT differs but not WHICH release was
#  deployed, and in an incident that is the first question. The stamp names the
#  release, the commit, and whether single files have been rolled out by hand
#  since. It is generated rather than copied, so it has its own check.*
VERSIONSDATEI=/etc/gameserver-version

version_stempeln() {   # version_stempeln [sauber|geaendert]
  local stand="${1:-sauber}" v c
  # Nur die erste Zeile, ohne Leerraum: eine VERSION-Datei mit einer zweiten
  # Zeile wuerde den Stempel sonst zerlegen und aus "VERSION=1.0.0" zwei
  # Zeilen machen, von denen die zweite kein Schluessel=Wert mehr ist.
  # *First line only: a stray second line would break the stamp's key=value
  #  format.*
  v=$(head -1 "$REPO/VERSION" 2>/dev/null | tr -d '[:space:]') || v=""
  [ -n "$v" ] || v=unbekannt
  # git steht NICHT in den Grundpaketen von Stufe 10 - es ist auf der Maschine
  # also nicht garantiert. Fehlt es, wird das benannt statt geraten.
  # *git is not among the base packages, so it may be absent; say so instead of
  #  guessing.*
  if c=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null); then
    git -C "$REPO" diff --quiet HEAD 2>/dev/null || stand=geaendert
  else
    c=unbekannt
  fi
  printf 'VERSION=%s\nCOMMIT=%s\nSTAND=%s\nDATUM=%s\n' \
         "$v" "$c" "$stand" "$(date -Is)" > "$VERSIONSDATEI"
  chmod 0644 "$VERSIONSDATEI"
}

# Wird von einsetzen() gerufen: sobald eine Stufe einzeln laeuft, stimmt der
# Stempel nicht mehr genau. einrichten.sh schreibt ihn nach ALLEN Stufen neu und
# setzt ihn damit wieder auf "sauber" - die Markierung bleibt also nur stehen,
# wenn wirklich einzeln nachgearbeitet wurde.
# *Called by einsetzen(): a single stage run makes the stamp inexact.
#  einrichten.sh rewrites it after all stages, so the mark survives only when
#  something really was done piecemeal.*
version_markieren() {
  [ -f "$VERSIONSDATEI" ] || return 0
  # Kein "sed -i": das braucht auf BSD ein Argument und scheitert dort still.
  # Der Stempel wird auf der Maschine geschrieben, also mit GNU sed - aber ein
  # Aufruf, der bei der kleinsten Abweichung wortlos nichts tut, ist genau die
  # Sorte Fehler, die man erst bemerkt, wenn man sich auf die Auskunft verlaesst.
  # Ueber eine Zwischendatei ersetzen: portabel und atomar.
  # *No "sed -i": on BSD it needs an argument and fails silently. A call that
  #  quietly does nothing is exactly the kind of fault one notices only when
  #  relying on its answer. Via a temporary file: portable and atomic.*
  local tmp="$VERSIONSDATEI.neu"
  sed 's/^STAND=.*/STAND=geaendert/' "$VERSIONSDATEI" > "$tmp" \
    && chmod 0644 "$tmp" && mv "$tmp" "$VERSIONSDATEI"
}

# dns_konf_uebernehmen — holt den DNS-Zugang aus dem alten Dateinamen herueber.
#
# Bis zum Anbieter-Umbau stand der Cloudflare-Token in
# /etc/cloudflare-gameserver.conf (CF_TOKEN=...). Heute stehen Anbieter und
# Token zusammen in /etc/dns-gameserver.conf. Beide Orte gleichzeitig zu lesen
# war die Uebergangshilfe; zwei Orte fuer dieselbe Angabe laufen aber
# frueher oder spaeter auseinander, und dann entscheidet ein Vorrang darueber,
# welches Geheimnis gilt - das will niemand nachvollziehen muessen.
#
# Uebernommen wird deshalb EINMAL, hier, und laut: die alte Datei wandert nach
# <datei>.vor-<datum>, und beide Pfade stehen im Protokoll. Das Token ist das
# einzige Geheimnis dieser Datei - wer hinterher nicht weiss, wo es liegt, sucht
# an der falschen Stelle.
#
# *Provider and token now live together in /etc/dns-gameserver.conf. Reading
#  both locations was the transition; two places for one setting drift, and then
#  a precedence rule decides which secret applies. Migrated once, here, and
#  loudly: the old file is moved aside and both paths are logged.*
DNS_KONF=/etc/dns-gameserver.conf
DNS_KONF_ALT=/etc/cloudflare-gameserver.conf

# --- Zertifikat --------------------------------------------------------------
# ZERTIFIKAT_WEG traegt den Namen der ACME-Pruefung, die Caddy benutzt - also
# das Wort, das auch im Caddy-Protokoll und bei Let's Encrypt steht. Eine eigene
# Sprache ("port"/"dns") waere eine Uebersetzung mehr zwischen Meldung und
# Konfiguration, und beim Suchen eines Fehlers sucht man nach dem Wort aus dem
# Protokoll.
#
#   http-01   Let's Encrypt ruft die Maschine auf Port 80 auf. Vorgabe.
#   dns-01    Caddy legt einen TXT-Eintrag in der Zone an. Braucht KEINEN
#             eingehenden Port, aber einen Caddy mit dem passenden
#             DNS-Modul und den Token aus /etc/dns-gameserver.conf.
#
# *Carries the ACME challenge name, so the configuration uses the same word as
#  the log and the CA. dns-01 needs no inbound port but needs a Caddy with the
#  provider module compiled in.*
case "$ZERTIFIKAT_WEG" in
  http-01|dns-01) ;;
  *) fehler "konfiguration.env: ZERTIFIKAT_WEG=\"$ZERTIFIKAT_WEG\" ist weder" \
            "\"http-01\" noch \"dns-01\"." ;;
esac
# dns-01 ohne DNS-Zugang ist kein halber Zustand, sondern ein Panel ohne
# Zertifikat - und das faellt erst auf, wenn niemand mehr hinsieht. Deshalb hier
# und nicht erst in Stufe 40: die Einrichtung soll anhalten, bevor sie Caddy
# umbaut.
# *dns-01 without DNS access is not a partial state but a panel without a
#  certificate; stop before rebuilding Caddy rather than after.*
if [ "$ZERTIFIKAT_WEG" = "dns-01" ] && [ ! -s "$DNS_KONF" ]; then
  fehler "ZERTIFIKAT_WEG=dns-01 braucht $DNS_KONF (ANBIETER= und TOKEN=)." \
         "Ohne DNS-Zugang kann Caddy den TXT-Eintrag nicht setzen."
fi


dns_konf_uebernehmen() {
  [ -s "$DNS_KONF_ALT" ] || return 0
  if [ -s "$DNS_KONF" ]; then
    warn "$DNS_KONF_ALT liegt noch da und wird NICHT mehr gelesen — es gilt $DNS_KONF."
    warn "Wegraeumen, sobald geprueft: mv $DNS_KONF_ALT $DNS_KONF_ALT.alt"
    return 0
  fi
  local tok
  tok=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}CF_TOKEN[[:space:]]*=[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]#]\{1,\}\).*/\2/p' \
          "$DNS_KONF_ALT" | head -1)
  [ -n "$tok" ] || fehler "$DNS_KONF_ALT enthaelt kein CF_TOKEN — von Hand nach $DNS_KONF uebertragen"
  printf 'ANBIETER=cloudflare\nTOKEN=%s\n' "$tok" > "$DNS_KONF"
  chmod 600 "$DNS_KONF"; chown root:root "$DNS_KONF"
  local weg="$DNS_KONF_ALT.vor-$(date +%Y%m%d-%H%M%S)"
  mv "$DNS_KONF_ALT" "$weg"
  log "DNS-Zugang uebernommen:"
  log "  von  $weg   (frueher $DNS_KONF_ALT)"
  log "  nach $DNS_KONF   (ANBIETER=cloudflare)"
}

# einsetzen <quelle> <ziel> [modus] [eigentuemer]
#
# Kopiert eine Repo-Datei nach <ziel> und ersetzt dabei jeden @@PLATZHALTER@@.
# Eine vorhandene Zieldatei wird VORHER nach <ziel>.vor-<datum> gesichert —
# ohne diesen Rueckweg ist eine zweite Ausfuehrung ein Datenverlust.
#
# *Installs a repo file, substituting every @@PLACEHOLDER@@. An existing
#  target is backed up to <target>.vor-<date> first: without that fallback a
#  second run would silently destroy hand edits.*
einsetzen() {
  local quelle="$1" ziel="$2" modus="${3:-0644}" eigner="${4:-root:root}"
  [ -f "$quelle" ] || fehler "Quelle fehlt: $quelle"
  mkdir -p "$(dirname "$ziel")"
  if [ -f "$ziel" ] && ! cmp -s <(rendern "$quelle") "$ziel"; then
    cp -a "$ziel" "$ziel.vor-$(date +%Y%m%d-%H%M%S)"
  fi
  rendern "$quelle" > "$ziel"
  chmod "$modus" "$ziel"; chown "$eigner" "$ziel"
  version_markieren
  log "$ziel"
}

# rendern <datei> — schreibt die Datei mit ersetzten Platzhaltern nach stdout.
# Ein uebrig gebliebener @@NAME@@ ist ein Fehler und bricht ab: eine Datei mit
# unersetztem Platzhalter faellt sonst erst im Betrieb auf, oft als leerer Wert.
# *A left-over @@NAME@@ aborts: unsubstituted placeholders otherwise surface
#  only at runtime, usually as an empty value.*
# Der zweite Parameter nennt Platzhalter, die STEHEN BLEIBEN duerfen: die
# Stack-Einrichtung setzt @@PASSWORT@@ und @@ADMIN_PASSWORT@@ erst danach ein,
# weil sie je Server frisch gewuerfelt werden und nicht in konfiguration.env
# gehoeren. Ohne diese Ausnahme wuerde rendern dort abbrechen.
# *The second argument lists placeholders allowed to survive: per-stack
#  passwords are generated afterwards and must not live in konfiguration.env.*
rendern() {
  local text; text=$(cat "$1")
  local erlaubt="${2:-}"
  local v
  for v in "${VARIABLEN[@]}"; do
    text=${text//@@${v}@@/${!v}}
  done
  local rest
  rest=$(grep -oE '@@[A-Z_]+@@' <<<"$text" | sort -u || true)
  [ -n "$erlaubt" ] && rest=$(grep -vE "$erlaubt" <<<"$rest" || true)
  if [ -n "$rest" ]; then
    while read -r p; do warn "unbekannter Platzhalter $p in $1"; done <<<"$rest"
    fehler "unersetzte Platzhalter in $1"
  fi
  printf '%s\n' "$text"
}

# passwort [laenge] — Beitrittspasswort ohne verwechselbare Zeichen.
# 0/O, 1/l/I und die Sonderzeichen fehlen bewusst: die Passwoerter werden
# vorgelesen und abgetippt, und manche Spiele filtern Sonderzeichen still weg.
# *No look-alike characters and no punctuation: these are read aloud and typed
#  by hand, and some games silently strip special characters.*
passwort() {
  local n="${1:-14}"
  tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c "$n"
}

# Zeitgeber fuer den A-Eintrag DNS_ZIEL (#195): einsetzen und je nach
# SERVER_IPV4 ein- oder ausschalten. Stand bis dahin nur in Stufe 70, und die
# laeuft in der dokumentierten Einrichtung NICHT mit - bei SERVER_IPV4=dynamic
# versprach konfiguration.env einen Zeitgeber, den niemand anlegte, alle Stufen
# meldeten "fertig", und die Adresse veraltete still. Jetzt ruft Stufe 25 (laeuft
# immer, sobald ein DNS-Token da ist) diese Funktion, Stufe 70 dieselbe.
# *Install the DNS_ZIEL timer and switch it by SERVER_IPV4. It lived only in
#  stage 70, which the documented install does not run - "dynamic" promised a
#  timer nobody created. Stage 25 now calls this, stage 70 the same function.*
dns_ziel_zeitgeber() {
  for u in dns-ziel.service dns-ziel.timer; do
    einsetzen "$REPO/systemd/$u" "/etc/systemd/system/$u"
  done
  systemctl daemon-reload
  if [ "$IP_DYNAMISCH" = "ja" ]; then
    systemctl enable --now dns-ziel.timer
    log "SERVER_IPV4=dynamic - Zeitgeber fuer ${DNS_ZIEL} laeuft (alle fuenf Minuten)"
  else
    # Liegt trotzdem auf der Maschine: ein Wechsel auf "dynamic" ist dann eine
    # Zeile in konfiguration.env und ein erneuter Lauf dieser Stufe.
    systemctl disable --now dns-ziel.timer 2>/dev/null || true
    log "SERVER_IPV4 ist fest (${SERVER_IPV4}) - Zeitgeber bleibt aus"
  fi
}
