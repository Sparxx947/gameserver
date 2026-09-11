#!/usr/bin/env python3
"""doku-englisch.py — hat jeder Abschnitt der Dokumentation seinen englischen Absatz?

Die Regel steht in CLAUDE.md: deutscher Abschnitt, danach ein englischer Absatz
in Kursiv, der denselben Inhalt traegt. Bei der Durchsicht am 2026-09-11 fehlte
er in 83 Abschnitten - die Regel stand nur als Satz da, und niemand merkte, wie
viele Abschnitte ohne entstanden. Eine erste Zaehlung von Hand fand sogar nur
60, weil sie Unterabschnitte dem Sammelabsatz des Oberabschnitts zuschlug.

*The rule lives in CLAUDE.md: a German section followed by an italic English
 paragraph carrying the same content. On 2026-09-11, 83 sections had none - the
 rule existed only as a sentence, and nobody noticed how many sections were
 written without. A first manual count found only 60, crediting subsections to
 their parent's summary paragraph.*

Geprueft wird je Ueberschrift der Ebenen 2 bis 4 bis zur naechsten Ueberschrift
BELIEBIGER Ebene: Enthaelt der Abschnitt ausserhalb von Codebloecken Text, muss
darin eine Zeile stehen, die mit "> *" beginnt. Ein Abschnitt nur aus einem
Codeblock braucht keinen.

  werkzeuge/doku-englisch.py [datei.md ...]      Exit 1 = es fehlt einer
  PLATZWART_DOKU_ENGLISCH=aus                    abschalten (nur mit Grund)
"""
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATEIEN = ["README.md", "ABNAHME.md", "CLAUDE.md"] + sorted(
    str(p.relative_to(REPO)) for p in (REPO / "docs").glob("*.md"))


def luecken(text: str) -> list:
    """(Zeile, Ueberschrift) jedes Abschnitts mit Text, aber ohne "> *"-Zeile."""
    code, akt, alle = False, None, []
    for nr, z in enumerate(text.split("\n"), 1):
        if z.startswith("```"):
            code = not code
            continue
        if code:
            continue
        m = re.match(r"^(#{2,4}) (.+)", z)
        if m:
            akt = {"nr": nr, "titel": m.group(2), "englisch": False, "text": 0}
            alle.append(akt)
            continue
        if akt is None:
            continue
        if z.startswith("> *"):
            akt["englisch"] = True
        elif z.strip() and not z.startswith(">"):
            akt["text"] += 1
    return [(a["nr"], a["titel"]) for a in alle if a["text"] and not a["englisch"]]


def selbsttest() -> int:
    faelle = [
        ("## A\nText\n\n> *English.*\n", 0),
        ("## A\nText ohne Englisch\n", 1),
        ("## A\n```\nnur Code\n```\n", 0),
        ("## A\nText\n### B\nText\n\n> *English for B only.*\n", 1),   # A fehlt
        ("## A\nText\n> *English.*\n### B\n```\nx\n```\n", 0),
        ("## A\n```\n## keine Ueberschrift im Code\n```\nText\n> *E.*\n", 0),
    ]
    schlecht = 0
    for text, soll in faelle:
        ist = len(luecken(text))
        ok = ist == soll
        schlecht += not ok
        print(f"  {'ok  ' if ok else 'FEHLER'} erwartet {soll}, gefunden {ist}: {text[:40]!r}")
    print("alles gruen." if not schlecht else f"{schlecht} FEHLER")
    return 1 if schlecht else 0


def main(a: list) -> int:
    if "--selbsttest" in a:
        return selbsttest()
    if os.environ.get("PLATZWART_DOKU_ENGLISCH") == "aus":
        print("abgeschaltet (PLATZWART_DOKU_ENGLISCH=aus)")
        return 0
    dateien = a or DATEIEN
    gesamt = 0
    for d in dateien:
        fehlt = luecken((REPO / d).read_text())
        for nr, titel in fehlt:
            print(f"  {d}:{nr}  {titel[:70]}")
        gesamt += len(fehlt)
    if gesamt:
        print(f"  {gesamt} Abschnitt(e) ohne englischen Absatz (\"> *...*\") —")
        print("  Regel: CLAUDE.md, Abschnitt Sprache. Vorbei: PLATZWART_DOKU_ENGLISCH=aus")
        return 1
    print(f"  ok: {len(dateien)} Dateien, jeder Abschnitt zweisprachig")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
