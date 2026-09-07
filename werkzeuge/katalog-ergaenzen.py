#!/usr/bin/env python3
"""katalog-ergaenzen.py — ergaenzt den Spielekatalog aus den ich777-Vorlagen.

Warum es das gibt: Der Katalog wurde einmal von Hand erzeugt. Wer ihn erweitern
wollte, haette dieselbe Recherche wiederholen muessen - und dabei dieselben
Fallen: Im Image steht bei vielen Tags nur GAME_ID=template; wer den Wert von
dort nimmt, baut einen Container, der nichts herunterlaedt. Verbindlich sind die
Unraid-Vorlagen unter github.com/ich777/docker-templates.

*The catalogue was assembled by hand once. Anyone extending it would repeat the
 same research and hit the same traps: many image tags carry only
 GAME_ID=template, and a container built from that downloads nothing. The Unraid
 templates are the authoritative source.*

Bewusst NUR ich777: eine Bauart, einheitliche Variablen (GAME_ID, GAME_PARAMS,
UID/GID - nicht PUID/PGID), erprobter Einrichtungsschritt und ein bekanntes
Muster fuer die Sicherungsausschluesse. Jede weitere Quelle braechte eigene
Konventionen mit, die einzeln zu pruefen waeren.

  katalog-ergaenzen.py <katalog.json> [--schreiben]

Ohne --schreiben wird nur berichtet, was hinzukaeme. Vorhandene Eintraege
werden NIE angefasst.
"""
import json, re, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VORLAGEN = "https://api.github.com/repos/ich777/docker-templates/contents/ich777"
GHCR_TOKEN = "https://ghcr.io/token?scope=repository:ich777/steamcmd:pull"
GHCR_TAGS = "https://ghcr.io/v2/ich777/steamcmd/tags/list?n=1000"

# Was in den Vorlagen zwar liegt, aber kein Spielserver ist.
KEIN_SPIEL = ("firefox", "chrome", "thunderbird", "radarr", "sonarr", "lidarr", "sabnzbd",
              "nzbhydra", "jenkins", "krusader", "remmina", "enpass", "electrum", "monero",
              "mycrypto", "ombi", "debian", "doh-", "proxy-", "openvpn", "rustdesk", "owncast",
              "stun-turn", "dirsync", "portfolio", "rapidphoto", "lancache", "gotify",
              "pushover", "online-check", "tor-", "ungoogled", "microsoft-edge", "csmm",
              "jdownloader", "luckybackup", "unmined", "xlinkkai")

# Verwaltungszugaenge gehoeren auf 127.0.0.1 - RCON, Webkonsolen und Query-
# Schnittstellen sind passwortgeschuetzte Administrationswege und beliebte
# Bruteforce-Ziele. Siehe docs/06-netz-dns-firewall.md.
# *Management ports bind to localhost: RCON and web consoles are admin paths.*
NUR_LOKAL = re.compile(r"rcon|webconsole|admin|telnet|api|control|query.?web|9011|9012|9014|9015|9031", re.I)

# Ressourcenbedarf steht in keiner Vorlage. Die Werte hier sind SCHAETZUNGEN
# nach Bauart des Spiels - sie bestimmen nur die Vorabpruefung ("passt das noch
# auf die Platte?") und die Speichergrenze, nicht das Spiel selbst. Wo sie
# danebenliegen, faellt es beim ersten Start auf und laesst sich im Panel
# korrigieren.
# *No template carries resource requirements. These are estimates by engine
#  family; they only drive the pre-flight check and the memory limit, and can be
#  corrected in the panel if they turn out wrong.*
# Dasselbe Spiel, anderer Vorlagenname - der Katalog fuehrt es bereits.
GLEICH = {"teamspeak3", "minecraftbasicserver", "vintagestory"}

GROESSE_STANDARD = (4, 10)
GROESSE = {
    "source": (2, 15),      # Source-Engine: klein im RAM, gross auf der Platte
    "klein":  (1, 3),       # Terraria, OpenTTD, Teeworlds ...
    "gross":  (8, 30),      # Unreal-Survival
}
BAUART = {
    "source": ("alienswarm", "alienswarmreactivedrop", "cstrike1.6", "dayofinfamy", "daysofwar",
               "dods", "fistfuloffrags", "garrysmod", "hl2dm", "hldm", "insurgency", "l4d",
               "neotokyo", "nomoreroominhell", "pvkii", "svencoop", "tf2", "zombiepanic", "cs2"),
    "klein":  ("terraria", "terrariatshock", "openttd", "openrct2", "teeworlds", "ddnet",
               "mindustry", "starmade", "xonotic", "quake3", "ioquake3", "zandronum",
               "urbanterror", "counterstrike2d", "altitude", "windward", "openmwtes3mp"),
    "gross":  ("squad", "postscriptum", "insurgencysandstorm", "killingfloor2", "mordhau",
               "scpsecretlaboratory", "vein", "pavlovvr", "assettocorsa", "wreckfest"),
}


