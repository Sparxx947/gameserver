# 12 — Module und die Statistikseite

Zwei Dinge auf einmal: **Module** — optionale Dienste, die sich nachinstallieren
lassen — und das erste davon, die **Statistik** mit Prometheus und Grafana.

> *Two things at once: modules — optional services that can be installed later —
> and the first of them, statistics with Prometheus and Grafana.*

---

## Warum Module keine Spiele sind

Der Spielekatalog bringt alles mit, was ein Spielserver braucht: ein
gewürfeltes Beitrittspasswort, einen DNS-Namen, einen Kanal auf TeamSpeak und
Discord, Spielerzählung, eine Endsicherung vor dem Entfernen — und die Regel,
dass der Port erst nach dem bestätigten Passwort aufgeht.

**Und sie liegen woanders.** Module stehen unter `/opt/module`, ihre Daten unter
`/srv/module` — nicht unter `/opt/stacks`, `/srv/games` oder `/srv/dienste`. Der
Grund ist gemessen: Bei der ersten echten Installation lag das Modul in
`/opt/stacks`, und damit erschien es überall, wo Spielserver gezählt werden — in
der Übersicht des Panels als Karte „gestoppt" (seine Container heißen
`statistik-prometheus`, nie wie der Stack), in den eigenen Metriken als Server,
der immer aus ist, und im Blickfeld von Verlauf, Wache, Leerlauf und
Auto-Update. Die Sicherung wiederum geht `/srv/games` und `/srv/dienste` durch;
ein Stack, dessen Inhalt ausgeschlossen ist, erzeugt ein fast leeres Archiv —
also genau das, was die Plausibilitätsprüfung melden soll (#263).

**Gesichert wird ein Modul deshalb nicht**, und das ist kein Verlust: Die
Dashboards und die Datenquelle kommen aus dem Repositorium, die Benutzer aus dem
Panel, und die Messwerte sind Messwerte. Eine Zeitreihendatenbank in jeder
Vollsicherung wäre das größte Archiv im Depot und das am wenigsten wertvolle.

Ein Statistikdienst braucht **nichts davon**. Ihn durch den Spielweg zu
schicken hieße, dort Ausnahmen einzubauen: „wenn kein Spiel, dann kein
Passwort, dann kein Port, dann kein Kanal". Genau das schließt
[CLAUDE.md](../CLAUDE.md) für neue Fähigkeiten aus — eine neue Aktion bekommt
eine eigene Prüfung, nicht eine gelockerte bestehende (Grenze 2). Also ein
zweiter, kleiner Weg mit eigener Liste:

| | Spiele | Module |
|---|---|---|
| Liste | `/etc/spiele-katalog.json` (179) | `/etc/module-katalog.json` (1) |
| Werkzeug | `spiel-verwalten` | `modul-verwalten` |
| Brücke | `panel-aktion installieren …` | `panel-aktion modul …` |
| Verzeichnis | `/opt/stacks/<name>` | `/opt/module/<name>` |
| Daten | `/srv/games/<name>` | `/srv/module/<name>` |
| Beitrittspasswort, DNS-Name, Kanal, Spielerzählung | ja | **nein** |
| Ports nach außen | ja, nach bestätigtem Passwort (E23, E26) | **keine** — alles auf `127.0.0.1` |
| Zugang | Spieler über den Spielport | Menschen über das Panel und seine Anmeldung |

> *Why modules are not games: the game catalogue brings a rolled join password,
> a DNS name, channels, player counting, a final backup and the rule that the
> port opens only after a confirmed password. A statistics service needs none of
> it, and routing it through the game path would mean building exceptions into
> exactly the code that must not have them (boundary 2). Hence a second, small
> path with its own list, tool, bridge action and data directory — and no
> outward ports at all.*

---

## Der Modulkatalog

`etc/module-katalog.json` beschreibt je Modul, was es kostet, wohin es gehört
und **was sich daran schalten lässt**:

| Feld | Bedeutung |
|---|---|
| `schluessel`, `name`, `kurz` | Name im Panel |
| `mem_gb`, `platte_gb` | Bedarf; die Installation bricht ab, wenn danach weniger als 2 GB Speicher bzw. 10 GB Platte frei blieben |
| `daten`, `unterordner` | wohin die Daten gehören (`/srv/module/…`) |
| `ports` | veröffentlichte Ports — beim Statistik-Modul genau einer, auf `127.0.0.1` |
| `route`, `ziel`, `csp`, `rolle` | Pfad im Panel, Ziel dahinter, Kopfzeilensatz, wer ihn sehen darf |
| `schalter` | Name, Titel, Beschreibung, Vorgabe, Art (`profil`, `sammler`, `grafana`) und — wo nötig — eine **Warnung** |
| `einstellungen` | Name, Titel, erlaubte Werte, Vorgabe |

Die Positivliste ist damit die Datei selbst: Was nicht im Katalog steht, kann
die Oberfläche nicht schalten, und `modul-verwalten` weist jeden Wert ab, der
nicht in der Liste des Eintrags steht.

> *The module catalogue describes per module what it costs, where it belongs and
> what can be toggled. The allow-list is the file itself: the panel cannot set
> what is not listed, and the manager rejects any value outside an entry's list.*

---

## Das Statistik-Modul

Drei Container, ein Sammler auf der Maschine:

| Teil | Aufgabe | Port |
|---|---|---|
| **Prometheus** | speichert die Messwerte | keiner nach außen, nur im compose-Netz |
| **Grafana** | zeigt sie | `127.0.0.1:19030` — davor steht Caddy |
| **node_exporter** | misst die Maschine: Last, Speicher, Platte, Netz, I/O, alle 30 s | keiner |
| **`platzwart-metriken`** | misst den Platzwart: Server, Spieler, Sicherungen, Platte je Spiel | — (schreibt Dateien) |

> *The statistics module: three containers and one collector on the machine —
> Prometheus stores the readings, Grafana shows them behind Caddy on localhost,
> node_exporter measures the machine every 30 seconds, and `platzwart-metriken`
> measures the Platzwart itself: servers, players, backups and disk per game.*

### Zugang: eine Anmeldung, kein zweites Passwort

```
Browser → Caddy  /statistik*  ──forward_auth──→  Panel  /auth-modul?modul=statistik
                     │                                   │ 204 + X-Webauth-User + X-Webauth-Role
                     └────────────reverse_proxy──────────→ Grafana (127.0.0.1:19030)
```

Caddy fragt **vor jedem Aufruf** beim Panel nach. Das Panel prüft die Sitzung
und die Rolle aus dem Katalog (`verwalten`) und gibt Benutzernamen und Rolle als
Kopfzeile zurück; Grafana meldet den Benutzer damit selbst an
(*auth proxy*) und legt ihn beim ersten Mal an. Grafanas eigenes
Anmeldeformular und Basic Auth sind **aus** — sie wären ein zweiter Weg hinein,
an der Anmeldung des Panels vorbei. Nachgemessen: ohne Kopfzeile antwortet
Grafana mit `401`, und das eingebaute Konto `admin` mit dem Standardpasswort
kommt nicht durch.

Die Rollen bilden sich so ab: `admin` → Grafana-`Admin`, `verwalten` →
Grafana-`Viewer`. Ein Viewer sieht die Dashboards (`200`), darf aber weder die
Benutzerliste (`403`) noch die Datenquelle ändern — nachgemessen.

Die Route selbst steht in `/etc/caddy/module.conf`, erzeugt von
`modul-verwalten` und von der Caddyfile fest eingebunden. Ohne installiertes
Modul ist die Datei leer.

> *Access: Caddy asks the panel before every request; the panel checks session
> and the role from the catalogue and returns the user name and a role as
> headers, so Grafana logs the user in itself and creates them on first sight.
> Grafana's own login form and basic auth are off — they would be a second way
> in past the panel. Measured: without the header Grafana answers 401, and the
> built-in admin account cannot be used. Roles map admin → Admin and verwalten →
> Viewer; a viewer sees dashboards (200) but may not list users (403) or change
> the datasource. The route lives in a generated file the Caddyfile imports
> unconditionally; without a module it is empty.*

### Die Schalter

| Schalter | Vorgabe | Was er bringt | Was er kostet |
|---|---|---|---|
| **Platzwart-Zahlen** | an | CPU, Speicher, Netz je Server, Spielerzahlen, Größe und Alter der Sicherungen, Platte je Spiel, Schlaf- und Update-Zustand | nichts Neues — der Sammler misst mit, was ohnehin gemessen wird |
| **Caddy-Zugriffe** | aus | Anfragen, Antwortzeiten, Zertifikatslage | nichts — der Sammler holt sie von `127.0.0.1:2019` |
| **Tailscale** | aus | Verbindungen und Durchsatz im Tailnet | nichts |
| **cAdvisor** | aus | Platten-I/O je Container, gedrosselte CPU-Zeit, OOM-Ereignisse | **Docker-Socket im Container** — eigene Bestätigung nötig |
| **Erreichbarkeitsprobe** | aus | prüft die Ports regelmäßig | ~20 MB — und sie misst **von dieser Maschine aus** |
| **Alarme nach Discord** | aus | drei Regeln in den Störungskanal | kann melden, was die Wache auch meldet |

Zwei Schalter tragen eine Warnung und führen deshalb über eine eigene
Bestätigungsseite:

**cAdvisor** braucht den Docker-Socket. Wer den Socket hat, kann einen Container
mit dem ganzen Dateisystem darin starten und ist damit faktisch root — deshalb
bekommt die Oberfläche ihn nie (Grenze 1). Der Schalter weicht diese Grenze
nicht auf, sondern stellt eine bewusste Entscheidung daneben: *ein zusätzlicher
Container* mit diesem Zugriff, eingeschaltet von Hand, nach einer Rückfrage, die
den Preis nennt. Ab Werk ist er aus, und ohne ihn fehlt **nichts** von dem, was
die Dashboards zeigen — die Container-Zahlen kommen aus dem Sammler.

**Die Erreichbarkeitsprobe** läuft auf derselben Maschine wie die Dienste. Sie
beweist, dass hier etwas lauscht — nicht, dass es durch Firewall und Anbieter
hindurch von außen erreichbar ist. Diese Verwechslung hat hier schon Zeit
gekostet, deshalb steht sie in der Warnung und nicht im Kleingedruckten.

> *Two switches carry a warning and lead through their own confirmation page.
> cAdvisor needs the Docker socket, which makes a container effectively root —
> the panel never gets it (boundary 1). The switch does not loosen that boundary
> but places a deliberate decision beside it: one extra container with that
> access, switched on by hand after a question naming the price. Off by default,
> and nothing in the dashboards is missing without it. The reachability probe
> runs on the same machine as the services: it proves something listens here, not
> that it is reachable from outside — a confusion that has cost time before.*

### Die Einstellungen

| Einstellung | Werte | Vorgabe |
|---|---|---|
| Aufbewahrung | 30d · 90d · 365d | 90d |
| Platte für Messwerte | 1 · 2 · 5 · 10 GB | 2 GB |
| Messabstand des Sammlers | 30s · 1min · 5min | 5min |

Beide Grenzen gelten gleichzeitig, und **die Platte greift zuerst**: Eine reine
Zeitgrenze ließe die Datenbank wachsen, bis die Platte voll ist — und dann steht
nicht die Statistik, sondern der Spielserver daneben.

> *Both limits apply and size wins: a time-only limit would grow until the disk
> is full, and then it is not the statistics that stop but the game server.*

---

## Warum kein cAdvisor ab Werk: der Textdatei-Sammler

`platzwart-metriken` läuft als Zeitgeber auf der Maschine, misst einmal
`docker stats` für alle Container zusammen (ein Aufruf kostet ~2 s, je Container
gerufen wären es 13 s) und schreibt `.prom`-Dateien nach
`/var/lib/platzwart-metriken/`. node_exporter liest den Ordner mit, Prometheus
holt alles in einem Abruf.

Jede Datei entsteht über eine temporäre Datei und `rename()`: Der Sammler in
node_exporter liest jederzeit, und eine halb geschriebene Datei verwirft er
**ganz** — dann fehlten alle Werte, nicht nur die neuen. Wird ein Schalter
ausgeschaltet, wird die zugehörige Datei **gelöscht**: Ein stehengebliebener
Wert sieht aus wie ein gemessener.

Was der Sammler schreibt:

| Metrik | Bedeutung |
|---|---|
| `platzwart_server_laeuft{stack}` | 1, wenn der Container läuft |
| `platzwart_server_speicher_bytes{stack}` · `platzwart_server_cpu_prozent{stack}` | Verbrauch je Server |
| `platzwart_server_netz_bytes_total{stack,richtung}` | Netzverkehr seit Containerstart |
| `platzwart_spieler{stack}` · `platzwart_spieler_max{stack}` | Spieler und Plätze |
| `platzwart_platte_bytes{stack}` | Platte der Spieldaten (höchstens stündlich neu gemessen — `du` läuft über zehntausende Dateien) |
| `platzwart_sicherung_groesse_bytes{archiv}` · `platzwart_sicherung_zeit_sekunden{archiv}` | deduplizierte Größe und Zeitpunkt des letzten Archivs |
| `platzwart_schlaeft{stack}` · `platzwart_autoupdate{stack}` | Leerlauf und Auto-Update |
| `platzwart_tailscale_*` | nur mit Schalter |
| `platzwart_metriken_lauf_zeit_sekunden` · `…_dauer_sekunden` | wann der Sammler zuletzt lief und wie lange |

Vom Caddy-Abruf übernimmt der Sammler **nur die `caddy_*`-Zeilen**: Caddy liefert
auch `go_*` und `process_*`, und die hat node_exporter selbst — doppelte
Zeitreihen lassen den ganzen Abruf scheitern, nicht nur die doppelten.

> *Why no cAdvisor by default: the collector runs on the host, measures all
> containers in one `docker stats` call and writes `.prom` files that
> node_exporter reads. Each file is written via a temporary file and renamed,
> because a half-written one is discarded whole; a switched-off source has its
> file deleted, since a frozen value looks like a measured one. From Caddy only
> the `caddy_*` lines are taken: `go_*` and `process_*` would collide with
> node_exporter's own and break the whole scrape.*

---

## Die Dashboards

Zwei Stück, erzeugt von `werkzeuge/statistik-dashboards.py` und bereitgestellt
aus Dateien — nach einem Neuaufbau sind sie damit wieder da, ohne dass jemand
sie nachbaut:

* **Maschine** — Last, Auslastung, Speicher, Platte mit **Hochrechnung auf 14
  Tage**, Netz- und Plattendurchsatz, Wartezeit auf Ein-/Ausgabe.
* **Spielserver** — Spieler je Server (gestapelt), Speicher, Prozessorzeit,
  Platte je Server, Größe und **Alter** der Sicherungen, Netz, schlafende Server.

Erzeugt und nicht von Hand gepflegt, weil ein Dashboard mehrere hundert Zeilen
JSON sind, in denen dieselbe Angabe zwanzigmal steht; von Hand weichen die
Tafeln voneinander ab und beim Einfügen verrutscht das Raster. Lücken werden
**nicht** überbrückt (`spanNulls: false`) — dieselbe Regel wie beim Verlauf im
Panel: Eine durchgezogene Linie behauptet Messwerte, die es nie gab.

> *Two dashboards, generated by a tool and provisioned from files so a rebuild
> brings them back: the machine (load, memory, disk with a 14-day projection,
> throughput, iowait) and the game servers (players stacked, memory, CPU, disk,
> backup size and age, network, sleeping servers). Generated because a dashboard
> is hundreds of lines of JSON repeating the same fields; gaps are never bridged,
> as in the panel's own history.*

---

## Alarme (optional)

Drei Regeln, die je eine Frage beantworten, die man wirklich stellt:

| Regel | Schlägt an, wenn |
|---|---|
| Platte läuft in 14 Tagen voll | die Hochrechnung der letzten sechs Stunden unter null landet, 30 Minuten lang |
| Arbeitsspeicher dauerhaft knapp | eine Stunde lang weniger als 1 GB frei ist |
| Sicherung zu alt | das neueste Archiv älter als 24 Stunden ist |

Sie gehen in den **Störungskanal** aus `/etc/platzwart-melden.conf` — Grafana
kann Discord direkt, es braucht keinen weiteren Dienst. Mehr Regeln wären keine
Verbesserung: Jeder Alarm, den auch die Wache meldet, macht beide leiser.

Wird der Schalter wieder ausgeschaltet, verschwinden Regeln **und**
Kontaktpunkt. Das ist kein Zierat: Beim Testen blieb der Kontaktpunkt zunächst
stehen — mitsamt der Webhook-Adresse in Grafanas Datenbank. Ein Geheimnis, das
nach dem Ausschalten weiterlebt, erwartet niemand.

> *Three alert rules — disk full within 14 days, memory tight for an hour, newest
> backup older than 24 hours — into the fault channel from the existing webhook
> file; Grafana speaks Discord directly. More rules would not help: every alert
> the watchdog also sends makes both easier to ignore. Switching off removes the
> rules and the contact point: in testing the contact point survived, webhook URL
> and all, and a secret that lives on after switching off is what nobody expects.*

---

## Installieren, schalten, entfernen

Im Panel unter **Module** (nur `admin`), oder auf der Maschine:

```bash
modul-verwalten katalog
modul-verwalten installieren statistik
modul-verwalten status statistik
modul-verwalten schalter statistik cadvisor an
modul-verwalten einstellung statistik aufbewahrung 365d
modul-verwalten entfernen statistik [--auch-daten]
```

Was beim Installieren geschieht: Platz und Speicher prüfen, Ports gegen die
**tatsächlich belegten** prüfen (lokale Bindungen zählen mit, #163),
`/opt/module/statistik` anlegen, die compose-Datei **unverändert** aus
`/etc/module/statistik/` kopieren, die erzeugten Dateien schreiben
(`prometheus.yml`, `grafana-provisioning/`, `.env`, `modul.json`), Datenordner
mit den Kennungen anlegen, die die Images erwarten (Prometheus 65534, Grafana
472) — **und jede Ebene darüber durchlässig machen**: `panel-aktion` setzt
`umask 077`, und ohne ein `chmod` nach dem `mkdir` entstehen `0700 root`-Ordner,
durch die kein Container zu seinen eigenen Daten kommt (#266) —, Container
starten, die Caddy-Route schreiben und den Zeitgeber des
Sammlers einschalten.

Die compose-Datei wird dabei **nie umgeschrieben** — die Schalter setzen
compose-**Profile**, die Einstellungen landen in der `.env` daneben. So bleibt
sie byte-gleich mit der Vorlage im Repositorium, und `abgleich.sh` sieht jede
Abweichung; eine umgeschriebene könnte er von einer verbastelten nicht
unterscheiden.

Beim Entfernen gehen Container, Route, Ausschluss und Einstellungen; die
gesammelten Messwerte bleiben liegen, wenn man sie nicht ausdrücklich
mitlöscht. Spielstände und Sicherungen berührt das nicht. Geht das letzte Modul,
schaltet sich der Sammler ab und räumt seine Dateien weg.

> *Installing checks disk and memory, checks ports against the really bound ones
> (local bindings included), creates the stack directory, copies the compose file
> unchanged, writes the generated files, creates data directories with the uids
> the images expect and makes every level above them traversable (panel-aktion
> sets umask 077, so without a chmod after mkdir the parents are 0700 root and no
> container reaches its own data, #266), starts the containers, writes the Caddy
> route and enables the collector's timer. The compose file is
> never rewritten — switches set compose profiles and settings go into the .env
> beside it, so it stays byte-identical to the template and the comparison tool
> can tell drift from tampering. Removal takes containers, route and settings; collected metrics stay unless explicitly deleted, and saves and
> backups are untouched. With the last module the collector switches itself off.*

---

## Die Caddy-Route und eine Falle darin

`modul-verwalten` schreibt `/etc/caddy/module.conf` neu, **prüft** die
Konfiguration (`caddy validate`) und lädt Caddy erst dann neu; lehnt Caddy ab,
kommt die alte Datei zurück. Dieselbe Reihenfolge wie bei der SSH-Härtung in
Stufe 10.

Diese Prüfung allein genügt aber nicht, und das ist gemessen: Eine **unbekannte
Direktive** in der Datei lässt `caddy validate` fehlschlagen (`rc=1`), eine
**offene geschweifte Klammer am Dateiende nicht** (`rc=0`) — die schließende
Klammer des Site-Blocks schließt sie, und es entsteht eine *gültige, aber
falsche* Konfiguration: Der Auffangblock des Panels läge dann innerhalb des
`handle`-Blocks, und das Panel wäre weg. Deshalb zählt `modul-verwalten` die
Klammern selbst, **bevor** die Datei entsteht, und schreibt sie über eine
temporäre Datei mit `rename()`.

> *The manager rewrites the route file, validates the configuration and only then
> reloads Caddy, rolling back if Caddy refuses — the same order as the SSH
> hardening in stage 10. That check alone is not enough, and this is measured: an
> unknown directive fails validation (rc=1), an unclosed brace at the end of the
> snippet does not (rc=0) — the site block's closing brace closes it and the
> result is a valid but wrong configuration in which the panel's catch-all sits
> inside the handle block. So the manager counts braces itself before writing,
> and writes atomically.*

---

## Was es kostet

| | |
|---|---|
| Arbeitsspeicher | rund 0,5 GB (Prometheus ≤1 GB Grenze, Grafana ≤512 MB, node_exporter ≤128 MB) |
| Platte | 1–2 GB bei der Vorgabe; die Zeitreihendatenbank ist von der Sicherung **ausgeschlossen**, Grafanas Einstellungen nicht |
| Auflösung | Maschine 30 s, Platzwart-Zahlen 5 min (einstellbar), Platte je Spiel stündlich |
| Fremdcode | zwei große Images (Prometheus, Grafana) mit eigenem Update-Takt |

Der Sammler läuft mit `Nice=10` und `IOSchedulingClass=idle`: `du` über alle
Spieldaten darf den Spielern nicht die Platte wegnehmen.

> *Costs: about 0.5 GB of memory, 1–2 GB of disk at the default (the time-series
> database is excluded from backups, Grafana's settings are not), 30 s resolution
> for the machine and 5 minutes for the Platzwart numbers, and two large
> third-party images with their own update cadence. The collector runs at low
> priority so its disk walk never takes the disk from the players.*

---

## Wenn etwas nicht stimmt

| Bild | Ursache | Weg |
|---|---|---|
| `/statistik` antwortet 401 | keine gültige Sitzung oder Rolle unter `verwalten` | im Panel anmelden; Rolle prüfen |
| Grafana zeigt „Datasource not found" | Bereitstellung nicht gelesen | `docker compose logs grafana` im Modulverzeichnis; `modul-verwalten anwenden statistik` |
| Grafana startet immer wieder neu, `GF_PATHS_DATA is not writable` | ein Elternordner der Daten ist `0700 root` | `chmod 755 /srv/module /srv/module/<modul>` — behoben seit #266 |
| Tafeln bleiben leer | Prometheus erreicht node_exporter nicht | `docker compose exec prometheus wget -qO- localhost:9090/api/v1/targets` |
| Platzwart-Zahlen fehlen | Sammler läuft nicht | `systemctl status platzwart-metriken.timer`, `platzwart-metriken --zeigen` |
| Spalten im Dashboard hören auf | Sammlerlauf ausgefallen | Lücke ist Absicht — `platzwart_metriken_lauf_zeit_sekunden` zeigt den letzten Lauf |
| Nach dem Entfernen ist `/statistik` noch da | Caddy nicht neu geladen | `systemctl reload caddy`; `/etc/caddy/module.conf` muss leer sein |

Selbsttests: `modul-verwalten --selbsttest` und `platzwart-metriken --selbsttest`.

> *Troubleshooting: 401 means no valid session or too low a role; a missing
> datasource points at provisioning (check Grafana's log and re-apply); empty
> panels at Prometheus not reaching node_exporter; missing Platzwart numbers at
> the collector's timer. A gap in a graph is deliberate. If `/statistik` survives
> removal, Caddy was not reloaded. Both tools carry self-tests.*

---

## Was geprüft ist — und was nicht

Geprüft in einem Testaufbau mit echten Images (Prometheus 3.14, Grafana 13.0,
node_exporter): Die erzeugte `prometheus.yml` ist gültig (`promtool: SUCCESS`),
node_exporter liest die Dateien des Sammlers und die Werte kommen in Prometheus
an, Grafana nimmt Datenquelle, beide Dashboards und die drei Alarmregeln
an, der Kontaktpunkt entsteht und verschwindet mit dem Schalter, die Anmeldung
über die Kopfzeile legt den Benutzer an und übernimmt die Rolle, ohne Kopfzeile
antwortet Grafana `401`, ein Viewer darf sehen und nicht ändern, und die
erzeugte Caddy-Route hält `caddy validate` stand.

**Nicht geprüft:** der Lauf auf der Maschine selbst — Installation über das
Panel, die sudo-Brücke, `forward_auth` gegen das echte Panel und das Verhalten
unter Last. Der Testaufbau lief mit podman auf einem Arbeitsplatzrechner, nicht
mit Docker auf dem Server.

> *Verified in a test setup with the real images: the generated Prometheus config
> is valid, node_exporter picks up the collector's files and the values arrive in
> Prometheus, Grafana accepts the datasource, both dashboards and the three alert
> rules, the contact point appears and disappears with the switch, header login
> creates the user and applies the role, Grafana answers 401 without the header, a
> viewer may look but not change, and the generated Caddy route passes validation.
> Not verified: the run on the machine itself — installation through the panel,
> the sudo bridge, forward_auth against the real panel and behaviour under load.*
