#!/usr/bin/env python3
"""katalog-bestand.py — gibt es noch, was der Katalog verspricht?

Ein Katalogeintrag ist eine Zusage: ein Klick, und dieser Server steht. Die
Zusage haengt aber an Dingen, die anderen gehoeren - ein Abbild kann aus der
Registry verschwinden, ein Steam-Titelbild kann wegfallen. Beides merkt man
heute erst bei der Installation, also beim Falschen und zum falschen Zeitpunkt.

Geprueft wird deshalb regelmaessig von aussen:
  * jedes `image` des Katalogs - antwortet die Registry noch mit einem Manifest?
  * jede `appid` > 0 - liefert Steam noch ein Titelbild (drei Namen, s. #305)?

*A catalogue entry is a promise, and it rests on things owned by others: an
 image can vanish from its registry, Steam artwork can disappear. Today both are
 noticed at install time - by the wrong person at the wrong moment.*

  werkzeuge/katalog-bestand.py            beides pruefen (Exit 1 = Fund)
  werkzeuge/katalog-bestand.py --bilder   nur die Titelbilder
  werkzeuge/katalog-bestand.py --abbilder nur die Abbilder
  werkzeuge/katalog-bestand.py --markdown Bericht fuer ein Issue
"""
import json
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import os

REPO = Path(__file__).resolve().parent.parent
KATALOG = Path(os.environ.get("BESTAND_KATALOG", REPO / "etc/spiele-katalog.json"))
EIGENE = Path(os.environ.get("BESTAND_EIGENE", REPO / "panel/bilder/eigene"))
BILD_NAMEN = ["header.jpg", "library_hero.jpg", "capsule_616x353.jpg"]
STEAM = "https://cdn.cloudflare.steamstatic.com/steam/apps/{}/{}"
ZEIT = 20
FAEDEN = 8


def hole(url: str, kopf: dict | None = None, methode: str = "GET", ganz: bool = False):
    """`ganz` liest die vollstaendige Antwort.

    Die erste Fassung las immer nur 4096 Bytes - genug fuer ein Bild, um es als
    "da" zu erkennen, aber ein Docker-Hub-Token ist laenger. Das abgeschnittene
    JSON scheiterte, der Fehler galt als "Abbild vermutlich da", und die Pruefung
    meldete beruhigende Zahlen fuer Abbilder, die sie nie angesehen hatte.
    *The first version always read 4096 bytes - enough to recognise an image but
     not a Docker Hub token; the truncated JSON failed, the failure counted as
     "probably there", and the check reported comforting numbers about images it
     had never looked at.*
    """
    r = urllib.request.Request(url, headers=kopf or {}, method=methode)
    with urllib.request.urlopen(r, timeout=ZEIT) as a:
        return a.status, (a.read() if ganz else a.read(4096))


def abbild_lebt(image: str) -> tuple[bool, str]:
    """Antwortet die Registry noch mit einem Manifest?

    Beide Wege brauchen ein anonymes Token - Docker Hub und ghcr geben es ohne
    Konto heraus, aber ohne Token antwortet die Registry mit 401, und das waere
    nicht von "weg" zu unterscheiden.
    *Both registries hand out an anonymous token; without one they answer 401,
     which would be indistinguishable from "gone".*
    """
    name, _, tag = image.partition(":")
    tag = tag or "latest"
    if name.startswith("ghcr.io/"):
        pfad = name[len("ghcr.io/"):]
        token_url = f"https://ghcr.io/token?scope=repository:{pfad}:pull&service=ghcr.io"
        registry = f"https://ghcr.io/v2/{pfad}/manifests/{tag}"
    else:
        pfad = name if "/" in name else f"library/{name}"
        token_url = ("https://auth.docker.io/token?service=registry.docker.io"
                     f"&scope=repository:{pfad}:pull")
        registry = f"https://registry-1.docker.io/v2/{pfad}/manifests/{tag}"
    try:
        _, roh = hole(token_url, ganz=True)
        token = json.loads(roh.decode()).get("token", "")
    except urllib.error.HTTPError as e:
        # Kein anonymes Token fuer dieses Repositorium: Genau das heisst fuer
        # unseren Zweck "weg" - jedes Katalogabbild MUSS ohne Konto ziehbar sein.
        # *No anonymous token means gone for our purpose: every catalogue image
        #  must be pullable without an account.*
        return False, f"kein anonymes Token (HTTP {e.code})"
    except Exception as e:
        return True, f"Token nicht zu bekommen ({type(e).__name__}) - als vorhanden gewertet"
    kopf = {"Authorization": f"Bearer {token}",
            "Accept": ("application/vnd.oci.image.index.v1+json,"
                       "application/vnd.docker.distribution.manifest.list.v2+json,"
                       "application/vnd.docker.distribution.manifest.v2+json")}
    try:
        hole(registry, kopf, "HEAD")
        return True, ""
    except urllib.error.HTTPError as e:
        # 404/401 nach gueltigem Token heisst: dieses Abbild gibt es nicht mehr.
        return (False, f"HTTP {e.code}") if e.code in (401, 403, 404) else (True, f"HTTP {e.code}")
    except Exception as e:
        # Netzfehler sind keine Aussage ueber das Abbild.
        return True, f"Netzfehler ({type(e).__name__})"


