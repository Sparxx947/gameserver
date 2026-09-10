# 09 — Referenz

Jedes Werkzeug, jede Unit, jede Datei — was sie tut, wie man sie aufruft, wo sie
liegt.

> *Every tool, unit and file: what it does, how it is called, where it lives.*

---

## Werkzeuge (`/usr/local/bin`)

### `panel-aktion`

Die einzige Brücke zwischen Weboberfläche und System. Aufgerufen ausschließlich
über `sudo` durch den Benutzer `panel`.

```
panel-aktion status                        Maschine und alle Container
panel-aktion start|stop|restart <stack>
panel-aktion archive <stack>               Borg-Archive dieses Servers
panel-aktion restore <stack> <archivname>
panel-aktion konfig-lesen <stack>
panel-aktion konfig-setzen <stack> <feld> <wert>
panel-aktion passwoerter                   alle Zugangsdaten
panel-aktion katalog                       den Spielekatalog ausgeben
panel-aktion installieren <schluessel>
panel-aktion deinstallieren <stack>
panel-aktion einrichtung <stack>           Stand der Passwort-Einrichtung
panel-aktion neustart                      Maschine neu starten
panel-aktion laufende-vorher               welche Container liefen vor dem Neustart
panel-aktion dns setzen|entfernen <name>
```

`status` holt **einen** `docker stats` für alle Container, nicht einen je
Container: Ein Aufruf kostet rund 1,9 s unabhängig von der Anzahl. Einzeln
gerufen brauchte die Aktion 13,2 s, gesammelt 2,0 s (gemessen 2026-09-06).

> *The only bridge between panel and system, invoked through sudo by the `panel`
> user. `status` issues a single `docker stats` for all containers: one call
> costs ~1.9 s regardless of count — per-container calls took 13.2 s versus 2.0 s
> batched.*

### `panel-aktion logs <stack> [zeilen]`

Die letzten Zeilen aus `docker logs`, mit Zeitstempeln, `2>&1` (die meisten
Spieleserver schreiben auf stderr). Die Zeilenzahl wird **hier** begrenzt, nicht
in der Oberfläche: 1 bis 2000, alles darüber wird auf 2000 gekappt, alles
Nichtnumerische abgewiesen. Ein unbegrenztes `--tail` wäre ein Selbstangriff.

### `spiel-verwalten`

```
spiel-verwalten katalog                     Katalog als JSON
spiel-verwalten installieren <schluessel>
spiel-verwalten deinstallieren <stack>
```

Der Installer. Prüft Platz und Ports, würfelt Passwörter, schreibt
`compose.yaml`, `panel.json` und den Ausschlussblock, legt das Datenverzeichnis
mit UID 4711 an, lädt das Titelbild und startet — wenn der Speicher reicht.

Die Deinstallation zieht **erst** eine Endsicherung; schlägt sie fehl, wird
nichts gelöscht. Verlangt zwingend eine `panel.json` und schützt damit die
handgepflegten Stacks.

> *The installer: checks space and ports, generates passwords, writes the compose
> and panel files and the backup exclusion block, creates the data directory as
> UID 4711, fetches artwork, and starts if memory allows. Uninstall takes a final
> backup first and aborts if it fails; it requires a `panel.json`, which protects
> the hand-maintained stacks.*

### `spiel-einrichtung`

```
spiel-einrichtung [<stack>]
```

Ohne Parameter; wird vom Timer alle zwei Minuten gerufen. Sucht bei frisch
installierten Servern die Konfigurationsdatei und trägt Beitrittspasswort,
Adminpasswort und Spielerzahl ein. Erkennt `.ini`, `.json`, `.xml` und `.cfg`
über Feldnamensmuster, im `.cfg`-Fall auch den id-Tech-Stil mit `set`-Präfix.
Gibt nach sechs Stunden auf und meldet das sichtbar.

Ruft **zuletzt** `port-ermitteln --aus-einrichtung`, sofern der Eintrag eine
`port_regel` trägt — und nur dann, wenn die Einrichtung entschieden ist (E23).

### `port-ermitteln`

```
port-ermitteln <stack> [--zeigen] [--aus-einrichtung]
```

Liest den Spielport aus der Konfiguration, die der erste Start geschrieben hat,
und trägt ihn in die `compose.yaml` ein. Für die 17 Katalogspiele, deren Port
vorab nicht bekannt ist; die Regel steht als `port_regel` im Katalogeintrag.

| Exit | Bedeutung |
|---|---|
| 0 | Port eingetragen, Container neu gestartet |
| 1 | Fehler (keine Regel, kein Datenverzeichnis, kein freier Ersatzport) |
| 2 | **warte** — Datei oder Feld noch nicht da; der Timer versucht es erneut |

`--zeigen` liest nur und ändert nichts. Ohne `--aus-einrichtung` übergibt das
Werkzeug per `execv` an `spiel-einrichtung`, damit es **genau einen** Weg gibt,
der einen Port veröffentlicht — sonst öffnete der Knopf im Panel einen Server,
bevor sein Beitrittspasswort steht.

Nach dem Schreiben vergleicht es die `compose.yaml` mit sich selbst **ohne** den
`ports`-Block und rollt zurück, falls sich mehr geändert hat als die Ports.

