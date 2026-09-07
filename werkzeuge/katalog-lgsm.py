#!/usr/bin/env python3
"""katalog-lgsm.py — ergaenzt den Katalog um LinuxGSM-Spielserver.

Zweite Bauart neben ich777. Vor der Aufnahme wurde sie an einem echten Fall
durchgetestet (Ricochet, 2026-09-07); dabei kamen vier Eigenheiten heraus, die
Anpassungen an den Werkzeugen noetig machten:

  1. "_default.cfg" traegt "DO NOT EDIT, ANY CHANGES WILL BE OVERWRITTEN!" und
     wird bei jedem Start neu geschrieben. Der Einrichtungsschritt setzte dort
     Werte und meldete Erfolg - wirkungslos. Jetzt in konfig-datei ausgefiltert.
  2. Jede LinuxGSM-Konfiguration enthaelt "betapassword" (Steam-Beta-Zweig) und
     "ntfypassword" (Benachrichtigungen). Beide sahen aus wie Beitrittspasswoerter.
  3. Die eigentliche Serverkonfiguration liegt unter serverfiles/ im GoldSrc-Stil
     ohne Gleichheitszeichen und ohne Semikolon: sv_password "". Das erkannte
     setze_cfg nicht - der Server waere ohne Beitrittspasswort gelaufen.
  4. serverfiles/ darf NICHT pauschal von der Sicherung ausgeschlossen werden:
     dort liegt neben 138 MB Installation die 1 KB grosse Serverkonfiguration.

*Second build style beside ich777, tested end-to-end on one real case before
 adoption. Four quirks required tool changes: a regenerated _default.cfg that
 made the setup step report success for nothing; two password-shaped fields that
 are not join passwords; the GoldSrc config style without "=" or ";"; and a
 serverfiles/ directory holding both the installation and the real config.*

  katalog-lgsm.py <katalog.json> [--schreiben]
"""
import csv, io, json, re, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

LISTE = "https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/serverlist.csv"
DEFAULTS = "https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/config-default/config-lgsm"
TAGS = "https://hub.docker.com/v2/repositories/gameservermanagers/gameserver/tags/?page_size=100"

# Einzeln geprueft, nicht geraten: gleicher Name, aber anderes Spiel.
EIGENSTAENDIG = {
    "cs2": "Counter-Strike 2 ist der Shooter, counterstrike2d der 2D-Klon",
    "dod": "Day of Defeat (GoldSrc) ist nicht Day of Defeat: Source",
    "hldms": "Half-Life Deathmatch: Source ist die Source-Neuauflage",
    "l4d2": "Left 4 Dead 2 ist ein eigenes Spiel",
    "scpslsm": "ServerMod-Variante, wie Terraria/TShock ein eigener Eintrag",
    "tf2c": "Team Fortress 2 Classified ist eine eigene Mod",
}
DOPPELT = {"tf": "The Front - bereits als thefront im Katalog"}

GROESSE_STANDARD = (2, 12)
GROSS = {"ark", "dayz", "arma3", "squad", "squad44", "ti", "tu", "hz", "ohd", "csgo", "cs2"}


def hole(u, roh=True):
    r = urllib.request.Request(u, headers={"User-Agent": "katalog-lgsm"})
    with urllib.request.urlopen(r, timeout=40) as f:
        d = f.read()
    return d.decode("utf-8", "replace") if roh else json.loads(d)


def tags() -> set:
    raus, url = set(), TAGS
    while url and len(raus) < 400:
        d = hole(url, roh=False)
        raus |= {t["name"] for t in d["results"]}
        url = d.get("next")
    return raus


def norm(s: str) -> str:
    s = re.sub(r"\b(server|dedicated|the)\b", "", s.lower())
    return re.sub(r"[^a-z0-9]", "", s)


def eintrag(kuerzel: str, z: dict, cfg: str, belegt: set) -> dict | None:
    def wert(n):
        m = re.search(rf'^{n}="?([^"\n#]*)"?', cfg, re.M)
        return (m.group(1).strip() if m else "")
    port = wert("port")
    if not port.isdigit():
        return None
    gs = z["gameservername"]
    sch = re.sub(r"[^a-z0-9]", "", kuerzel.lower())
    mem, platte = (8, 30) if kuerzel in GROSS else GROESSE_STANDARD

    ports, adresse = [], 0
    for p, proto in ((port, "udp"), (port, "tcp"), (wert("queryport"), "udp")):
        if not p.isdigit():
            continue
        h = int(p)
        while (h, proto) in belegt:
            h = max(30300, h + 1) if h < 30300 else h + 1
        belegt.add((h, proto))
        ports.append(f"{h}:{p}/{proto}")
        if not adresse:
            adresse = h
    return {
        "schluessel": sch, "name": z["gamename"],
        "kurz": z["gamename"] + " (LinuxGSM)",
        "appid": 0,                      # GAME_ID ist bei LinuxGSM nicht die Bild-ID
        "image": f"gameservermanagers/gameserver:{kuerzel}",
        "mem_gb": mem, "platte_gb": platte,
        "ports": ports,
        "volumes": [f"/srv/games/{sch}:/data"],
        "env": {"GAMESERVER": gs, "UID": "4711", "GID": "4711",
                "VALIDATE_ON_START": "false", "UPDATE_CHECK": "0", "TZ": "Europe/Berlin"},
        "passwort": {"art": "datei", "pfad": "", "feld": ""},
        "adresse_port": adresse, "spieler": 4,
        "hinweis": (f"{z['gamename']} in der LinuxGSM-Bauart. Daten unter /data, Konfiguration "
                    f"in config-lgsm/{gs}/ und serverfiles/. Speicher- und Plattenbedarf sind "
                    f"geschaetzt und im Panel aenderbar. Manche LinuxGSM-Spiele setzen "
                    f"Einstellungen durch HINZUFUEGEN von Zeilen in common.cfg - findet der "
                    f"Einrichtungsschritt kein Feld, meldet er das."),
        # serverfiles NICHT pauschal: dort liegt neben der Installation die
        # eigentliche Serverkonfiguration (bei Ricochet 138 MB gegen 1 KB).
        "ausschluss": ["serverfiles/steamapps", "log", ".steam"],
        "bauart": "linuxgsm",
    }


