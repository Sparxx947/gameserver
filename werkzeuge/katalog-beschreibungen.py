#!/usr/bin/env python3
"""katalog-beschreibungen.py — gibt jedem Katalogspiel eine echte Kurzbeschreibung.

Warum es das gibt: Die aus LinuxGSM abgeleiteten Einträge trugen als `kurz` nur
ihren eigenen Namen — "DayZ (LinuxGSM)" unter der Überschrift "DayZ". Auf der
Katalogkarte stand damit zweimal dasselbe, die Textsuche fand über `kurz` nichts
Zusätzliches, und in den selbst gezeichneten Titelbildern war der Untertitel
leer an Information. Gemessen am 2026-09-08: 85 von 179 Einträgen.

*Why this exists: entries derived from LinuxGSM carried only their own name in
 `kurz` — "DayZ (LinuxGSM)" beneath the heading "DayZ". The catalogue card said
 the same thing twice, the text search gained nothing from `kurz`, and the
 subtitle in the self-drawn artwork carried no information. 85 of 179 entries.*

Warum von Hand und nicht aus dem Steam-Store: Die Store-Texte sind Werke Dritter.
Titelbilder werden deshalb zur Laufzeit geholt statt im Repositorium abgelegt
(siehe `titelbild.py`); für Beschreibungen gilt dasselbe. Die Sätze hier sind
deshalb selbst formuliert — sachlich, ohne Werbesprache, Genre und Kernmechanik.

*Why by hand rather than from the Steam store: store texts are third-party works.
 Artwork is fetched at runtime rather than committed for that reason, and the
 same applies to descriptions. These sentences are written here instead —
 factual, no marketing voice, genre and core mechanic.*

Die Zuordnung steht EINZELN in diesem Werkzeug, wie in `katalog-kategorien.py`.
Wer einen Satz für falsch hält, ändert eine Zeile. Spiele ohne Eintrag werden
beim Lauf **benannt**, statt still ihren Namen zu behalten.

  katalog-beschreibungen.py [katalog.json] [--schreiben] [--pruefen]
"""
import json
import sys
from pathlib import Path

KATALOG = Path(__file__).resolve().parent.parent / "etc" / "spiele-katalog.json"