### `spiele-sicherung`

```
spiele-sicherung                 nur laufende Spiele
spiele-sicherung --alle          auch gestoppte, dazu /opt/stacks und /etc
spiele-sicherung --nur <name>    ein einzelnes Spiel
```

Ein Archiv je Spiel, Name `<spiel>-JJJJMMTT-HHMMSS`. `prune` je Präfix,
anschließend `borg compact`. Rechte `0700 root` — die Datei enthält den Pfad zum
Repositorium.

### `dns-pflegen` (früher `cf-dns`)

```
dns-pflegen setzen <name>        CNAME <name>.<zone> -> <ziel>, dns-only
dns-pflegen entfernen <name>
dns-pflegen liste
dns-pflegen pruefen              meldet Einträge, die fälschlich proxied sind
dns-pflegen ziel-zeigen          misst die eigene IPv4, vergleicht mit dem A-Eintrag
dns-pflegen ziel-setzen          trägt die gemessene IPv4 als A-Eintrag ein
dns-pflegen grundgeruest         legt <ziel> und <panel> an, WENN sie fehlen —
                            und ändert nie einen vorhandenen Eintrag
dns-pflegen anbieter             zeigt den eingestellten Anbieter
```

Der Anbieter steht in `/etc/dns-gameserver.conf` (`ANBIETER=`), die API-Kenntnis
in genau einer Klasse. Umgesetzt sind **cloudflare** und **hetzner** (letzterer noch nicht gegen eine
echte Zone gelaufen); ein weiterer ist fünf Methoden und ein Eintrag in
`ANBIETER` — die Regeln darüber, welcher Eintrag angelegt, geändert oder in Ruhe
gelassen wird, stehen einmal für alle. Anleitung:
[06-netz-dns-firewall.md](06-netz-dns-firewall.md), „Einen weiteren Anbieter
schreiben".

Fragt **nur die API**, nie die Namensauflösung — ein Wildcard in der Zone würde
jede Existenzprüfung per `dig` wertlos machen. Löscht nur Einträge, die
tatsächlich auf `DNS_ZIEL` zeigen. Erzwingt IPv4.

`ziel-zeigen` ändert nichts und gibt **1** zurück, sobald der A-Eintrag von der
gemessenen Adresse abweicht — so lässt es sich als Prüfung verwenden.
`ziel-setzen` ist der Schreibweg und wird von `dns-ziel.timer` gerufen; ohne
`SERVER_IPV4=dynamic` läuft dieser Timer nicht.

Die Adresse kommt **nicht aus einer einzelnen Quelle**: drei unabhängige
Auskunftsstellen werden befragt, und erst wenn zwei dieselbe Antwort geben, wird
geschrieben. Eine Adresse aus `100.64.0.0/10` wird verworfen — sie bedeutet
entweder Provider-NAT (dann gibt es gar keine eigene öffentliche IPv4) oder die
Anfrage lief durch Tailscale.

> *`ziel-zeigen` changes nothing and returns 1 as soon as the A record differs
> from the measured address, so it doubles as a check. `ziel-setzen` is the
> writing path, called by `dns-ziel.timer`, which only runs with
> `SERVER_IPV4=dynamic`. The address never comes from a single source: three
> independent services are asked and two must agree before anything is written.
> An address from `100.64.0.0/10` is rejected — it means either carrier NAT (no
> public IPv4 of one's own) or that the request went through Tailscale.*

### `katalog-doku.py`

```
werkzeuge/katalog-doku.py             Zahlen und Spieleliste in der Doku schreiben
werkzeuge/katalog-doku.py --pruefen   nur berichten (Exit 1 = veraltet)
```

Hält die Dokumentation am Katalog: die Gesamtzahl an vier ausdrücklich
benannten Stellen und die erzeugte Spieleliste in
[04-spielekatalog.md](04-spielekatalog.md). Wird von `vollstaendigkeit.sh`
mitgeprüft.

Geprüft werden **benannte Stellen**, keine Suche nach „Zahl vor dem Wort
Spiele": in der Doku stehen mehrere Zahlen, die etwas anderes zählen (13 Spiele
an der Sammel-ID 90, 17 Spiele ohne vorab bekannten Port). Jedes Muster muss
**genau einmal** passen — kein Treffer heißt „die Stelle hat sich verschoben",
nicht „in Ordnung".

### `katalog-vorpruefung`

Ohne Parameter. Prüft alle Katalogeinträge **ohne Download**: Pflichtfelder,
Schlüsselform, Portkollisionen (installierte Spiele ausgenommen), erzeugt die
echte `compose.yaml` und lässt `docker compose config -q` darauf laufen, fragt
`docker manifest inspect` ab.

Ergebnis vom 2026-09-06: 34 ohne Befund, 5 Hinweis, 0 Fehler, 2 installiert.

### `compose-feld`

```
compose-feld lesen  <stack>
compose-feld setzen <stack> <name>          (Wert über stdin)
```

Liest und setzt die Umgebungsvariablen eines Stacks. Geändert wird
**ausschließlich** der `environment`-Block; Volumes, Ports, Image, `user`,
`privileged` und `cap_add` bleiben unantastbar.

