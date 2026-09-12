#!/usr/bin/env python3
"""statistik-dashboards.py — erzeugt die Grafana-Dashboards des Moduls "Statistik".

Warum erzeugt und nicht von Hand gepflegt: Ein Dashboard ist mehrere hundert
Zeilen JSON, in denen dieselbe Angabe (Datenquelle, Einheit, Rasterlage)
zwanzigmal steht. Von Hand gepflegt weichen die Tafeln voneinander ab, und beim
Einfuegen einer Tafel verrutscht das Raster. Hier steht je Tafel eine Zeile.

*Generated rather than hand-maintained: a dashboard is hundreds of lines of JSON
 repeating the same datasource, unit and grid position; by hand the panels drift
 apart and inserting one shifts the grid.*

  werkzeuge/statistik-dashboards.py               schreibt die Dateien
  werkzeuge/statistik-dashboards.py --pruefen     meldet Abweichungen (Exit 1)
  werkzeuge/statistik-dashboards.py --daten ZIEL  fragt JEDE Tafel bei der
                                                  laufenden Prometheus-Instanz
                                                  ab und meldet leere (Exit 1)

Der Datenmodus ist die Pruefung, die zaehlt: Eine Tafel, die immer leer bleibt,
faellt sonst niemandem auf - sie sieht aus wie ein ruhiger Messwert. Er braucht
einen SSH-Zugang zur Maschine, weil Prometheus nur im compose-Netz lauscht.

*The data mode is the check that matters: a permanently empty panel looks like a
 quiet measurement. It needs SSH access, since Prometheus listens only inside the
 compose network.*
"""
import json
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ZIEL = REPO / "etc/module/statistik/grafana/dashboards"
QUELLE = {"type": "prometheus", "uid": "platzwart-prometheus"}
# Die Protokolle liegen in einer zweiten Datenquelle. Tafeln, die daraus lesen,
# sprechen LogQL und nicht PromQL - die Datenpruefung laesst sie deshalb aus.
# *Logs live in a second datasource and speak LogQL; the data check skips them.*
LOKI = {"type": "loki", "uid": "platzwart-loki"}
# Nur Metriken, die es auf DIESER Maschine gibt. Kein hwmon (virtuelle
# Maschine), kein systemd-Sammler, keine Drosselungs- und OOM-Werte von cAdvisor
# (/dev/kmsg ist im Container nicht erlaubt) - Tafeln dafuer waeren dauerhaft
# leer, und leere Tafeln bringen einem bei, das Dashboard zu ueberblaettern.
# *Only metrics this machine actually has; permanently empty panels teach people
#  to skip the dashboard.*


class Bau:
    """Sammelt Tafeln und fuehrt das Raster mit: je Zeile 24 Einheiten."""

    def __init__(self):
        self.tafeln = []
        self.nr = 0
        self.y = 0
        self.x = 0
        self.zeilenhoehe = 0

    def reihe(self, titel):
        """Eine Trennzeile - sie macht ein langes Dashboard erst lesbar."""
        self._umbruch()
        self.nr += 1
        self.tafeln.append({"id": self.nr, "type": "row", "title": titel,
                            "collapsed": False, "panels": [],
                            "gridPos": {"h": 1, "w": 24, "x": 0, "y": self.y}})
        self.y += 1

    def _umbruch(self):
        if self.x:
            self.y += self.zeilenhoehe
            self.x = 0
            self.zeilenhoehe = 0

    def platz(self, breite, hoehe):
        if self.x + breite > 24:
            self._umbruch()
        pos = {"h": hoehe, "w": breite, "x": self.x, "y": self.y}
        self.x += breite
        self.zeilenhoehe = max(self.zeilenhoehe, hoehe)
        return pos

    def tafel(self, titel, art, ziele, breite=12, hoehe=8, einheit=None,
              beschreibung="", legende="{{stack}}", stapel=False, max_wert=None,
              min_wert=None, schwellen=None, spalten=None, sortierung=None,
              modus=None, quelle=None):
        quelle = quelle or QUELLE
        self.nr += 1
        ausdruecke = []
        for i, z in enumerate(ziele):
            expr, leg = z if isinstance(z, tuple) else (z, legende)
            a = {"datasource": quelle, "editorMode": "code", "expr": expr,
                 "legendFormat": leg, "refId": chr(65 + i)}
            a["instant"] = art in ("stat", "gauge", "bargauge", "table") and quelle is QUELLE
            if quelle is LOKI:
                a["queryType"] = "range"
            a["range"] = not a["instant"]
            if art == "table":
                a["format"] = "table"
            ausdruecke.append(a)
        feld = {"defaults": {"color": {"mode": "palette-classic"}, "mappings": []},
                "overrides": []}
        if art in ("timeseries",):
            feld["defaults"]["custom"] = {
                "drawStyle": "line", "fillOpacity": 18, "lineWidth": 1,
                "showPoints": "never",
                "stacking": {"mode": "normal" if stapel else "none"},
                # Luecken NICHT verbinden: Faellt ein Lauf aus, soll man das Loch
                # sehen. Eine durchgezogene Linie behauptet Messwerte, die es nie
                # gab - dieselbe Regel wie im Verlauf des Panels.
                "spanNulls": False}
        if einheit:
            feld["defaults"]["unit"] = einheit
        if max_wert is not None:
            feld["defaults"]["max"] = max_wert
        if min_wert is not None:
            feld["defaults"]["min"] = min_wert
        if schwellen:
            feld["defaults"]["thresholds"] = {"mode": "absolute", "steps": schwellen}
            feld["defaults"]["color"] = {"mode": "thresholds"}
        t = {"id": self.nr, "title": titel, "type": art, "datasource": quelle,
             "description": beschreibung, "fieldConfig": feld,
             "gridPos": self.platz(breite, hoehe), "targets": ausdruecke}
        if art == "timeseries":
            t["options"] = {"legend": {"displayMode": "list", "placement": "bottom",
                                       "showLegend": True, "calcs": []},
                            "tooltip": {"mode": "multi", "sort": "desc"}}
        elif art == "stat":
            t["options"] = {"colorMode": "value", "graphMode": modus or "area",
                            "justifyMode": "auto", "orientation": "auto",
                            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "",
                                              "values": False},
                            "textMode": "auto"}
        elif art in ("gauge", "bargauge"):
            t["options"] = {"displayMode": "gradient", "orientation": "horizontal",
                            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "",
                                              "values": False},
                            "showUnfilled": True}
        elif art == "logs":
            t["options"] = {"showTime": True, "showLabels": False, "wrapLogMessage": True,
                            "sortOrder": "Descending", "enableLogDetails": True,
                            "dedupStrategy": "none", "prettifyLogMessage": False}
        elif art == "table":
            t["options"] = {"showHeader": True,
                            "sortBy": [{"desc": True, "displayName": sortierung}] if sortierung else []}
            t["transformations"] = [
                {"id": "merge", "options": {}},
                {"id": "organize", "options": {
                    "excludeByName": {"Time": True, "__name__": True, "job": True,
                                      "instance": True, "id": True},
                    "renameByName": spalten or {}}}]
        self.tafeln.append(t)
        return t

    def text(self, titel, inhalt, hoehe=3):
        self.nr += 1
        self.tafeln.append({"id": self.nr, "type": "text", "title": titel,
                            "gridPos": self.platz(24, hoehe),
                            "options": {"mode": "markdown", "content": inhalt}})


