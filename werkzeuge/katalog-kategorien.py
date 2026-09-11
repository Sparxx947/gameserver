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
  katalog-kategorien.py <katalog.json> --pruefen     Exit 1, wenn ein Eintrag
                                                    keine gueltige Kategorie hat

--pruefen gibt es wegen #251: Die Generatoren legten 17 Spiele ohne das Feld an,
und dieses Werkzeug lief nur von Hand. Die Spiele fehlten danach in JEDEM
Kategoriefilter, auch in "Sonstiges" - und nichts sagte es.
*--pruefen exists because of #251: 17 generated entries had no category and
 vanished from every category filter, silently.*
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
        terratechworlds memoriesofmars st""",
    # --- Survival & Koop ----------------------------------------------------
    "survival": """7daystodie abioticfactor ark astroneer barotrauma citadelforgedwithfire
        conanexiles corekeeper craftopia creativerse dayz dontstarvetogether frozenflame
        hurtworld hz icarus lastoasis lifeisfeudalyourown lotrreturntomoria necesse
        projectzomboid rust sonsoftheforest soulmask subsistence survivethenights
        theforest thefront ti unturned valheim vrising wurmunlimited minecraft
        terraria terrariatshock starbound vintagestory windward dodr rw
        minecraftbedrock minecraftfabric minecraftforge minecraftneoforge
        minecraftpaper minecraftpurpur minecraftquilt minecraftspigot""",
    # --- Sandbox & Rollenspiel ---------------------------------------------
    "sandbox": """garrysmod starmade openmwtes3mp avorion fivem redm samp multitheftauto
        tu jk2 jc2 jc3 onset""",
    # --- Shooter ------------------------------------------------------------
    "shooter": """americasarmyprovinggrounds arma3 cod cod2 cod4 coduo codwaw cs cs2 cscz
        csgo css cstrike16 dayofdefeatsource dayofinfamy daysofwar dod insurgency
        insurgencysandstorm killingfloor killingfloor2 l4d2 left4dead mcv mohaa mordhau
        nd neotokyo nmrih ns ns2 ns2c ohd postscriptum pvr rtcw scpsecretlaboratory
        scpslsm sof2 squad squad44 svencoop teamfortress2 tf2c tfc chivalrymedievalwarfare
        alienswarm alienswarmreactivedrop bb bb2 bd bmdm bs btl cc dab dys em
        fistfuloffrags hcu halflife2deathmatch halflifedeathmatch hldms jbep3 opfor
        pvkii sbots sfc ts vs zmr zps
        armar bf1942 bfv etl wet ro""",
    # --- Arena & Klassiker --------------------------------------------------
    "arena": """q2 q3 q4 quakelive qw xonotic zandronum urbanterror ut ut3 teeworlds ddnet
        counterstrike2d altitude ahl ahl2 dmc ricochet ios wf
        bo sol ut2k4 ut99""",
    # --- Rennen & Fahren ----------------------------------------------------
    "rennen": """assettocorsa americantrucksimulator eurotrucksimulator2 pc pc2""",
    # --- Dienste ------------------------------------------------------------
    "dienst": """teamspeak""",
}


def main():
    if len(sys.argv) < 2:
        print("Aufruf: katalog-kategorien.py <katalog.json> [--schreiben]"); sys.exit(1)
    pfad = Path(sys.argv[1])
    d = json.loads(pfad.read_text())

    if "--pruefen" in sys.argv:
        # Geprueft wird der KATALOG, nicht die Zuordnung hier: entscheidend ist,
        # was die Oberflaeche liest. "sonstiges" ist gueltig - es ist sichtbar.
        gueltig = set(d.get("_kategorien", {}))
        falsch = [g["schluessel"] for g in d["spiele"] if g.get("kategorie") not in gueltig]
        if not gueltig:
            print("FEHLER: _kategorien fehlt im Katalog"); sys.exit(1)
        if falsch:
            print(f"FEHLER: {len(falsch)} Eintraege ohne gueltige Kategorie: {' '.join(falsch)}")
            print("  Zuordnung in werkzeuge/katalog-kategorien.py ergaenzen, dann")
            print("  werkzeuge/katalog-kategorien.py etc/spiele-katalog.json --schreiben")
            sys.exit(1)
        print(f"ok: {len(d['spiele'])} Eintraege, alle mit Kategorie")
        return

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
