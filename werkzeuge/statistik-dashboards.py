#!/usr/bin/env python3
"""statistik-dashboards.py — erzeugt die Grafana-Dashboards des Moduls "Statistik".

Warum erzeugt und nicht von Hand gepflegt: Ein Grafana-Dashboard ist mehrere
hundert Zeilen JSON, in denen dieselbe Angabe (Datenquelle, Einheit, Rasterlage)
zwanzigmal steht. Von Hand gepflegt weichen die Tafeln voneinander ab, und beim
Einfuegen einer Tafel verrutscht das Raster. Hier steht je Tafel eine Zeile.

*Generated rather than hand-maintained: a dashboard is hundreds of lines of JSON
 repeating the same datasource, unit and grid position; by hand the panels drift
 apart and inserting one shifts the grid.*

  werkzeuge/statistik-dashboards.py            schreibt die Dateien
  werkzeuge/statistik-dashboards.py --pruefen  meldet Abweichungen (Exit 1)

Die Dateien liegen in etc/module/statistik/grafana/dashboards/ und werden von
Grafana beim Start eingelesen (Bereitstellung, nicht Datenbank).
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ZIEL = REPO / "etc/module/statistik/grafana/dashboards"
QUELLE = {"type": "prometheus", "uid": "platzwart-prometheus"}


def tafel(nr, titel, art, ziele, breite=12, hoehe=8, x=0, y=0, einheit=None,
          beschreibung="", legende="{{stack}}", stapel=False, max_wert=None):
    """Eine Tafel. 'ziele' sind (ausdruck, legende)-Paare oder blosse Ausdruecke."""
    ausdruecke = []
    for i, z in enumerate(ziele):
        expr, leg = z if isinstance(z, tuple) else (z, legende)
        ausdruecke.append({"datasource": QUELLE, "editorMode": "code", "expr": expr,
                           "legendFormat": leg, "range": True, "refId": chr(65 + i)})
    feld = {"defaults": {"color": {"mode": "palette-classic"},
                         "custom": {"drawStyle": "line", "fillOpacity": 18,
                                    "lineWidth": 1, "showPoints": "never",
                                    "stacking": {"mode": "normal" if stapel else "none"},
                                    # Luecken NICHT verbinden: Faellt ein Lauf aus,
                                    # soll man das Loch sehen. Eine durchgezogene
                                    # Linie behauptet Messwerte, die es nie gab -
                                    # dieselbe Regel wie im Verlauf des Panels.
                                    "spanNulls": False},
                         "mappings": []},
             "overrides": []}
    if einheit:
        feld["defaults"]["unit"] = einheit
    if max_wert is not None:
        feld["defaults"]["max"] = max_wert
    if art == "stat":
        feld["defaults"].pop("custom", None)
    t = {"id": nr, "title": titel, "type": art, "datasource": QUELLE,
         "description": beschreibung, "fieldConfig": feld,
         "gridPos": {"h": hoehe, "w": breite, "x": x, "y": y},
         "targets": ausdruecke}
    if art == "timeseries":
        t["options"] = {"legend": {"displayMode": "list", "placement": "bottom",
                                   "showLegend": True, "calcs": []},
                        "tooltip": {"mode": "multi", "sort": "desc"}}
    elif art == "stat":
        t["options"] = {"colorMode": "value", "graphMode": "area",
                        "justifyMode": "auto", "orientation": "auto",
                        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "",
                                          "values": False},
                        "textMode": "auto"}
    return t


def dashboard(uid, titel, beschreibung, tafeln, zeitraum="now-24h"):
    return {"uid": uid, "title": titel, "description": beschreibung,
            "tags": ["platzwart"], "timezone": "browser", "schemaVersion": 39,
            "version": 1, "refresh": "1m", "editable": True,
            "time": {"from": zeitraum, "to": "now"},
            "timepicker": {}, "annotations": {"list": []}, "templating": {"list": []},
            "panels": tafeln}


def maschine():
    y, nr, t = 0, 0, []

    def naechste(*args, **kw):
        nonlocal nr
        nr += 1
        return tafel(nr, *args, **kw)

    t.append(naechste("Prozessorlast (Durchschnitt 1 min)", "stat",
                      ["node_load1"], breite=6, hoehe=4, x=0, y=y,
                      beschreibung="Ueber der Kernzahl heisst: es warten Prozesse.",
                      legende="Last"))
    t.append(naechste("Freier Arbeitsspeicher", "stat",
                      ["node_memory_MemAvailable_bytes"], breite=6, hoehe=4, x=6, y=y,
                      einheit="bytes", legende="frei"))
    t.append(naechste("Freie Platte auf /", "stat",
                      ['node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"}'],
                      breite=6, hoehe=4, x=12, y=y, einheit="bytes", legende="frei"))
    t.append(naechste("Laufzeit seit dem Start", "stat",
                      ["time() - node_boot_time_seconds"], breite=6, hoehe=4, x=18, y=y,
                      einheit="s", legende="Laufzeit"))
    y += 4
    t.append(naechste("Prozessorauslastung", "timeseries",
                      [('100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
                        "belegt")],
                      breite=12, hoehe=8, x=0, y=y, einheit="percent", max_wert=100,
                      beschreibung="Alle Kerne zusammen."))
    t.append(naechste("Arbeitsspeicher", "timeseries",
                      [("node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes", "belegt"),
                       ("node_memory_MemTotal_bytes", "eingebaut"),
                       ("node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes", "Auslagerung")],
                      breite=12, hoehe=8, x=12, y=y, einheit="bytes"))
    y += 8
    t.append(naechste("Platte: belegt und Vorhersage", "timeseries",
                      [('node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}', "belegt"),
                       ('node_filesystem_size_bytes{mountpoint="/"}', "Gesamt"),
                       # Die Vorhersage beantwortet die Frage, die man wirklich
                       # stellt: nicht "wie voll ist es", sondern "wann ist Schluss".
                       ('node_filesystem_size_bytes{mountpoint="/"} - predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 14*24*3600)',
                        "belegt in 14 Tagen (Hochrechnung)")],
                      breite=12, hoehe=8, x=0, y=y, einheit="bytes",
                      beschreibung="Die dritte Linie rechnet die letzten sechs Stunden 14 Tage weiter."))
    t.append(naechste("Netzdurchsatz", "timeseries",
                      [('rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "herein {{device}}"),
                       ('rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "hinaus {{device}}")],
                      breite=12, hoehe=8, x=12, y=y, einheit="bps"))
    y += 8
    t.append(naechste("Platten-Durchsatz", "timeseries",
                      [('rate(node_disk_read_bytes_total[5m])', "lesen {{device}}"),
                       ('rate(node_disk_written_bytes_total[5m])', "schreiben {{device}}")],
                      breite=12, hoehe=8, x=0, y=y, einheit="Bps"))
    t.append(naechste("Wartezeit auf Ein-/Ausgabe", "timeseries",
                      [('avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100', "iowait")],
                      breite=12, hoehe=8, x=12, y=y, einheit="percent",
                      beschreibung="Hohe Werte heissen: die Platte bremst, nicht der Prozessor."))
    return dashboard("platzwart-maschine", "Maschine",
                     "Last, Speicher, Platte und Netz der Maschine. Quelle: node_exporter.", t)


def platzwart():
    y, nr, t = 0, 0, []

    def naechste(*args, **kw):
        nonlocal nr
        nr += 1
        return tafel(nr, *args, **kw)

    t.append(naechste("Spieler jetzt", "stat", [("sum(platzwart_spieler)", "Spieler")],
                      breite=6, hoehe=4, x=0, y=y))
    t.append(naechste("Server laufen", "stat", [("sum(platzwart_server_laeuft)", "laufen")],
                      breite=6, hoehe=4, x=6, y=y))
    t.append(naechste("Juengste Sicherung", "stat",
                      [("time() - max(platzwart_sicherung_zeit_sekunden)", "Alter")],
                      breite=6, hoehe=4, x=12, y=y, einheit="s",
                      beschreibung="Alter des neuesten Archivs ueber alle Server."))
    t.append(naechste("Platte aller Spieldaten", "stat",
                      [("sum(platzwart_platte_bytes)", "belegt")],
                      breite=6, hoehe=4, x=18, y=y, einheit="bytes"))
    y += 4
    t.append(naechste("Spieler je Server", "timeseries", ["platzwart_spieler"],
                      breite=12, hoehe=8, x=0, y=y, stapel=True,
                      beschreibung="Gestapelt: die obere Kante ist die Gesamtzahl."))
    t.append(naechste("Arbeitsspeicher je Server", "timeseries",
                      ["platzwart_server_speicher_bytes"],
                      breite=12, hoehe=8, x=12, y=y, einheit="bytes"))
    y += 8
    t.append(naechste("Prozessorzeit je Server", "timeseries",
                      ["platzwart_server_cpu_prozent"],
                      breite=12, hoehe=8, x=0, y=y, einheit="percent"))
    t.append(naechste("Platte je Server", "timeseries", ["platzwart_platte_bytes"],
                      breite=12, hoehe=8, x=12, y=y, einheit="bytes", stapel=True,
                      beschreibung="Waechst hier eine Linie, weiss man, welches Spiel den Platz frisst."))
    y += 8
    t.append(naechste("Groesse der letzten Sicherung je Server", "timeseries",
                      [("platzwart_sicherung_groesse_bytes", "{{archiv}}")],
                      breite=12, hoehe=8, x=0, y=y, einheit="bytes",
                      beschreibung="Dedupliziert, also was das Archiv wirklich neu belegt."))
    t.append(naechste("Alter der Sicherung je Server", "timeseries",
                      [("time() - platzwart_sicherung_zeit_sekunden", "{{archiv}}")],
                      breite=12, hoehe=8, x=12, y=y, einheit="s",
                      beschreibung="Springt eine Linie nach oben und bleibt oben, sichert dieser Server nicht mehr."))
    y += 8
    t.append(naechste("Netz je Server", "timeseries",
                      [('rate(platzwart_server_netz_bytes_total{richtung="herein"}[10m])*8', "herein {{stack}}"),
                       ('rate(platzwart_server_netz_bytes_total{richtung="hinaus"}[10m])*8', "hinaus {{stack}}")],
                      breite=12, hoehe=8, x=0, y=y, einheit="bps"))
    t.append(naechste("Schlafende Server", "timeseries", ["platzwart_schlaeft"],
                      breite=12, hoehe=8, x=12, y=y, max_wert=1,
                      beschreibung="1 = der Server schlaeft und belegt keinen Speicher."))
    return dashboard("platzwart-server", "Spielserver",
                     "Spieler, Speicher, Platte und Sicherungen je Server. Quelle: platzwart-metriken.", t)


def main():
    pruefen = "--pruefen" in sys.argv
    ZIEL.mkdir(parents=True, exist_ok=True)
    schlecht = 0
    for name, bau in (("maschine.json", maschine), ("spielserver.json", platzwart)):
        datei = ZIEL / name
        text = json.dumps(bau(), indent=2, ensure_ascii=False) + "\n"
        if pruefen:
            alt = datei.read_text() if datei.exists() else ""
            if alt != text:
                print(f"  ABWEICHUNG {datei.relative_to(REPO)} — "
                      f"werkzeuge/statistik-dashboards.py neu laufen lassen")
                schlecht += 1
        else:
            datei.write_text(text)
            print(f"  geschrieben: {datei.relative_to(REPO)}")
    if pruefen and schlecht:
        return 1
    if pruefen:
        print("  Dashboards stimmen mit dem Generator ueberein.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
