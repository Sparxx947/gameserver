#!/usr/bin/env python3
"""doku-links.py — prueft die Verweise zwischen den Dokumentationsdateien.

Die Kapitel verweisen dicht aufeinander ("siehe [05-sicherung.md](...)"), und
ein Verweis stirbt lautlos: Die Datei wird umbenannt, die Ueberschrift
umformuliert, und der Link zeigt ins Leere. Beim Lesen faellt das erst auf, wenn
jemand darauf klickt - also selten, und dann beim Falschen.

Geprueft wird beides: ob die Zieldatei existiert und ob der Anker (#teil) als
Ueberschrift darin vorkommt. GitHubs Ankerregeln sind nachgebildet: Kleinschrift,
Satzzeichen weg, Leerzeichen zu Bindestrichen, Umlaute bleiben.

*Checks links between documentation files - target file and heading anchor -
 because a dead link fails silently and is only noticed by whoever clicks it.*

  werkzeuge/doku-links.py            meldet tote Verweise (Exit 1)
  werkzeuge/doku-links.py --liste    zeigt alle gefundenen Verweise
"""
import re
import sys
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# Verweise auf Dateien im Repositorium, nicht ins Netz.
LINK = re.compile(r"\[[^\]]*\]\((?!https?://|mailto:)([^)\s]+)\)")
UEBERSCHRIFT = re.compile(r"^#{1,6}\s+(.*?)\s*$", re.M)
# Code zuerst entfernen: In der Doku stehen regulaere Ausdruecke wie
# "^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$" - eine Zeichenklasse vor einer Klammer
# sieht fuer jedes Linkmuster aus wie ein Verweis. Die erste Fassung meldete
# genau zwei davon als tot. *Strip code first: a character class before a
# parenthesis looks exactly like a link to any pattern.*
CODEBLOCK = re.compile(r"```.*?```", re.S)
CODESPANNE = re.compile(r"`[^`\n]*`")
# Verweise, die GitHub aufloest, das Dateisystem aber nicht: das Wiki liegt in
# einem eigenen Repositorium. *Links GitHub resolves though the file system
# cannot: the wiki is a repository of its own.*
AUSSERHALB = ("../../wiki", "../../issues", "../../pulls")


def anker(text: str) -> str:
    """GitHubs Regel: Kleinschrift, alles ausser Buchstaben/Ziffern/Leer/Bindestrich
    weg, Leerzeichen zu Bindestrichen. Umlaute zaehlen als Buchstaben."""
    t = unicodedata.normalize("NFC", text).strip().lower()
    t = re.sub(r"[`*_\[\]()]", "", t)
    t = "".join(c for c in t if c.isalnum() or c in " -_")
    return re.sub(r"\s+", "-", t.strip())


def anker_von(datei: Path) -> set:
    return {anker(m.group(1)) for m in UEBERSCHRIFT.finditer(datei.read_text())}


def main() -> int:
    dateien = sorted(REPO.glob("docs/*.md")) + [REPO / "README.md", REPO / "ABNAHME.md",
                                                REPO / "CLAUDE.md"]
    dateien = [d for d in dateien if d.is_file()]
    anker_je_datei, tot, gesamt = {}, [], 0
    for d in dateien:
        text = CODESPANNE.sub("`", CODEBLOCK.sub("", d.read_text()))
        for m in LINK.finditer(text):
            ziel = m.group(1)
            gesamt += 1
            if ziel.split("/#")[0].rstrip("/") in AUSSERHALB or ziel in AUSSERHALB:
                continue
            pfad, _, teil = ziel.partition("#")
            z = (d.parent / pfad).resolve() if pfad else d
            if "--liste" in sys.argv:
                print(f"  {d.relative_to(REPO)} -> {ziel}")
            if not z.exists():
                tot.append(f"{d.relative_to(REPO)}: Datei fehlt -> {ziel}")
                continue
            if teil and z.suffix == ".md":
                if z not in anker_je_datei:
                    anker_je_datei[z] = anker_von(z)
                if anker(teil) not in anker_je_datei[z]:
                    tot.append(f"{d.relative_to(REPO)}: Ueberschrift fehlt -> {ziel}")
    if tot:
        print(f"  {len(tot)} toter Verweis/tote Verweise von {gesamt}:")
        for z in tot[:20]:
            print(f"    {z}")
        if len(tot) > 20:
            print(f"    … und {len(tot) - 20} weitere")
        return 1
    print(f"  ok: {gesamt} Verweise in {len(dateien)} Dateien, alle erreichbar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
