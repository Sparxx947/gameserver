#!/usr/bin/env python3
"""titelbild.py — erzeugt ein Titelbild fuer Spiele ohne Steam-Eintrag.

Warum es das gibt: spiel-verwalten holt Titelbilder von Steam, ueber die
appid im Katalog. Spiele mit "appid": 0 gibt es dort nicht — Minecraft (Java),
Vintage Story und TeamSpeak. Fuer sie blieb die Karte in der Uebersicht leer,
ohne dass irgendetwas darauf hinwies (gemeldet 2026-09-07).

Die Bilder werden SELBST GEZEICHNET und nicht irgendwo geladen. Steam-Header
sind Werke Dritter; sie liegen deshalb bewusst nicht im Repositorium, sondern
werden zur Laufzeit geholt. Ein selbst erzeugtes Bild darf hier liegen — und
enthaelt bewusst kein fremdes Logo und keine Marke, sondern ein abstraktes
Motiv in den Farben des Panels.

*Why this exists: spiel-verwalten fetches artwork from Steam via the catalogue's
 appid. Games with "appid": 0 do not exist there, and their cards stayed blank
 with nothing indicating why. These images are drawn here rather than fetched:
 Steam headers are third-party works and stay out of the repository, while a
 self-made image may live here — deliberately carrying no foreign logo or brand,
 just an abstract motif in the panel's colours.*

  titelbild.py <schluessel> <Name> <Untertitel> <Adresse> [--motiv wuerfel|welle|kreis]

Masse 460x215 wie die Steam-Header, damit die Karten gleich aussehen.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BREITE, HOEHE = 460, 215
ZIEL = Path(__file__).resolve().parent.parent / "panel" / "bilder" / "eigene"

# Panelfarben aus app.py, damit sich die Bilder nicht von der Oberflaeche
# absetzen. --a ist das Blau der Kopfleiste, --g das Gruen.
BLAU, GRUEN, TEXT, GEDIMMT = (91, 157, 217), (76, 175, 125), (230, 232, 236), (154, 161, 173)

SCHRIFT = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"


def font(groesse, fett=False):
    try:
        return ImageFont.truetype(SCHRIFT % ("-Bold" if fett else ""), groesse)
    except OSError:
        return ImageFont.load_default(groesse)


def verlauf(akzent):
    """Diagonaler Verlauf von fast schwarz zur Akzentfarbe. Zeilenweise gemalt -
    Pillow kann das nicht von sich aus, und eine Bibliothek dafuer waere hier
    unverhaeltnismaessig."""
    im = Image.new("RGB", (BREITE, HOEHE))
    d = ImageDraw.Draw(im)
    r0, g0, b0 = 17, 22, 28
    r1, g1, b1 = (int(k * 0.55) for k in akzent)
    for y in range(HOEHE):
        t = y / HOEHE
        d.line([(0, y), (BREITE, y)],
               fill=(int(r0 + (r1 - r0) * t), int(g0 + (g1 - g0) * t), int(b0 + (b1 - b0) * t)))
    return im


def wuerfel(d, cx, cy, s, akzent):
    """Drei isometrische Wuerfel — abstrakt, KEIN Grasblock: die charakteristische
    Gras-Erde-Textur ist Mojangs Marke und hat hier nichts zu suchen.
    *Abstract cubes, deliberately not a grass block: that texture is Mojang's
     trademark and does not belong here.*"""
    hell = akzent
    mittel = tuple(int(k * 0.72) for k in akzent)
    dunkel = tuple(int(k * 0.45) for k in akzent)
    for dx, dy, sk in ((0, 0, 1.0), (-s * 0.95, s * 0.5, 0.62), (s * 0.95, s * 0.5, 0.62)):
        x, y, h = cx + dx, cy + dy, s * sk
        d.polygon([(x, y - h), (x + h, y - h / 2), (x, y), (x - h, y - h / 2)], fill=hell)      # Deckel
        d.polygon([(x - h, y - h / 2), (x, y), (x, y + h), (x - h, y + h / 2)], fill=mittel)    # links
        d.polygon([(x + h, y - h / 2), (x, y), (x, y + h), (x + h, y + h / 2)], fill=dunkel)    # rechts


def welle(d, cx, cy, s, akzent):
    d.ellipse([cx - s * .28, cy - s * .28, cx + s * .28, cy + s * .28], fill=TEXT)
    for i, w in enumerate((.62, .95, 1.28)):
        f = tuple(int(k * (1 - i * .22)) for k in akzent)
        d.arc([cx - s * w, cy - s * w, cx + s * w, cy + s * w], -60, 60, fill=f, width=5)


def kreis(d, cx, cy, s, akzent):
    for i, w in enumerate((1.0, .68, .36)):
        f = akzent if i % 2 == 0 else tuple(int(k * .5) for k in akzent)
        d.ellipse([cx - s * w, cy - s * w, cx + s * w, cy + s * w], outline=f, width=6)


MOTIVE = {"wuerfel": wuerfel, "welle": welle, "kreis": kreis}


def erzeugen(schluessel, name, unter, adresse, motiv="wuerfel", akzent=None):
    akzent = akzent or (GRUEN if motiv == "wuerfel" else BLAU)
    im = verlauf(akzent)
    d = ImageDraw.Draw(im)
    MOTIVE[motiv](d, 78, HOEHE // 2 - 6, 34, akzent)

    # Der Name schrumpft, bis er passt - sonst laeuft "American Truck Simulator"
    # aus dem Bild und niemand sieht es, weil das Bild ja "da" ist.
    # *The title shrinks until it fits: otherwise a long name runs off the image
    #  and nobody notices, because the picture is "there".*
    groesse = 34
    while groesse > 15 and d.textlength(name, font=font(groesse, True)) > BREITE - 165:
        groesse -= 1
    d.text((150, 62), name, font=font(groesse, True), fill=TEXT)

    # Der Untertitel bekam zunaechst keine Breitenpruefung - "Transportunternehmen
    # aufbauen, Koop, sehr genuegsam" endete als "Transportunternehmen aufbauen,
    # Ko" mitten im Wort. Erst schrumpfen, dann notfalls an einer Wortgrenze
    # kuerzen: ein abgeschnittenes Wort sieht nach Fehler aus, ein Auslassungs-
    # zeichen nach Absicht.
    # *The subtitle had no width check at first and was cut mid-word, which reads
    #  as a defect; shrink first, then truncate at a word boundary with an
    #  ellipsis, which reads as intent.*
    platz = BREITE - 165
    ug = 17
    while ug > 12 and d.textlength(unter, font=font(ug)) > platz:
        ug -= 1
    if d.textlength(unter, font=font(ug)) > platz:
        worte = unter.split()
        while worte and d.textlength(" ".join(worte) + " …", font=font(ug)) > platz:
            worte.pop()
        unter = (" ".join(worte) + " …") if worte else unter[:20] + "…"
    d.text((152, 108), unter, font=font(ug), fill=GEDIMMT)
    if adresse:
        d.text((152, 136), adresse, font=font(15), fill=tuple(int(k * .85) for k in akzent))

    ZIEL.mkdir(parents=True, exist_ok=True)
    pfad = ZIEL / f"{schluessel}.jpg"
    im.save(pfad, "JPEG", quality=88, optimize=True)
    return pfad


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    m = "wuerfel"
    if "--motiv" in sys.argv:
        m = sys.argv[sys.argv.index("--motiv") + 1]
    if len(a) < 3:
        print(__doc__.split("\n\n")[-2].strip()); sys.exit(1)
    p = erzeugen(a[0], a[1], a[2], a[3] if len(a) > 3 else "", m)
    print(f"{p}  ({p.stat().st_size} Bytes)")