def bild_lebt(appid: int) -> tuple[bool, str]:
    for n in BILD_NAMEN:
        try:
            st, daten = hole(STEAM.format(appid, n))
            if st == 200 and len(daten) > 2000:
                return True, n
        except urllib.error.HTTPError:
            continue
        except Exception as e:
            return True, f"Netzfehler ({type(e).__name__})"
    return False, "keiner der drei Namen"


def main() -> int:
    spiele = json.loads(KATALOG.read_text())["spiele"]
    nur_bilder = "--bilder" in sys.argv
    nur_abbilder = "--abbilder" in sys.argv
    md = "--markdown" in sys.argv
    funde = []

    if not nur_bilder:
        bilder = {g["image"] for g in spiele}
        with ThreadPoolExecutor(FAEDEN) as e:
            ergebnis = dict(zip(bilder, e.map(abbild_lebt, bilder)))
        weg = sorted(i for i, (lebt, _) in ergebnis.items() if not lebt)
        for i in weg:
            wer = sorted(g["schluessel"] for g in spiele if g["image"] == i)
            funde.append(f"Abbild weg: `{i}` ({ergebnis[i][1]}) - betrifft {', '.join(wer)}")
        print(f"  {len(bilder)} Abbilder geprueft, {len(weg)} nicht mehr da")

    if not nur_abbilder:
        ids = {g["appid"] for g in spiele if g.get("appid")}
        with ThreadPoolExecutor(FAEDEN) as e:
            ergebnis = dict(zip(ids, e.map(bild_lebt, ids)))
        # Gemeldet wird nur, was die Kachel wirklich leer liesse: Steam liefert
        # nichts UND es gibt kein gezeichnetes Ersatzbild. Sonst meldete diese
        # Pruefung woechentlich elf Eintraege, deren Kachel tadellos aussieht -
        # etwa die GoldSrc-Sammel-ID 90, ein Serverwerkzeug ohne Ladenseite, das
        # nie ein Titelbild hatte. Eine Pruefung, die Richtiges meldet, erzieht
        # zum Wegsehen.
        # *Only what would actually leave a tile blank: Steam serves nothing AND
        #  there is no drawn stand-in. Otherwise this would report eleven perfect
        #  tiles every week - among them the GoldSrc collective id 90, a server
        #  tool that never had artwork.*
        ohne = []
        for i, (lebt, grund) in sorted(ergebnis.items()):
            if lebt:
                continue
            wer = sorted(g["schluessel"] for g in spiele if g.get("appid") == i)
            blank = [k for k in wer if not (EIGENE / f"{k}.jpg").is_file()]
            if blank:
                ohne.append(i)
                funde.append(f"Titelbild weg und kein Ersatz: Steam-App {i} ({grund})"
                             f" - Kachel bliebe leer bei {', '.join(blank)}")
        mit_ersatz = sum(1 for i, (lebt, _) in ergebnis.items() if not lebt) - len(ohne)
        print(f"  {len(ids)} Titelbilder geprueft, {len(ohne)} ohne Bild und ohne Ersatz"
              f" ({mit_ersatz} ohne Steam-Bild, aber mit gezeichnetem Ersatz)")

    if funde:
        print()
        for z in funde:
            print(("- " if md else "  ") + z)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