Drei Schranken, aufsteigend nach Verlässlichkeit:

1. **Namensmuster und Sperrliste** — `UID`/`GID`/`PUID`/`PGID` (Dateirechte),
   `GAME_ID`/`APPID` (wäre ein anderes Spiel), `EULA`/`TS3SERVER_LICENSE`
   (Zustimmung), `PATH`/`LD_*`.
2. **Kein Zeilenumbruch im Wert** — sonst ließe sich über einen Wert neue
   YAML-Struktur einschleusen, etwa ein Volume `/:/host`.
3. **Der eigentliche Schutz: ein Vergleich der von Docker erzeugten Endfassung
   vor und nach der Änderung.** Weichen Volumes, Ports, Image, `user`,
   `privileged` oder `cap_add` auch nur um ein Zeichen ab, wird zurückgerollt.
   Diese Prüfung sieht das **Ergebnis** an und hängt nicht davon ab, dass 1 und
   2 lückenlos sind.

Nachgewiesen: `geruest()` unterscheidet einen geänderten Port und erkennt ein
Volume `/:/host`; bei einer erzwungenen Abweichung wird die Datei byte-genau
zurückgerollt.

**Bekannte Grenze:** StarRupture baut seine compose-Datei über YAML-Anker
(`x-image: &image`, `<<: *image`). Die zeilenweise Analyse findet dort keinen
`environment`-Block; die Variablen dieses Stacks erscheinen nicht im Panel.

> *Reads and writes a stack's environment variables — only the `environment`
> block; volumes, ports and image stay untouchable. Three barriers in ascending
> reliability: a name pattern plus deny-list, a no-newline rule on the value, and
> — the real protection — a before/after comparison of docker's rendered config
> that rolls back on any difference. Known limit: StarRupture's compose file uses
> YAML anchors, so its variables do not appear.*

### `konfig-datei`

```
konfig-datei liste <stack>
konfig-datei lesen <stack> <relpfad>
konfig-datei schreiben <stack> <relpfad>     (Inhalt über stdin)
```

Listet, liest und schreibt die Konfigurationsdateien der Spiele unter
`/srv/games` bzw. `/srv/dienste`. Aufgerufen nur über `panel-aktion`.

**Die Pfadprüfung ist der Kern:** Jeder Pfad wird **zuerst vollständig
aufgelöst** und **danach** geprüft, ob er noch im Datenverzeichnis liegt. Diese
Reihenfolge ist nicht verhandelbar — unter
`/srv/games/starrupture/.wine/dosdevices/` liegt ein Symlink `z:` auf `/`.
Nachgemessen am 2026-09-07: `readlink -f` auf `…/z:/etc/passwd` ergibt
`/etc/passwd`. Ein Editor, der als root schreibt und vor dem Auflösen prüft,
wäre ein Schreibzugriff auf das gesamte Dateisystem.

Weitere Grenzen: nur bekannte Endungen, 4 B bis 256 KB, ein Rauschfilter gegen
Manifeste, Lizenztexte, Absturzberichte und die eigenen Sicherungen, keine neuen
Dateien (nur bestehende ändern), Eigentümer und Rechte werden vom Original
übernommen — nie von root, sonst kann der Container seine eigene Datei nicht
mehr schreiben.

> *Lists, reads and writes the games' configuration files, invoked only through
> `panel-aktion`. Every path is resolved **first** and checked **afterwards** —
> non-negotiable, because a `z: -> /` symlink exists in StarRupture's Wine
> prefix; checking before resolving would turn the editor into a root write to
> the entire filesystem. Ownership is inherited from the original, never root.*

### `katalogbilder-holen`

```
katalogbilder-holen              fehlende Titelbilder der Katalogseite holen
katalogbilder-holen --alle       auch vorhandene neu holen
katalogbilder-holen --pruefen    nur berichten (Exit 1 = Lücken)
```

Holt die Steam-Header nach `/opt/panel/bilder/katalog`. Spiele ohne
Steam-Eintrag (`"appid": 0`) bekommen das selbst gezeichnete Bild aus
`/opt/panel/bilder/eigene`.

**Dieses Verzeichnis wurde bisher von keinem Skript gefüllt** — die Bilder waren
einmal von Hand geholt worden. Nach einem Neuaufbau nach `install/` wäre die
Katalogseite vollständig bildlos gewesen. Stufe 30 ruft das Werkzeug jetzt auf;
ein Fehlschlag ist erlaubt (kein Netz), die Kacheln bleiben dann blass.

> *Fetches Steam headers for the catalogue page; games with no Steam entry get
> the self-drawn image instead. The directory was previously populated by no
> script at all — after a rebuild the page would have been entirely image-less.
> Stage 30 now calls it, and is allowed to fail.*

### `titelbild.py` (in `werkzeuge/`)

```
werkzeuge/titelbild.py <schluessel> <Name> <Untertitel> <Adresse> [--motiv wuerfel|welle|kreis]
```

Zeichnet ein Titelbild im Format der Steam-Header (460×215) in den Farben des
Panels und legt es unter `panel/bilder/eigene/` ab. **Selbst gezeichnet, nicht
geladen:** Steam-Header sind Werke Dritter und liegen deshalb nicht im
Repositorium; ein eigenes Bild darf hier liegen. Es enthält bewusst kein fremdes
Logo und keine Marke.

