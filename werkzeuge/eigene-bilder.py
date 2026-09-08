#!/usr/bin/env python3
"""eigene-bilder.py — erzeugt die selbst gezeichneten Titelbilder aus dem Katalog.

Warum es das gibt: `titelbild.py` zeichnet EIN Bild, auf Zuruf. Die 64 Bilder
unter `panel/bilder/eigene/` lagen deshalb nur deshalb im Repositorium, weil sie
irgendwann einmal von Hand erzeugt wurden — genau das Muster, das bei den
Steam-Bildern schon einmal aufgefallen ist: ein Verzeichnis, das niemand füllt.
Kommt ein Katalogspiel ohne Steam-Eintrag dazu, fehlt sein Bild, und nichts sagt
es. Am 2026-09-08 waren das sechs Stück (bf1942, bfv, bo, etl, ut2k4, ut99).

*Why this exists: `titelbild.py` draws one image on request, so the 64 files under
 `panel/bilder/eigene/` were in the repository only because somebody once made
 them by hand — the same pattern already seen with the Steam artwork: a directory
 nobody fills. Add a catalogue game without a Steam entry and its image is simply
 missing, with nothing saying so.*

Das Motiv wird aus dem Schlüssel abgeleitet, nicht zufällig gewählt: derselbe
Katalog ergibt so immer dieselben Bilder, und ein erneuter Lauf ändert nichts.

  eigene-bilder.py [katalog.json] [--alle] [--pruefen]

  ohne Schalter   nur fehlende Bilder erzeugen
  --alle          auch vorhandene neu zeichnen (nach Änderungen an titelbild.py)
  --pruefen       nur berichten, nichts schreiben (Exit 1 = es fehlt etwas)
"""
import json
import subprocess
import sys
from pathlib import Path

HIER = Path(__file__).resolve().parent
ZIEL = HIER.parent / "panel" / "bilder" / "eigene"
KATALOG = HIER.parent / "etc" / "spiele-katalog.json"
MOTIVE = ("wuerfel", "welle", "kreis")


def motiv(schluessel: str) -> str:
    """Aus dem Schlüssel abgeleitet, damit derselbe Katalog dieselben Bilder
    ergibt. `hash()` wäre hier falsch — der ist pro Prozess anders gesalzen und
    liefert bei jedem Lauf ein anderes Motiv."""
    return MOTIVE[sum(schluessel.encode()) % len(MOTIVE)]


def spiele(pfad: Path) -> list:
    d = json.loads(pfad.read_text())
    sp = d if isinstance(d, list) else d.get("spiele", [])
    # Genau die ohne Steam-Eintrag: für alle anderen holt katalogbilder-holen
    # den Steam-Header, und ein selbst gezeichnetes Bild wäre nur im Weg.
    return [s for s in sp if not s.get("appid")]


def main() -> int:
    alle = "--alle" in sys.argv
    nur_pruefen = "--pruefen" in sys.argv
    argumente = [a for a in sys.argv[1:] if not a.startswith("--")]
    katalog = Path(argumente[0]) if argumente else KATALOG
    if not katalog.exists():
        print(f"Katalog nicht gefunden: {katalog}", file=sys.stderr)
        return 1

    sp = spiele(katalog)
    fehlend, erzeugt, fehler = [], 0, 0
    for s in sp:
        k = s["schluessel"]
        ziel = ZIEL / f"{k}.jpg"
        if ziel.exists() and not alle:
            continue
        fehlend.append(k)
        if nur_pruefen:
            continue
        r = subprocess.run(
            ["python3", str(HIER / "titelbild.py"), k, s.get("name", k),
             s.get("kurz") or s.get("name", k), "", "--motiv", motiv(k)],
            capture_output=True, text=True)
        if r.returncode == 0:
            erzeugt += 1
        else:
            fehler += 1
            print(f"  FEHLER {k}: {r.stderr.strip()[:100]}", file=sys.stderr)

    if nur_pruefen:
        if fehlend:
            print(f"{len(fehlend)} von {len(sp)} Bildern fehlen: {' '.join(sorted(fehlend))}")
            return 1
        print(f"vollstaendig — {len(sp)} Spiele ohne Steam-Eintrag, alle mit Bild")
        return 0

    print(f"{len(sp)} Spiele ohne Steam-Eintrag, {erzeugt} Bilder erzeugt"
          + (f", {fehler} fehlgeschlagen" if fehler else ""))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
