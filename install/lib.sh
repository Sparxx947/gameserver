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
           ADMIN_NETZ ADMIN_IP BORG_REPO BORG_TAILSCALE_IP FREMD_IPV4)

for v in "${VARIABLEN[@]}"; do
  [ -n "${!v}" ] || fehler "konfiguration.env: \$$v ist leer"
done

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