> *Draws artwork in the Steam header format and the panel's colours. Self-drawn
> rather than fetched: Steam headers are third-party works and stay out of the
> repository, while a self-made image may live here — deliberately carrying no
> foreign logo or brand.*

### `katalog-beschreibungen.py` (in `werkzeuge/`)

```
werkzeuge/katalog-beschreibungen.py [katalog.json] [--schreiben] [--pruefen]
```

Setzt das Feld `kurz` für Einträge, die dort nur ihren eigenen Namen tragen —
"DayZ (LinuxGSM)" unter der Überschrift "DayZ". Das betraf **85 von 179**
Einträgen: die Katalogkarte sagte zweimal dasselbe, die Textsuche gewann über
`kurz` nichts, und der Untertitel der selbst gezeichneten Titelbilder war leer
an Information.

Die Sätze sind **selbst formuliert**, nicht aus dem Steam-Store übernommen:
Store-Texte sind Werke Dritter, aus demselben Grund, aus dem Titelbilder zur
Laufzeit geholt statt eingecheckt werden. Die Zuordnung steht einzeln im
Werkzeug, wie in `katalog-kategorien.py`; Spiele ohne Eintrag werden beim Lauf
benannt statt still ihren Namen zu behalten.

> *Fills `kurz` for entries that carried only their own name — 85 of 179. The
> sentences are written here rather than taken from the Steam store: store texts
> are third-party works, the same reason artwork is fetched at runtime instead of
> committed. Games without an entry are named on each run rather than quietly
> keeping their name.*

### `logo.py` (in `werkzeuge/`)

```
werkzeuge/logo.py [--schreiben] [--vorschau]
```

Erzeugt das Zeichen des Panels aus **einer** Beschreibung: `favicon.svg`,
`favicon.ico`, `apple-touch-icon.png` und die Zeile `LOGO = …` für `app.py`.
`--vorschau` legt ein Blatt in 24, 32, 48, 64 und 128 px auf dem
Panelhintergrund ab — den Größen, in denen das Zeichen wirklich vorkommt.

**Warum ein Werkzeug und keine vier Dateien:** Das Zeichen erscheint an vier
Stellen. Wer sie einzeln pflegt, hat nach der ersten Änderung vier Fassungen, von
denen drei alt sind. Die Formen stehen deshalb einmal als Zahlen; SVG und
Rasterbilder entstehen daraus. `app.py` trägt einen Hinweis, dass die Zeile
erzeugt und nicht von Hand zu ändern ist.

**Das Motiv** ist die Mitte eines Spielfelds — Mittellinie, Anstoßkreis,
Anstoßpunkt. Das Projekt soll *Platzwart* heißen, und ein Platzwart hält den
Platz bereit, damit andere darauf spielen können.

Der erste Entwurf hatte zusätzlich die Seitenlinien des ganzen Feldes. In der
Vorschau nebeneinander war das bei **24 px ein Klumpen**: drei Elemente auf so
wenig Fläche heben sich gegenseitig auf. Deshalb nur noch drei Linien, und die
Mittellinie läuft bis an den Rand.

> *Generates the panel's mark from one description — SVG, ICO, PNG and the inline
> line for `app.py` — because four separately maintained files means three stale
> ones after the first change. `--vorschau` renders it at the sizes it actually
> appears in. The motif is the centre of a pitch: the project is to be called
> Platzwart, a groundskeeper who keeps the pitch ready for others to play on. An
> earlier draft included the full touchlines and turned into a blob at 24 px.*

### `eigene-bilder.py` (in `werkzeuge/`)

```
werkzeuge/eigene-bilder.py [katalog.json] [--alle] [--pruefen]
```

Erzeugt über `titelbild.py` ein Bild für **jedes** Katalogspiel ohne
Steam-Eintrag (`"appid": 0`). Ohne Schalter nur die fehlenden, `--alle` zeichnet
auch vorhandene neu, `--pruefen` berichtet nur (Exit 1 = es fehlt etwas).

Warum es das braucht: `titelbild.py` zeichnet ein Bild auf Zuruf. Die Dateien
unter `panel/bilder/eigene/` lagen deshalb nur im Repositorium, weil sie einmal
von Hand erzeugt wurden — dasselbe Muster wie bei den Steam-Bildern zuvor. Kam
ein Spiel ohne Steam-Eintrag dazu, fehlte sein Bild, und nichts sagte es; am
2026-09-08 waren es sechs. `vollstaendigkeit.sh` ruft deshalb `--pruefen`.

Das Motiv wird aus dem Schlüssel abgeleitet, nicht zufällig gewählt: derselbe
Katalog ergibt dieselben Bilder, zwei Läufe sind bytegleich. `hash()` wäre dafür
falsch — der ist pro Prozess anders gesalzen.

> *Draws artwork for every catalogue game without a Steam entry. Previously these
> files existed only because somebody made them by hand once, so a new game
> without a Steam entry silently had none — six of them on 2026-09-08. The motif
> is derived from the key rather than chosen at random, so the same catalogue
> yields byte-identical images; `hash()` would be wrong, being salted per
> process.*

