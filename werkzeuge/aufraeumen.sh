#!/bin/bash
# aufraeumen.sh — raeumt alte .vor-<datum>-Kopien von der Maschine.
#
# Warum es die Kopien gibt: Jede Einrichtungsstufe, jedes ausrollen.sh und jede
# Aenderung ueber die Weboberflaeche legt vor dem Ueberschreiben eine Kopie an.
# Das ist der Rueckweg — und genau deshalb wird hier nicht einfach alles
# geloescht, sondern je Datei die juengsten behalten.
#
# Drei Sorten entstehen:
#   <datei>.vor-<datum>              Einrichtung und ausrollen.sh
#   <datei>.vor-panel-<datum>        Oberflaeche (Konfigdateien, compose-Felder)
#   <verz>.vor-restore-<datum>       VOLLE Kopie eines Spieldatenverzeichnisses
#                                    vor einem Zurueckspielen - Gigabytes
#
# Die dritte Sorte haengt an einem eigenen Schalter. Sie ist der einzige Weg
# zurueck, wenn sich ein Zurueckspielen als falsch herausstellt und man nicht
# ueber Borg gehen will.
#
# *Every install stage, every rollout and every change made through the panel
#  leaves a copy behind before overwriting. Those copies are the way back, which
#  is why this keeps the newest ones per file instead of deleting everything.
#  The third kind - a full copy of a game's data directory taken before a
#  restore - runs off its own flag: it is the only way back if a restore turns
#  out to have been wrong.*
#
#   werkzeuge/aufraeumen.sh <ssh-ziel> [--behalte N] [--aelter-als T]
#                           [--mit-restore-kopien] [--wirklich]
#
# Exit 0 = durch, 1 = einzelne Schritte fehlgeschlagen, 2 = gar nicht erst los.
set -uo pipefail

ZIEL=""; WIRKLICH=0; BEHALTE=3; TAGE=14; MIT_RESTORE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wirklich)           WIRKLICH=1 ;;
    --mit-restore-kopien) MIT_RESTORE=1 ;;
    --behalte)            BEHALTE="${2:-}"; shift ;;
    --aelter-als)         TAGE="${2:-}"; shift ;;
    -*) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    *)  [ -z "$ZIEL" ] || { echo "Nur ein Ziel angeben." >&2; exit 2; }; ZIEL="$1" ;;
  esac
  shift
done
[ -n "$ZIEL" ] || { cat >&2 <<TEXT
Aufruf: $0 <ssh-ziel> [--behalte N] [--aelter-als T] [--mit-restore-kopien] [--wirklich]

  --behalte N        je Datei die N juengsten Kopien behalten (Vorgabe: 3)
  --aelter-als T     nur loeschen, was aelter als T Tage ist (Vorgabe: 14)
  --wirklich         ohne diesen Schalter wird nur gezeigt, was geschehen wuerde
TEXT
exit 2; }
[[ "$BEHALTE" =~ ^[0-9]+$ ]] || { echo "--behalte braucht eine Zahl." >&2; exit 2; }
[[ "$TAGE"    =~ ^[0-9]+$ ]] || { echo "--aelter-als braucht eine Zahl." >&2; exit 2; }

fern() { ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "$@"; }
fern true 2>/dev/null || { echo "Nicht erreichbar: $ZIEL"; exit 2; }

# Die Grenze wird auf DIESER Maschine gerechnet, und die kann BSD-date haben
# (macOS) oder GNU-date (Linux). Beide Formen probieren statt eine anzunehmen.
# *Computed on this workstation, which may have BSD or GNU date.*
GRENZE=$(date -d "-$TAGE days" +%Y%m%d-%H%M%S 2>/dev/null \
      || date -v-"${TAGE}"d +%Y%m%d-%H%M%S 2>/dev/null)
[ -n "$GRENZE" ] || { echo "Konnte die Zeitgrenze nicht berechnen." >&2; exit 2; }

# Nur bekannte Bereiche absuchen. Ein find ueber / waere langsam und wuerde
# Kopien anfassen, die nicht von dieser Einrichtung stammen.
# *Only known areas: a find over / would be slow and would touch copies this
#  installation never made.*
BEREICHE="/etc /usr/local/bin /opt/panel /opt/stacks /srv/games /srv/dienste"

# Restore-Kopien gehen in die Gigabyte. "8192.0 MB" liest sich niemand richtig.
# *Restore copies run into gigabytes; nobody reads "8192.0 MB" correctly.*
menge() {   # menge <bytes>
  awk -v b="$1" 'BEGIN{
    if (b >= 1073741824) printf "%.1f GB", b/1073741824
    else if (b >= 1048576) printf "%.1f MB", b/1048576
    else printf "%.0f kB", b/1024 }'
}

