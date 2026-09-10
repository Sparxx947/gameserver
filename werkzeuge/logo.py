#!/usr/bin/env python3
"""logo.py — erzeugt Zeichen und Symbole des Panels aus EINER Beschreibung.

Warum ein Werkzeug und nicht drei von Hand gepflegte Dateien: Das Zeichen
erscheint an vier Stellen — inline in der Kopfleiste, als `favicon.svg`, als
`favicon.ico` und als `apple-touch-icon.png`. Wer die einzeln pflegt, hat nach
der ersten Änderung vier Fassungen, von denen drei alt sind. Hier stehen die
Formen einmal als Zahlen, und alle Ausgaben entstehen daraus.

*One description, four outputs: the mark appears inline in the header, as
 favicon.svg, favicon.ico and apple-touch-icon.png. Maintained separately, the
 first change leaves three stale copies.*

Das Motiv: die Mitte eines Spielfelds — Mittellinie, Anstosskreis, Anstosspunkt.
Das Projekt heisst Platzwart (Issue #69), und ein Platzwart haelt den Platz
bereit, damit andere darauf spielen koennen. Genau das tut dieses Panel.

Warum so einfach: Das Zeichen steht in der Kopfleiste **24 px** gross. Was dort
nicht mehr zu erkennen ist, ist verschenkt — Feinheiten, die erst bei 200 px
wirken, verwandeln sich bei 24 px in Grau. Deshalb nur drei Linien: Rand,
Mittellinie, Kreis, Punkt.

Der erste Entwurf hatte zusaetzlich die Seitenlinien des ganzen Feldes. In der
Vorschau nebeneinander war das bei 24 px ein Klumpen: drei Elemente auf so wenig
Flaeche heben sich gegenseitig auf. Der Feldrand ist deshalb weg — die
Mittellinie laeuft jetzt durch bis an den Rand des Zeichens.

*The mark is a pitch seen from above. The project is called Platzwart — a groundskeeper keeps the pitch ready so others can play on it, which is what this
 panel does. Only three lines, because the mark is 24 px in the header and
 anything finer turns to grey at that size.*

  logo.py [--schreiben] [--vorschau]

Ohne Schalter wird nur berichtet, was entstehen wuerde.
"""
import sys
from pathlib import Path

HIER = Path(__file__).resolve().parent
BILDER = HIER.parent / "panel" / "bilder"

# Farben aus dem Stylesheet des Panels. Wer sie dort aendert, aendert sie hier
# mit - sonst faellt das Zeichen aus dem Bild.
RASEN = "#3f9c6d"      # etwas satter als --g, damit die weissen Linien tragen
RASEN_HELL = "#4caf7d"  # --g, fuer den Streifen
LINIE = "#eef1f4"

# Alle Masse in einem 32x32-Feld. Die Zahlen stehen genau einmal.
KASTEN = dict(x=1, y=1, w=30, h=30, r=8)

# Der Platz: Rand, Mittellinie, Anstosskreis. Mehr traegt bei 24 px nicht.
# Mehr Luft als beim ersten Entwurf: dort fuellte das Feld fast das ganze
# Quadrat und der Kreis fast die Breite - bei 24 px wurde daraus ein Klumpen.
# Die Strichstaerke ist bewusst kraeftig, sonst verschwindet die Mittellinie.
PLATZ = dict(links=5.0, rechts=27.0, strich=2.2)
MITTE_Y = 16.0
KREIS_R = 5.4
PUNKT_R = 1.4


def svg(groesse: int | None = None, klasse: str = "") -> str:
    """Das Zeichen als SVG. Ohne Groesse skaliert es mit dem Elternelement -
    so wird es in der Kopfleiste eingebettet."""
    k, p = KASTEN, PLATZ
    masse = f' width="{groesse}" height="{groesse}"' if groesse else ""
    kl = f' class={klasse}' if klasse else ""
    st = p["strich"]
    return "".join([
        f'<svg{kl} viewBox="0 0 32 32"{masse} xmlns="http://www.w3.org/2000/svg"'
        f' aria-hidden=true>',
        # Rasen, mit einem helleren Streifen in der oberen Haelfte - der eine
        # Andeutung von gemaehten Bahnen gibt, ohne bei 24 px zu stoeren.
        f'<rect x={k["x"]} y={k["y"]} width={k["w"]} height={k["h"]} '
        f'rx={k["r"]} fill="{RASEN}"/>',
        # Zwei gemaehte Bahnen. Bei 24 px kaum zu sehen und genau deshalb
        # richtig: sie geben der grossen Ansicht Tiefe, ohne die kleine zu
        # stoeren.
        f'<path d="M1 6h30v6.5H1z" fill="{RASEN_HELL}" opacity=".45"/>',
        f'<path d="M1 19h30v6.5H1z" fill="{RASEN_HELL}" opacity=".45"/>',
        # Mittellinie, durchlaufend bis an den Rand
        f'<path d="M{p["links"]} {MITTE_Y}H{p["rechts"]}" stroke="{LINIE}" '
        f'stroke-width={st} stroke-linecap="round"/>',
        # Anstosskreis
        f'<circle cx="16" cy="{MITTE_Y}" r="{KREIS_R}" fill="none" '
        f'stroke="{LINIE}" stroke-width={st}/>',
        # Anstosspunkt - er macht aus einem durchgestrichenen Kreis eine
        # Spielfeldmitte. Bei 24 px kaum zu sehen, bei 64 px entscheidend.
        f'<circle cx="16" cy="{MITTE_Y}" r="{PUNKT_R}" fill="{LINIE}"/>',
        "</svg>",
    ])


