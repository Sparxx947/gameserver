#!/usr/bin/env python3
"""katalog-ports.py — prueft die Portangaben des Spielekatalogs. Aendert nichts.

Vier Regeln, jede aus einem Fehler, den es im Katalog wirklich gab (#163):

1. VERWALTUNGSPORTS NUR LOKAL (Grenze 4). FiveM und RedM veroeffentlichten ihre
   "WebConsole" - ein gotty-Terminal, das an der Serverkonsole haengt, ohne
   Anmeldung. Dazu RCON bei gut fuenfzig Source-Spielen, Squad und Quake Live,
   die Webadministration von Killing Floor 1 und 2. Die Regel zum Lokalbinden
   gab es, sie verglich ihr Namensmuster aber mit der Portnummer statt mit dem
   Portnamen und griff deshalb nie.
2. TCP UND UDP EINES CONTAINERPORTS AUF DENSELBEN HOSTPORT. Die Kollisions-
   aufloesung verschob beide Protokolle getrennt. FiveM braucht beide auf einem
   Port; TF2 bekam seine Beitrittsadresse auf den TCP-Port, das Spiel lauscht
   auf einem anderen UDP-Port.
3. DIE BEITRITTSADRESSE ZEIGT AUF EINEN PORT, AUF DEM DAS SPIEL ANKOMMT: bei
   UDP-Spielen ein veroeffentlichter UDP-Port.
4. KEIN HOSTPORT DOPPELT - auch nicht zwischen 127.0.0.1 und allen Adressen:
   Docker weist 127.0.0.1:8081 ab, wenn ein anderer Container 0.0.0.0:8081
   haelt. Der alte Generator liess lokale Ports bei dieser Zaehlung aus.

Die Liste der Verwaltungsports ist eine Heuristik ueber Containerports - der
Katalog speichert keine Portnamen. Sie faengt die bekannten; ein neues Spiel mit
einem neuen Verwaltungsport faellt erst auf, wenn jemand den Namen liest.

Abschalten (nur wenn man weiss, warum): PLATZWART_PORTPRUEFUNG=aus

*Four rules, each from a real catalogue defect (#163): management ports local
 only; TCP and UDP of one container port share a host port; the join port is a
 port the game actually listens on; no host port used twice, 127.0.0.1 included.
 The management list is a heuristic over container ports - the catalogue stores
 no port names.*

Exit 0 = in Ordnung, 1 = Verstoss.
"""
import json, os, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KATALOG = REPO / "etc/spiele-katalog.json"
STACKS = REPO / "stacks"

# (Containerport, Protokoll) -> was dort lauscht. Belegt an den ich777-Vorlagen
# (Portnamen) bzw. am Spiel selbst.
VERWALTUNG = {
    (27015, "tcp"): "RCON der Source-Engine (Vorlagen TF2/GarrysMod: \"TCP RCON\")",
    (25575, "tcp"): "RCON",
    (28017, "tcp"): "RCON (Rust)",
    (21114, "tcp"): "RCON (Squad)",
    (21114, "udp"): "RCON (Squad)",
    (28690, "tcp"): "RCON (Quake Live)",
    (8080, "tcp"): "WebConsole/Webadministration (gotty bei ich777, KF2 Web Admin)",
    (8075, "tcp"): "Admin Port (Killing Floor)",
    (8082, "tcp"): "Web Panel (7 Days to Die)",
    (8772, "tcp"): "Assetto-Server-Manager",
    (10011, "tcp"): "TeamSpeak ServerQuery",
}
# Wo derselbe Containerport im Spiel etwas anderes ist. Mit Grund.
# Unturned stand hier mit 27015/tcp ("TCP1 - Game Port" laut Vorlage) - gemessen
# lauscht es auf keinem TCP-Port, der Eintrag ist seit #223 weg.
AUSNAHMEN = {}
# Spiele, die ueber TCP beitreten - dort ist die Beitrittsadresse ein TCP-Port.
TCP_SPIELE = {"minecraft", "minecraftfabric", "minecraftforge", "minecraftneoforge",
              "minecraftpaper", "minecraftpurpur", "minecraftquilt", "minecraftspigot",
              "openrct2", "starmade", "terraria", "terrariatshock", "vintagestory",
              "windward", "mindustry", "openttd", "starbound", "craftopia",
              "avorion", "lifeisfeudalyourown", "wurmunlimited", "ddnet"}

PORT = re.compile(r"(?:(127\.0\.0\.1):)?(\d+)(?:-(\d+))?:(\d+)(?:-(\d+))?(?:/(tcp|udp))?")


def zerlegen(p: str):
    """'127.0.0.1:30018:27015/tcp' -> [(lokal, host, container, proto), ...]"""
    m = PORT.fullmatch(p.strip().strip('"'))
    if not m:
        return None
    lokal, h1, h2, c1, c2, proto = m.groups()
    h1, c1 = int(h1), int(c1)
    n = int(h2 or h1) - h1
    return [(bool(lokal), h1 + i, c1 + i, proto or "tcp") for i in range(n + 1)]


NUR_LOKAL_NAME = re.compile(r"rcon|webconsole|web.?admin|admin|telnet|web.?panel|"
                            r"control|query.?web|server.?manager", re.I)