def dashboard(uid, titel, beschreibung, bau, zeitraum="now-6h", variablen=None):
    return {"uid": uid, "title": titel, "description": beschreibung,
            "tags": ["platzwart"], "timezone": "browser", "schemaVersion": 39,
            "version": 1, "refresh": "1m", "editable": True,
            "time": {"from": zeitraum, "to": "now"}, "timepicker": {},
            "annotations": {"list": []},
            "templating": {"list": variablen or []},
            "panels": bau.tafeln}


def auswahl(name, metrik, etikett="stack", titel=None, quelle=None):
    """Eine Mehrfachauswahl oben im Dashboard - ohne sie ist jede Tafel mit
    sieben Servern eine Tapete."""
    return {"name": name, "label": titel or name, "type": "query",
            "datasource": quelle or QUELLE, "refresh": 1, "multi": True, "includeAll": True,
            "allValue": ".*", "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
            "query": {"query": f"label_values({metrik}, {etikett})", "refId": "A"},
            "definition": f"label_values({metrik}, {etikett})", "sort": 1,
            "options": [], "hide": 0}


GRUEN_ROT = [{"color": "red", "value": None}, {"color": "green", "value": 1}]
ROT_AB = lambda n: [{"color": "green", "value": None}, {"color": "red", "value": n}]


