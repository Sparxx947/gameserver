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


def suche(begriff: str) -> list:
    try:
        d = json.loads(hole(SUCHE + urllib.parse.urlencode(
            {"term": begriff, "cc": "de", "l": "german"})))
        return d.get("items") or []
    except Exception:
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
    try:
        d = json.loads(hole(f"https://store.steampowered.com/api/appdetails?"
                            f"appids={appid}&cc=de&l=german")).get(str(appid), {})
        return d["data"] if d.get("success") else None
    except Exception:
        return None


# Spiele, deren Name auch ein NEUERES Spiel traegt. Die Suche findet dann das
# neue: "Call of Duty" liefert den Sammeltitel von 2022, waehrend LinuxGSM den
# Server des Spiels von 2003 anbietet. Exakte Namensgleichheit reicht hier nicht -
# solche Faelle stehen einzeln hier.
# *Games whose name a newer title also carries: "Call of Duty" resolves to the
#  2022 release while LinuxGSM serves the 2003 game. Exact name matching is not
#  enough; such cases are listed individually.*
VON_HAND = {
    "cod": 2620,        # Call of Duty (2003), nicht der Sammeltitel von 2022
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