echo "== Alte Kopien auf $ZIEL =="
printf '  behalten je Datei: %s   nur loeschen wenn aelter als: %s Tage (vor %s)\n' \
       "$BEHALTE" "$TAGE" "$GRENZE"
echo

# Je Sorte ein eigener Lauf. Die Laenge des Namenszusatzes ist dadurch bekannt,
# und die Zuordnung Kopie -> Ursprungsdatei braucht kein Raten.
# *One pass per kind, so the suffix length is known and mapping a copy back to
#  its original needs no guessing.*
sammeln() {   # sammeln <regex> <suffixlaenge>
  fern "find $BEREICHE -xdev -type f -regextype posix-extended -regex '$1' -printf '%s\t%p\n' 2>/dev/null" \
    | awk -F'\t' -v laenge="$2" '
        NF==2 {
          pfad=$2
          basis=substr(pfad, 1, length(pfad)-laenge)
          stempel=substr(pfad, length(pfad)-14)
          print basis "\t" stempel "\t" $1 "\t" pfad
        }'
}

# Sortiert nach Datei und Zeitstempel absteigend, dann je Datei durchzaehlen:
# alles ab dem (BEHALTE+1)-ten faellt weg, aber nur wenn es alt genug ist.
#
# Entschieden wird nach dem ZEITSTEMPEL IM NAMEN, nicht nach der mtime. Die
# Kopien entstehen mit "cp -a" und shutil.copy2 - beide uebernehmen die mtime
# der Quelldatei. Eine gestern angelegte Kopie einer ein Jahr alten Datei sieht
# in der mtime ein Jahr alt aus, und ein Aufraeumen nach mtime wuerde genau den
# frischesten Rueckweg zuerst wegwerfen.
# *Decided by the timestamp in the NAME, never by mtime: the copies are made
#  with cp -a and shutil.copy2, both of which carry the source's mtime across.
#  A copy taken yesterday of a year-old file looks a year old, so cleaning by
#  mtime would throw away the freshest way back first.*
auswaehlen() {
  sort -t$'\t' -k1,1 -k2,2r | awk -F'\t' -v behalte="$BEHALTE" -v grenze="$GRENZE" '
    $1 != vorherige { vorherige=$1; n=0 }
    { n++
      if (n > behalte && $2 < grenze) { print $3 "\t" $4; weg++; byte+=$3 }
      else                            { bleibt++ } }
    END { printf "ZUSAMMEN\t%d\t%d\t%d\n", (weg+0), (byte+0), (bleibt+0) }'
}

D8='[0-9]{8}'; D6='[0-9]{6}'
liste=$( { sammeln ".*\.vor-$D8-$D6" 20; sammeln ".*\.vor-panel-$D8-$D6" 26; } | auswaehlen )
zusammen=$(grep '^ZUSAMMEN' <<<"$liste")
kandidaten=$(grep -v '^ZUSAMMEN' <<<"$liste")
weg=$(cut -f2 <<<"$zusammen"); byte=$(cut -f3 <<<"$zusammen"); bleibt=$(cut -f4 <<<"$zusammen")

printf '  Dateikopien: %s zu entfernen (%s), %s bleiben stehen\n' \
       "$weg" "$(menge "$byte")" "$bleibt"

# Die Restore-Kopien einzeln, mit du: -printf %s waere bei einem Verzeichnis
# nur die Groesse des Verzeichniseintrags, nicht die des Inhalts.
# *du per directory: %s on a directory is the size of the entry, not the tree.*
restore=""
if [ "$MIT_RESTORE" -eq 1 ]; then
  restore=$(fern "find /srv/games /srv/dienste -maxdepth 1 -type d -regextype posix-extended -regex '.*\.vor-restore-$D8-$D6' 2>/dev/null" || true)
  rweg=0; rbyte=0; rliste=""
  while read -r d; do
    [ -n "$d" ] || continue
    stempel="${d: -15}"
    [ "$stempel" \< "$GRENZE" ] || continue
    groesse=$(fern "du -sk '$d' 2>/dev/null | cut -f1" 2>/dev/null || true)
    # Antwort pruefen statt sie zu glauben: verschwindet das Verzeichnis
    # zwischen find und du, liefert du nichts, und $((...)) bricht mit einem
    # Syntaxfehler mitten im Lauf ab - ausgerechnet beim Zaehlen von Platz.
    # *Validate the answer instead of trusting it: if the directory disappears
    #  between find and du, du returns nothing and the arithmetic aborts.*
    [[ "$groesse" =~ ^[0-9]+$ ]] || groesse=0
    rbyte=$((rbyte + groesse)); rweg=$((rweg+1))
    rliste+="$d"$'\n'
  done <<<"$restore"
  printf '  Restore-Kopien: %s zu entfernen (%s)\n' \
         "$rweg" "$(menge $((rbyte * 1024)))"
fi

