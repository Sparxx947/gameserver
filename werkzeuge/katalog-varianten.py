#!/usr/bin/env python3
"""katalog-varianten.py — ergaenzt Spielvarianten, die dasselbe Image anders starten.

Manche Images bedienen mehrere Server-Arten, die sich nur in einer
Umgebungsvariablen unterscheiden. itzg/minecraft-server kennt acht: VANILLA,
PAPER, FABRIC, FORGE, NEOFORGE, PURPUR, SPIGOT und QUILT. Im Katalog stand
davon genau eine - dabei entscheidet gerade diese Wahl darueber, ob Plugins oder
Mods ueberhaupt moeglich sind.

*Some images serve several server kinds that differ only in one environment
 variable. itzg/minecraft-server knows eight; the catalogue held exactly one,
 although that choice decides whether plugins or mods are possible at all.*

Die Varianten stehen EINZELN hier, mit eigener Beschreibung. Sie aus einer Liste
zu erzeugen waere kuerzer, aber dann stuenden acht Eintraege mit demselben
nichtssagenden Text im Katalog - genau das, was bei den LinuxGSM-Eintraegen
schon einmal passiert ist.

  katalog-varianten.py <katalog.json> [--schreiben]
"""
import json, sys
from pathlib import Path

MINECRAFT = "itzg/minecraft-server:latest"

# (schluessel, Name, Kurzbeschreibung, TYPE, Speicher GB, Platte GB)
VARIANTEN = [
    ("minecraftpaper",    "Minecraft (Paper)",    "Plugin-Server, deutlich schneller als Vanilla", "PAPER",    4, 6),
    ("minecraftfabric",   "Minecraft (Fabric)",   "Mods ueber Fabric, leicht und schnell aktuell", "FABRIC",   5, 8),
    ("minecraftforge",    "Minecraft (Forge)",    "Mods ueber Forge, Grundlage der meisten Modpacks", "FORGE", 6, 10),
    ("minecraftneoforge", "Minecraft (NeoForge)", "Forge-Nachfolger fuer neuere Fassungen",        "NEOFORGE", 6, 10),
    ("minecraftpurpur",   "Minecraft (Purpur)",   "Paper-Ableger mit vielen zusaetzlichen Reglern", "PURPUR",  4, 6),
    ("minecraftspigot",   "Minecraft (Spigot)",   "Plugin-Server, Vorlaeufer von Paper",           "SPIGOT",   4, 6),
    ("minecraftquilt",    "Minecraft (Quilt)",    "Fabric-Ableger mit eigenem Modloader",          "QUILT",    5, 8),
]

# Bedrock hat ein EIGENES Image und einen eigenen Port - es ist keine Variante,
# sondern ein anderer Server. Deshalb hier getrennt.
BEDROCK = {
    "schluessel": "minecraftbedrock",
    "name": "Minecraft (Bedrock)",
    "kurz": "Fuer Konsole, Handy und die Windows-Fassung - nicht Java",
    "appid": 0,
    "image": "itzg/minecraft-bedrock-server:latest",
    "mem_gb": 3, "platte_gb": 4,
    "ports": ["19132:19132/udp"],
    "volumes": ["/srv/games/minecraftbedrock:/data"],
    "env": {"EULA": "TRUE", "GAMEMODE": "survival", "DIFFICULTY": "easy",
            "SERVER_NAME": "@@WELT_NAME@@", "UID": "4711", "GID": "4711",
            "TZ": "Europe/Berlin", "ALLOW_CHEATS": "false", "MAX_PLAYERS": "4",
            "ONLINE_MODE": "true", "ALLOW_LIST": "true"},
    "passwort": {"art": "keins"},
    "adresse_port": 19132, "spieler": 4,
    "hinweis": ("ACHTUNG: Die Installation setzt EULA=TRUE - das ist die Zustimmung zu Mojangs "
                "Nutzungsbedingungen. Bedrock ist NICHT mit der Java-Fassung kompatibel: wer "
                "Java spielt, kommt hier nicht rein und umgekehrt. Ein Beitrittspasswort gibt es "
                "nicht; stattdessen ist die Zulassungsliste an (allowlist.json)."),
    "ausschluss": [], "bauart": "eigenes-image", "kategorie": "survival",
}


def eintrag(sch, name, kurz, typ, mem, platte, port):
    return {
        "schluessel": sch, "name": name, "kurz": kurz, "appid": 0,
        "image": MINECRAFT, "mem_gb": mem, "platte_gb": platte,
        "ports": [f"{port}:25565/tcp"],
        "volumes": [f"/srv/games/{sch}:/data"],
        "env": {"EULA": "TRUE", "TYPE": typ, "MEMORY": f"{mem - 1}G",
                "UID": "4711", "GID": "4711", "TZ": "Europe/Berlin",
                "MOTD": "@@WELT_NAME@@", "ENABLE_WHITELIST": "true",
                "ENFORCE_WHITELIST": "true"},
        "passwort": {"art": "keins"},
        "adresse_port": port, "spieler": 4,
        "hinweis": (f"{kurz}. ACHTUNG: Die Installation setzt EULA=TRUE - das ist die Zustimmung "
                    f"zu Mojangs Nutzungsbedingungen. Minecraft kennt kein Serverpasswort; "
                    f"stattdessen ist die Weissliste an: Mitspieler mit \"whitelist add <Name>\" "
                    f"freischalten. Mods und Plugins gehoeren in die Konfigdateien unter mods/ "
                    f"bzw. plugins/."),
        "ausschluss": ["libraries", "versions", "minecraft_server.*.jar", "logs"],
        "bauart": "eigenes-image", "kategorie": "survival",
    }


def main():
    if len(sys.argv) < 2:
        print("Aufruf: katalog-varianten.py <katalog.json> [--schreiben]"); sys.exit(1)
    pfad = Path(sys.argv[1])
    d = json.loads(pfad.read_text())
    vorhanden = {g["schluessel"] for g in d["spiele"]}

    belegt = set()
    for g in d["spiele"]:
        for p in g["ports"]:
            teile = p.split(":")
            if len(teile) == 3:
                continue
            belegt.add((int(teile[0]), p.rsplit("/", 1)[-1].lower()))

    neu = []
    port = 25566          # 25565 hat die Vanilla-Fassung
    for sch, name, kurz, typ, mem, platte in VARIANTEN:
        if sch in vorhanden:
            continue
        while (port, "tcp") in belegt:
            port += 1
        belegt.add((port, "tcp"))
        neu.append(eintrag(sch, name, kurz, typ, mem, platte, port))
        port += 1
    if BEDROCK["schluessel"] not in vorhanden and (19132, "udp") not in belegt:
        neu.append(BEDROCK)

    print(f"Neu: {len(neu)}")
    for e in neu:
        print("  %-20s %-24s %-34s %s" % (e["schluessel"], e["name"],
              e["image"].split("/")[-1], ",".join(e["ports"])))
    if "--schreiben" in sys.argv and neu:
        d["spiele"] = sorted(d["spiele"] + neu, key=lambda g: g["schluessel"])
        pfad.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n")
        print(f"\ngeschrieben: {len(d['spiele'])} Spiele")
    elif "--schreiben" not in sys.argv:
        print("\n(nur Bericht - mit --schreiben uebernehmen)")


if __name__ == "__main__":
    main()