### `ttyd`

Das Webterminal, Version 1.7.7 als Release-Binary. Nicht aus Debian: bookworm
liefert 1.6, dessen `--base-path` sich anders verhält.

---

## Prüfwerkzeuge (`werkzeuge/`)

### `abgleich.sh <ssh-ziel>`

Vergleicht das Repositorium mit einer laufenden Maschine — **33 Prüfpunkte**:

| Was | Wie verglichen |
|---|---|
| 22 Dateien (Werkzeuge, `/etc`, Units, `app.py`) | byte-genau, nach Einsetzen der Platzhalter |
| Python-Umgebung des Panels | `pip list --format=freeze` gegen `panel/requirements.txt` |
| ttyd | installierte Version gegen `TTYD_VERSION` in Stufe 40 |
| 3 Symbole | byte-genau |
| selbst gezeichnete Titelbilder | byte-genau |
| Katalogbilder | nur Vollständigkeit — die Steam-Header liegen nicht im Repositorium |

Die letzten vier Punkte fehlten zunächst. Aufgefallen ist das erst, als ein
Dependabot-PR `requirements.txt` änderte und der Abgleich von Hand nachgezogen
werden musste — **eine Prüfung, die einen Bereich gar nicht ansieht, meldet ihn
als in Ordnung.**

Exit 0 = deckungsgleich, 1 = Abweichungen (mit Diff), 2 = nicht erreichbar.
Ändert nichts.

> *Compares the repository against a running machine across 27 checks: 22 files
> byte-for-byte after placeholder substitution, plus the panel's Python
> environment, the ttyd version, and the three icons. The last four were missing
> at first and only surfaced when a Dependabot PR changed `requirements.txt` — a
> check that never looks at an area reports it as fine.*

### `ausrollen.sh <ssh-ziel> <repo-datei> [...]`

Bringt Repo-Dateien **mit eingesetzten Platzhaltern** auf die Maschine, legt
vorher eine Sicherung an und ersetzt atomar. Bricht ab, wenn ein Platzhalter
übrig bleibt oder das Ziel unbekannt ist.

Entstanden, weil an einem Tag **zweimal** eine Datei per `scp` direkt kopiert
wurde und die `@@PLATZHALTER@@` mitgingen — einmal stand der Weltname als
`@@WELT_NAME@@` im Katalog, einmal war das Borg-Repository in `panel-aktion`
weg. Beide Male fand `abgleich.sh` es. Die Ersetzung von Hand zu tippen ist der
Fehler, nicht das Vergessen.

> *Deploys repository files with placeholders substituted, backing up first and
> replacing atomically; aborts on a left-over placeholder or unknown target. It
> exists because two files were scp'd across untouched in a single day.*

### Die Fassung

`VERSION` im Wurzelverzeichnis nennt die Fassung dieses Bausatzes. Beim
Einrichten entsteht daraus `/etc/gameserver-version` auf der Maschine:

```
VERSION=1.0.0
COMMIT=d18d650
STAND=sauber
DATUM=2026-09-07T18:42:11+02:00
```

`abgleich.sh` vergleicht die Fassung und meldet eine **Abweichung**, wenn sie
nicht stimmt oder der Stempel ganz fehlt.

`STAND` sagt, ob seit der letzten vollen Einrichtung einzelne Dateien mit
`ausrollen.sh` nachgezogen wurden. Das zählt **bewusst nicht** als Abweichung:
einzeln nachzurollen ist der vorgesehene Arbeitsweg, und es jedes Mal als
Abweichung zu melden hieße, eine Meldung zu erzeugen, die man sich abgewöhnt zu
lesen. Was tatsächlich abweicht, findet der Dateivergleich ohnehin genau.

Wann die Zahl steigt:

| Stelle | wann |
|---|---|
| erste (`1.x.x`) | eine der vier nicht verhandelbaren Grenzen ändert sich, oder eine bestehende Einrichtung lässt sich nicht mehr ohne Handarbeit weiterbetreiben |
| zweite (`x.1.x`) | neue Fähigkeit, neue Einrichtungsstufe, neue Variable in `konfiguration.env` |
| dritte (`x.x.1`) | Fehlerbehebung, Dokumentation, nichts, wofür man etwas tun muss |

Zur Fassung gehört ein Git-Tag auf `main`, nach dem Merge:

```bash
git tag -a v1.0.0 -m "Fassung 1.0.0" && git push origin v1.0.0
```

> *`VERSION` names the release of this kit; installing turns it into
> `/etc/gameserver-version`, holding the release, the commit, whether single
> files have been rolled out by hand since, and when. `abgleich.sh` reports a
> deviation when the release differs or the stamp is missing. `STAND` is
> deliberately not a deviation: rolling out single files is the intended
> workflow, and flagging it every time would train people to ignore the message,
> while actual drift is found precisely by the file comparison. The first digit
> moves when one of the four non-negotiables changes or an existing installation
> can no longer be carried forward without manual work; the second for new
> capabilities, stages or configuration variables; the third for fixes and
> documentation. Each release gets a git tag on `main` after the merge.*
### `rueckbau.sh <ssh-ziel> [Stufen] [--wirklich]`

