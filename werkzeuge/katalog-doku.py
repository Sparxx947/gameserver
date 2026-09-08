#!/usr/bin/env python3
"""katalog-doku.py — haelt die Dokumentation am Spielekatalog.

Warum es das gibt: Der Katalog ist ueber mehrere Aenderungen von 41 auf 179
Spiele gewachsen - 41, 86, 154, 162, 179. Die Doku ist bei 41 geblieben, an
vier Stellen, ueber Monate. Eine Zahl, die einmal gestimmt hat, liest sich wie
eine gepruefte Angabe: man handelt danach und merkt den Fehler nicht. Genau
davor warnt abgleich.sh im eigenen Kopf - "eine Dokumentation, die vom System
abweicht, ist schlimmer als keine" -, nur galt das bisher fuer die Maschine und
nicht fuer das Repositorium selbst.

Von Hand nachzupflegen loest das nicht. Es ist beim letzten Mal nicht passiert
und beim vorletzten auch nicht; was hilft, ist eine Pruefung, die MECKERT.
Deshalb --pruefen und ein Aufruf aus vollstaendigkeit.sh.

*Why this exists: the catalogue grew 41 -> 86 -> 154 -> 162 -> 179 while the
 documentation stayed at 41 in four places for months. A number that was once
 correct reads like a verified statement; people act on it and never notice.
 Maintaining it by hand is what already failed twice - what helps is a check
 that complains, so --pruefen is wired into vollstaendigkeit.sh.*

  werkzeuge/katalog-doku.py             Zahlen und Liste schreiben
  werkzeuge/katalog-doku.py --pruefen   nur berichten (Exit 1 = veraltet)
"""
import json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KATALOG = REPO / "etc/spiele-katalog.json"

# Wo die Gesamtzahl in der Doku steht. Ausdrueckliche Liste statt einer
# Suche nach "<Zahl> Spiele": in der Doku stehen mehrere Zahlen, die etwas
# ANDERES zaehlen ("13 Spiele teilen sich die Sammel-ID 90", "17 Spiele nennen
# ihren Port erst spaeter"). Eine Heuristik wuerde die mitfangen und Meldungen
# erzeugen, die man sich abgewoehnt zu lesen.
#
# Jeder Ausdruck MUSS genau einmal passen. Kein Treffer heisst nicht "in
# Ordnung", sondern "die Stelle hat sich verschoben" - sonst pruefte man ins
# Leere und haelt das fuer ein gutes Ergebnis.
#
# *An explicit list rather than a search for "<number> games": the docs carry
#  other numbers counting other things, and a heuristic would fire on those.
#  Each pattern must match exactly once - no match means the passage moved, not
#  that everything is fine.*
STELLEN = [
    ("README.md",                r"ein Katalog von (?P<zahl>\d+)"),
    ("README.md",                r"a catalogue of (?P<zahl>\d+)"),
    ("docs/01-architektur.md",   r"die (?P<zahl>\d+) installierbaren Spiele"),
    ("docs/04-spielekatalog.md", r"— (?P<zahl>\d+) Spiele, die sich"),
    ("docs/04-spielekatalog.md", r"\*(?P<zahl>\d+) games installable"),
    ("docs/09-referenz.md",      r"\| (?P<zahl>\d+) installierbare Spiele \|"),
]

# Zwischen diesen Marken steht die erzeugte Liste. Marken statt "ans Ende
# haengen": so bleibt der Platz im Dokument die Entscheidung eines Menschen und
# der Inhalt die des Katalogs.
# *Markers rather than appending: where the list sits stays a human decision,
#  what it contains does not.*
LISTE_DATEI = "docs/04-spielekatalog.md"
ANFANG = "<!-- katalog:anfang -->"
ENDE   = "<!-- katalog:ende -->"


def spiele() -> list:
    return json.loads(KATALOG.read_text())["spiele"]


def liste_bauen(s: list) -> str:
    """Die Tabelle. Erzeugt, nie von Hand angefasst."""
    zeilen = [ANFANG,
              "",
              f"<!-- Erzeugt von werkzeuge/katalog-doku.py — nicht von Hand aendern. -->",
              "",
              "| Schlüssel | Name | Kategorie | Bauart | Steam |",
              "|---|---|---|---|---|"]
    for g in sorted(s, key=lambda g: g["schluessel"]):
        appid = g.get("appid") or ""
        steam = f"`{appid}`" if appid else "—"
        zeilen.append(f"| `{g['schluessel']}` | {g.get('name','')} | "
                      f"{g.get('kategorie','')} | {g.get('bauart','')} | {steam} |")
    zeilen += ["", ENDE]
    return "\n".join(zeilen)


def main() -> int:
    pruefen = "--pruefen" in sys.argv
    s = spiele()
    anzahl = len(s)
    offen = []

    # 1. Die Zahlen
    for datei, muster in STELLEN:
        p = REPO / datei
        text = p.read_text()
        treffer = list(re.finditer(muster, text))
        if len(treffer) != 1:
            offen.append(f"{datei}: Muster passt {len(treffer)}x statt 1x — "
                         f"die Stelle hat sich verschoben: {muster}")
            continue
        m = treffer[0]
        if m.group("zahl") == str(anzahl):
            continue
        offen.append(f"{datei}: {m.group('zahl')} statt {anzahl}")
        if not pruefen:
            a, e = m.span("zahl")
            p.write_text(text[:a] + str(anzahl) + text[e:])

    # 2. Die Liste
    p = REPO / LISTE_DATEI
    text = p.read_text()
    soll = liste_bauen(s)
    if ANFANG not in text or ENDE not in text:
        offen.append(f"{LISTE_DATEI}: die Marken {ANFANG} / {ENDE} fehlen")
    else:
        a = text.index(ANFANG)
        e = text.index(ENDE) + len(ENDE)
        if text[a:e] != soll:
            offen.append(f"{LISTE_DATEI}: die Spieleliste ist nicht der Katalog")
            if not pruefen:
                p.write_text(text[:a] + soll + text[e:])

    if not offen:
        print(f"{anzahl} Spiele — Doku stimmt.")
        return 0
    for z in offen:
        print(("veraltet: " if pruefen else "berichtigt: ") + z)
    if pruefen:
        print("mit: python3 werkzeuge/katalog-doku.py")
    return 1 if pruefen else 0


if __name__ == "__main__":
    sys.exit(main())
