#!/usr/bin/env python3
"""steam-appid.py — sucht zu jedem Katalogspiel die richtige Steam-App-ID.

Warum es das gibt: Im Katalog stand als "appid" die SERVER-App-ID aus der
Vorlage (z.B. 232130 fuer den Killing-Floor-2-Server). Steam-Titelbilder gibt es
aber nur zur SPIEL-App-ID (232090). Deshalb blieben 44 Kacheln ohne Bild, und
niemand sah, warum.

*The catalogue carried the SERVER app id from the template, while Steam artwork
 exists only for the GAME app id — so 44 tiles had no image and nothing said
 why.*

DIE WICHTIGE REGEL: Nur EXAKTE Namenstreffer zaehlen. Die Store-Suche ist
unscharf - "Ricochet" liefert als erstes "Ricochet Abyss", "Squad" liefert
"Ore Factory Squad". Wer den ersten Treffer nimmt, haengt an ein Dutzend Spiele
das Bild eines fremden. Ein generisches Bild ist besser als ein falsches.

*The store search is fuzzy: "Ricochet" returns "Ricochet Abyss" first and
 "Squad" returns "Ore Factory Squad". Taking the first hit would attach a
 stranger's artwork to a dozen games. A generic image beats a wrong one.*

  steam-appid.py <katalog.json> [--schreiben]
"""
import json, re, sys, time, urllib.parse, urllib.request
from pathlib import Path

SUCHE = "https://store.steampowered.com/api/storesearch/?"
HEADER = "https://cdn.cloudflare.steamstatic.com/steam/apps/{}/header.jpg"


def norm(s: str) -> str:
    s = s.lower().replace("&", "and")
    s = re.sub(r"\b(the|dedicated|server)\b", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def hole(u, kopf=None, timeout=25):
    r = urllib.request.Request(u, headers=kopf or {"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(r, timeout=timeout) as f:
        return f.read()


# Regionen in dieser Reihenfolge. Der deutsche Store zeigt nicht, was in
# Deutschland nicht gelistet ist - und das trifft ausgerechnet die Titel, von
# denen dieser Katalog viele hat: "Wolfenstein: Enemy Territory" (1873030) gibt
# es dort weder in der Suche noch in appdetails (`success: false`), im
# US-Store beides. Ohne den zweiten Anlauf bleibt so ein Spiel ohne Bild, und
# nichts sagt warum.
# *The German store hides what is not listed in Germany, which hits exactly the
#  titles this catalogue has many of: Wolfenstein: Enemy Territory is absent from
#  both search and appdetails there, present in the US store. Without a second
#  region such a game silently stays without artwork.*
REGIONEN = (("de", "german"), ("us", "english"))


def suche(begriff: str) -> list:
    for cc, l in REGIONEN:
        try:
            d = json.loads(hole(SUCHE + urllib.parse.urlencode(
                {"term": begriff, "cc": cc, "l": l})))
            if d.get("items"):
                return d["items"]
        except Exception:
            pass
        time.sleep(0.4)
    return []


def hat_bild(appid: int) -> bool:
    """Steam antwortet auf unbekannte IDs mit einer winzigen Platzhalterdatei
    statt mit 404 - die Groesse ist das verlaesslichere Kriterium."""
    try:
        return len(hole(HEADER.format(appid), timeout=20)) > 2000
    except Exception:
        return False


def echter_eintrag(appid: int) -> dict | None:
    """Store-Eintrag zur App-ID, oder None.

    Ein vorhandenes Titelbild beweist NICHT, dass die ID zum Spiel gehoert: zu
    3043210 ("Vampire Slayer") und 889400 ("StickyBots") lieferte die Suche eine
    ID mit Bild, aber der Store kennt sie nicht (success=false). Ohne diese
    zweite Frage haengt an einem Spiel das Bild von irgendetwas.
    *A header image does not prove the id belongs to the game: two ids had
     artwork but no store entry at all.*
    """
    for cc, l in REGIONEN:
        try:
            d = json.loads(hole(f"https://store.steampowered.com/api/appdetails?"
                                f"appids={appid}&cc={cc}&l={l}")).get(str(appid), {})
            if d.get("success"):
                return d["data"]
        except Exception:
            pass
        time.sleep(0.4)
    return None


# Spiele, deren Name auch ein NEUERES Spiel traegt. Die Suche findet dann das
# neue: "Call of Duty" liefert den Sammeltitel von 2022, waehrend LinuxGSM den
# Server des Spiels von 2003 anbietet. Exakte Namensgleichheit reicht hier nicht -
# solche Faelle stehen einzeln hier.
# *Games whose name a newer title also carries: "Call of Duty" resolves to the
#  2022 release while LinuxGSM serves the 2003 game. Exact name matching is not
#  enough; such cases are listed individually.*
# Dazu Spiele, die aus dem Store GENOMMEN wurden: die Suche findet sie nicht mehr,
# appdetails und das Titelbild gibt es aber weiter. Jede dieser IDs ist gegen
# appdetails geprueft - der dort gemeldete Name stimmt normalisiert mit dem
# Katalognamen ueberein, geraten ist keine.
# *Plus games delisted from the store: search no longer finds them, while
#  appdetails and the header image remain. Every id here was checked against
#  appdetails and matches the catalogue name; none is a guess.*
VON_HAND = {
    "cod": 2620,        # Call of Duty (2003), nicht der Sammeltitel von 2022
    "pc":  234630,      # "Project CARS"   - delistet, appdetails bestaetigt den Namen
    "pc2": 378860,      # "Project CARS 2" - delistet, appdetails bestaetigt den Namen
}


def finde(name: str) -> int:
    """App-ID zu einem Spielnamen, oder 0. Nur exakte Namensgleichheit."""
    ziel = norm(name)
    for begriff in (name, re.sub(r"[:\-].*$", "", name).strip()):
        for treffer in suche(begriff):
            if norm(treffer.get("name", "")) == ziel:
                return int(treffer["id"])
        time.sleep(0.4)          # der Store mag keine Salven
    return 0


def main():
    if len(sys.argv) < 2:
        print("Aufruf: steam-appid.py <katalog.json> [--schreiben]"); sys.exit(1)
    pfad = Path(sys.argv[1])
    d = json.loads(pfad.read_text())
    schreiben = "--schreiben" in sys.argv

    gefunden = behalten = ohne = 0
    for g in d["spiele"]:
        alt = g.get("appid") or 0
        # Hat die bisherige ID ein Bild? Dann ist sie brauchbar - nicht anfassen.
        if alt and hat_bild(alt):
            behalten += 1
            continue
        neu = VON_HAND.get(g["schluessel"]) or finde(g["name"])
        # Erst wenn der Store die ID wirklich kennt, wird sie uebernommen.
        if neu and not echter_eintrag(neu):
            neu = 0
        if neu and hat_bild(neu):
            print("  %-24s %-34s %s -> %s" % (g["schluessel"], g["name"][:32], alt or "-", neu))
            g["appid"] = neu
            gefunden += 1
        else:
            ohne += 1
        time.sleep(0.3)

    print(f"\n{behalten} hatten schon ein Bild, {gefunden} neu gefunden, {ohne} ohne Steam-Bild")
    if schreiben and gefunden:
        pfad.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n")
        print("geschrieben.")
    elif not schreiben:
        print("(nur Bericht - mit --schreiben uebernehmen)")


if __name__ == "__main__":
    main()
