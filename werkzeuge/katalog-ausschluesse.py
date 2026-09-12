#!/usr/bin/env python3
"""katalog-ausschluesse.py — haelt die Sicherungsausschluesse des Katalogs vollstaendig.

Gemessen an der laufenden Maschine (#221): Von Valheims 2,65 GB sind 1,93 GB
Unity-Daten (`*_Data`) und 0,31 GB geteilte Bibliotheken (`*.so`) - zusammen 85 %
der Installation, und nichts davon kann ein Spielstand sein: Unity legt
Spielstaende unter `.config` ab, nicht in seinen Datenordner. Valheims Eintrag
schliesst das laengst aus, die uebrigen 164 nicht - sie sicherten ihre
Spielinstallation mit.

*Measured: of Valheim's 2.65 GB, 1.93 GB are Unity asset data and 0.31 GB are
 shared libraries - 85 % of the install, and none of it can be a save. Valheim's
 entry excludes it; the other 164 did not.*

  werkzeuge/katalog-ausschluesse.py               ergaenzt die Muster
  werkzeuge/katalog-ausschluesse.py --pruefen     meldet Abweichungen (Exit 1)
  werkzeuge/katalog-ausschluesse.py --selbsttest  prueft sich selbst

Was hier steht, ist bewusst NUR das, wovon sich BELEGEN laesst, dass es kein
Spielstand ist - Bibliotheken, Steam-Laufzeit, Engine- und Abbildordner. Wo ein
Spielstand liegt, weiss nur das jeweilige Spiel; diese Datei raet es nicht.
Ein zu weit gefasstes Muster kostet einen Spielstand, und das ist der einzige
Fehler, den eine Sicherung nicht machen darf.

*Deliberately only what can be shown not to be a save. Where a save lives is
 known only per game; this file does not guess - too broad a pattern costs a
 save, the one mistake a backup must not make.*
"""
import fnmatch
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KATALOG = REPO / "etc/spiele-katalog.json"
MODS = REPO / "etc/spiele-mods.json"

# Gemeinsam fuer jede Bauart, die das Spiel nach serverfiles/ installiert.
# "**" ueberspringt Verzeichnisse, "*" nicht - borgs sh:-Muster (CLAUDE.md).
GEMEINSAM = [
    "serverfiles/**/*.so",        # geteilte Bibliotheken
    "serverfiles/**/*.so.*",
    "serverfiles/steamclient*",   # Steams Laufzeit
    "serverfiles/linux32",
    "serverfiles/linux64",
    "serverfiles/**/*_Data",      # Unity: Abbilder, Szenen, Musik
    "serverfiles/Engine",         # Unreal: die Engine selbst
    "serverfiles/*/Binaries",     # Unreal: das Programm
    "serverfiles/*/Content",      # Unreal: die Inhalte
    "serverfiles/*/Plugins",
]
# Was die Bauarten zusaetzlich mitbringen.
JE_BAUART = {
    "ich777": ["steamcmd", "serverfiles/steamapps", ".steam"],
    "linuxgsm": ["serverfiles/steamapps", "log", ".steam"],
}
# Spiele, deren Spielstand IN einem dieser Ordner liegt - hier nie ausschliessen.
# Leer, solange keins bekannt ist: Der Eintrag existiert, damit ein solcher Fall
# eine Stelle hat und nicht als Ausnahme im Code landet.
# *Games whose save lives inside one of those directories - none known; the entry
#  exists so such a case has a place instead of becoming a special case in code.*
AUSNAHMEN: dict = {}


def deckt(muster: str, pfad: str) -> bool:
    """Wuerde `muster` den Pfad (oder einen seiner Elternordner) ausschliessen?

    Bewusst grosszuegiger als borg: ohne Ruecksicht auf Gross-/Kleinschreibung
    und mit `*` ueber `/` hinweg. Wer hier faelschlich anschlaegt, verliert ein
    Muster; wer faelschlich schweigt, verliert einen Mod. Valheims Mods liegen
    in `serverfiles/BepInEx/plugins` und entgingen `serverfiles/*/Plugins` sonst
    nur durch das kleine p.

    *Deliberately broader than borg - case-insensitive and `*` crossing `/`. A
     false hit costs a pattern, a false silence costs a mod.*
    """
    teile = pfad.strip("/").split("/")
    return any(fnmatch.fnmatchcase("/".join(teile[:i]).lower(), muster.lower())
               for i in range(1, len(teile) + 1))