cat <<TEXT

== Wird NICHT angefasst ==
TEXT
printf '  %-38s %s\n' "die $BEHALTE juengsten Kopien je Datei" "der Rueckweg bleibt erhalten"
printf '  %-38s %s\n' "alles neuer als $TAGE Tage" "ein Fehler faellt oft erst spaeter auf"
printf '  %-38s %s\n' "das Borg-Repository" "davon lebt die Wiederherstellung"
[ "$MIT_RESTORE" -eq 0 ] && printf '  %-38s %s\n' ".vor-restore-Verzeichnisse" "nur mit --mit-restore-kopien"
echo

if [ -z "$kandidaten" ] && [ "${rweg:-0}" -eq 0 ]; then
  echo "Nichts aufzuraeumen."
  exit 0
fi

if [ "$WIRKLICH" -eq 0 ]; then
  echo "== Was entfernt wuerde =="
  cut -f2 <<<"$kandidaten" | sed 's/^/  /' | head -40
  [ "$(wc -l <<<"$kandidaten")" -gt 40 ] && echo "  ... und weitere"
  [ -n "${rliste:-}" ] && sed 's/^/  /' <<<"$rliste"
  echo
  echo "Planlauf — nichts geaendert. Ausfuehren mit --wirklich."
  exit 0
fi

# Rueckfrage wie beim Rueckbau: der NAME des Ziels, nicht "ja". Gleiche
# Mechanik an beiden Stellen, damit man sie einmal lernt.
# *Same confirmation as the teardown tool, so it is learned once.*
if [ ! -t 0 ]; then
  echo "FEHLER: --wirklich braucht ein Terminal fuer die Rueckfrage." >&2
  exit 2
fi
printf 'Zum Bestaetigen den Namen des Ziels eintippen (%s): ' "$ZIEL"
read -r antwort
antwort="${antwort%$'\r'}"; antwort="${antwort#"${antwort%%[![:space:]]*}"}"
antwort="${antwort%"${antwort##*[![:space:]]}"}"
[ "$antwort" = "$ZIEL" ] || { echo "Abgebrochen — nichts geaendert."; exit 2; }

echo
echo "== Entfernen =="
fehlschlaege=0; getan=0
while read -r zeile; do
  [ -n "$zeile" ] || continue
  pfad=$(cut -f2 <<<"$zeile")
  if fern "rm -f -- '$pfad'" 2>/dev/null; then getan=$((getan+1))
  else echo "  FEHLGESCHLAGEN: $pfad"; fehlschlaege=$((fehlschlaege+1)); fi
done <<<"$kandidaten"
while read -r d; do
  [ -n "$d" ] || continue
  if fern "rm -rf -- '$d'" 2>/dev/null; then getan=$((getan+1)); echo "  entfernt: $d"
  else echo "  FEHLGESCHLAGEN: $d"; fehlschlaege=$((fehlschlaege+1)); fi
done <<<"${rliste:-}"

# --- Gegenprobe mit Kontrollwert ---------------------------------------------
# Geprueft wird beides: dass die Kandidaten weg sind UND dass je Datei noch eine
# Kopie steht, wo vorher eine stand. Ohne den zweiten Teil bemerkte man nicht,
# wenn die Auswahl zu gierig war und den Rueckweg mitgenommen haette.
# *Both halves are checked: that the candidates are gone and that a copy still
#  stands where one stood before. Without the second half, an over-greedy
#  selection that took the way back with it would go unnoticed.*
echo
echo "== Gegenprobe =="
uebrig=0
while read -r zeile; do
  [ -n "$zeile" ] || continue
  pfad=$(cut -f2 <<<"$zeile")
  fern "test -e '$pfad'" 2>/dev/null && { echo "  UEBRIG: $pfad"; uebrig=$((uebrig+1)); }
done <<<"$kandidaten"
[ "$uebrig" -eq 0 ] && echo "  alle Kandidaten entfernt."

echo "== Kontrollwert: steht je Datei noch eine Kopie? =="
ohne=0
for basis in $(cut -f1 <<<"$(sort -u <<<"$kandidaten" | cut -f2 | sed -E 's/\.vor(-panel)?-[0-9]{8}-[0-9]{6}$//')" | sort -u); do
  fern "ls -1 '$basis'.vor-* >/dev/null 2>&1" 2>/dev/null \
    || { echo "  KEINE KOPIE MEHR: $basis"; ohne=$((ohne+1)); }
done
[ "$ohne" -eq 0 ] && echo "  ueberall mindestens eine."

echo
printf 'entfernt: %d   fehlgeschlagen: %d   uebrig: %d   ohne Kopie: %d\n' \
       "$getan" "$fehlschlaege" "$uebrig" "$ohne"
[ $((fehlschlaege + uebrig + ohne)) -eq 0 ] || exit 1