def hole(url, kopf=None, roh=False):
    r = urllib.request.Request(url, headers=kopf or {"User-Agent": "katalog-ergaenzen"})
    with urllib.request.urlopen(r, timeout=40) as f:
        d = f.read()
    return d.decode("utf-8", "replace") if roh else json.loads(d)


def schluessel(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())[:30]


def groesse(sch: str) -> tuple:
    for art, liste in BAUART.items():
        if sch in liste:
            return GROESSE[art]
    return GROESSE_STANDARD


def vorlagen_laden() -> dict:
    liste = hole(VORLAGEN)
    urls = {e["name"][:-4]: e["download_url"] for e in liste if e["name"].endswith(".xml")}

    def eine(nu):
        n, u = nu
        try:
            return n, hole(u, roh=True)
        except Exception:
            return n, ""
    with ThreadPoolExecutor(max_workers=10) as ex:
        return {n: t for n, t in ex.map(eine, urls.items()) if t}


def auswerten(name: str, xml: str) -> dict | None:
    repo = re.search(r"<Repository>\s*([^<\s]+)\s*</Repository>", xml)
    if not repo:
        return None
    image = repo.group(1)
    if "ich777" not in image or any(k in image.lower() for k in KEIN_SPIEL):
        return None
    # "steamcmd:latest" ist kein Spiel, sondern das Grundimage. Eine Vorlage,
    # die darauf verweist, beschreibt eine Bauanleitung, keinen Spielserver.
    # *"steamcmd:latest" is the base image, not a game.*
    if image.rstrip("/").endswith("steamcmd:latest") or image.rstrip("/").endswith("steamcmd"):
        return None
    gid = re.search(r'Name="GAME_ID"[^>]*>\s*([^<\s]*)\s*<', xml)
    gid = gid.group(1) if gid else ""
    ports = re.findall(r"<HostPort>(\d+)</HostPort>\s*<ContainerPort>(\d+)</ContainerPort>"
                       r"\s*<Protocol>(\w+)</Protocol>", xml)
    params = re.search(r'Name="GAME_PARAMS"[^>]*>(.*?)</Config>', xml, re.S)
    besch = re.search(r"<Overview>(.*?)</Overview>", xml, re.S)
    steamcmd = "steamcmd:" in image
    if steamcmd and not gid.isdigit():
        return None          # ohne echte GAME_ID laedt der Container nichts
    return {
        "name": name.replace("-", " "),
        "image": image if ":" in image.split("/")[-1] else image + ":latest",
        "game_id": gid if gid.isdigit() else "",
        "ports": ports,
        "params": re.sub(r"<[^>]+>|\s+", " ", params.group(1)).strip() if params else "",
        "kurz": re.sub(r"<[^>]+>|\s+", " ", besch.group(1)).strip() if besch else "",
        "steamcmd": steamcmd,
    }


def ports_bauen(roh: list, belegt: set) -> tuple:
    """Portangaben erzeugen und Kollisionen mit BEREITS VERGEBENEN aufloesen.

    Der Ersatzbereich beginnt bei 30100, weil der Katalog 30000-30099 schon
    nutzt. Verwaltungsports werden an 127.0.0.1 gebunden und zaehlen deshalb
    nicht als belegt - sie kollidieren nicht nach aussen.
    """
    raus, erster = [], 0
    for host, cont, proto in roh:
        h, c, p = int(host), int(cont), proto.lower()
        lokal = bool(NUR_LOKAL.search(str(h)) or NUR_LOKAL.search(str(c)))
        if lokal:
            raus.append(f"127.0.0.1:{h}:{c}/{p}")
            continue
        while (h, p) in belegt:
            h = max(30100, h + 1) if h < 30100 else h + 1
        belegt.add((h, p))
        raus.append(f"{h}:{c}/{p}")
        if not erster:
            erster = h
    return raus, erster


