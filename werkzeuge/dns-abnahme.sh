#!/bin/bash
# dns-abnahme.sh — laesst die Pruefliste aus Issue #60 gegen eine ECHTE Zone
# laufen, ohne irgendetwas zu installieren.
#
# Warum es das gibt: Anbietercode, der nie gegen die echte API lief, sieht aus
# als liefe er. Die Pruefliste dagegen von Hand abzuarbeiten sind neun Schritte,
# von denen ZWEI fehlschlagen muessen - und ein Schritt, der nicht fehlschlaegt
# obwohl er soll, faellt beim Ablesen nicht auf. Genau deshalb steht die Liste
# hier als Programm und nicht als Prosa.
#
# *Provider code that never ran against the real API looks like it runs. Doing
#  the checklist by hand is nine steps, two of which must FAIL - and a step that
#  fails to fail is not noticed when read off a screen.*
#
# Angefasst wird nichts Installiertes: weder /etc/dns-gameserver.conf noch eine
# ausgerollte Fassung. Stattdessen entsteht in einem temporaeren Verzeichnis
# (Modus 700) eine Wegwerf-Fassung von bin/dns-pflegen mit den Werten dieses
# Laufs. Sie wird am Ende geloescht, auch wenn etwas schiefgeht.
#
#   werkzeuge/dns-abnahme.sh --anbieter hetzner --zone beispiel.de \
#                            --ip 203.0.113.10 --token-datei ~/.hetzner-token
#
#   --anbieter <name>     hetzner | cloudflare (muss in ANBIETER stehen)
#   --zone <zone>         die Zone, in der geschrieben wird
#   --ip <ipv4>           Adresse, auf die die A-Eintraege zeigen sollen
#   --token-datei <pfad>  Datei mit dem Token; ALTERNATIV die Umgebungsvariable
#                         DNS_ABNAHME_TOKEN. NIE als Argument - Argumente stehen
#                         fuer jeden lesbar in der Prozessliste.
#   --behalten            am Ende nicht aufraeumen (zum Nachsehen in der Zone)
#   --selbsttest          nur das Geruest pruefen, ohne jede API
#
# Exit: 0 = alle Schritte wie erwartet, 1 = mindestens einer nicht.
set -uo pipefail

ANBIETER=""; ZONE=""; IP=""; TOKEN_DATEI=""; BEHALTEN=0; SELBSTTEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --anbieter)    ANBIETER="${2:-}"; shift 2 ;;
        --zone)        ZONE="${2:-}"; shift 2 ;;
        --ip)          IP="${2:-}"; shift 2 ;;
        --token-datei) TOKEN_DATEI="${2:-}"; shift 2 ;;
        --behalten)    BEHALTEN=1; shift ;;
        --selbsttest)  SELBSTTEST=1; shift ;;
        -h|--help)     sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unbekanntes Argument: $1" >&2; exit 2 ;;
    esac
done

HIER=$(cd "$(dirname "$0")/.." && pwd)
QUELLE="$HIER/bin/dns-pflegen"
[ -r "$QUELLE" ] || { echo "$QUELLE nicht lesbar" >&2; exit 2; }