Das Gegenstück zu `install/einrichten.sh`: entfernt von einer Maschine wieder,
was dieses Repositorium dort einbaut.

```
werkzeuge/rueckbau.sh gameserver                        # zeigt nur den Plan
werkzeuge/rueckbau.sh gameserver --wirklich             # Dienste und Programme
werkzeuge/rueckbau.sh gameserver --mit-spielstaenden \
                                 --mit-benutzern \
                                 --mit-dns --wirklich   # alles
```

**Ohne `--wirklich` ändert es nichts**, sondern zeigt jeden Schritt mit dem
Befehl, der ausgeführt würde. Mit `--wirklich` fragt es nach dem **Namen des
Ziels** — nicht nach „ja": ein „ja" tippt man auch dann, wenn man versehentlich
die falsche Maschine erwischt hat. Ohne Terminal bricht es ab, statt
unbeaufsichtigt loszulaufen.

Die Liste der systemd-Einheiten und der Werkzeuge entsteht **aus dem
Repositorium selbst** (`systemd/` und `bin/`). Genau diese beiden Listen waren
in der früheren Anleitung falsch: sie löschte keine einzige Unit-Datei, und in
der Werkzeugliste fehlten zwei Einträge.

Was ausdrücklich **stehen bleibt**: das Borg-Repository und
`/root/.borg-passphrase` (der einzige Schlüssel dazu — wer sie löscht, macht
jedes vorhandene Archiv wertlos), die ufw-Regeln und `sshd_config.d` (ein
Zurücksetzen könnte den SSH-Zugang kappen), die Pakete, und `ADMIN_USER` — das
ist der Zugang, über den gerade gearbeitet wird.

Nach dem Lauf eine **Gegenprobe** samt **Kontrollwert**: nachgesehen wird, was
noch da ist, und gleichzeitig, dass Docker, `ADMIN_USER` und die Passphrase
*noch* da sind. Ohne den Kontrollwert wäre „nichts mehr gefunden" nicht von „die
Maschine antwortet gar nicht mehr" zu unterscheiden.

**Geprüft wird ein Rückbau nur so:** zurückbauen, `install/einrichten.sh` erneut
laufen lassen, `abgleich.sh` muss grün sein. Auf einer Maschine, die man verlieren
darf — auf keiner anderen.

> *The counterpart to the installer. Without `--wirklich` it only prints the plan
> and changes nothing; with it, it asks for the target's name rather than for
> "yes", because people type "yes" even when they grabbed the wrong machine, and
> it refuses to run without a terminal. The unit and tool lists are derived from
> the repository itself — exactly the two lists the old written instructions had
> wrong. The Borg repository and its passphrase, the firewall rules, the packages
> and `ADMIN_USER` are deliberately left alone. Afterwards it verifies what
> remains and measures a control value alongside, so "found nothing" cannot be
> confused with "the machine stopped answering". The only real test of a teardown
> is: tear down, run the installer again, and `abgleich.sh` must be green — on a
> machine you can afford to lose.*
### `aufraeumen.sh <ssh-ziel> [Stufen] [--wirklich]`

Räumt alte `.vor-<datum>`-Kopien weg. Ohne `--wirklich` wird nur gezeigt, was
entfernt würde, mitsamt der Menge, die das freimacht.

```
--behalte N            je Datei die N jüngsten Kopien behalten (Vorgabe: 3)
--aelter-als T         nur löschen, was älter als T Tage ist (Vorgabe: 14)
--mit-restore-kopien   auch die vollen Verzeichniskopien vor einem Restore
```

Gesucht wird nur in `/etc`, `/usr/local/bin`, `/opt/panel`, `/opt/stacks`,
`/srv/games` und `/srv/dienste` — ein `find` über `/` wäre langsam und griffe
Kopien an, die diese Einrichtung nie angelegt hat.

Entschieden wird nach dem **Zeitstempel im Dateinamen**, nicht nach der `mtime`;
Begründung in `docs/08-betrieb-und-stoerungen.md`. Nach dem Lauf eine Gegenprobe
(sind die Kandidaten wirklich weg?) und ein Kontrollwert (steht je Datei noch
mindestens eine Kopie?) — ohne den zweiten Teil fiele eine zu gierige Auswahl
nicht auf.

> *Removes old `.vor-<date>` copies, showing the plan and the space it frees
> unless `--wirklich` is given. It keeps the newest N per file and deletes only
> what is older than T days, searching known areas only. Decisions use the
> timestamp in the filename, not `mtime`. Afterwards it verifies the candidates
> are gone and measures a control value — that at least one copy still stands per
> file — because otherwise an over-greedy selection would go unnoticed.*

### `vollstaendigkeit.sh`