def zeichnen(kante: int):
    """Dasselbe mit Pillow, fuer die Rasterformate. Die Formen kommen aus
    denselben Zahlen wie das SVG - zwei getrennt gepflegte Zeichnungen liefen
    frueher oder spaeter auseinander."""
    from PIL import Image, ImageDraw
    # Vierfach zeichnen und verkleinern: Pillow glaettet Kanten nicht, ein Kreis
    # mit harten Treppen saehe bei 32 px unsauber aus.
    # *Drawn at 4x and downscaled: Pillow has no antialiasing.*
    f = 4
    m = kante * f
    s = m / 32.0
    k, p = KASTEN, PLATZ
    st = max(1, round(p["strich"] * s))
    bild = Image.new("RGBA", (m, m), (0, 0, 0, 0))
    d = ImageDraw.Draw(bild)
    d.rounded_rectangle([k["x"] * s, k["y"] * s, (k["x"] + k["w"]) * s,
                         (k["y"] + k["h"]) * s], radius=k["r"] * s, fill=RASEN)
    # Heller Streifen, auf den Rasen begrenzt
    streifen = Image.new("RGBA", (m, m), (0, 0, 0, 0))
    for oben, unten in ((6, 12.5), (19, 25.5)):
        ImageDraw.Draw(streifen).rectangle([0, oben * s, m, unten * s],
                                           fill=RASEN_HELL + "73")
    maske = Image.new("L", (m, m), 0)
    ImageDraw.Draw(maske).rounded_rectangle(
        [k["x"] * s, k["y"] * s, (k["x"] + k["w"]) * s, (k["y"] + k["h"]) * s],
        radius=k["r"] * s, fill=255)
    bild.paste(streifen, (0, 0), Image.composite(streifen.split()[3], maske, maske))
    d = ImageDraw.Draw(bild)
    d.line([p["links"] * s, MITTE_Y * s, p["rechts"] * s, MITTE_Y * s],
           fill=LINIE, width=st)
    d.ellipse([(16 - KREIS_R) * s, (MITTE_Y - KREIS_R) * s,
               (16 + KREIS_R) * s, (MITTE_Y + KREIS_R) * s],
              outline=LINIE, width=st)
    d.ellipse([(16 - PUNKT_R) * s, (MITTE_Y - PUNKT_R) * s,
               (16 + PUNKT_R) * s, (MITTE_Y + PUNKT_R) * s], fill=LINIE)
    return bild.resize((kante, kante), Image.LANCZOS)


def main() -> int:
    schreiben = "--schreiben" in sys.argv
    vorschau = "--vorschau" in sys.argv

    if vorschau:
        # Nebeneinander in den Groessen, in denen das Zeichen wirklich vorkommt.
        from PIL import Image
        groessen = [24, 32, 48, 64, 128]
        breite = sum(g + 12 for g in groessen)
        blatt = Image.new("RGB", (breite, 150), "#14161a")   # Panelhintergrund
        x = 6
        for g in groessen:
            blatt.paste(zeichnen(g), (x, (150 - g) // 2), zeichnen(g))
            x += g + 12
        ziel = Path("/tmp/logo-vorschau.png")
        blatt.save(ziel)
        print(f"  Vorschau: {ziel}  (Groessen: {', '.join(map(str, groessen))} px)")
        return 0

    # 192 und 512 verlangt der Web-App-Manifest-Standard; Android nimmt 192 fuer
    # das Startsymbol und 512 fuer den Startbildschirm beim Oeffnen. Sie stehen
    # hier und nicht als von Hand gezeichnete Dateien daneben - genau dafuer
    # gibt es dieses Werkzeug.
    # *192 and 512 are what the web app manifest wants; drawn here rather than
    #  kept as hand-made files, which is the whole point of this tool.*
    dateien = {
        "favicon.svg": None,
        "favicon.ico": [16, 32, 48],
        "apple-touch-icon.png": 180,
        "icon-192.png": 192,
        "icon-512.png": 512,
    }
    if not schreiben:
        print("  wuerde schreiben:")
        for n in dateien:
            print(f"    {BILDER / n}")
        print("  und das Inline-SVG fuer app.py ausgeben (--schreiben)")
        return 0

    BILDER.mkdir(parents=True, exist_ok=True)
    (BILDER / "favicon.svg").write_text(svg(32) + "\n")
    grund = zeichnen(256)
    grund.resize((180, 180), 1).save(BILDER / "apple-touch-icon.png")
    grund.resize((192, 192), 1).save(BILDER / "icon-192.png")
    zeichnen(512).save(BILDER / "icon-512.png")
    zeichnen(48).save(BILDER / "favicon.ico",
                      sizes=[(16, 16), (32, 32), (48, 48)])
    for n in dateien:
        p = BILDER / n
        print(f"    {p.name:24} {p.stat().st_size:>6} Byte")
    print("\n  Zeile fuer panel/app.py:\n")
    print(f"LOGO = ({svg(klasse='logo')!r})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