# --- Wegwerf-Umgebung -------------------------------------------------------
# umask VOR dem Anlegen: der mode-Parameter von mkdir wird von der umask
# beschnitten, und in dieser Datei landet gleich ein Token.
# *umask before mkdir: the mode argument is masked, and a token goes in here.*
umask 077
ARBEIT=$(mktemp -d -t dns-abnahme.XXXXXXXX) || exit 2
GEBAUT=()          # was dieser Lauf angelegt hat - fuers Aufraeumen
aufraeumen() {
    local rc=$?
    if [ $BEHALTEN -eq 0 ] && [ ${#GEBAUT[@]} -gt 0 ] && [ -x "$ARBEIT/dns" ]; then
        echo
        echo "== Aufraeumen =="
        for n in "${GEBAUT[@]}"; do
            "$ARBEIT/dns" entfernen "$n" 2>&1 | sed 's/^/  /'
        done
    fi
    rm -rf "$ARBEIT"
    exit $rc
}
trap aufraeumen EXIT

schritte=0; schlecht=0
# erwartet <0|1> <ueberschrift> <befehl...>
# 0 = muss durchlaufen, 1 = muss fehlschlagen. Zwei Schritte dieser Liste sind
# nur dann bestanden, wenn sie NICHT funktionieren; das ist der halbe Sinn.
erwartet() {
    local soll="$1" titel="$2"; shift 2
    schritte=$((schritte+1))
    echo
    echo "-- [$schritte] $titel"
    local aus rc
    aus=$("$@" 2>&1); rc=$?
    sed 's/^/     /' <<<"$aus"
    if [ "$soll" -eq 0 ] && [ $rc -ne 0 ]; then
        echo "  FEHLGESCHLAGEN (Exit $rc, erwartet war 0)"; schlecht=$((schlecht+1)); return 1
    fi
    if [ "$soll" -eq 1 ] && [ $rc -eq 0 ]; then
        echo "  FEHLGESCHLAGEN — dieser Schritt haette abgewiesen werden MUESSEN"
        schlecht=$((schlecht+1)); return 1
    fi
    echo "  ok"
    return 0
}

# enthaelt <text> <muster> <erklaerung>
enthaelt() {
    schritte=$((schritte+1))
    echo
    echo "-- [$schritte] $3"
    if grep -qE "$2" <<<"$1"; then
        echo "  ok"
    else
        echo "  FEHLGESCHLAGEN — '$2' kam in der Ausgabe nicht vor:"
        sed 's/^/     /' <<<"$1"; schlecht=$((schlecht+1))
    fi
}

# --- Die Wegwerf-Fassung bauen ----------------------------------------------
# Ersetzt werden die Platzhalter UND der feste Pfad der Konfiguration. Danach
# wird nachgesehen, ob wirklich nichts uebrig blieb: ein uebersehener
# @@PLATZHALTER@@ hat schon einmal einen gruenen Test mit falschem Inhalt
# erzeugt (siehe die Falle "Dateien auf die Maschine bringen" in CLAUDE.md).
# *The placeholders AND the fixed config path are substituted, then checked:
#  a missed placeholder has produced a green test with wrong content before.*
# @@FREMD_IPV4@@ kommt nur in einem Kommentar vor (dem Beispiel, warum `dig`
# bei einem Wildcard nichts beweist). Ersetzt wird es trotzdem, denn die Pruefung
# darunter ist mit Absicht stumpf: sie bricht bei JEDEM uebrig gebliebenen @@ ab.
# Wer spaeter einen neuen Platzhalter in dns-pflegen einbaut, laeuft hier auf und
# muss ihn hier eintragen - besser als eine Abnahme, die mit dem Wort
# "@@SERVER_IPV4@@" als Adresse gruen wird.
# *Substituted although it only appears in a comment: the check below is
#  deliberately blunt and aborts on ANY leftover @@, so a newly introduced
#  placeholder stops the acceptance run instead of being rendered literally.*
bauen() {   # $1 = ZIEL-fqdn, $2 = PANEL-fqdn, $3 = zieldatei, $4 = quelle (opt.)
    local quelle="${4:-$QUELLE}"
    sed -e "s|@@FREMD_IPV4@@|198.51.100.7|g" \
        -e "s|@@DNS_ZONE@@|$ZONE|g" \
        -e "s|@@DNS_ZIEL@@|$1|g" \
        -e "s|@@PANEL_DOMAIN@@|$2|g" \
        -e "s|@@SERVER_IPV4@@|$IP|g" \
        -e "s|^KONF = Path(\"/etc/dns-gameserver.conf\")$|KONF = Path(\"$ARBEIT/conf\")|" \
        -e "s|^KONF_ALT = Path(\"/etc/cloudflare-gameserver.conf\")$|KONF_ALT = Path(\"$ARBEIT/conf-alt\")|" \
        "$quelle" > "$3"
    chmod 700 "$3"
    if grep -q '@@' "$3"; then
        echo "ABBRUCH: nach dem Ersetzen steht noch ein Platzhalter drin:" >&2
        grep -on '@@[A-Z_]*@@' "$3" | head -5 >&2
        return 1
    fi
    grep -q "KONF = Path(\"$ARBEIT/conf\")" "$3" || {
        echo "ABBRUCH: der Konfigurationspfad wurde NICHT umgebogen — das haette" >&2
        echo "  gegen /etc/dns-gameserver.conf gelaufen." >&2
        return 1
    }
    return 0
}

# --- Selbsttest: beweist das Geruest, ohne eine einzige API zu fragen --------
# Der OK-Fall beweist nichts. Hier wird nachgewiesen, dass (a) das Ersetzen
# wirklich prueft, (b) "muss fehlschlagen" auch anschlaegt.
if [ $SELBSTTEST -eq 1 ]; then
    ZONE="${ZONE:-beispiel.test}"; IP="${IP:-203.0.113.10}"
    echo "== Selbsttest (ohne Netz) =="
    echo
    echo "-- Platzhalterpruefung: ein UNBEKANNTER Platzhalter muss abbrechen"
    # Nachgewiesen an einer eigens verdorbenen Kopie - nicht an einer leeren
    # Zone. Eine leere Zone loest hier zwar auch einen Abbruch aus, aber aus
    # einem anderen Grund; ein Nachweis, der aus dem falschen Grund gruen wird,
    # ist keiner. (Genau das ist beim ersten Entwurf passiert.)
    # *Proven on a deliberately doctored copy: an empty zone would also abort,
    #  but for a different reason - a proof that passes for the wrong reason is
    #  not a proof. The first draft did exactly that.*
    sed '1a # @@VOELLIG_NEUER_PLATZHALTER@@' "$QUELLE" > "$ARBEIT/verdorben"
    # Ausgabe erst einsammeln, dann durchsuchen. Mit `| grep` waere das hier
    # falsch: bauen() gibt absichtlich 1 zurueck, und unter `set -o pipefail`
    # gilt damit die GANZE Pipeline als gescheitert - der Nachweis waere rot
    # gewesen, obwohl er zutraf. (Steht als Falle in CLAUDE.md; hier trotzdem
    # hineingelaufen.)
    # *Collected first, searched after: bauen() returns 1 on purpose, and under
    #  pipefail that fails the whole pipeline even when grep matched.*
    meldung=$(bauen "ziel.$ZONE" "panel.$ZONE" "$ARBEIT/kaputt" "$ARBEIT/verdorben" 2>&1)
    if grep -q VOELLIG_NEUER <<<"$meldung"; then
        echo "  ok  ein unbekannter Platzhalter bricht ab und wird benannt"
    else
        echo "  FEHLER: unbekannter Platzhalter kam durch"; exit 1
    fi
    echo
    echo "-- Gegenprobe: die unveraenderte Quelle darf NICHT abbrechen"
    if bauen "ziel.$ZONE" "panel.$ZONE" "$ARBEIT/heil" >/dev/null 2>&1; then
        echo "  ok  sonst wuerde die Pruefung fuer jede Eingabe dasselbe melden"
    else
        echo "  FEHLER: die Pruefung weist ALLES ab - sie prueft nichts"; exit 1
    fi
    echo
    echo "-- Konfigurationspfad: muss im Arbeitsverzeichnis liegen, nicht in /etc"
    bauen "ziel.$ZONE" "panel.$ZONE" "$ARBEIT/dns" || exit 1
    # Genau die ZUWEISUNG pruefen, nicht das Vorkommen der Zeichenkette: der
    # Pfad steht auch in der Hilfe des Programms, und die soll er behalten.
    # *The assignment, not the string: the path also appears in the help text.*
    if grep -qE '^KONF = Path\("/etc/' "$ARBEIT/dns"; then
        echo "  FEHLER: KONF zeigt weiter nach /etc"; exit 1
    fi
    grep -E '^KONF = Path' "$ARBEIT/dns" | sed 's/^/  ok  /' 
    echo
    echo "-- 'muss fehlschlagen' schlaegt an: ein unzulaessiger Name"
    # pruefe_name() greift VOR jedem API-Aufruf - deshalb braucht dieser
    # Nachweis kein Netz und keinen Token.
    # Ein Anbietername, den es nicht gibt: damit scheitert konfiguration() -
    # UND zwar erst NACH pruefe_name(). So laesst sich die Namenspruefung in
    # beide Richtungen nachweisen, ohne dass ein einziges Paket das Haus
    # verlaesst. (Der erste Entwurf nahm hier einen ungueltigen Token und
    # fragte damit die echte API an - "ohne Netz" stand daneben und stimmte
    # nicht.)
    # *A provider name that does not exist fails in konfiguration(), which runs
    #  AFTER pruefe_name() - so the name check can be shown to fire and to not
    #  fire, without a single packet leaving the machine.*
    printf 'ANBIETER=%s\nTOKEN=%s\n' "gibtesnicht" "ungenutzt" > "$ARBEIT/conf"
    erwartet 1 "setzen 'Kein Gueltiger Name' muss abgewiesen werden" \
        "$ARBEIT/dns" setzen "Kein Gueltiger Name" || exit 1
    aus=$("$ARBEIT/dns" setzen "Kein Gueltiger Name" 2>&1)
    grep -qi "unzulaessiger name" <<<"$aus" || {
        echo "  FEHLER: abgewiesen, aber aus einem anderen Grund:"
        sed 's/^/     /' <<<"$aus"; exit 1; }
    echo
    echo "-- Gegenprobe: ein ZULAESSIGER Name darf hier nicht am Namen scheitern"
    aus=$("$ARBEIT/dns" setzen "abnahme" 2>&1)
    if grep -qi "unzulaessiger name" <<<"$aus"; then
        echo "  FEHLER: die Namenspruefung weist ALLES ab — sie prueft nichts"
        exit 1
    fi
    echo "  ok  kommt an der Namenspruefung vorbei und scheitert erst danach:"
    sed 's/^/     /' <<<"$aus" | head -2
    echo
    echo "Selbsttest bestanden — das Geruest greift. Fuer die echte Abnahme"
    echo "dasselbe ohne --selbsttest, mit Zone, IP und Token."
    exit 0
fi

# --- Ab hier wird wirklich geschrieben --------------------------------------
for pflicht in ANBIETER ZONE IP; do
    [ -n "${!pflicht}" ] || { echo "--${pflicht,,} fehlt (siehe --help)" >&2; exit 2; }
done
TOKEN="${DNS_ABNAHME_TOKEN:-}"
if [ -n "$TOKEN_DATEI" ]; then
    [ -r "$TOKEN_DATEI" ] || { echo "Tokendatei nicht lesbar: $TOKEN_DATEI" >&2; exit 2; }
    TOKEN=$(tr -d '\r\n' < "$TOKEN_DATEI")
fi
[ -n "$TOKEN" ] || { echo "kein Token — --token-datei oder DNS_ABNAHME_TOKEN" >&2; exit 2; }

# Zufaelliger Namensraum: dieser Lauf kann keinen vorhandenen Eintrag treffen.
# *A random namespace per run: this cannot collide with an existing record.*
LAUF="abnahme-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
ZIEL="$LAUF-ziel.$ZONE"
PANEL="$LAUF-panel.$ZONE"
SPIEL="$LAUF-spiel"
FREMD_ZIEL="$LAUF-fremd.$ZONE"

echo "== DNS-Abnahme =="
echo "  Anbieter   $ANBIETER"
echo "  Zone       $ZONE"
echo "  Namensraum $LAUF-*   (alles andere in der Zone bleibt unberuehrt)"
echo "  Token      aus ${TOKEN_DATEI:-\$DNS_ABNAHME_TOKEN} — wird nicht ausgegeben"

printf 'ANBIETER=%s\nTOKEN=%s\n' "$ANBIETER" "$TOKEN" > "$ARBEIT/conf"
bauen "$ZIEL" "$PANEL" "$ARBEIT/dns" || exit 1
# Zweite Fassung mit einem ANDEREN Ziel. Damit entsteht der "fremde Eintrag"
# ohne eine einzige anbieterspezifische Zeile: derselbe CNAME zeigt aus ihrer
# Sicht woandershin, und genau den darf entfernen() nicht anfassen.
# *A second rendering with a different target produces the "foreign record"
#  without one provider-specific line.*
bauen "$FREMD_ZIEL" "$PANEL" "$ARBEIT/dns-fremd" || exit 1

erwartet 0 "anbieter — zeigt Anbieter, Zone und Proxy-Kenntnis" \
    "$ARBEIT/dns" anbieter
aus=$("$ARBEIT/dns" anbieter 2>&1)
enthaelt "$aus" "^anbieter[[:space:]]+$ANBIETER$" "der gemeldete Anbieter ist $ANBIETER"

erwartet 0 "grundgeruest — legt $ZIEL und $PANEL an" \
    "$ARBEIT/dns" grundgeruest
GEBAUT+=("$SPIEL")     # ab jetzt raeumt der trap auf

aus=$("$ARBEIT/dns" grundgeruest 2>&1)
schritte=$((schritte+1))
echo
echo "-- [$schritte] grundgeruest zum ZWEITEN Mal — darf NICHTS mehr anlegen"
sed 's/^/     /' <<<"$aus"
if grep -qE '^ok[[:space:]]+0 Eintrag' <<<"$aus"; then
    echo "  ok"
else
    echo "  FEHLGESCHLAGEN — der zweite Lauf haette 0 anlegen muessen."
    echo "  Das ist das Fehlerbild aus #60: ein Anbieter, der einen API-Fehler"
    echo "  als leere Liste durchreicht, laesst hier alles doppelt entstehen."
    schlecht=$((schlecht+1))
fi

erwartet 0 "setzen $SPIEL — CNAME auf $ZIEL" \
    "$ARBEIT/dns" setzen "$SPIEL"
aus=$("$ARBEIT/dns" setzen "$SPIEL" 2>&1)
enthaelt "$aus" "steht bereits richtig" "setzen zum zweiten Mal aendert nichts"

aus=$("$ARBEIT/dns" liste 2>&1)
enthaelt "$aus" "$SPIEL\.$ZONE" "liste zeigt $SPIEL.$ZONE"

erwartet 0 "pruefen — bei einem Anbieter ohne Proxy endet das mit 0" \
    "$ARBEIT/dns" pruefen

erwartet 1 "entfernen aus SICHT EINES ANDEREN ZIELS — muss verweigert werden" \
    "$ARBEIT/dns-fremd" entfernen "$SPIEL"
aus=$("$ARBEIT/dns" liste 2>&1)
enthaelt "$aus" "$SPIEL\.$ZONE" "und der Eintrag steht danach noch da"

erwartet 0 "entfernen $SPIEL — mit dem richtigen Ziel geht es" \
    "$ARBEIT/dns" entfernen "$SPIEL"
aus=$("$ARBEIT/dns" liste 2>&1)
schritte=$((schritte+1))
echo
echo "-- [$schritte] liste zeigt $SPIEL.$ZONE nicht mehr"
if grep -qE "$SPIEL\.$ZONE" <<<"$aus"; then
    echo "  FEHLGESCHLAGEN — der Eintrag ist noch da"; schlecht=$((schlecht+1))
else
    echo "  ok"
fi
GEBAUT=()   # ist weg, der trap muss nicht mehr

erwartet 0 "entfernen eines Namens, den es nie gab — kein Fehler" \
    "$ARBEIT/dns" entfernen "$LAUF-gibtesnicht"

echo
echo "=========================================================="
if [ $schlecht -eq 0 ]; then
    echo "  $schritte Schritte, alle wie erwartet."
else
    echo "  $schritte Schritte, davon $schlecht NICHT wie erwartet."
fi
echo
echo "  Von Hand zu loeschen — dns-pflegen kennt keinen Befehl dafuer,"
echo "  weil es A-Eintraege nie loescht (E21):"
echo "      $ZIEL"
echo "      $PANEL"
echo "=========================================================="
exit $((schlecht > 0))