Prüft, ob das Repositorium alles enthält, was die Einrichtung anfasst: existiert
jede von `install/` referenzierte Datei **und wird sie von git verfolgt**, sind
alle Skripte syntaktisch heil, steckt irgendwo ein Geheimnis, ist jeder
`@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt.

Als Bremse vor jedem Commit:
`ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit`.
Notausgang `GAMESERVER_KEIN_GATE=1`.

> *Verifies the repository holds everything the installation touches: every file
> referenced by `install/` exists and is tracked, all scripts parse, no secret is
> present, every placeholder is documented. Wire it in as a pre-commit hook via
> the symlink above; bypass with `GAMESERVER_KEIN_GATE=1`.*

---

## systemd

| Unit | Zeitpunkt | Zweck |
|---|---|---|
| `spiele-autoupdate.timer` | täglich 05:15, ±30 min | freigeschaltete Server aktualisieren (`Persistent=false`) |
| `platzwart-wache.timer` | alle 5 min | Lage prüfen, **Änderungen** nach Discord melden (`Persistent=false`) |
| `spieler-zaehlen.timer` | jede Minute | Spielerzahlen abfragen (`Persistent=false`) |
| `platzwart-status.timer` | jede Minute | öffentliche Statusseite neu schreiben (`Persistent=false`) |
| `platzwart-verlauf.timer` | alle 5 min | Speicher, Last und Spielerzahl mitschreiben (`Persistent=false`) |
| `platzwart-schlaf.timer` | alle 10 min | leere Server schlafen legen (`Persistent=false`) |
| `platzwart-wecken-<stack>.socket` | — | von `platzwart-schlaf` erzeugt, hält die Spielports während des Schlafs |
| `spiele-wiederanlauf.service` | beim Hochfahren | startet die Server wieder, die `panel-aktion neustart` vorher angehalten hat |
| `panel.service` | dauerhaft | Weboberfläche, `User=panel`, uvicorn auf `127.0.0.1:8099` |
| `ttyd.service` | dauerhaft | Webterminal, `User=<admin>`, `127.0.0.1:7681` |
| `spiele-sicherung.timer` | `*:0/15`, ±60 s | Sicherung laufender Spiele (aus bei `BORG_REPO=aus`) |
| `spiele-sicherung-voll.timer` | täglich 04:00, ±300 s | Vollsicherung (aus bei `BORG_REPO=aus`) |
| `spiel-einrichtung.timer` | alle 2 min, ab 3 min nach dem Start | Passwörter frischer Server setzen |
| `palworld-neustart.timer` | 05:30 und 17:30 | gegen das Speicherleck |
| `dns-ziel.timer` | alle 5 min, ab 2 min nach dem Start, ±30 s | öffentliche IPv4 messen und den A-Eintrag nachziehen (nur bei `SERVER_IPV4=dynamic`) |

`Persistent=true` bei allen Sicherungs- und Einrichtungs-Timern: Verpasste Läufe
werden nachgeholt. **`Persistent=false` bei `palworld-neustart`**, mit Absicht —
ein nachgeholter Neustart liefe womöglich mitten in einer Spielsitzung.

> *All backup and setup timers are `Persistent=true` so missed runs catch up.
> The Palworld restart is deliberately `false`: a caught-up restart could fire
> mid-session.*

**`spiel-einrichtung.service` läuft bewusst ohne Härtung.** Er ruft
`docker compose` und schreibt nach `/srv/games`; Härtungsoptionen haben hier
schon einmal dazu geführt, dass Aufrufe still fehlschlugen.

---

## Dateien

| Pfad | Rechte | Inhalt |
|---|---|---|
| `/etc/spiele-katalog.json` | `0644 root` | 179 installierbare Spiele |
| `/etc/borg-ausschluss.txt` | `0644 root` | was nicht gesichert wird |
| `/etc/caddy/Caddyfile` | `0644 root` | HTTPS, Vorschaltung, Kopfzeilen |
| `/etc/fail2ban/jail.local` | `0644 root` | sshd-Jail, Ausnahmen |
| `/etc/sudoers.d/panel` | `0440 root` | die eine Rechteerweiterung |
| `/etc/dns-gameserver.conf` | `0600 root` | `ANBIETER=…`, `TOKEN=…` |
| `/etc/cloudflare-gameserver.conf` | `0600 root` | älterer Ort, wird noch gelesen |
| `/root/.borg-passphrase` | `0600 root` | Schlüssel zur Sicherung |
| `/opt/panel/app.py` | `0644 root` | die Oberfläche |
| `/opt/panel/daten/nutzer.json` | `0600 panel` | Benutzer, Hashes, TOTP |
| `/opt/panel/daten/zugangsdaten.json` | `0600 panel` | selbst gepflegte Zugänge |
| `/opt/panel/daten/nutzer.json` … Feld `codes` | `0600 panel` | Wiederherstellungscodes, Argon2id-Hashes, je 93,3 Bit |
| `/var/lib/spiele-autoupdate.liste` | `0600 root` | freigeschaltete Server für nächtliche Updates, eine Zeile je Stack |
| `/etc/platzwart-melden.conf` | `0600 root` | Discord-Webhooks. **Nicht** von der Einrichtung angelegt; fehlt sie, meldet nichts |
| `/etc/spiele-adressen.json` | `0644 root` | Beitrittsadressen der von Hand gebauten Server; gelesen von Panel **und** Statusseite |
| `/var/lib/platzwart-status/index.html` | `0644 root` | die öffentliche Seite; Caddy liefert sie unmittelbar aus |
| `/var/lib/platzwart-schlaf.liste` | `0644 root` | für den Leerlauf freigeschaltete Server, eine Zeile je Stack |
| `/var/lib/platzwart-schlaf.json` | `0644 root` | seit wann leer, welche Ports, wie oft geweckt |
| `/var/lib/platzwart-verlauf.json` | `0644 root` | Ringpuffer, 2016 Werte je Server = eine Woche; jeder Wert mit eigener Zeit, damit Lücken sichtbar bleiben |
| `/var/lib/platzwart-spieler.json` | `0644 root` | zuletzt gemessene Spielerzahlen; **kein Eintrag = keine Antwort**, nicht null |
| `/var/lib/platzwart-spieler.stumm` | `0644 root` | wer zuletzt nicht antwortete — Wiedervorlage nach 30 min |
| `/var/lib/platzwart-wache.zustand` | `0600 root` | welche Befunde beim letzten Lauf offen waren — daraus entsteht Störung vs. Entwarnung |
| `/var/lib/platzwart-melden.gesehen` | `0600 root` | zuletzt verschickte Meldungen, gegen Wiederholung (Standard 180 min) |
| `/var/lib/spiele-sicherung.groessen` | `0600 root` | Archivgröße je Spiel aus dem letzten Lauf — daraus entsteht der Einbruchsvergleich |
| `/var/lib/spiele-sicherung.stoerung` | `0600 root` | Marke: die letzte Sicherung schlug fehl — der nächste Erfolg meldet Entwarnung |
| `/opt/panel/statisch/passkey.js` | `0644 root` | das einzige JavaScript des Panels (WebAuthn) |
| `/opt/panel/daten/audit.jsonl` | `0644 panel` | Protokoll: wer hat wann was getan (Rotation bei 4 MB nach `.jsonl.1`) |
| `/opt/stacks/<n>/compose.yaml` | `0600 root` | Serverdefinition mit Passwörtern |
| `/opt/stacks/<n>/panel.json` | `0640 root:panel` | Anzeigedaten |

---

## Benutzer

| Benutzer | UID | Shell | Zweck |
|---|---|---|---|
| `<admin>` | 1000 | `/bin/bash` | Mensch; Webterminal, `sudo`, Gruppe `panel` |
| `panel` | System | `nologin` | Weboberfläche; darf nur `panel-aktion` |
| `spiele` | **4711** | `nologin` | Eigentümer aller Spieldaten |

Die feste UID 4711 ist wichtig: Die Container laufen unter dieser Kennung
(`PUID`/`UID` in der compose-Datei). Ohne festen Wert gehören die Spielstände
nach einem Neuaufbau niemandem, und der Server kann nicht schreiben.

**Niemand ist in der Gruppe `docker`.** Siehe
[07-sicherheitsentwurf.md](07-sicherheitsentwurf.md).

---

## Ports

| Port | Wo gebunden | Dienst |
|---|---|---|
| 22 | öffentlich, nur aus `ADMIN_NETZ` | SSH |
| 80 | öffentlich | Caddy, nur für die Zertifikatsausstellung |
| 443 | öffentlich | Caddy → Panel und Terminal |
| 8099 | `127.0.0.1` | Panel (uvicorn) |
| 7681 | `127.0.0.1` | ttyd |
| Spielports | öffentlich, von Docker | je Stack, siehe compose |
| Verwaltungsports | `127.0.0.1` | RCON, Webkonsolen, ServerQuery |

---

## Umgebungsvariablen der Einrichtung

Alle in `konfiguration.env`, alle Pflicht:

| Variable | Beispiel | Wo sie landet |
|---|---|---|
| `DNS_ZONE` | `beispiel.de` | `dns-pflegen`, `app.py`, Beitrittsadressen |
| `DNS_ZIEL` | `gs.beispiel.de` | `dns-pflegen` (CNAME-Ziel, A-Eintrag) |
| `PANEL_DOMAIN` | `panel.beispiel.de` | `Caddyfile`, `dns-pflegen` |
| `SERVER_IPV4` | `203.0.113.10` **oder** `dynamic` | schaltet `dns-ziel.timer` ein oder aus |
| `WELT_NAME` | `meinserver` | Server- und Weltnamen in den Spielen |
| `ADMIN_USER` | `admin` | `ttyd.service`, Benutzeranlage |
| `ADMIN_NETZ` | `203.0.113.0/30` | `fail2ban` |
| `ADMIN_IP` | `203.0.113.1` | `ufw`-Regel auf Port 22 |
| `BORG_REPO` | `ssh://borg@…/…` **oder** `aus` | `spiele-sicherung`, `panel-aktion`, `spiel-verwalten`, `app.py`; `aus` schaltet die Sicherung ab |
| `BORG_TAILSCALE_IP` | `100.100.100.100` | Dokumentation, Prüfungen (bei `BORG_REPO=aus` ebenfalls `aus`) |
| `FREMD_IPV4` | `198.51.100.10` | Kommentar in `dns-pflegen` (Wildcard-Ziel) |

Bleibt beim Einbau ein `@@PLATZHALTER@@` stehen, bricht die Einrichtung ab.

> *All values live in `konfiguration.env` and are mandatory; a left-over
> placeholder aborts the installation.*
