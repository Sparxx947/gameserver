#!/usr/bin/env python3
"""katalog-kategorien.py — ordnet jedem Katalogspiel eine Kategorie zu.

Warum von Hand und nicht aus Steam: Die Steam-Genres sind fuer diesen Zweck
unbrauchbar. Terraria steht dort unter "Action, Abenteuer, Indie, Rollenspiel",
Killing Floor 2 unter "Action" - beides sagt nichts darueber, ob ein Spiel zu
zweit an einem Abend Spass macht. Gemessen am 2026-09-08.

*Steam's genres are useless here: Terraria is filed under "Action, Adventure,
 Indie, RPG" and Killing Floor 2 under "Action" - neither says anything about
 whether a game suits an evening for two.*

Die Zuordnung steht deshalb EINZELN in diesem Werkzeug. Wer sie fuer falsch
haelt, aendert eine Zeile - er muss keine Heuristik verstehen. Unbekannte Spiele
landen sichtbar in "sonstiges" und werden beim Lauf benannt, statt still in eine
Sammelkategorie zu rutschen.

*The mapping is listed entry by entry. Anyone who disagrees changes one line
 instead of understanding a heuristic. Unknown games land visibly in "sonstiges"
 and are named, rather than quietly slipping into a catch-all.*

  katalog-kategorien.py <katalog.json> [--schreiben]
"""
import json, sys
from pathlib import Path

# Reihenfolge = Reihenfolge in der Oberflaeche. Von "passt zu uns" nach aussen.
KATEGORIEN = [
    ("aufbau",    "Aufbau & Simulation"),
    ("survival",  "Survival & Koop"),
    ("sandbox",   "Sandbox & Rollenspiel"),
    ("shooter",   "Shooter"),
    ("arena",     "Arena & Klassiker"),
    ("rennen",    "Rennen & Fahren"),
    ("dienst",    "Dienste"),
    ("sonstiges", "Sonstiges"),
]

ZUORDNUNG = {
    # --- Aufbau & Simulation ------------------------------------------------
    "aufbau": """factorio openttd openrct2 mindustry eco colonysurvival
        terratechworlds memoriesofmars""",
    # --- Survival & Koop ----------------------------------------------------
    "survival": """7daystodie abioticfactor ark astroneer barotrauma citadelforgedwithfire
        conanexiles corekeeper craftopia creativerse dayz dontstarvetogether frozenflame
        hurtworld hz icarus lastoasis lifeisfeudalyourown lotrreturntomoria necesse
        projectzomboid rust sonsoftheforest soulmask subsistence survivethenights
        theforest thefront ti unturned valheim vrising wurmunlimited minecraft
        terraria terrariatshock starbound vintagestory windward dodr""",
    # --- Sandbox & Rollenspiel ---------------------------------------------
    "sandbox": """garrysmod starmade openmwtes3mp avorion fivem redm samp multitheftauto
        tu jk2""",
    # --- Shooter ------------------------------------------------------------
    "shooter": """americasarmyprovinggrounds arma3 cod cod2 cod4 coduo codwaw cs cs2 cscz
        csgo css cstrike16 dayofdefeatsource dayofinfamy daysofwar dod insurgency
        insurgencysandstorm killingfloor killingfloor2 l4d2 left4dead mcv mohaa mordhau
        nd neotokyo nmrih ns ns2 ns2c ohd postscriptum pvr rtcw scpsecretlaboratory
        scpslsm sof2 squad squad44 svencoop teamfortress2 tf2c tfc chivalrymedievalwarfare
        alienswarm alienswarmreactivedrop bb bb2 bd bmdm bs btl cc dab dys em
        fistfuloffrags hcu halflife2deathmatch halflifedeathmatch hldms jbep3 opfor
        pvkii sbots sfc ts vs zmr zps""",
    # --- Arena & Klassiker --------------------------------------------------
    "arena": """q2 q3 q4 quakelive qw xonotic zandronum urbanterror ut ut3 teeworlds ddnet
        counterstrike2d altitude ahl ahl2 dmc ricochet ios wf""",
    # --- Rennen & Fahren ----------------------------------------------------
    "rennen": """assettocorsa americantrucksimulator eurotrucksimulator2""",
    # --- Dienste ------------------------------------------------------------
    "dienst": """teamspeak""",
}


def main():
    if len(sys.argv) < 2:
        print("Aufruf: katalog-kategorien.py <katalog.json> [--schreiben]"); sys.exit(1)
    pfad = Path(sys.argv[1])
    d = json.loads(pfad.read_text())

    nach_spiel = {}
    doppelt = []
    for kat, liste in ZUORDNUNG.items():
        for s in liste.split():
            if s in nach_spiel:
                doppelt.append((s, nach_spiel[s], kat))
            nach_spiel[s] = kat
    if doppelt:
        print("FEHLER: doppelt zugeordnet:")
        for s, a, b in doppelt:
            print(f"  {s}: {a} und {b}")
        sys.exit(1)

    zahl, ohne = {}, []
    for g in d["spiele"]:
        k = nach_spiel.get(g["schluessel"], "sonstiges")
        g["kategorie"] = k
        zahl[k] = zahl.get(k, 0) + 1
        if k == "sonstiges":
            ohne.append(g["schluessel"])

    # Eintraege in der Zuordnung, die es im Katalog gar nicht gibt - meist ein
    # Tippfehler. Ohne diese Meldung faellt er nie auf.
    fehlt = sorted(set(nach_spiel) - {g["schluessel"] for g in d["spiele"]})

    for k, name in KATEGORIEN:
        print(f"  {name:<24} {zahl.get(k, 0):>4}")
    if ohne:
        print("\n  ohne Zuordnung (landen in 'Sonstiges'):")
        for i in range(0, len(ohne), 5):
            print("    " + "  ".join(f"{s:<22}" for s in ohne[i:i+5]))
    if fehlt:
        print("\n  in der Zuordnung, aber nicht im Katalog (Tippfehler?):")
        print("    " + ", ".join(fehlt))

    if "--schreiben" in sys.argv:
        d["_kategorien"] = {k: n for k, n in KATEGORIEN}
        pfad.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n")
        print("\n  geschrieben.")
    else:
        print("\n  (nur Bericht - mit --schreiben uebernehmen)")


if __name__ == "__main__":
    main()