def mod_pfade(konf: dict) -> dict:
    """Je Spiel die Verzeichnisse, in denen Mods liegen - samt Voraussetzung."""
    heilig = {}
    for stack, m in konf.get("mods", {}).items():
        p = [m["pfad"]] if m.get("pfad") else []
        if isinstance(m.get("voraussetzung"), dict) and m["voraussetzung"].get("pfad"):
            p.append(m["voraussetzung"]["pfad"])
        heilig[stack] = p
    return heilig


def soll(g: dict, heilig: dict) -> list:
    if g["bauart"] not in JE_BAUART:
        return sorted(set(g.get("ausschluss") or []))
    muster = set(g.get("ausschluss") or [])
    muster |= set(JE_BAUART[g["bauart"]])
    muster |= set(GEMEINSAM) - set(AUSNAHMEN.get(g["schluessel"], []))
    # Ein Mod ist nicht nachladbar - selbst hochgeladene erst recht nicht.
    # Jedes Muster, das ein bekanntes Modverzeichnis verdeckt, faellt weg.
    for pfad in heilig.get(g["schluessel"], []):
        muster -= {m for m in muster if deckt(m, pfad)}
    return sorted(muster)


def selbsttest() -> int:
    """Prueft die Regeln an erfundenen Daten - fasst weder Katalog noch System an."""
    fehler = []

    def gleich(was, ist, soll_):
        if ist != soll_:
            fehler.append(f"{was}: {ist!r} statt {soll_!r}")

    # deckt(): Elternordner, Gross-/Kleinschreibung, und was NICHT trifft
    gleich("Ordner deckt alles darunter",
           deckt("serverfiles/*/Plugins", "serverfiles/Pal/Plugins/mod.dll"), True)
    gleich("Kleinschreibung schuetzt nicht",
           deckt("serverfiles/*/Plugins", "serverfiles/BepInEx/plugins"), True)
    gleich("fremder Pfad bleibt frei",
           deckt("serverfiles/*/Content", "serverfiles/BepInEx/plugins"), False)
    gleich("Datei-Muster trifft Datei",
           deckt("serverfiles/**/*.so", "serverfiles/lib/x.so"), True)

    # Der Alarmpfad: ein Modverzeichnis unter einem Muster nimmt das Muster weg.
    spiel = {"schluessel": "probe", "bauart": "ich777", "ausschluss": []}
    ohne = soll(spiel, {})
    gleich("ohne Mods steht das Muster drin", "serverfiles/*/Plugins" in ohne, True)
    mit = soll(spiel, {"probe": ["serverfiles/Spiel/Plugins"]})
    gleich("mit Mods faellt das Muster weg", "serverfiles/*/Plugins" in mit, False)
    gleich("die uebrigen Muster bleiben", "serverfiles/Engine" in mit, True)

    # Voraussetzungspfade zaehlen mit (BepInEx/core ohne core kein Mod)
    konf = {"mods": {"a": {"pfad": "x/mods",
                           "voraussetzung": {"pfad": "serverfiles/BepInEx/core"}}}}
    gleich("Voraussetzung wird mitgelesen",
           mod_pfade(konf)["a"], ["x/mods", "serverfiles/BepInEx/core"])

    # Fremde Bauarten bleiben unberuehrt - dort weiss niemand, wo etwas liegt.
    eigen = {"schluessel": "e", "bauart": "eigenes-image", "ausschluss": ["data"]}
    gleich("eigenes-image unveraendert", soll(eigen, {}), ["data"])

    for z in fehler:
        print(f"  FEHLER {z}")
    print("  Selbsttest bestanden." if not fehler else f"  {len(fehler)} Fehler.")
    return 1 if fehler else 0


def main() -> int:
    if "--selbsttest" in sys.argv:
        return selbsttest()
    pruefen = "--pruefen" in sys.argv
    d = json.loads(KATALOG.read_text())
    heilig = mod_pfade(json.loads(MODS.read_text()))
    geaendert = []
    for g in d["spiele"]:
        neu = soll(g, heilig)
        if neu != sorted(set(g.get("ausschluss") or [])):
            geaendert.append(g["schluessel"])
            g["ausschluss"] = neu
        else:
            g["ausschluss"] = neu
    if pruefen:
        if geaendert:
            print(f"  {len(geaendert)} Katalogeintrag/-eintraege ohne die belegten Ausschluesse:")
            print("    " + ", ".join(geaendert[:12]) + (" …" if len(geaendert) > 12 else ""))
            print("    werkzeuge/katalog-ausschluesse.py laufen lassen.")
            return 1
        print("  Ausschluesse vollstaendig.")
        return 0
    KATALOG.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"  {len(geaendert)} Eintrag/Eintraege ergaenzt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