def eintrag_bauen(sch: str, v: dict, belegt: set) -> dict:
    ports, adresse = ports_bauen(v["ports"], belegt)
    mem, platte = groesse(sch)
    env = {"UID": "4711", "GID": "4711", "UMASK": "000", "DATA_PERM": "770"}
    if v["steamcmd"]:
        env = {"GAME_ID": v["game_id"], "GAME_PARAMS": v["params"], **env}
    return {
        "schluessel": sch,
        "name": v["name"],
        "kurz": (v["kurz"][:110] or v["name"]),
        "appid": int(v["game_id"]) if v["game_id"] else 0,
        "image": v["image"],
        "mem_gb": mem,
        "platte_gb": platte,
        "ports": ports,
        "volumes": [f"/srv/games/{sch}:/serverdata"],
        "env": env,
        # "datei" ist bei ich777 der Normalfall: nur eine Handvoll Spiele nimmt
        # das Passwort aus der Umgebung. spiel-einrichtung findet das Feld selbst
        # und meldet ehrlich, wenn es keines gibt.
        "passwort": {"art": "datei", "pfad": "", "feld": ""},
        "adresse_port": adresse,
        "spieler": 4,
        "hinweis": (v["kurz"][:200] + " ").strip() +
                   " Aus der ich777-Vorlage uebernommen; Speicher- und Plattenbedarf sind "
                   "geschaetzt und im Panel aenderbar.",
        "ausschluss": ["steamcmd", "serverfiles/steamapps"] if v["steamcmd"] else [],
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-4]); sys.exit(1)
    pfad = Path(sys.argv[1])
    schreiben = "--schreiben" in sys.argv
    katalog = json.loads(pfad.read_text())
    vorhanden = {g["schluessel"] for g in katalog["spiele"]}

    # Bereits vergebene Ports einsammeln - nur die oeffentlichen. NEBEN dem
    # Katalog auch die von Hand gebauten Stacks: Satisfactory belegt 7777, und
    # ein neuer Katalogeintrag auf demselben Port waere auf dieser Maschine nicht
    # installierbar. Der Katalog allein weiss davon nichts.
    # *Besides the catalogue, the hand-built stacks count too: Satisfactory holds
    #  7777, and the catalogue alone knows nothing about it.*
    belegt = set()
    for g in katalog["spiele"]:
        for p in g["ports"]:
            teile = p.split(":")
            if len(teile) == 3:
                continue
            belegt.add((int(teile[0]), p.rsplit("/", 1)[-1].lower()))
    stacks = pfad.parent.parent / "stacks"
    for y in sorted(stacks.glob("*.yaml")) if stacks.is_dir() else []:
        for m in re.finditer(r'^\s*-\s*"?(?:127\.0\.0\.1:)?(\d+):\d+(?:/(\w+))?"?\s*$',
                             y.read_text(), re.M):
            if "127.0.0.1" in m.group(0):
                continue
            belegt.add((int(m.group(1)), (m.group(2) or "tcp").lower()))
    print(f"  {len(belegt)} Ports bereits vergeben (Katalog + vorhandene Stacks)")

    print("Vorlagen laden ...")
    xmls = vorlagen_laden()
    print(f"  {len(xmls)} Vorlagen")

    neu, uebersprungen = [], []
    for name, xml in sorted(xmls.items()):
        v = auswerten(name, xml)
        if not v:
            continue
        sch = schluessel(name)
        # Dasselbe Spiel unter anderem Namen. Die Gleichsetzungen stehen
        # EINZELN da und werden nicht geraten: ein Praefixvergleich warf
        # "insurgencysandstorm" wegen "insurgency" und "killingfloor2" wegen
        # "killingfloor" weg - beides eigene Spiele. Gepruefte Duplikate sind
        # nur die hier genannten und exakt gleiche Images.
        # *Equivalences are listed individually rather than guessed: a prefix
        #  comparison discarded "insurgencysandstorm" and "killingfloor2", which
        #  are separate games.*
        if sch in vorhanden or sch in GLEICH or \
           any(g["image"] == v["image"] for g in katalog["spiele"]):
            uebersprungen.append(sch)
            continue
        if not v["ports"]:
            uebersprungen.append(f"{sch} (keine Ports in der Vorlage)")
            continue
        neu.append(eintrag_bauen(sch, v, belegt))
        vorhanden.add(sch)

    print(f"\nNeu: {len(neu)}   bereits vorhanden oder ohne Ports: {len(uebersprungen)}")
    for e in neu:
        print("  %-24s %-42s %s" % (e["schluessel"], e["image"].split("/")[-1][:40],
                                    ",".join(e["ports"])[:44]))
    if not schreiben:
        print("\n(nur Bericht - mit --schreiben in den Katalog uebernehmen)")
        return
    katalog["spiele"] = sorted(katalog["spiele"] + neu, key=lambda g: g["schluessel"])
    pfad.write_text(json.dumps(katalog, indent=1, ensure_ascii=False) + "\n")
    print(f"\ngeschrieben: {len(katalog['spiele'])} Spiele im Katalog")


if __name__ == "__main__":
    main()