def main():
    if len(sys.argv) < 2:
        print("Aufruf: katalog-lgsm.py <katalog.json> [--schreiben]"); sys.exit(1)
    pfad = Path(sys.argv[1])
    katalog = json.loads(pfad.read_text())
    formen = {}
    for g in katalog["spiele"]:
        for f in (g["name"], g["schluessel"], g["image"].split(":")[-1]):
            formen.setdefault(norm(f), g["schluessel"])
    # Auch die von Hand gebauten Stacks: Palworld und Satisfactory laufen, stehen
    # aber in keinem Katalog - ohne sie gaebe es zwei Wege zum selben Spiel.
    stacks = pfad.parent.parent / "stacks"
    for y in sorted(stacks.glob("*.yaml")) if stacks.is_dir() else []:
        formen.setdefault(norm(y.stem), f"{y.stem} (laufender Stack)")

    # Belegte Ports aus dem Katalog UND aus den laufenden Stacks. Die Stacks
    # allein waren zuerst nur beim Namensabgleich beruecksichtigt, nicht bei den
    # Ports - ARK bekam dadurch 7777, den Satisfactory haelt. Wer beide Listen
    # fuehrt, muss sie auch beide vollstaendig fuehren.
    # *The stacks were at first only considered for name matching, not for ports,
    #  so ARK was assigned 7777 which Satisfactory holds.*
    belegt = set()
    for g in katalog["spiele"]:
        for p in g["ports"]:
            teile = p.split(":")
            if len(teile) == 3:
                continue
            belegt.add((int(teile[0]), p.rsplit("/", 1)[-1].lower()))
    for y in sorted(stacks.glob("*.yaml")) if stacks.is_dir() else []:
        for m in re.finditer(r'^\s*-\s*"?(?:127\.0\.0\.1:)?(\d+):\d+(?:/(\w+))?"?\s*$',
                             y.read_text(), re.M):
            if "127.0.0.1" in m.group(0):
                continue
            belegt.add((int(m.group(1)), (m.group(2) or "tcp").lower()))
    print(f"  {len(belegt)} Ports bereits vergeben (Katalog + laufende Stacks)")

    print("Serverliste und Docker-Tags laden ...")
    zeilen = {z["shortname"]: z for z in csv.DictReader(io.StringIO(hole(LISTE)))}
    verfuegbar = tags() & set(zeilen)
    print(f"  {len(zeilen)} Spiele, {len(verfuegbar)} mit Docker-Image")

    def cfg(k):
        try:
            return k, hole(f"{DEFAULTS}/{zeilen[k]['gameservername']}/_default.cfg")
        except Exception:
            return k, ""
    with ThreadPoolExecutor(max_workers=10) as ex:
        cfgs = dict(ex.map(cfg, sorted(verfuegbar)))

    neu, uebersprungen = [], []
    for k in sorted(verfuegbar):
        z = zeilen[k]
        if k in DOPPELT:
            uebersprungen.append(f"{k} ({DOPPELT[k]})"); continue
        if k not in EIGENSTAENDIG:
            treffer = {formen[f] for f in (norm(z["gamename"]), norm(z["gameservername"]), norm(k))
                       if f in formen}
            if treffer:
                uebersprungen.append(f"{k} = {sorted(treffer)[0]}"); continue
        e = eintrag(k, z, cfgs.get(k, ""), belegt)
        if not e:
            uebersprungen.append(f"{k} (kein Port in der Vorlage)"); continue
        if e["schluessel"] in {g["schluessel"] for g in katalog["spiele"]}:
            uebersprungen.append(f"{k} (Schluessel belegt)"); continue
        neu.append(e)

    print(f"\nNeu: {len(neu)}   uebersprungen: {len(uebersprungen)}")
    for e in neu:
        print("  %-12s %-34s %s" % (e["schluessel"], e["name"][:32], ",".join(e["ports"])[:34]))
    print("\nDoppelt oder unbrauchbar:")
    for u in uebersprungen:
        print("  " + u)
    if "--schreiben" not in sys.argv:
        print("\n(nur Bericht - mit --schreiben uebernehmen)")
        return
    katalog["spiele"] = sorted(katalog["spiele"] + neu, key=lambda g: g["schluessel"])
    pfad.write_text(json.dumps(katalog, indent=1, ensure_ascii=False) + "\n")
    print(f"\ngeschrieben: {len(katalog['spiele'])} Spiele")


if __name__ == "__main__":
    main()