# --- Maschine ----------------------------------------------------------------
def maschine():
    b = Bau()
    b.reihe("Auf einen Blick")
    # scalar() ist noetig, nicht Zierat: node_load1 traegt Etiketten, die
    # Kernzahl nicht - ohne scalar findet Prometheus kein Paar und die Tafel
    # bleibt leer. Gefunden mit --daten, nicht im Browser.
    # *scalar() is required: node_load1 carries labels, the core count does not,
    #  so without it the vectors never match and the panel stays empty.*
    b.tafel("Last je Kern", "stat",
            [("node_load1 / scalar(count(count(node_cpu_seconds_total) by (cpu)))", "Last")],
            breite=4, hoehe=4, einheit="percentunit",
            beschreibung="Last geteilt durch die Kernzahl. Ueber 1 warten Prozesse auf Rechenzeit.",
            schwellen=ROT_AB(1))
    b.tafel("Prozessor belegt", "stat",
            [('100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)', "belegt")],
            breite=4, hoehe=4, einheit="percent", schwellen=ROT_AB(85))
    b.tafel("Speicher frei", "stat", [("node_memory_MemAvailable_bytes", "frei")],
            breite=4, hoehe=4, einheit="bytes")
    b.tafel("Platte frei", "stat",
            [('node_filesystem_avail_bytes{mountpoint="/"}', "frei")],
            breite=4, hoehe=4, einheit="bytes")
    b.tafel("Auslagerung belegt", "stat",
            [("node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes", "belegt")],
            breite=4, hoehe=4, einheit="bytes",
            beschreibung="Dauerhaft belegte Auslagerung heisst: der Speicher ist zu knapp.")
    b.tafel("Laufzeit", "stat", [("time() - node_boot_time_seconds", "Laufzeit")],
            breite=4, hoehe=4, einheit="s", modus="none")

    b.reihe("Prozessor")
    b.tafel("Auslastung nach Art", "timeseries",
            [('sum by (mode) (rate(node_cpu_seconds_total{mode!="idle"}[5m])) '
              '/ scalar(count(count(node_cpu_seconds_total) by (cpu))) * 100', "{{mode}}")],
            einheit="percent", stapel=True, max_wert=100,
            beschreibung="system = Kern, user = Programme, iowait = Warten auf die Platte, "
                         "steal = der Wirt hat den Kern jemand anderem gegeben.")
    b.tafel("Je Kern", "timeseries",
            [('100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100)', "Kern {{cpu}}")],
            einheit="percent", max_wert=100,
            beschreibung="Ein einzelner Kern am Anschlag bremst ein Spiel, auch wenn der Schnitt harmlos aussieht.")
    b.tafel("Last 1/5/15 Minuten", "timeseries",
            [("node_load1", "1 min"), ("node_load5", "5 min"), ("node_load15", "15 min"),
             ("count(count(node_cpu_seconds_total) by (cpu))", "Kerne")])
    b.tafel("Wartedruck (PSI)", "timeseries",
            [("rate(node_pressure_cpu_waiting_seconds_total[5m]) * 100", "Prozessor"),
             ("rate(node_pressure_io_waiting_seconds_total[5m]) * 100", "Ein-/Ausgabe"),
             ("rate(node_pressure_memory_waiting_seconds_total[5m]) * 100", "Speicher")],
            einheit="percent",
            beschreibung="Anteil der Zeit, in der mindestens eine Aufgabe auf die Betriebsmittel wartet. "
                         "Zeigt Engpaesse frueher als die Auslastung selbst.")

    b.reihe("Speicher")
    b.tafel("Verteilung", "timeseries",
            [("node_memory_MemTotal_bytes - node_memory_MemFree_bytes - node_memory_Buffers_bytes - node_memory_Cached_bytes", "Programme"),
             ("node_memory_Cached_bytes", "Dateicache"),
             ("node_memory_Buffers_bytes", "Puffer"),
             ("node_memory_MemFree_bytes", "frei")],
            einheit="bytes", stapel=True,
            beschreibung="Dateicache ist kein Verbrauch - er wird abgegeben, wenn ein Programm den Platz braucht.")
    b.tafel("Auslagerung und Aufraeumdruck", "timeseries",
            [("node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes", "ausgelagert"),
             ("rate(node_vmstat_pgmajfault[5m])", "Seitenfehler/s (rechte Skala)")],
            einheit="bytes")

    b.reihe("Platte")
    b.tafel("Belegung je Einhaengepunkt", "timeseries",
            [('node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"} - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}',
              "{{mountpoint}} belegt")],
            einheit="bytes")
    b.tafel("Frei, mit Hochrechnung auf 14 Tage", "timeseries",
            [('node_filesystem_avail_bytes{mountpoint="/"}', "frei"),
             ('predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 14*24*3600)',
              "frei in 14 Tagen (Hochrechnung)")],
            einheit="bytes",
            beschreibung="Die zweite Linie rechnet die letzten sechs Stunden 14 Tage weiter. "
                         "Geht sie unter null, ist das Datum absehbar.")
    b.tafel("Durchsatz je Geraet", "timeseries",
            [('rate(node_disk_read_bytes_total{device!~"loop.*"}[5m])', "lesen {{device}}"),
             ('rate(node_disk_written_bytes_total{device!~"loop.*"}[5m])', "schreiben {{device}}")],
            einheit="Bps")
    b.tafel("Wartezeit und Auslastung der Platte", "timeseries",
            [('rate(node_disk_io_time_seconds_total{device!~"loop.*"}[5m]) * 100', "belegt {{device}}"),
             ('avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100', "iowait")],
            einheit="percent",
            beschreibung="Hohe Werte heissen: die Platte bremst, nicht der Prozessor.")
    b.tafel("Inodes frei", "timeseries",
            [('node_filesystem_files_free{fstype!~"tmpfs|overlay|squashfs"}', "{{mountpoint}}")],
            breite=8, hoehe=6,
            beschreibung="Viele kleine Dateien koennen die Platte belegen, ohne dass Bytes fehlen.")
    b.tafel("Offene Dateien", "timeseries",
            [("node_filefd_allocated", "offen"), ("node_filefd_maximum", "Grenze")],
            breite=8, hoehe=6)
    b.tafel("Kontextwechsel und neue Prozesse", "timeseries",
            [("rate(node_context_switches_total[5m])", "Kontextwechsel/s"),
             ("rate(node_forks_total[5m])", "neue Prozesse/s")],
            breite=8, hoehe=6)

    b.reihe("Netz")
    b.tafel("Durchsatz je Schnittstelle", "timeseries",
            [('rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "herein {{device}}"),
             ('rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "hinaus {{device}}")],
            einheit="bps")
    b.tafel("Pakete, Fehler, Verworfene", "timeseries",
            [('rate(node_network_receive_packets_total{device!~"lo|veth.*"}[5m])', "Pakete herein {{device}}"),
             ('rate(node_network_transmit_packets_total{device!~"lo|veth.*"}[5m])', "Pakete hinaus {{device}}"),
             ('rate(node_network_receive_errs_total{device!~"lo|veth.*"}[5m])', "Fehler {{device}}"),
             ('rate(node_network_receive_drop_total{device!~"lo|veth.*"}[5m])', "verworfen {{device}}")],
            beschreibung="Fehler und Verworfene sollten flach auf null liegen.")
    b.tafel("TCP-Verbindungen", "timeseries",
            [("node_netstat_Tcp_CurrEstab", "bestehend"),
             ("rate(node_netstat_Tcp_ActiveOpens[5m])", "neu/s ausgehend"),
             ("rate(node_netstat_Tcp_PassiveOpens[5m])", "neu/s eingehend"),
             ("rate(node_netstat_Tcp_RetransSegs[5m])", "Wiederholungen/s")],
            breite=12, hoehe=8,
            beschreibung="Viele Wiederholungen heissen Paketverlust auf dem Weg.")
    return dashboard("platzwart-maschine", "Maschine",
                     "Prozessor, Speicher, Platte und Netz der Maschine. Quelle: node_exporter.", b)


# --- Spielserver -------------------------------------------------------------
def spielserver():
    b = Bau()
    b.reihe("Auf einen Blick")
    b.tafel("Spieler jetzt", "stat", [('sum(platzwart_spieler{stack=~"$stack"})', "Spieler")],
            breite=4, hoehe=4)
    b.tafel("Server laufen", "stat", [('sum(platzwart_server_laeuft{stack=~"$stack"})', "laufen")],
            breite=4, hoehe=4)
    b.tafel("davon schlafend", "stat", [('sum(platzwart_schlaeft{stack=~"$stack"})', "schlafen")],
            breite=4, hoehe=4,
            beschreibung="Leere Server schlafen und geben ihren Speicher frei; der Weckposten holt sie zurueck.")
    b.tafel("Spieldaten gesamt", "stat", [('sum(platzwart_platte_bytes{stack=~"$stack"})', "belegt")],
            breite=4, hoehe=4, einheit="bytes")
    b.tafel("Aelteste Sicherung", "stat",
            [("time() - min(platzwart_sicherung_zeit_sekunden)", "Alter")],
            breite=4, hoehe=4, einheit="s", schwellen=ROT_AB(86400),
            beschreibung="Das aelteste Archiv ueber alle Server. Rot ab 24 Stunden.")
    b.tafel("Erreichbar", "stat", [('sum(probe_success{stack=~"$stack"})', "Ports offen")],
            breite=4, hoehe=4,
            beschreibung="Von DIESER Maschine aus gemessen - ueber Firewall und Anbieter sagt das nichts.")

    b.reihe("Spieler")
    b.tafel("Spieler je Server", "timeseries", [('platzwart_spieler{stack=~"$stack"}', "{{stack}}")],
            stapel=True, beschreibung="Gestapelt: die obere Kante ist die Gesamtzahl.")
    b.tafel("Belegung der Plaetze", "bargauge",
            [('platzwart_spieler{stack=~"$stack"} / platzwart_spieler_max{stack=~"$stack"}', "{{stack}}")],
            einheit="percentunit", max_wert=1, min_wert=0,
            beschreibung="Spieler geteilt durch Plaetze. Dauerhaft voll heisst: mehr Plaetze oder mehr Server.")
    b.tafel("Spielerstunden je Tag", "timeseries",
            [('sum by (stack) (sum_over_time(platzwart_spieler{stack=~"$stack"}[1d])) / 12', "{{stack}}")],
            breite=24, hoehe=7, einheit="h",
            beschreibung="Summe der Messwerte eines Tages, geteilt durch die Messungen je Stunde "
                         "(12 bei fuenf Minuten Abstand) - also grob die gespielten Stunden.")

    b.reihe("Verbrauch je Server")
    b.tafel("Arbeitsspeicher", "timeseries",
            [('platzwart_server_speicher_bytes{stack=~"$stack"}', "{{stack}}")], einheit="bytes")
    b.tafel("Prozessorzeit", "timeseries",
            [('platzwart_server_cpu_prozent{stack=~"$stack"}', "{{stack}}")], einheit="percent",
            beschreibung="Prozent eines Kerns, wie 'docker stats' es zaehlt - ueber 100 % heisst mehrere Kerne.")
    b.tafel("Netz", "timeseries",
            [('rate(platzwart_server_netz_bytes_total{stack=~"$stack",richtung="herein"}[10m])*8', "herein {{stack}}"),
             ('rate(platzwart_server_netz_bytes_total{stack=~"$stack",richtung="hinaus"}[10m])*8', "hinaus {{stack}}")],
            einheit="bps")
    b.tafel("Platte je Server", "timeseries",
            [('platzwart_platte_bytes{stack=~"$stack"}', "{{stack}}")], einheit="bytes", stapel=True,
            beschreibung="Waechst hier eine Linie, weiss man, welches Spiel den Platz frisst. "
                         "Gemessen wird hoechstens stuendlich.")
    b.tafel("Wachstum je Tag", "timeseries",
            [('deriv(platzwart_platte_bytes{stack=~"$stack"}[6h]) * 86400', "{{stack}}")],
            breite=24, hoehe=7, einheit="bytes",
            beschreibung="Hochgerechnet aus den letzten sechs Stunden: So viel kaeme pro Tag dazu.")

    b.reihe("Zustand")
    b.tafel("Laeuft, schlaeft, Auto-Update", "table",
            [('platzwart_server_laeuft{stack=~"$stack"}', ""),
             ('platzwart_schlaeft{stack=~"$stack"}', ""),
             ('platzwart_autoupdate{stack=~"$stack"}', ""),
             ('platzwart_spieler{stack=~"$stack"}', "")],
            breite=12, hoehe=9,
            spalten={"Value #A": "laeuft", "Value #B": "schlaeft",
                     "Value #C": "Auto-Update", "Value #D": "Spieler"})
    b.tafel("Erreichbarkeit je Port", "table",
            [('probe_success{stack=~"$stack"}', ""),
             ('probe_duration_seconds{stack=~"$stack"}', "")],
            breite=12, hoehe=9,
            spalten={"Value #A": "erreichbar", "Value #B": "Antwortzeit (s)"},
            beschreibung="Gemessen von dieser Maschine aus.")
    return dashboard("platzwart-server", "Spielserver",
                     "Spieler, Verbrauch, Platte und Erreichbarkeit je Server. "
                     "Quellen: platzwart-metriken, blackbox.", b,
                     variablen=[auswahl("stack", "platzwart_server_laeuft", titel="Server")])


# --- Container ---------------------------------------------------------------
def container():
    b = Bau()
    b.text("Woher die Zahlen kommen",
           "Diese Seite braucht den Schalter **Container-Tiefenwerte (cAdvisor)** "
           "unter *Module*. Ist er aus, bleiben die Tafeln leer — die Zahlen je "
           "Spielserver stehen dann im Dashboard **Spielserver**, gemessen vom "
           "Sammler auf der Maschine.\n\n"
           "*Needs the cAdvisor switch; without it these panels stay empty and the "
           "per-server numbers live on the Spielserver dashboard.*", hoehe=3)
    b.reihe("Prozessor")
    b.tafel("Prozessorzeit je Container", "timeseries",
            [('sum by (name) (rate(container_cpu_usage_seconds_total{name=~".+",name=~"$container"}[5m])) * 100',
              "{{name}}")],
            einheit="percent", beschreibung="Prozent eines Kerns.")
    b.tafel("Kern gegen Programm", "timeseries",
            [('sum by (name) (rate(container_cpu_system_seconds_total{name=~".+",name=~"$container"}[5m])) * 100', "Kern {{name}}"),
             ('sum by (name) (rate(container_cpu_user_seconds_total{name=~".+",name=~"$container"}[5m])) * 100', "Programm {{name}}")],
            einheit="percent",
            beschreibung="Viel Kernzeit heisst meist Ein-/Ausgabe oder Netz, nicht Rechenarbeit.")

    b.reihe("Speicher")
    b.tafel("Belegt (working set)", "timeseries",
            [('container_memory_working_set_bytes{name=~".+",name=~"$container"}', "{{name}}")],
            einheit="bytes",
            beschreibung="Was der Container wirklich haelt - ohne den Dateicache, den er jederzeit abgeben kann.")
    b.tafel("Anteil an der Grenze", "bargauge",
            [('container_memory_working_set_bytes{name=~".+",name=~"$container"} '
              '/ container_spec_memory_limit_bytes{name=~".+",name=~"$container"} > 0', "{{name}}")],
            einheit="percentunit", max_wert=1, min_wert=0, schwellen=ROT_AB(0.9),
            beschreibung="Naehert sich ein Balken der Eins, wird der Container bald angehalten.")
    b.tafel("Aufteilung", "timeseries",
            [('container_memory_rss{name=~".+",name=~"$container"}', "Programme {{name}}"),
             ('container_memory_cache{name=~".+",name=~"$container"}', "Dateicache {{name}}"),
             ('container_memory_swap{name=~".+",name=~"$container"}', "ausgelagert {{name}}")],
            einheit="bytes")
    b.tafel("Abgewiesene Speicheranforderungen", "timeseries",
            [('rate(container_memory_failcnt{name=~".+",name=~"$container"}[5m])', "{{name}}")],
            beschreibung="Steigt das, stoesst der Container an seine Grenze. "
                         "Ereignisse des Kerns (OOM) kann cAdvisor hier nicht lesen - "
                         "/dev/kmsg ist im Container nicht erlaubt.")

    b.reihe("Platte und Netz")
    b.tafel("Platten-Durchsatz je Container", "timeseries",
            [('sum by (name) (rate(container_fs_reads_bytes_total{name=~".+",name=~"$container"}[5m]))', "lesen {{name}}"),
             ('sum by (name) (rate(container_fs_writes_bytes_total{name=~".+",name=~"$container"}[5m]))', "schreiben {{name}}")],
            einheit="Bps")
    b.tafel("Zugriffe je Sekunde", "timeseries",
            [('sum by (name) (rate(container_fs_reads_total{name=~".+",name=~"$container"}[5m]))', "lesen {{name}}"),
             ('sum by (name) (rate(container_fs_writes_total{name=~".+",name=~"$container"}[5m]))', "schreiben {{name}}")],
            beschreibung="Viele kleine Zugriffe bremsen mehr als wenige grosse.")
    b.tafel("Netz je Container", "timeseries",
            [('sum by (name) (rate(container_network_receive_bytes_total{name=~".+",name=~"$container"}[5m]))*8', "herein {{name}}"),
             ('sum by (name) (rate(container_network_transmit_bytes_total{name=~".+",name=~"$container"}[5m]))*8', "hinaus {{name}}")],
            einheit="bps")
    b.tafel("Verworfene Pakete", "timeseries",
            [('sum by (name) (rate(container_network_receive_packets_dropped_total{name=~".+",name=~"$container"}[5m]))', "herein {{name}}"),
             ('sum by (name) (rate(container_network_transmit_packets_dropped_total{name=~".+",name=~"$container"}[5m]))', "hinaus {{name}}")],
            beschreibung="Sollte flach auf null liegen.")

    b.reihe("Docker")
    b.tafel("Container laufen", "stat",
            [('count(container_last_seen{name=~".+"})', "Container")],
            breite=6, hoehe=5)
    # sum() statt count(... > 0): Mit dem Filter bleibt die Tafel leer, solange
    # NICHTS neu gestartet ist - und "keine Daten" sieht aus wie ein Defekt,
    # nicht wie Ruhe. So steht da eine ehrliche Null.
    # *sum() rather than a filtered count: with the filter the panel is empty
    #  while nothing restarted, and "no data" looks like a fault, not like calm.*
    b.tafel("Neustarts in 24 Stunden", "stat",
            [('sum(changes(container_start_time_seconds{name=~".+"}[24h]))', "Neustarts")],
            breite=6, hoehe=5, schwellen=ROT_AB(1),
            beschreibung="Ein Container, der ohne Grund neu startet, faellt sonst erst auf, "
                         "wenn jemand beim Spielen herausfliegt.")
    b.tafel("Juengster Containerstart", "stat",
            [('time() - max(container_start_time_seconds{name=~".+"})', "her")],
            breite=6, hoehe=5, einheit="s", modus="none",
            beschreibung="Wie lange der letzte Start her ist. Springt der Wert staendig auf null, "
                         "startet irgendetwas in einer Schleife.")
    b.tafel("Verkehr ueber die Docker-Bruecken", "timeseries",
            [('sum(rate(node_network_receive_bytes_total{device=~"docker.*|br-.*"}[5m]))*8', "herein"),
             ('sum(rate(node_network_transmit_bytes_total{device=~"docker.*|br-.*"}[5m]))*8', "hinaus")],
            breite=6, hoehe=5, einheit="bps",
            beschreibung="Alles, was zwischen Maschine und Containern laeuft - im Wesentlichen die Spieler.")
    b.tafel("Laufzeit je Container", "timeseries",
            [('time() - container_start_time_seconds{name=~".+",name=~"$container"}', "{{name}}")],
            breite=12, hoehe=7, einheit="s",
            beschreibung="Faellt eine Linie auf null, ist der Container neu gestartet. "
                         "Wiederholt sich das, laeuft er in eine Schleife.")
    # Keine Tafel fuer die Schreibschicht je Container: cAdvisor liefert
    # container_fs_usage_bytes hier NUR maschinenweit (id="/"), ohne Namen -
    # gemessen, 41 Zeitreihen und keine einzige mit Etikett "name". Eine Tafel
    # dafuer waere dauerhaft leer. Was jeder Server auf der Platte belegt, misst
    # der Sammler und zeigt das Dashboard "Sicherung und Platte".
    # *No per-container write-layer panel: cAdvisor here exports fs usage only
    #  machine-wide, without a name label - the panel would stay empty forever.*
    b.tafel("Prozesse je Container", "timeseries",
            [('container_tasks_state{name=~".+",name=~"$container",state="running"}', "{{name}}")],
            breite=12, hoehe=7,
            beschreibung="Steigt die Zahl unaufhoerlich, startet ein Server Kindprozesse, die nicht enden.")

    b.reihe("Uebersicht")
    b.tafel("Laufzeit und Verbrauch", "table",
            [('time() - container_start_time_seconds{name=~".+",name=~"$container"}', ""),
             ('container_memory_working_set_bytes{name=~".+",name=~"$container"}', ""),
             ('container_spec_memory_limit_bytes{name=~".+",name=~"$container"}', ""),
             ('container_tasks_state{name=~".+",name=~"$container",state="running"}', "")],
            breite=24, hoehe=9,
            spalten={"Value #A": "Laufzeit (s)", "Value #B": "Speicher", 
                     "Value #C": "Speichergrenze", "Value #D": "laufende Aufgaben"},
            beschreibung="Eine kurze Laufzeit bei einem Server, der laufen sollte, heisst: er startet staendig neu.")
    return dashboard("platzwart-container", "Docker und Container",
                     "Prozessor, Speicher, Platte und Netz je Container, dazu die Docker-Sicht. "
                     "Quelle: cAdvisor (Schalter 'Container-Tiefenwerte').", b,
                     variablen=[auswahl("container", "container_last_seen", "name", titel="Container")])


# --- Web ---------------------------------------------------------------------
def web():
    b = Bau()
    b.text("Woher die Zahlen kommen",
           "Diese Seite braucht den Schalter **Caddy-Zugriffe** unter *Module*. "
           "Caddy zählt Anfragen nur, wenn in der Caddyfile `servers { metrics }` "
           "steht — sonst bleiben alle Tafeln ausser *Neuladen* leer.\n\n"
           "*Needs the Caddy switch; Caddy only counts requests with the `metrics` "
           "option set.*", hoehe=3)
    b.reihe("Anfragen")
    b.tafel("Anfragen je Sekunde", "timeseries",
            [("sum by (handler) (rate(caddy_http_requests_total[5m]))", "{{handler}}")],
            beschreibung="Nach Art der Zustellung: reverse_proxy ist das Panel, file_server die Statusseite.")
    b.tafel("Antwortcodes", "timeseries",
            [("sum by (code) (rate(caddy_http_requests_total[5m]))", "{{code}}")],
            stapel=True,
            beschreibung="401 ist normal: So antwortet die Statistik ohne Anmeldung. "
                         "5xx ist es nicht.")
    b.tafel("Antwortzeit", "timeseries",
            [('histogram_quantile(0.5, sum by (le) (rate(caddy_http_request_duration_seconds_bucket[5m])))', "Mitte (p50)"),
             ('histogram_quantile(0.9, sum by (le) (rate(caddy_http_request_duration_seconds_bucket[5m])))', "p90"),
             ('histogram_quantile(0.99, sum by (le) (rate(caddy_http_request_duration_seconds_bucket[5m])))', "p99")],
            einheit="s",
            beschreibung="Nicht der Durchschnitt: Der verdeckt genau die langsamen Anfragen, um die es geht.")
    b.tafel("Gleichzeitig offen", "timeseries",
            [("sum(caddy_http_requests_in_flight)", "offen")],
            beschreibung="Bleibt das oben stehen, haengt etwas hinter dem Proxy.")

    b.reihe("Groessen und Zustand")
    b.tafel("Antwortgroesse", "timeseries",
            [('histogram_quantile(0.9, sum by (le) (rate(caddy_http_response_size_bytes_bucket[5m])))', "p90"),
             ('sum(rate(caddy_http_response_size_bytes_sum[5m]))', "Durchsatz (B/s)")],
            einheit="bytes")
    b.tafel("Upstreams gesund", "stat",
            [("sum(caddy_reverse_proxy_upstreams_healthy)", "gesund")],
            breite=4, hoehe=6, schwellen=GRUEN_ROT,
            beschreibung="Das Panel und das Webterminal hinter Caddy.")
    b.tafel("Letztes Neuladen", "stat",
            [("time() - caddy_config_last_reload_success_timestamp_seconds", "her")],
            breite=4, hoehe=6, einheit="s", modus="none")
    b.tafel("Neuladen erfolgreich", "stat",
            [("caddy_config_last_reload_successful", "Zustand")],
            breite=4, hoehe=6, schwellen=GRUEN_ROT,
            beschreibung="Null heisst: Caddy laeuft mit einer aelteren Konfiguration weiter.")
    b.reihe("Zertifikat")
    b.tafel("Laeuft ab in", "stat",
            [("(min(probe_ssl_earliest_cert_expiry) - time()) / 86400", "Tage")],
            breite=6, hoehe=5, einheit="d", schwellen=[{"color": "red", "value": None},
                                                       {"color": "orange", "value": 14},
                                                       {"color": "green", "value": 21}],
            beschreibung="Caddy erneuert bei 30 Tagen Restlaufzeit. Faellt der Wert darunter und "
                         "bleibt dort, erneuert es nicht mehr - und das faellt sonst erst auf, "
                         "wenn das Zertifikat abgelaufen ist.")
    b.tafel("Statusseite erreichbar", "stat", [("probe_success{job=\"zertifikat\"}", "Zustand")],
            breite=6, hoehe=5, schwellen=GRUEN_ROT,
            beschreibung="Gemessen von dieser Maschine aus - ueber den Weg von aussen sagt das nichts.")
    b.tafel("Antwortzeit der Statusseite", "timeseries",
            [("probe_duration_seconds{job=\"zertifikat\"}", "gesamt"),
             ("probe_http_duration_seconds{job=\"zertifikat\"}", "{{phase}}")],
            breite=12, hoehe=5, einheit="s",
            beschreibung="Aufgeschluesselt nach Verbindungsaufbau, TLS und Uebertragung.")
    return dashboard("platzwart-web", "Web und Zertifikat",
                     "Anfragen, Antwortzeiten und Zustand von Caddy. "
                     "Quelle: Caddys Verwaltungsschnittstelle ueber platzwart-metriken.", b)


# --- Netz und Erreichbarkeit -------------------------------------------------
def netz():
    b = Bau()
    b.reihe("Erreichbarkeit der Spielports")
    b.tafel("Erreichbar", "bargauge",
            [('probe_success{stack=~".+"}', "{{stack}}:{{port}}")],
            breite=12, hoehe=8, max_wert=1, min_wert=0, schwellen=GRUEN_ROT,
            beschreibung="1 = der Port nimmt eine Verbindung an. Gemessen VON DIESER MASCHINE - "
                         "ueber Firewall und Anbieter sagt das nichts.")
    b.tafel("Antwortzeit der Probe", "timeseries",
            [('probe_duration_seconds{stack=~".+"}', "{{stack}}:{{port}}")],
            breite=12, hoehe=8, einheit="s")
    b.tafel("Ausfaelle ueber die Zeit", "timeseries",
            [('probe_success{stack=~".+"}', "{{stack}}:{{port}}")],
            breite=24, hoehe=7, max_wert=1, min_wert=0,
            beschreibung="Jeder Einbruch auf null ist ein Port, der gerade nichts annahm.")

    b.reihe("Tailscale")
    b.tafel("Verbunden", "stat", [("platzwart_tailscale_verbunden", "Zustand")],
            breite=6, hoehe=5, schwellen=GRUEN_ROT,
            beschreibung="Ueber das Tailnet laeuft die Sicherung - und der Rueckweg, wenn SSH zu ist.")
    b.tafel("Gegenstellen erreichbar", "stat",
            [("platzwart_tailscale_peers_online", "online"), ("platzwart_tailscale_peers", "bekannt")],
            breite=6, hoehe=5)
    b.tafel("Durchsatz im Tailnet", "timeseries",
            [('rate(platzwart_tailscale_bytes_total{richtung="herein"}[10m])*8', "herein"),
             ('rate(platzwart_tailscale_bytes_total{richtung="hinaus"}[10m])*8', "hinaus")],
            breite=12, hoehe=5, einheit="bps",
            beschreibung="Steigt hier nachts etwas an, ist das die Sicherung.")

    b.reihe("Schnittstellen der Maschine")
    b.tafel("Durchsatz", "timeseries",
            [('rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "herein {{device}}"),
             ('rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*"}[5m])*8', "hinaus {{device}}")],
            einheit="bps")
    b.tafel("Docker-Bruecken", "timeseries",
            [('rate(node_network_receive_bytes_total{device=~"docker.*|br-.*"}[5m])*8', "herein {{device}}"),
             ('rate(node_network_transmit_bytes_total{device=~"docker.*|br-.*"}[5m])*8', "hinaus {{device}}")],
            einheit="bps",
            beschreibung="Verkehr zu den Containern - also im Wesentlichen die Spieler.")
    return dashboard("platzwart-netz", "Netz und Erreichbarkeit",
                     "Proben der Spielports, Tailnet und Schnittstellen. "
                     "Quellen: blackbox (Schalter 'Erreichbarkeitsprobe'), "
                     "platzwart-metriken (Schalter 'Tailscale'), node_exporter.", b)


# --- Sicherung und Platte ----------------------------------------------------
def sicherung():
    b = Bau()
    b.reihe("Auf einen Blick")
    b.tafel("Juengste Sicherung", "stat",
            [("time() - max(platzwart_sicherung_zeit_sekunden)", "her")],
            breite=6, hoehe=4, einheit="s", schwellen=ROT_AB(3600))
    b.tafel("Aelteste Sicherung", "stat",
            [("time() - min(platzwart_sicherung_zeit_sekunden)", "her")],
            breite=6, hoehe=4, einheit="s", schwellen=ROT_AB(86400),
            beschreibung="Der Server, dessen Archiv am laengsten zurueckliegt. Rot ab 24 Stunden.")
    b.tafel("Archive gesamt", "stat",
            [("sum(platzwart_sicherung_groesse_bytes)", "dedupliziert")],
            breite=6, hoehe=4, einheit="bytes",
            beschreibung="Summe der letzten Archive - was sie im Depot wirklich neu belegt haben.")
    b.tafel("Spieldaten gesamt", "stat", [("sum(platzwart_platte_bytes)", "belegt")],
            breite=6, hoehe=4, einheit="bytes")

    b.reihe("Je Server")
    b.tafel("Alter der Sicherung", "timeseries",
            [("time() - platzwart_sicherung_zeit_sekunden", "{{archiv}}")],
            einheit="s",
            beschreibung="Springt eine Linie nach oben und bleibt oben, sichert dieser Server nicht mehr. "
                         "Die Saegezaehne sind der Viertelstundenlauf.")
    b.tafel("Groesse des letzten Archivs", "timeseries",
            [("platzwart_sicherung_groesse_bytes", "{{archiv}}")], einheit="bytes",
            beschreibung="Faellt eine Linie ploetzlich auf fast null, ist das Archiv hohl - "
                         "genau der Fall, den die Sicherung selbst meldet.")
    b.tafel("Platte je Server", "timeseries", [("platzwart_platte_bytes", "{{stack}}")],
            einheit="bytes", stapel=True)
    b.tafel("Wachstum je Tag", "timeseries",
            [("deriv(platzwart_platte_bytes[6h]) * 86400", "{{stack}}")],
            einheit="bytes",
            beschreibung="Hochgerechnet aus sechs Stunden. Die Summe davon zeigt, wie lange die Platte noch reicht.")

    b.reihe("Platz auf der Maschine")
    b.tafel("Frei, mit Hochrechnung auf 30 Tage", "timeseries",
            [('node_filesystem_avail_bytes{mountpoint="/"}', "frei"),
             ('predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[12h], 30*24*3600)', "in 30 Tagen")],
            breite=12, hoehe=8, einheit="bytes")
    b.tafel("Messwertdatenbank", "timeseries",
            [("prometheus_tsdb_storage_blocks_bytes", "Bloecke auf der Platte"),
             ("prometheus_tsdb_head_series", "Zeitreihen im Kopf (rechte Skala)")],
            breite=12, hoehe=8, einheit="bytes",
            beschreibung="Die Statistik selbst. Die Obergrenze steht unter Module in den Einstellungen.")
    return dashboard("platzwart-sicherung", "Sicherung und Platte",
                     "Alter und Groesse der Borg-Archive, Platte je Server und Hochrechnung. "
                     "Quelle: platzwart-metriken aus /var/lib/spiele-sicherung.groessen.", b,
                     zeitraum="now-7d")


# --- Die Messung selbst ------------------------------------------------------
def selbst():
    b = Bau()
    b.text("Wozu diese Seite",
           "Ein Netz, das sich heil meldet und nichts fängt, ist schlimmer als keins. "
           "Hier steht, ob die Messung selbst noch arbeitet: welche Ziele antworten, "
           "wann der Sammler zuletzt lief, wie viel die Datenbank hält.\n\n"
           "*A safety net that reports itself intact while catching nothing is worse "
           "than none: this page shows whether the measurement itself still works.*",
           hoehe=3)
    b.reihe("Ziele")
    b.tafel("Antworten alle Ziele?", "stat", [("sum(up)", "antworten"), ("count(up)", "insgesamt")],
            breite=6, hoehe=5, schwellen=GRUEN_ROT)
    b.tafel("Ziele je Auftrag", "table", [("up", "")], breite=18, hoehe=5,
            spalten={"Value": "antwortet"},
            beschreibung="0 heisst: Prometheus erreicht diese Quelle nicht.")
    b.tafel("Dauer eines Abrufs", "timeseries",
            [("scrape_duration_seconds", "{{job}} {{instance}}")], einheit="s",
            beschreibung="Wird ein Abruf langsamer als sein Abstand, fehlen Messwerte.")
    b.tafel("Zeitreihen je Abruf", "timeseries",
            [("scrape_samples_scraped", "{{job}}")],
            beschreibung="Faellt eine Linie, liefert die Quelle weniger als vorher.")

    b.reihe("Der Sammler auf der Maschine")
    b.tafel("Letzter Lauf", "stat",
            [("time() - platzwart_metriken_lauf_zeit_sekunden", "her")],
            breite=6, hoehe=5, einheit="s", schwellen=ROT_AB(900),
            beschreibung="Der Zeitgeber laeuft alle fuenf Minuten (einstellbar). "
                         "Rot ab einer Viertelstunde.")
    b.tafel("Dauer des Laufs", "timeseries",
            [("platzwart_metriken_dauer_sekunden", "Dauer")], breite=9, hoehe=5, einheit="s",
            beschreibung="Springt sie, misst er gerade die Platte - das tut er hoechstens stuendlich.")
    b.tafel("Alter der Textdateien", "timeseries",
            [("time() - node_textfile_mtime_seconds", "{{file}}")], breite=9, hoehe=5, einheit="s",
            beschreibung="Bleibt eine Datei alt, schreibt der Sammler sie nicht mehr.")

    b.reihe("Prometheus")
    b.tafel("Aufgenommene Messwerte", "timeseries",
            [("rate(prometheus_tsdb_head_samples_appended_total[5m])", "Messwerte/s")])
    b.tafel("Zeitreihen im Kopf", "timeseries",
            [("prometheus_tsdb_head_series", "Zeitreihen")],
            beschreibung="Waechst das unaufhoerlich, erzeugt eine Quelle staendig neue Etiketten.")
    b.tafel("Platte der Datenbank", "timeseries",
            [("prometheus_tsdb_storage_blocks_bytes", "Bloecke")], einheit="bytes")
    b.tafel("Abgewiesene Messwerte", "timeseries",
            [("rate(prometheus_target_scrapes_sample_out_of_order_total[5m])", "ausser der Reihe"),
             ("rate(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m])", "doppelter Zeitstempel")],
            beschreibung="Sollte flach auf null liegen.")
    return dashboard("platzwart-selbst", "Die Messung selbst",
                     "Ziele, Sammler und Prometheus. Zeigt, ob die Statistik noch misst.", b)


def server_vorlage():
    """Die Vorlage fuer EIN Spielserver-Dashboard. __STACK__ setzt
    modul-verwalten auf der Maschine ein - der Bauplan steht hier, welche Server
    es gibt, weiss nur die Maschine.

    Die Marke heisst bewusst nicht @@STACK@@: So sehen die Platzhalter aus, die
    beim Ausrollen aus konfiguration.env kommen, und vollstaendigkeit.sh
    verlangt fuer jeden von ihnen eine Erklaerung in der Vorlage - zu Recht.
    *Deliberately not @@STACK@@: that is the shape of the rollout placeholders,
     and the completeness check demands an explanation for each of those.*

    *The template for a single server's dashboard; the machine fills in the name,
     because only it knows which servers exist.*
    """
    b = Bau()
    S = '{stack="__STACK__"}'
    C = '{name="__STACK__"}'
    b.reihe("__STACK__ auf einen Blick")
    b.tafel("Spieler", "stat", [(f"platzwart_spieler{S}", "jetzt")], breite=4, hoehe=4)
    b.tafel("Plaetze", "stat", [(f"platzwart_spieler_max{S}", "Plaetze")], breite=4, hoehe=4)
    b.tafel("Laeuft", "stat", [(f"platzwart_server_laeuft{S}", "Zustand")],
            breite=4, hoehe=4, schwellen=GRUEN_ROT)
    b.tafel("Schlaeft", "stat", [(f"platzwart_schlaeft{S}", "Zustand")], breite=4, hoehe=4,
            beschreibung="1 = im Leerlauf schlafen gelegt; der Weckposten holt ihn beim Beitritt zurueck.")
    b.tafel("Speicher", "stat", [(f"platzwart_server_speicher_bytes{S}", "belegt")],
            breite=4, hoehe=4, einheit="bytes")
    b.tafel("Sicherung her", "stat",
            [('time() - platzwart_sicherung_zeit_sekunden{archiv="__STACK__"}', "Alter")],
            breite=4, hoehe=4, einheit="s", schwellen=ROT_AB(86400))

    b.reihe("Spieler und Verbrauch")
    b.tafel("Spieler", "timeseries",
            [(f"platzwart_spieler{S}", "Spieler"), (f"platzwart_spieler_max{S}", "Plaetze")],
            beschreibung="Beruehrt die untere Linie die obere, war der Server voll.")
    b.tafel("Arbeitsspeicher", "timeseries",
            [(f"platzwart_server_speicher_bytes{S}", "belegt"),
             (f'container_spec_memory_limit_bytes{C} > 0', "Grenze")],
            einheit="bytes",
            beschreibung="Die Grenze kommt von cAdvisor; ohne diesen Schalter fehlt die zweite Linie.")
    b.tafel("Prozessorzeit", "timeseries", [(f"platzwart_server_cpu_prozent{S}", "Prozent eines Kerns")],
            einheit="percent")
    b.tafel("Netz", "timeseries",
            [(f'rate(platzwart_server_netz_bytes_total{{stack="__STACK__",richtung="herein"}}[10m])*8', "herein"),
             (f'rate(platzwart_server_netz_bytes_total{{stack="__STACK__",richtung="hinaus"}}[10m])*8', "hinaus")],
            einheit="bps")

    b.reihe("Platte und Sicherung")
    b.tafel("Spieldaten", "timeseries", [(f"platzwart_platte_bytes{S}", "belegt")], einheit="bytes")
    b.tafel("Wachstum je Tag", "timeseries",
            [(f"deriv(platzwart_platte_bytes{S}[6h]) * 86400", "hochgerechnet")], einheit="bytes")
    b.tafel("Groesse des letzten Archivs", "timeseries",
            [('platzwart_sicherung_groesse_bytes{archiv="__STACK__"}', "dedupliziert")], einheit="bytes",
            beschreibung="Faellt die Linie ploetzlich auf fast null, ist das Archiv hohl.")
    b.tafel("Alter der Sicherung", "timeseries",
            [('time() - platzwart_sicherung_zeit_sekunden{archiv="__STACK__"}', "Alter")], einheit="s",
            beschreibung="Die Saegezaehne sind der Viertelstundenlauf. Eine Treppe nach oben ist ein Ausfall.")

    b.reihe("Erreichbarkeit und Container")
    b.tafel("Ports erreichbar", "timeseries",
            [(f'probe_success{S}', "{{port}}")], min_wert=0, max_wert=1,
            beschreibung="Von dieser Maschine aus gemessen (Schalter 'Erreichbarkeitsprobe').")
    b.tafel("Laufzeit des Containers", "timeseries",
            [(f"time() - container_start_time_seconds{C}", "Laufzeit")], einheit="s",
            beschreibung="Faellt sie auf null, ist der Container neu gestartet (Schalter 'cAdvisor').")
    b.tafel("Platten-Zugriffe des Containers", "timeseries",
            [(f"rate(container_fs_reads_bytes_total{C}[5m])", "lesen"),
             (f"rate(container_fs_writes_bytes_total{C}[5m])", "schreiben")], einheit="Bps")
    b.tafel("Auto-Update", "stat", [(f"platzwart_autoupdate{S}", "Zustand")], breite=6, hoehe=6,
            beschreibung="1 = das Spiel wird automatisch aktualisiert.")
    b.reihe("Protokoll")
    b.tafel("Was dieser Server schreibt", "logs",
            [('{job="platzwart", stack="__STACK__"}', "")],
            breite=24, hoehe=12, quelle=LOKI,
            beschreibung="Derselbe Zeitraum wie die Kurven darueber - damit man zu einem Ausschlag "
                         "die Zeilen von genau diesem Moment sieht. Braucht den Schalter "
                         "'Protokolle sammeln'.")
    return dashboard("platzwart-server-__STACK__", "Server: __STACK__",
                     "Alles zu einem einzelnen Spielserver. Erzeugt je Server von modul-verwalten.",
                     b)


def protokolle():
    b = Bau()
    b.text("Woher die Zeilen kommen",
           "Diese Seite braucht den Schalter **Protokolle sammeln** unter *Module*. "
           "`platzwart-protokolle` folgt auf der Maschine den Ausgaben aller Container, "
           "**schwärzt bekannte Passwortmuster** und schiebt die Zeilen nach Loki — ohne "
           "Docker-Socket in einem Container.\n\n"
           "*Needs the log switch; the shipper follows every container's output on the "
           "host, redacts known password patterns and pushes to Loki — no Docker socket "
           "in a container.*", hoehe=3)
    b.reihe("Menge und Auffaelliges")
    b.tafel("Zeilen je Sekunde", "timeseries",
            [('sum by (stack) (rate({job="platzwart"}[5m]))', "{{stack}}")],
            breite=16, hoehe=7, quelle=LOKI, stapel=True,
            beschreibung="Ein Server, der ploetzlich zehnmal so viel schreibt, hat ein Problem - "
                         "oft bevor er ausfaellt.")
    b.tafel("Auffaellige Zeilen (1 h)", "stat",
            [('sum(count_over_time({job="platzwart"} |~ `(?i)error|exception|fatal|panic` [1h]))',
              "Treffer")],
            breite=8, hoehe=7, quelle=LOKI, schwellen=ROT_AB(50),
            beschreibung="Fehler, Ausnahmen, Abstuerze - ein grober Filter, bewusst ohne Anspruch "
                         "auf Vollstaendigkeit.")
    b.reihe("Alles, was geschrieben wurde")
    b.tafel("Protokoll", "logs", [('{job="platzwart", stack=~"$stack"}', "")],
            breite=24, hoehe=14, quelle=LOKI,
            beschreibung="Oben die Auswahl, oben rechts der Zeitraum. Suchen mit einem Filter, "
                         "zum Beispiel: {job=\"platzwart\"} |= \"Verbindung\"")
    b.reihe("Nur das Auffaellige")
    b.tafel("Fehler und Ausnahmen", "logs",
            [('{job="platzwart", stack=~"$stack"} |~ `(?i)error|exception|fatal|panic`', "")],
            breite=24, hoehe=12, quelle=LOKI)
    return dashboard("platzwart-protokolle", "Protokolle",
                     "Die Ausgaben aller Container, durchsuchbar. Quelle: Loki "
                     "(Schalter 'Protokolle sammeln').", b,
                     variablen=[auswahl("stack", '{job="platzwart"}', titel="Server", quelle=LOKI)])


DASHBOARDS = [("maschine.json", maschine), ("spielserver.json", spielserver),
              ("container.json", container), ("web.json", web),
              ("netz.json", netz), ("sicherung.json", sicherung),
              ("selbst.json", selbst), ("protokolle.json", protokolle)]
# Die Vorlage liegt NICHT im Dashboard-Ordner: Grafana wuerde sie sonst mit
# __STACK__ im Titel laden - ein Dashboard fuer einen Server, den es nicht gibt.
# *The template lives outside the dashboards directory, or Grafana would load it
#  with the placeholder still in its title.*
VORLAGE = (REPO / "etc/module/statistik/grafana/server-vorlage.json", server_vorlage)


# --- Datenpruefung gegen die laufende Instanz --------------------------------
def ausdruecke_sammeln():
    """[(datei, tafel, expr)] - jede Abfrage, die in einer Tafel steht."""
    raus = []
    for name, bau in DASHBOARDS + [("server-vorlage.json", server_vorlage)]:
        d = bau()
        for t in d["panels"]:
            if (t.get("datasource") or {}).get("type") == "loki":
                continue  # LogQL, nicht PromQL - gehoert nicht in diese Pruefung
            for z in t.get("targets", []):
                # Auswahlvariablen durch "alles" ersetzen - so laesst sich die
                # Abfrage ausserhalb von Grafana ausfuehren.
                # Auswahlvariablen und den Platzhalter der Server-Vorlage durch
                # "irgendetwas" ersetzen - sonst liesse sich die Abfrage
                # ausserhalb von Grafana nicht ausfuehren.
                expr = re.sub(r"\$[a-z]+", ".*", z["expr"]).replace("__STACK__", ".*")
                # Aus name="x" wird dabei ein Vergleich, der nie passt.
                expr = expr.replace('="' + ".*" + '"', '=~"' + ".*" + '"')
                raus.append((name, t["title"], expr))
    return raus


def daten_pruefen(ziel: str) -> int:
    fragen = ausdruecke_sammeln()
    # Alle Abfragen in EINEM Aufruf: je Abfrage eine eigene SSH-Sitzung waere
    # hundertmal Anmelden fuer hundert Zahlen.
    # Der abschliessende Zeilenumbruch ist Pflicht: "read" gibt bei einer
    # letzten Zeile ohne ihn einen Fehlerwert zurueck, die Schleife endet - und
    # die letzte Abfrage fiel stumm heraus (136 Antworten auf 137 Fragen).
    # *The trailing newline is required: without it "read" fails on the last
    #  line and the loop drops it silently.*
    liste = "".join(urllib.parse.quote(e, safe="") + "\n" for _, _, e in fragen)
    # Der Weg durch GRAFANA, nicht an ihm vorbei: Genau daran haette sich ein
    # Fehler gezeigt, den die Abfrage direkt bei Prometheus verdeckte - die
    # Datenquelle zeigte auf einen Containernamen, den es nicht mehr gab. Die
    # Tafeln waren leer, und die Pruefung sagte "alles da" (#275).
    # Genau EINE Zeile je Abfrage - "{" heisst Daten, "]" heisst leer.
    # *Through Grafana rather than past it: querying Prometheus directly hid a
    #  broken datasource - panels empty while the check said all good.*
    befehl = ("while read -r q; do "
              "a=$(curl -s -H 'X-Webauth-User: pruefung' -H 'X-Webauth-Role: Admin' "
              "\"http://127.0.0.1:19030/statistik/api/datasources/proxy/uid/"
              "platzwart-prometheus/api/v1/query?query=$q\" "
              "| tr -d '\\n' | sed 's/.*\"result\":\\[//' | cut -c1-1); "
              "echo \"$a\"; done")
    p = subprocess.run(["ssh", ziel, befehl], input=liste, capture_output=True, text=True)
    if p.returncode != 0:
        print("  Abfrage nicht moeglich:", (p.stderr or p.stdout).strip()[-300:])
        return 1
    antworten = p.stdout.splitlines()
    if len(antworten) != len(fragen):
        print(f"  {len(antworten)} Antworten auf {len(fragen)} Abfragen - Abbruch")
        return 1
    leer = [(d, t, e) for (d, t, e), a in zip(fragen, antworten) if a.strip() == "]"]
    letzte = None
    for d, t, e in leer:
        if d != letzte:
            print(f"  {d}:")
            letzte = d
        print(f"    ohne Daten: {t} — {e[:100]}")
    print(f"  {len(fragen) - len(leer)} von {len(fragen)} Abfragen liefern Daten.")
    return 1 if leer else 0


def main():
    if "--daten" in sys.argv:
        i = sys.argv.index("--daten")
        if len(sys.argv) <= i + 1:
            print("  --daten braucht ein SSH-Ziel")
            return 1
        return daten_pruefen(sys.argv[i + 1])
    pruefen = "--pruefen" in sys.argv
    ZIEL.mkdir(parents=True, exist_ok=True)
    schlecht = 0
    for datei, bau in [(ZIEL / n, b) for n, b in DASHBOARDS] + [VORLAGE]:
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