# Kurz, sachlich, ohne Werbesprache. Zielmass rund 45 Zeichen: laenger passt
# nicht in den Untertitel der selbst gezeichneten Titelbilder, dort wird an der
# Wortgrenze gekuerzt.
BESCHREIBUNGEN = {
    # --- Half-Life- und Source-Mods ---------------------------------------
    "ahl":      "Half-Life-Mod mit realistischeren Waffen",
    "ahl2":     "Action Half-Life auf der Source-Engine",
    "bb":       "Half-Life-Mod: Koop gegen Zombiehorden",
    "bb2":      "Koop-Shooter gegen Zombies, Source-Engine",
    "bd":       "Koop-Mod: Basis gegen Wellen verteidigen",
    "bmdm":     "Deathmatch im Black-Mesa-Neubau",
    "cc":       "Koop-Shooter gegen Infizierte, bis 4",
    "dab":      "Stunt-Shooter mit Zeitlupe, Hongkong-Stil",
    "dmc":      "Quake-Deathmatch auf der Half-Life-Engine",
    "dys":      "Cyberpunk-Teamshooter mit Implantaten",
    "em":       "Team-Shooter mit Kommandant und Basisbau",
    "hldms":    "Half-Life-Deathmatch auf Source",
    "jbep3":    "Chaotischer Deathmatch-Mod, viele Modi",
    "nd":       "Team-Shooter mit Kommandant, Source",
    "nmrih":    "Koop-Survival gegen Zombies, sehr zäh",
    "ns":       "Marines gegen Aliens, ein Spieler führt",
    "ns2":      "Marines gegen Aliens, Bau und Kommandant",
    "ns2c":     "Natural Selection 2 ohne Aufbauteil",
    "opfor":    "Half-Life aus Sicht der Soldaten",
    "sfc":      "Teamshooter mit baubaren Festungen",
    "tfc":      "Klassenbasierter Teamshooter, neun Klassen",
    "tf2c":     "Team Fortress 2 mit eigenen Klassen",
    "ts":       "Shooter mit Zeitlupe im Hongkong-Stil",
    "vs":       "Menschen gegen Vampire, Half-Life-Mod",
    "zmr":      "Ein Spieler steuert die Zombies",
    "zps":      "Menschen gegen Zombies, Rundenmodus",
    # --- Counter-Strike-Reihe ---------------------------------------------
    "cs":       "Der Klassiker: Terroristen gegen GSG 9",
    "cs2":      "Counter-Strike auf der Source-2-Engine",
    "cscz":     "Counter-Strike mit Einzelspieler-Kampagne",
    "csgo":     "Counter-Strike vor der Source-2-Fassung",
    "css":      "Counter-Strike auf der Source-Engine",
    # --- Call of Duty ------------------------------------------------------
    "cod":      "Zweiter Weltkrieg, Mehrspieler von 2003",
    "cod2":     "Zweiter Weltkrieg, Nachfolger von 2005",
    "cod4":     "Modern Warfare, Mehrspieler von 2007",
    "coduo":    "Erweiterung des ersten Call of Duty",
    "codwaw":   "Pazifik und Ostfront, mit Zombie-Modus",
    # --- id-Tech: Quake, Wolfenstein, Jedi Knight --------------------------
    "etl":      "Freier Nachbau von Wolfenstein: ET",
    "jk2":      "Lichtschwert-Duelle im Star-Wars-Universum",
    "q2":       "Quake 2 mit Deathmatch und Koop",
    "q3":       "Reine Arena-Deathmatches, sehr schnell",
    "q4":       "Quake 4, Nachfolger mit Strogg-Kampagne",
    "qw":       "QuakeWorld: Quake 1 fürs Netz optimiert",
    "rtcw":     "Wolfenstein-Mehrspieler, Klassen und Ziele",
    "sof2":     "Taktischer Shooter mit Trefferzonen",
    "wet":      "Achsenmächte gegen Alliierte, Klassen",
    "wf":       "Arena-Shooter im Stil von Quake 3",
    # --- Unreal ------------------------------------------------------------
    "ut":       "Unreal Tournament, Arena-Deathmatch",
    "ut2k4":    "Arena-Shooter mit Fahrzeugen und Onslaught",
    "ut3":      "Unreal Tournament 3 mit Warfare-Modus",
    "ut99":     "Der erste Unreal Tournament von 1999",
    # --- Battlefield und Militärshooter ------------------------------------
    "arma3":    "Militärsimulation mit großen Karten",
    "armar":    "Arma auf der Enfusion-Engine",
    "bf1942":   "Zweiter Weltkrieg mit Fahrzeugen, 2002",
    "bfv":      "Vietnamkrieg mit Fahrzeugen und Hubschraubern",
    "btl":      "Zweiter Weltkrieg, Nachfolger von Battalion",
    "mcv":      "Vietnamkrieg im Stil älterer Shooter",
    "mohaa":    "Zweiter Weltkrieg, Mehrspieler von 2002",
    "ohd":      "Freier taktischer Shooter, große Karten",
    "ro":       "Ostfront, ohne Fadenkreuz und sehr tödlich",
    "squad44":  "Taktischer Shooter im Zweiten Weltkrieg",
    # --- Survival und Open World -------------------------------------------
    "ark":      "Survival mit zähmbaren Dinosauriern",
    "dayz":     "Survival in der Zombie-Apokalypse",
    "dodr":     "Survival als Drache, Aufzucht und Flug",
    "hz":       "Survival-Koop in der Zombie-Apokalypse",
    "rw":       "Aufbau und Erkundung in Voxelwelten",
    "st":       "Raumstationen bauen, harte Physik",
    "ti":       "Als Dinosaurier überleben, Nahrungskette",
    "tu":       "Virtuelles Wohnzimmer mit Minispielen",
    # --- Rennen, Sport, Sonstiges ------------------------------------------
    "ios":      "Fußball im Team, ein Spieler pro Position",
    "jc2":      "Just Cause 2 im Mehrspieler-Modus",
    "jc3":      "Just Cause 3 im Mehrspieler-Modus",
    "onset":    "Freies Open-World-Rollenspiel mit Skripten",
    "pc":       "Rennsimulation mit vielen Klassen",
    "pc2":      "Rennsimulation, Nachfolger mit mehr Strecken",
    "samp":     "GTA San Andreas im Mehrspieler-Modus",
    "sol":      "2D-Shooter mit Seilhaken, schnelle Runden",
    # --- Arena, Party, Kleinere --------------------------------------------
    "bo":       "Schneller Arena-Shooter, kurze Runden",
    "bs":       "Schwertkampf mit gezielten Schlägen",
    "dod":      "Zweiter Weltkrieg, Klassen und Frontlinie",
    "hcu":      "Koop gegen Spielzeugroboter, bis 4",
    "l4d2":     "Koop gegen Zombiehorden, vier Überlebende",
    "pvr":      "VR-Shooter mit Such-und-Zerstör-Modus",
    "ricochet": "Wurfscheiben-Duelle auf schwebenden Feldern",
    "sbots":    "Roboter-Arena mit Haftgeschossen",
    "scpslsm":  "SCP: Secret Laboratory mit Server-Mod",
}


def bauart_hinweis(s: dict) -> str:
    """Frueher stand die Bauart im `kurz`-Feld ("(LinuxGSM)"). Die 94 gepflegten
    Eintraege fuehren sie dort NICHT — sie steht in `bauart` und im `hinweis`.
    Einheitlich ist besser als doppelt, deshalb faellt sie hier weg."""
    return ""


def main() -> int:
    schreiben = "--schreiben" in sys.argv
    nur_pruefen = "--pruefen" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    pfad = Path(args[0]) if args else KATALOG
    d = json.loads(pfad.read_text())
    sp = d if isinstance(d, list) else d.get("spiele", [])

    ohne, geaendert = [], []
    for s in sp:
        k = s["schluessel"]
        alt = (s.get("kurz") or "").strip()
        # "Name" oder "Name (LinuxGSM)" gilt als leer - das ist keine Beschreibung.
        leer = alt.replace(" (LinuxGSM)", "").strip() == s["name"].strip()
        if not leer:
            continue
        neu = BESCHREIBUNGEN.get(k)
        if not neu:
            ohne.append(f"{k} ({s['name']})")
            continue
        geaendert.append((k, alt, neu))
        if schreiben:
            s["kurz"] = neu + bauart_hinweis(s)

    for k, alt, neu in geaendert:
        print(f"  {k:<12} {alt[:34]:<36} -> {neu}")
    if ohne:
        print(f"\n  OHNE BESCHREIBUNG ({len(ohne)}): {', '.join(ohne)}")
        print("  Diese behalten ihren Namen. Zeile in BESCHREIBUNGEN ergaenzen.")

    print(f"\n{len(geaendert)} Beschreibungen gesetzt, {len(ohne)} offen")
    if nur_pruefen:
        return 1 if ohne else 0
    if schreiben:
        pfad.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n")
        print("geschrieben.")
    else:
        print("(nur Bericht - mit --schreiben uebernehmen)")
    return 1 if ohne else 0


if __name__ == "__main__":
    sys.exit(main())