def ist_verwaltung(container: int, proto: str, name: str = "") -> bool:
    """Gehoert dieser Containerport auf 127.0.0.1?

    Kennt die Vorlage einen Namen, entscheidet der Name - Unturned nennt 27015/tcp
    "Game Port", TF2 nennt denselben Port "TCP RCON". Ohne Namen entscheidet die
    Liste der bekannten Verwaltungsports. Von den Generatoren benutzt, damit es
    die Regel nur EINMAL gibt: Sie stand vorher als Kopie im Generator und
    verglich dort ihr Namensmuster mit der Portnummer.
    *With a template name, the name decides; without one, the known list. Used by
     the generators so the rule exists once - the copy there matched the name
     pattern against the port number.*
    """
    if name:
        return bool(NUR_LOKAL_NAME.search(name))
    return (container, proto) in VERWALTUNG


def belegte_ports(katalog: list, stackports: dict) -> set:
    """(Hostport, Protokoll) aus Katalog und Stacks - die LOKALEN eingeschlossen.

    127.0.0.1:N und 0.0.0.0:N schliessen sich aus (gemessen, #163); die
    Generatoren liessen lokale Ports bei dieser Zaehlung aus.
    """
    raus = set()
    quellen = [p for e in katalog for p in e["ports"]] + [p for v in stackports.values() for p in v]
    for p in quellen:
        for lokal, h, c, pr in zerlegen(p) or []:
            raus.add((h, pr))
    return raus


def hostport_fuer(start: int, protos, belegt: set, ab: int) -> int:
    """Ein Hostport, der fuer ALLE genannten Protokolle frei ist, und belegt ihn."""
    h = start
    while any((h, p) in belegt for p in protos):
        h = max(ab, h + 1) if h < ab else h + 1
    belegt.update((h, p) for p in protos)
    return h


def pruefen(katalog: list, stackports: dict) -> list[str]:
    fehler = []
    wer = {}          # (host, proto) -> Eigentuemer
    for sch, ports in stackports.items():
        for p in ports:
            for lokal, h, c, pr in zerlegen(p) or []:
                wer.setdefault((h, pr), f"stacks/{sch}.yaml")
    for e in katalog:
        sch = e["schluessel"]
        oeff = {}     # (container, proto) -> host
        for p in e["ports"]:
            teile = zerlegen(p)
            if teile is None:
                fehler.append(f"{sch}: unlesbare Portangabe {p!r}")
                continue
            for lokal, h, c, pr in teile:
                # Regel 1
                if not lokal and (c, pr) in VERWALTUNG and (sch, c, pr) not in AUSNAHMEN:
                    fehler.append(f"{sch}: {p} ist oeffentlich, dort lauscht "
                                  f"{VERWALTUNG[(c, pr)]} - gehoert auf 127.0.0.1")
                # Regel 4 - ein Spiel, das es auch als Stack gibt, ist dasselbe Spiel
                andere = wer.get((h, pr))
                if andere and andere != sch and andere != f"stacks/{sch}.yaml":
                    fehler.append(f"{sch}: Hostport {h}/{pr} haelt schon {andere}")
                wer.setdefault((h, pr), sch)
                if not lokal:
                    oeff[(c, pr)] = h
        # Regel 2
        for (c, pr), h in oeff.items():
            if pr == "tcp" and (c, "udp") in oeff and oeff[(c, "udp")] != h:
                fehler.append(f"{sch}: Containerport {c} liegt auf {h}/tcp, aber "
                              f"{oeff[(c, 'udp')]}/udp - beide gehoeren auf einen Hostport")
        # Regel 3
        ap = e.get("adresse_port") or 0
        if ap:
            udp = {h for (c, pr), h in oeff.items() if pr == "udp"}
            tcp = {h for (c, pr), h in oeff.items() if pr == "tcp"}
            if sch in TCP_SPIELE or not udp:
                if ap not in tcp and ap not in udp:
                    fehler.append(f"{sch}: Beitrittsport {ap} ist nicht veroeffentlicht")
            elif ap not in udp:
                fehler.append(f"{sch}: Beitrittsport {ap} ist kein veroeffentlichter "
                              f"UDP-Port (UDP: {sorted(udp)})")
    return fehler


def stackports_lesen() -> dict:
    raus = {}
    for y in sorted(STACKS.glob("*.yaml")) if STACKS.is_dir() else []:
        raus[y.stem] = re.findall(r'^\s*-\s*"?((?:127\.0\.0\.1:)?\d+(?:-\d+)?:\d+(?:-\d+)?(?:/\w+)?)"?',
                                  y.read_text(), re.M)
    return raus


if __name__ == "__main__":
    if os.environ.get("PLATZWART_PORTPRUEFUNG") == "aus":
        print("  uebersprungen (PLATZWART_PORTPRUEFUNG=aus)")
        sys.exit(0)
    katalog = json.loads(KATALOG.read_text())["spiele"]
    f = pruefen(katalog, stackports_lesen())
    for z in f:
        print("  " + z)
    if f:
        print(f"  {len(f)} Verstoesse. Regeln und Ausnahmen: werkzeuge/katalog-ports.py "
              "(abschaltbar mit PLATZWART_PORTPRUEFUNG=aus)")
        sys.exit(1)
    print(f"  {len(katalog)} Spiele - Ports in Ordnung.")
