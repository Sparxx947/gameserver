# 09 — Referenz

Jedes Werkzeug, jede Unit, jede Datei — was sie tut, wie man sie aufruft, wo sie
liegt. Die Gründe hinter den Details stehen in den Kapiteln davor und in
[10-entscheidungen.md](10-entscheidungen.md); hier steht, was ist.

> *Every tool, unit and file: what it does, how it is called, where it lives.
> The reasons behind the details are in the preceding chapters and the decision
> log; this chapter states what is.*

---

## Werkzeuge auf der Maschine (`/usr/local/bin`)

Alle eingesetzt von Stufe 30 (`spiele-sicherung` von Stufe 50, `dns-pflegen`
schon von Stufe 25), `0755 root` bzw. `0700 root`. Aufgerufen von
`panel-aktion`, von systemd-Units oder von Hand als root; keines davon darf der
Benutzer `panel` direkt.

> *All installed by stage 30 (the backup tool by stage 50, the DNS tool already
> by stage 25), owned by root. Called by `panel-aktion`, by systemd units or by
> hand as root; the `panel` user may run none of them directly.*

### `panel-aktion`

Die einzige Brücke zwischen Weboberfläche und System. Aufgerufen ausschließlich
über `sudo` durch den Benutzer `panel` (`/etc/sudoers.d/panel`, eine Zeile).
Jede Aktion ist ein eigener, fest verdrahteter Zweig; jeder Parameter wird dort
gegen eine Positivliste geprüft, bevor irgendetwas geschieht. Kein `eval`, keine
Shell-Expansion von Eingaben. Werte, die groß sind oder Geheimnisse tragen
(Dateiinhalte, Mod-Dateien, Zugangsdaten), kommen **über stdin**, nie als
Argument — Argumente stehen für jeden Benutzer der Maschine in der Prozessliste.

Gemeinsame Prüfungen:

| Parameter | Regel |
|---|---|
| Stack | `^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$` **und** es gibt `/opt/stacks/<stack>/` (Here-String statt Pipe, siehe unten) |
| Archiv | `^[a-z0-9-]{1,40}-[0-9]{8}-[0-9]{6}$` **und** beginnt mit `<stack>-` |
| Katalogschlüssel | Form wie Stack; ob er im Katalog steht, prüft `spiel-verwalten` |
| Sicherung | Archivwege brechen bei `BORG_REPO=aus` mit einer eigenen Meldung ab, statt an der fehlenden Passphrase zu scheitern |

Alle Aktionen:

| Aktion | Was sie tut | Eigene Prüfung |
|---|---|---|
| `status` | eine Systemzeile (Speicher, Last, Kerne, Platte, Auslagerung) und je Stack Zustand, CPU, Speicher, Netzverkehr — aus **einem** `docker stats` | — |
| `start` / `stop` / `restart <stack>` | `docker compose up -d` / `stop` / `stop` + `up -d` (so wird eine geänderte compose.yaml übernommen) | Stack |
| `alle-anhalten` | merkt die laufenden Stacks in `/var/lib/spiele-wiederanlauf` und hält sie an | — |
| `alle-starten` | startet genau die Stacks aus dieser Liste und löscht sie | Liste muss existieren |
| `laufende-vorher` | welche Container gerade laufen (für die Rückfrage vor dem Neustart) | — |
| `neustart` | merkt die laufenden Stacks, hält sie an, startet die Maschine neu | bricht ab, wenn gerade `borg create/prune/compact` läuft |
| `logs <stack> [zeilen]` | letzte Zeilen aus `docker logs`, mit Zeitstempeln, `2>&1` | Zahl, 1–2000 |
| `aktualisieren <stack>` | Sicherung **als Bedingung**, dann `docker compose pull`, Neustart nur wenn er lief; Antwort „schon aktuell" oder „aktualisiert" nach Image-ID | Stack; ohne Sicherung kein Update |
| `auto-update <stack> an\|aus` · `auto-update-liste` | Zeile in `/var/lib/spiele-autoupdate.liste` setzen/löschen · Liste ausgeben | `an`/`aus` |
| `schlaf <stack> an\|aus` · `schlaf-liste` | Zeile in `/var/lib/platzwart-schlaf.liste`; `aus` weckt einen schlafenden Server sofort · Liste ausgeben | `an`/`aus` |
| `konfig-lesen <stack>` | die elf Felder der Positivliste, `mem_limit` und bei Palworld die wirksamen Werte aus `PalWorldSettings.ini` | Stack |
| `konfig-setzen <stack> <feld> <wert>` | eines dieser Felder setzen, vorher Kopie `.vor-panel-<zeit>` | Feld aus der Liste; Wert `^[A-Za-z0-9ÄÖÜäöüß._!?+-]{1,40}$`; `mem_limit` wie `8g`; Palworld-Spielerzahl zweistellig |
| `compose-lesen` / `compose-setzen <stack> <name>` | alle Umgebungsvariablen lesen / eine setzen (Wert über stdin) — über `compose-feld` | dort: Sperrliste, kein Zeilenumbruch, Gerüstvergleich |
| `konfig-dateien` / `konfig-datei-lesen` / `konfig-datei-schreiben <stack> <relpfad>` | Konfigurationsdateien des Spiels — über `konfig-datei` (Inhalt über stdin) | dort: erst auflösen, dann prüfen |
| `groesse <stack>` | wie viel beim Entfernen gelöscht würde | Stack |
| `passwoerter` | alle Zugangsdaten aus compose-Dateien, `panel.json` und Palworlds wirksamer INI | — |
| `katalog` | Katalog mit Zustand je Eintrag (`installiert`/`frei`) | — |
| `installieren <schlüssel>` | `spiel-verwalten installieren`, danach Kanal-Abgleich anstoßen und DNS-Namen setzen | Form des Schlüssels |
| `deinstallieren <stack>` | nur mit `panel.json`: `spiel-verwalten deinstallieren`, **danach** DNS-Namen entfernen, Kanal-Abgleich anstoßen | Stack, `panel.json` muss existieren |
| `fremd-entfernen <stack>` | nur **ohne** `panel.json` (von Hand gebaut): `spiel-verwalten fremd-entfernen`, danach DNS-Namen entfernen (#253), Kanal-Abgleich | Stack, `panel.json` darf nicht existieren |
| `einrichtung` | Stand der Passwort-Einrichtung je Katalogserver | — |
| `port-ermitteln <stack>` | übergibt an `port-ermitteln` (und das per `execv` an `spiel-einrichtung`) | Stack |
| `port-freigeben <stack>` | Freigabe von Hand für Spiele ohne Beitrittspasswort — `spiel-einrichtung --freigeben` | Stack; „nur bei `keins`" prüft `spiel-einrichtung` |
| `whitelist <stack> liste\|hinzu\|weg [spieler]` | Minecraft-Whitelist über `rcon-cli` **im** Container | Image `itzg/minecraft-server`, Container läuft, Name `^[A-Za-z0-9_]{3,16}$` |
| `mod-ziel` / `mod-liste <stack>` | wohin ein Mod gehört / was dort liegt — `mod-verwalten` | Stack |
| `mod-annehmen <stack> <datei>` | Moddatei über stdin an `mod-verwalten` | Name ohne `/`, `\`, führenden Punkt; `^[A-Za-z0-9._-]{1,100}$` |
| `mod-entfernen <stack> <name>` | Mod löschen — `mod-verwalten` | `^[A-Za-z0-9._-]{1,100}$` |
| `workshop kann\|liste <stack>` | Workshop-Anbindung vorhanden? Suche möglich? · eingetragene Mods | Stack |
| `workshop hinzu\|weg <stack> <id>` | eine ID ein- oder austragen | `^[0-9]{3,12}$` |
| `workshop pruefen <stack> <eingabe>` | Link, ID oder Sammlung auflösen und bei Steam prüfen | `^[A-Za-z0-9:/?=&._%-]{1,200}$` |
| `workshop suche <stack> <text> [seite]` | Workshop-Suche (braucht den Steam-Schlüssel) | Text `^[A-Za-z0-9ÄÖÜäöüß ._-]{1,60}$`, Seite ein- oder zweistellig |
| `archive <stack>` | Archivliste | Stack; wartet bis 150 s auf die Borg-Sperre |
| `archiv-groesse <stack> <archiv>` | Originalgröße des Archivs, vor dem Download angezeigt | Archiv; 150 s Sperrwartezeit |
| `archiv-strom <stack> <archiv>` | `borg export-tar … -` als Strom auf stdout, **ohne** Zeitlimit | Archiv; 900 s Sperrwartezeit |
| `restore <stack> <archiv>` | Wiederherstellung, Ablauf in [05-sicherung.md](05-sicherung.md#über-die-oberfläche) | Archiv; 600 s Sperrwartezeit |
| `kanaele abgleich` | `kanal-abgleich.service` im Hintergrund anstoßen | — |
| `kanaele vorschau <stack>` | was beim Entfernen mit den Kanälen geschieht | Stack |
| `kanaele pruefen` / `pruefen-discord` | TeamSpeak-Zugang bzw. Discord-Bot prüfen, Zugangsdaten über stdin | — |
| `dns setzen\|entfernen <name>` · `dns liste\|pruefen` | über `dns-pflegen` | Aktion aus der Liste; Name wie Stack |
| `modul katalog` · `modul status <modul>` | Zusatzmodule auflisten, Stand eines Moduls | Modulname `^[a-z][a-z0-9-]{1,30}$` |
| `modul installieren\|entfernen <modul> [--auch-daten]` | Modul einrichten oder entfernen | Modulname; als Zusatz ist **nur** `--auch-daten` erlaubt |
| `modul schalter <modul> <name> <an\|aus>` | einen Schalter des Moduls setzen | Name wie oben; Wert nur `an` oder `aus`; ob es den Schalter gibt, prüft `modul-verwalten` gegen den Katalog |
| `modul einstellung <modul> <name> <wert>` | eine Einstellung setzen | Name `^[a-z_][a-z0-9_]{1,30}$`, Wert `^[A-Za-z0-9]{1,12}$`; erlaubte Werte stehen im Katalog |

`status` holt **einen** `docker stats` für alle Container, nicht einen je
Container: Ein Aufruf kostet rund 1,9 s unabhängig von der Anzahl. Einzeln
gerufen brauchte die Aktion 13,2 s, gesammelt 2,0 s (gemessen 2026-09-06).

**Here-String statt Pipe.** Die Stack-Prüfung vergleicht mit `grep -qx` gegen
die Liste der Verzeichnisse — über einen Here-String. In einer Pipe beendet
sich `grep -q` beim ersten Treffer, die schreibende Seite bekommt `SIGPIPE`, und
mit `set -o pipefail` gilt die Pipeline als gescheitert: Jeder **gültige** Stack
wäre abgewiesen worden.

> *The only bridge between panel and system, invoked through sudo by the `panel`
> user. Every action is a hard-wired branch whose parameters are checked against
> an allow-list before anything happens; no eval, no shell expansion of input.
> Large or secret values — file contents, mod files, credentials — arrive on
> stdin, never as an argument, because arguments are visible to every user in
> the process list. The table lists every action with its purpose and its own
> check: stack names must match a pattern and exist under `/opt/stacks`,
> archive names must match the backup naming and start with the stack, and the
> archive paths refuse cleanly when backups are switched off. `status` issues a
> single `docker stats` for all containers: one call costs ~1.9 s regardless of
> count — per-container calls took 13.2 s versus 2.0 s batched. The stack check
> uses a here-string rather than a pipe: `grep -q` exits on the first match, the
> writer gets SIGPIPE, and with `pipefail` every valid stack would have been
> rejected.*

#### `logs`: die Zeilenzahl wird hier begrenzt

Die letzten Zeilen aus `docker logs`, mit Zeitstempeln, `2>&1` (die meisten
Spieleserver schreiben auf stderr). Die Zeilenzahl wird **hier** begrenzt, nicht
in der Oberfläche: 1 bis 2000, alles darüber wird auf 2000 gekappt, alles
Nichtnumerische abgewiesen — mit einer Meldung, die genau das nennt, was geprüft
wurde („99999" *ist* eine Zahl, nur eine zu große). Ein unbegrenztes `--tail`
auf einen tagelang laufenden Container wäre ein Selbstangriff auf das Panel.
Auch ein gestoppter Container hat Logs; gerade dann sind sie interessant.

> *The last lines of `docker logs`, with timestamps and stderr merged, since
> most game servers write there. The line count is bounded here, not in the UI:
> 1 to 2000, anything larger capped, anything non-numeric refused with a message
> naming exactly what was checked. An unbounded `--tail` on a container running
> for days would be a denial of service against the panel. Stopped containers
> have logs too — that is when they matter most.*

### `spiel-verwalten`

```
spiel-verwalten katalog                     Katalog als Tabelle, mit Zustand je Eintrag
spiel-verwalten installieren <schluessel>
spiel-verwalten deinstallieren <stack>      nur mit panel.json
spiel-verwalten fremd-entfernen <stack>     nur OHNE panel.json (von Hand gebaut)
spiel-verwalten groesse <stack>             was beim Entfernen gelöscht würde
spiel-verwalten ausschluesse                Sicherungsausschlüsse installierter
                                            Katalogspiele an den Katalog angleichen
spiel-verwalten katalog-abgleich            ausschluesse + fehlende Umgebungsvariablen
                                            mit ihrem wörtlichen Vorgabewert nachtragen
```

**Installieren** prüft Platz (`platte_gb` + 10 GB Reserve) und Ports gegen die
**tatsächlich gebundenen** (lokale eingeschlossen), würfelt zwei Passwörter,
legt das Stack-Verzeichnis `0750 root:panel` und das Datenverzeichnis als UID
4711 an (bei ich777-Images zusätzlich `steamcmd/`, `serverfiles/` und die
Katalog-`ordner`), schreibt `compose.yaml` (`0600`) und `panel.json` (`0640
root:panel`, mit `einrichtung_offen`, `port_regel`, `ports_ausstehend` und
gegebenenfalls `befehlsdatei`), trägt die Zugangsdaten, den Ausschlussblock und
das Titelbild ein, lässt bei Spielen mit `passwort.befehle` die Befehlsdatei
**vor dem ersten Start** schreiben (`spiel-einrichtung --vorab`; scheitert das,
startet nichts) und startet, wenn der freie Arbeitsspeicher `mem_gb` + 2 GB
beträgt. Öffentliche Ports stehen dann noch **nicht** in der compose.yaml — die
trägt `port-ermitteln` ein, sobald das Beitrittspasswort steht.

**Deinstallieren** zieht **erst** eine Endsicherung (Wartezeit bis 1800 s);
schlägt sie fehl, wird nichts gelöscht. Danach Leerlauf abräumen
(`platzwart-schlaf --vergessen`, ohne zu starten), `docker compose down`,
Datenverzeichnis, Stack-Verzeichnis, Ausschlussblock, Titelbild, Zugangsdaten
und den Auto-Update-Eintrag. Verlangt zwingend eine `panel.json` und schützt
damit die von Hand gebauten Stacks. **Fremd-entfernen** ist derselbe Ablauf für
Stacks ohne `panel.json`; die Datenverzeichnisse kommen dann aus der
compose.yaml, begrenzt auf `/srv/games/`.

**Katalog-Abgleich** läuft in Stufe 30 und nach jedem `ausrollen.sh` mit dem
Katalog oder der Ausschlussliste — die Fassung der Ausschlussliste im
Repositorium trägt die Blöcke der installierten Spiele nicht, der Abgleich legt
sie danach wieder an. Er ändert nie einen gesetzten Wert, trägt nur fehlende Variablen mit
wörtlichem Vorgabewert nach (nie Platzhalter wie `{PASSWORT}`, über `compose-feld
anlegen` mit Gerüstvergleich) und startet nichts neu. Ändert sich ein
Ausschlussblock, wird die gemerkte Archivgröße dieses Stacks verworfen.

> *The installer and remover. Installing checks disk space and real port
> collisions (local ports included), generates two passwords, creates the stack
> directory and the data directory as UID 4711 (plus the folders ich777 images
> expect and the catalogue's `ordner`), writes `compose.yaml` and `panel.json`
> (with the setup state, the port rule, the held-back public ports and, where
> needed, the command file), records credentials, the backup exclusion block
> and the artwork, writes the command file before the first start for games
> that need it (if that fails, nothing starts), and starts when free memory
> covers the limit plus 2 GB. Public ports are not yet in the compose file —
> `port-ermitteln` adds them once the join password is in place. Uninstalling
> takes a final backup first and aborts if it fails, then clears idle sleep
> without starting the server, runs compose down and removes data, stack,
> exclusion block, artwork, credentials and the auto-update entry; it requires
> `panel.json`, which protects the hand-built stacks. `fremd-entfernen` is the
> same flow for stacks without `panel.json`, taking the data paths from the
> compose file, limited to `/srv/games/`. The catalogue sync runs in stage 30
> and after every catalogue rollout: it never changes a set value, only adds
> missing variables with literal defaults through `compose-feld anlegen`, and
> restarts nothing; a changed exclusion block resets the stored archive size.*

### `spiel-einrichtung`

```
spiel-einrichtung                  alle offenen Einrichtungen abarbeiten (Timer)
spiel-einrichtung <stack>          nur diesen, auch wenn er nicht offen ist
spiel-einrichtung --vorab <stack>  Befehlsdatei vor dem ersten Start schreiben
spiel-einrichtung --freigeben <stack>  Port eines Spiels ohne Passwort freigeben
```

Wird vom Timer alle zwei Minuten gerufen, unter einer Sperre
(`/run/spiel-einrichtung.lock`), damit sich zwei Läufe nicht gegenseitig
überschreiben. Sucht bei frisch installierten Servern die
Konfigurationsdatei und trägt Beitrittspasswort, Adminpasswort und
Spielerzahl ein. Erkennt `.ini`, `.json`, `.xml` und `.cfg` über
Feldnamensmuster, im `.cfg`-Fall auch den GoldSrc-Stil ohne Gleichheitszeichen
und den id-Tech-Stil mit `set`-Präfix. Schalter (`true`/`false`, Namen wie
`NoPassword`) und Kommentarfelder bleiben unangetastet; ersetzt wird in JSON nur
Gleiches durch Gleiches. Bei `passwort.art = params` entscheidet der laufende
Server per A2S („Passwort nötig"), bei einer Befehlsdatei ebenfalls.

Meldet nach sechs Stunden ohne Feld sichtbar; der Port bleibt dann zu, bis ein
Passwort gefunden oder per A2S bestätigt ist (E26). Vor jeder Meldung sieht es
nach, ob der Container überhaupt läuft, und benennt sonst den wahren Grund
(„SERVER STARTET NICHT …"). Ruft **zuletzt** `port-ermitteln --aus-einrichtung`,
sofern der Eintrag eine `port_regel` oder ausstehende Ports trägt — und nur,
wenn die Einrichtung entschieden ist (E23). Zählt nebenbei die
Konfigurationsdateien je Server für die Anzeige
(`/opt/panel/daten/konfigzahlen.json`).

`--freigeben` gilt nur für `passwort.art = keins` (Minecraft, TeamSpeak) und
schreibt die Freigabe unter derselben Sperre wie der Timer.

> *Called by the timer every two minutes, under a lock. Finds the config file a
> fresh server wrote on first start and sets join password, admin password and
> player count, matching field names by pattern across ini/json/xml/cfg —
> including the GoldSrc style without "=" and the id-Tech style with a `set`
> prefix. Switches and comment fields are left alone, and JSON only replaces like
> with like. For start-parameter passwords and command files the running server
> decides via A2S. After six hours without a field it reports visibly and the
> port stays closed (E26); before any such message it checks whether the
> container runs at all and names the real reason otherwise. It calls
> `port-ermitteln --aus-einrichtung` last, only once setup has settled (E23),
> and counts config files per server for the panel. `--vorab` writes a command
> file before the first start; `--freigeben` releases the port of a game
> without a join password, only for `keins`, under the same lock.*

### `port-ermitteln`

```
port-ermitteln <stack> [--zeigen] [--aus-einrichtung]
```

Trägt die öffentlichen Ports eines Katalogservers in die `compose.yaml` ein —
der Schritt, der den Server nach außen öffnet. Zwei Fälle: die
**zurückgehaltenen Katalogports** aus `ports_ausstehend` (seit #156) und bei den
17 Spielen, deren Port vorab nicht bekannt ist, der Port aus der Konfiguration,
die der erste Start geschrieben hat (Regel `port_regel` im Katalogeintrag, aus
LinuxGSM übernommen).

| Exit | Bedeutung |
|---|---|
| 0 | Port eingetragen, Container neu gestartet |
| 1 | Fehler (keine Regel, kein Datenverzeichnis, kein freier Ersatzport) |
| 2 | **warte** — Datei oder Feld noch nicht da; der Timer versucht es erneut |

`--zeigen` liest nur und ändert nichts. Ohne `--aus-einrichtung` übergibt das
Werkzeug per `execv` an `spiel-einrichtung`, damit es **genau einen** Weg gibt,
der einen Port veröffentlicht — sonst öffnete der Knopf im Panel einen Server,
bevor sein Beitrittspasswort steht. Kollidiert ein Port, weicht der **Host**-Port
auf 30500–30999 aus; der Containerport bleibt.

Nach dem Schreiben vergleicht es die `compose.yaml` mit sich selbst **ohne** den
`ports`-Block und rollt zurück, falls sich mehr geändert hat als die Ports.

> *Writes a catalogue server's public ports into its compose file — the step
> that exposes it. Two cases: the catalogue ports held back in
> `ports_ausstehend` (since #156), and for the 17 games whose port is unknown
> beforehand, the port from the config the first start wrote (rule copied from
> LinuxGSM). Exit 0 means written and restarted, 1 an error, 2 "wait" — the
> timer retries. `--zeigen` only reads. Called on its own it hands over to
> `spiel-einrichtung` via `execv`, so exactly one path publishes ports. A
> colliding host port moves into 30500–30999; the container port stays. After
> writing, the compose file is compared with itself minus the ports block and
> rolled back if anything else changed.*

### `spiele-sicherung`

```
spiele-sicherung                 nur laufende Spiele und Dienste
spiele-sicherung --alle          auch gestoppte, dazu /opt/stacks (config-*),
                                 /etc (etc-*) und /opt/panel/daten (panel-*)
spiele-sicherung --nur <name>    ein einzelnes Spiel
spiele-sicherung --selbsttest    die drei Prüfungen und die Verdrahtung
```

Ein Archiv je Spiel, Name `<spiel>-JJJJMMTT-HHMMSS`, Kompression `zstd,6`.
`prune` je Präfix, anschließend `borg compact`. Jeder Borg-Aufruf wartet bis zu
900 s auf die Sperre eines anderen Laufs (`SICHERUNG_SPERRE_WARTEN`). Nach jedem
Spielarchiv drei Prüfungen — Untergrenze (unter 50 kB), Einbruch (unter 25 % des
letzten Laufs) und Stillstand (24 h nichts Neues bei laufendem Container) —,
deren Funde mit einem Tag Ruhezeit nach Discord gehen; ein fehlgeschlagener Lauf
geht als Störung mit drei Stunden Ruhezeit hinaus, der nächste gelungene als
Entwarnung. Rechte `0700 root` — die Datei enthält den Pfad zum Repositorium.
Unmittelbar vor der Schleife prüft jeder Lauf, dass seine Helfer definiert sind,
und bricht sonst mit Exit **3** ab. Einzelheiten:
[05-sicherung.md](05-sicherung.md).

> *One archive per game named `<game>-YYYYMMDD-HHMMSS`, zstd level 6, pruned per
> prefix and compacted afterwards. Every borg call waits up to 900 s for another
> run's lock. Three checks follow each game archive — an absolute floor, a
> collapse against the previous run, and silence (nothing new for 24 h while
> the container runs) — reported to Discord with a one-day quiet period; a
> failed run is reported as a fault with three hours of quiet, the next good run
> as an all-clear. The full run also archives `/opt/stacks`, `/etc` and the
> panel data. Mode 0700 root, since the file holds the repository path. Right
> before the loop every run checks that its helpers are defined and aborts with
> exit 3 otherwise. Details in the backup chapter.*

### `sicherung-probe`

```
sicherung-probe <stack>              neuestes Archiv
sicherung-probe <stack> --archiv X   ein bestimmtes
sicherung-probe --selbsttest
```

Spielt ein Archiv **probeweise** zurück, ohne den Server anzufassen: auspacken
in ein Wegwerfverzeichnis, hineinsehen, wegwerfen. Meldet, ob es sich auspacken
lässt, was herauskommt (Dateien, Größe, jüngste Datei) und wie das zu dem steht,
was jetzt auf der Platte liegt — mit denselben Ausschlüssen herausgerechnet, nach
Borgs `sh:`-Musterregel. Schreibt nie nach `/srv/games` (es startet zwingend aus
dem Wegwerfverzeichnis), lässt nichts liegen, bricht ab, wenn danach weniger als
10 GB frei blieben (`PROBE_RESERVE_GB`), wartet bis 15 min auf die Borg-Sperre
(`PROBE_LOCK_WAIT`) und läuft bewusst **nicht** auf einem Zeitgeber. Von Hand
aufzurufen, als root.

> *Test-restores an archive without touching the server: extract to a scratch
> directory, look inside, throw it away. Reports whether it extracts, what comes
> out (files, size, newest file) and how that compares with the live data, with
> the same exclusions subtracted using borg's pattern rule. Never writes into
> `/srv/games`, leaves nothing behind, refuses when less than 10 GB would remain
> free, waits up to 15 minutes for the borg lock, and deliberately runs on no
> timer. Called by hand, as root.*

### `spiele-autoupdate`

```
spiele-autoupdate [--trocken] [--jetzt]
```

Vom Timer nachts um 05:15 (±30 min) gerufen. Nimmt nur Server, die in
`/var/lib/spiele-autoupdate.liste` stehen (Schalter `autoupdate` auf der
Einstellungsseite), und prüft je Server vier Bedingungen einzeln:
freigeschaltet, sicherbar (die Sicherung erzwingt `panel-aktion aktualisieren`),
ruhig (unter 4 kB/s über 20 s, `AU_RUHE_BYTES`, `AU_MESSDAUER`; ein fallender
Zähler heißt Neustart und überspringt den Server) und wirklich neu. Ein
gestoppter Server wird ohne Verkehrsprüfung aktualisiert. Ein eingespieltes
Update geht nach `#platzwart-meldungen`, ein gescheitertes nach
`#platzwart-stoerung`. `--trocken` zeigt nur, `--jetzt` misst ohne die 20 s
Wartezeit. Exit 1, wenn mindestens ein Update scheiterte.

> *Called by the timer at 05:15 (±30 min). Only servers listed in
> `/var/lib/spiele-autoupdate.liste` are considered, and four conditions are
> checked per server: enabled, backup possible (enforced by `panel-aktion
> aktualisieren`), quiet (under 4 kB/s over 20 s; a falling counter means a
> restart and skips the server) and actually new. A stopped server is updated
> without the traffic check. Applied updates go to the notices channel, failed
> ones to the faults channel. `--trocken` only shows, `--jetzt` skips the 20 s
> wait. Exit 1 if at least one update failed.*

### `spiele-wiederanlauf`

Ohne Parameter; läuft als `spiele-wiederanlauf.service` beim Hochfahren, nach
`docker.service`, und nur, wenn `/var/lib/spiele-wiederanlauf` existiert.
Startet genau die Stacks aus dieser Liste, die `panel-aktion neustart` vor dem
Anhalten geschrieben hat — überspringt, was es nicht mehr gibt oder schon
läuft, und räumt die Liste **nach** dem Lauf weg. Ohne diese Liste käme nach
einem Neustart über das Panel kein Server zurück: `docker compose stop` schaltet
`restart: unless-stopped` ab, und Docker merkt sich das über den Neustart.

> *No parameters; runs as a boot unit after docker, only when the list exists.
> Starts exactly the stacks `panel-aktion neustart` recorded before stopping
> them, skips what no longer exists or already runs, and removes the list after
> the run. Without it nothing would return after a reboot from the panel: an
> explicit stop disables `unless-stopped`, and Docker remembers that across the
> reboot.*

### `platzwart-schlaf`

```
platzwart-schlaf --pruefen          vom Zeitgeber: wer darf schlafen?
platzwart-schlaf --wecken <stack>   von der Socket-Aktivierung
platzwart-schlaf --schlafen <stack> von Hand
platzwart-schlaf --vergessen <stack> beim Entfernen eines Servers (startet NICHT)
platzwart-schlaf --liste
platzwart-schlaf --selbsttest
```

Legt leere Server schlafen und weckt sie beim ersten Paket. Freigeschaltet wird
je Server über `/var/lib/platzwart-schlaf.liste`. Leer heißt: 30 min eine echte
Spielerzahl von null (`SCHLAF_LEER_MIN`) oder, wo es keine gibt, 180 min unter
1,5 kB/s (`SCHLAF_LEER_MIN_VERKEHR`, `SCHLAF_RUHE_BYTES`); eine fehlende Zahl
gilt nie als null. Beim Schlafenlegen hält es den Container an, legt je
öffentlichem Spielport eine Socket-Unit `platzwart-wecken-<stack>.socket` und
eine ufw-Regel mit dem Kommentar `platzwart-schlaf:<stack>` an. Das erste Paket
startet `platzwart-wecken@<stack>.service`, das per `Conflicts=` den Socket
beendet, die ufw-Regeln wieder entfernt, wartet, bis die Ports frei sind, den
Container startet und am **Ergebnis** prüft, ob die Ports veröffentlicht sind
(sonst einmal `--force-recreate`). Mehr als zwölf Weckvorgänge am Tag
(`SCHLAF_FLATTER`) werden als Flattern gemeldet. Jeder Lauf nimmt die Sperre
`/run/platzwart-schlaf.lock`; der Zustand steht in
`/var/lib/platzwart-schlaf.json`. Verwaltungsports auf `127.0.0.1` werden nie
in einen Weckposten übernommen. Einzelheiten:
[03-panel.md](03-panel.md#leerlauf-schlafen-legen-und-beim-beitritt-wecken).

> *Puts empty servers to sleep and wakes them on the first packet; enabled per
> server through its list. Empty means a real player count of zero for 30
> minutes or, where there is none, 180 minutes under 1.5 kB/s; a missing count
> never counts as zero. Sleeping stops the container and creates, per public
> game port, a socket unit and a ufw rule tagged with the stack. The first
> packet starts the wake unit, which ends the socket via `Conflicts=`, removes
> the ufw rules, waits for the ports to free up, starts the container and checks
> the result rather than the return code (recreating once if the ports are
> missing). More than twelve wake-ups a day are reported as flapping. Every run
> takes a lock; localhost management ports never become wake ports.*

### `spieler-zaehlen`

```
spieler-zaehlen [--einmal] [--zeigen] [--selbsttest]
```

Fragt jede Minute (Timer) die laufenden Server per **A2S_INFO** nach Spielern
und Plätzen — mit dem Challenge-Schritt, den Server seit 2020 verlangen (die
erste Anfrage bekommt `0x41`). Der Abfrageport wird **gefunden**, nicht
konfiguriert: Die veröffentlichten UDP-Ports werden durchprobiert, der
antwortende wird gemerkt. Antwortzeit 1,2 s (`SPIELER_TIMEOUT`); wer schweigt,
wird 30 min lang nicht erneut gefragt (`SPIELER_STUMM_PAUSE`,
`/var/lib/platzwart-spieler.stumm`). Alle Server werden parallel gefragt.
Schreibt `/var/lib/platzwart-spieler.json` mit Spielern (`spieler`), Plätzen
(`max`), Servername, Spiel, Abfrageart, antwortendem Port und Zeit; **wer nicht
antwortet, steht nicht drin** — keine erfundene Null. Die Abfragearten sind
Klassen (`ARTEN`), eine weitere ist eine Klasse und ein Eintrag. Die Bestätigung
„Passwort nötig" (E27) fragt `spiel-einrichtung` mit einer eigenen
A2S-Abfrage (Feld `visibility`).

> *Queries running servers every minute via A2S_INFO for players and slots,
> including the challenge step servers have required since 2020. The query port
> is discovered, not configured: published UDP ports are probed and the one that
> answers is remembered. A silent server is not asked again for 30 minutes;
> all servers are queried in parallel. Writes players, slots, server name,
> game, query kind, answering port and a timestamp; a server that does not
> answer is absent rather than zero. Query kinds are classes, so another
> protocol is one class and one entry. The "password required" confirmation
> (E27) is done by `spiel-einrichtung` with an A2S query of its own (the
> visibility field).*

### `platzwart-verlauf`

```
platzwart-verlauf [--zeigen] [--selbsttest]
```

Schreibt alle fünf Minuten je Server einen Wert nach
`/var/lib/platzwart-verlauf.json`: `[zeit, mem_mb, cpu_prozent, spieler|null]`.
Ein Ringpuffer mit 2016 Werten je Server (`VERLAUF_MAX`) — bei diesem Abstand
eine Woche, rund 60 kB. Jeder Wert trägt seine eigene Zeit, damit Lücken
sichtbar bleiben; nur frische Spielerzahlen (unter drei Minuten alt) gehen
hinein. Entfernt wird nur, was es als Container nicht mehr gibt. Läuft kein
Container, endet es ohne Fehler; antwortet Docker nicht, mit Fehler.

> *Every five minutes, one sample per server — time, memory, CPU, players or
> null — into a ring buffer of 2016 samples per server (a week, about 60 kB).
> Every sample carries its own timestamp so gaps stay visible; only fresh player
> counts are recorded. Only containers that no longer exist are dropped. Nothing
> running is not an error; Docker not answering is.*

### `platzwart-metriken`

```
platzwart-metriken [--zeigen] [--selbsttest]
```

Schreibt die Zahlen des Platzwarts für Prometheus nach
`/var/lib/platzwart-metriken/*.prom`; node_exporter liest den Ordner mit
(*textfile collector*). Gibt es nur zusammen mit dem Modul **Statistik**
([12](12-module-und-statistik.md)) — sein Zeitgeber ist sonst aus.

Gemessen wird je Lauf einmal `docker stats` für alle Container zusammen (ein
Aufruf ~2 s, je Container gerufen 13 s), dazu Spielerzahlen, Schlaf- und
Update-Listen, Größe und Zeit der letzten Archive aus
`/var/lib/spiele-sicherung.groessen` und — höchstens stündlich — die belegte
Platte je Server. Welche Quellen laufen, steht in
`/opt/module/statistik/modul.json`; eine abgeschaltete Quelle bekommt ihre Datei
**gelöscht**, damit kein eingefrorener Wert wie ein gemessener aussieht.

Jede Datei entsteht über eine temporäre Datei und `rename()`: node_exporter
liest jederzeit und verwirft eine halb geschriebene Datei ganz.

Der Grund für dieses Werkzeug ist eine Grenze: Container-Metriken kämen sonst
von cAdvisor, und cAdvisor will den Docker-Socket (Grenze 1, E36).

> *Writes the Platzwart's numbers for Prometheus into `.prom` files that
> node_exporter reads. Exists only with the statistics module. One `docker stats`
> call per run for all containers, plus player counts, sleep and update lists,
> backup size and time, and hourly disk usage per server. Which sources run comes
> from the module's state file; a switched-off source has its file deleted so no
> frozen value looks measured. Files are written atomically. It exists because
> container metrics would otherwise come from cAdvisor, which wants the Docker
> socket (boundary 1, E36).*

### `modul-verwalten`

```
modul-verwalten katalog | status <modul>
modul-verwalten installieren <modul> | entfernen <modul> [--auch-daten]
modul-verwalten schalter <modul> <name> <an|aus>
modul-verwalten einstellung <modul> <name> <wert>
modul-verwalten anwenden <modul> | dashboards <modul> | --selbsttest
```

Der Modulweg neben dem Spielweg (#261, E35): eigener Katalog
(`/etc/module-katalog.json`), eigene Positivliste, keine Spielmaschinerie.
Installiert nach `/opt/module/<modul>`, Daten nach `/srv/module/<modul>` —
**nicht** in die Verzeichnisse der Spielserver: Dort erschien das Modul als
Spielserver, der immer gestoppt ist (#263).
kopiert die compose-Datei **unverändert** aus `/etc/module/<modul>/` und
erzeugt daneben `prometheus.yml`, `grafana-provisioning/`, `.env` und
`modul.json`.

Schalter setzen **compose-Profile**, Einstellungen landen in der `.env` — die
compose-Datei wird nie umgeschrieben und bleibt byte-gleich mit der Vorlage.
Abgeschaltete Profile werden ausdrücklich abgeräumt, sonst liefe ein Container
weiter, dessen Schalter aus ist.

Die Caddy-Route entsteht in `/etc/caddy/module.conf`: erst Klammern zählen, dann
atomar schreiben, dann `caddy validate`, dann `systemctl reload caddy` — und bei
einer Ablehnung die alte Datei zurück. Die Klammernzählung ist nicht überflüssig:
`caddy validate` erkennt eine unbekannte Direktive, eine offene Klammer am
Dateiende aber nicht (gemessen).

`dashboards <modul>` setzt aus der Vorlage je installiertem Spielserver ein
Dashboard zusammen und entfernt die, deren Server es nicht mehr gibt. Aufgerufen
von `anwenden`, von `panel-aktion` nach jeder Installation und Entfernung und von
Stufe 60 — jeder Weg, der einen Server anlegt oder entfernt, zieht die
Dashboards nach.

Eine Änderung zur Zeit: Jede verändernde Aktion nimmt eine Sperre (`flock`,
`/run/modul-verwalten.sperre`) und wartet höchstens zehn Minuten darauf.
Gespeichert wird der neue Zustand **erst nach** erfolgreichem Anwenden.

Umgebungsvariablen für Tests: `MODUL_KATALOG`, `MODUL_VORLAGEN`, `MODUL_STACKS`,
`MODUL_CADDY`, `MODUL_CADDYFILE`, `MODUL_MELDEN`, `MODUL_TIMER`, `MODUL_VERZ`,
`MODUL_SPERRE`, `MODUL_SPERRFRIST`.

> *The module path beside the game path: its own catalogue, its own allow-list,
> none of the game machinery. Installs to `/opt/module/<module>` with data in
> `/srv/module/<module>` — outside the game servers' directories, where it showed
> up as a permanently stopped server (#263) — copies the compose file unchanged and generates the
> rest beside it. Switches set compose profiles and settings go into the .env, so
> the compose file is never rewritten; deactivated profiles are explicitly
> removed, or a container would keep running with its switch off. The Caddy route
> is written after counting braces, atomically, then validated and reloaded, with
> a rollback if Caddy refuses — the brace count is not redundant, since validation
> catches an unknown directive but not an unclosed brace at the end (measured).*

### `platzwart-ereignisse`

```
platzwart-ereignisse [--selbsttest]
```

Vergleicht jede Minute die Spielerzahlen mit dem letzten Lauf
(`/var/lib/platzwart-ereignisse.json`) und meldet den Wechsel zwischen leer und
belegt über `kanal-verwalten ereignis` in den **Textkanal des Servers**. Aus,
solange der Schalter bei den Discord-Kanälen nicht steht; der Stand wird
trotzdem fortgeschrieben, damit das Einschalten nicht alles Aufgestaute auf
einmal meldet.

Nur frische Messwerte (`EREIGNIS_FRISCH`, 180 s). **`zeit` in
`platzwart-spieler.json` ist ein Zeitstempel, kein Alter** — der erste Entwurf
verglich ihn gegen die Sekundenzahl, jeder Server fiel heraus, und der
Selbsttest merkte nichts, weil er dieselbe Annahme traf.

> *Compares player counts to the previous run and reports the transition between
> empty and occupied into the server's own channel; off until the switch is set,
> but the state is carried forward so switching on does not report everything at
> once. Fresh readings only — and `zeit` is a timestamp, not an age, which the
> first draft got wrong while its self-test shared the assumption.*

### `platzwart-status`

```
platzwart-status [--zeigen] [--ziel VERZEICHNIS]
```

Schreibt jede Minute die öffentliche Statusseite als fertige Datei
`/var/lib/platzwart-status/index.html` (daneben geschrieben, dann umbenannt), die
Caddy unter `/status` unmittelbar ausliefert — ohne `reverse_proxy`, ohne
Sitzung. Zeigt je Server Zustand, Beitrittsadresse und — wo frisch gemessen —
Spielerzahl; lässt Server mit offener Einrichtung und Server ohne Adresse weg.
Adressen aus `/etc/spiele-adressen.json` bzw. `panel.json`. Kein JavaScript,
kein Bild; das Zeichen ist Inline-SVG aus `logo.py`, das Tab-Symbol eine
`data:`-URI. `--zeigen` gibt die Seite aus, statt sie zu schreiben.

> *Every minute, writes the public status page as a finished file (beside the
> target, then renamed) that Caddy serves directly under `/status` — no reverse
> proxy, no session. Shows state, join address and, where freshly measured,
> player count per server; servers with unfinished setup or without an address
> are left out. No JavaScript, no images; the mark is inline SVG and the tab icon
> a `data:` URI. `--zeigen` prints instead of writing.*

### `platzwart-wache`

```
platzwart-wache [--trocken] [--selbsttest]
```

Alle fünf Minuten: Was stimmt gerade nicht? Verglichen mit dem letzten Lauf
(`/var/lib/platzwart-wache.zustand`) wird **Neues** als Störung und
**Weggefallenes** als Entwarnung gemeldet; Unverändertes bleibt still.

| Befund | Schwelle |
|---|---|
| Container abgestürzt | beendet mit einem Exit außer 0 und 143 |
| Neustartschleife | ≥ 3 Neustarts (`WACHE_NEUSTART_WARN`) **und** startet gerade neu oder läuft < 10 min (`WACHE_FRISCH_MIN`) |
| Gesundheitstest schlägt fehl | `unhealthy` |
| Platte knapp | ≥ 85 % (`WACHE_PLATTE_WARN`) |
| Arbeitsspeicher knapp | ≥ 85 % belegt (`WACHE_SPEICHER_WARN`), Summe der Grenzen im Text |
| Einrichtung nicht abgeschlossen | Katalogserver mit offener Einrichtung — der Port ist zu |
| eigener Dienst fehlgeschlagen | `spiele-*`, `platzwart-*`, `spiel-*`, `sicherung-*`, Panel, Caddy, ttyd, Palworld-Neustart — mit den letzten Journalzeilen |
| compose-Datei gilt nicht | Server aus `KONFIG_GILT` (heute Palworld): Spielkonfiguration fehlt, Passwort dort leer, oder compose und Konfiguration sagen Verschiedenes — die Meldung nennt nie einen Wert |

`--trocken` zeigt die Lage, ohne zu melden; `--selbsttest` spielt Vergleich,
Speicher- und Schleifenprüfung mit erfundenen Zahlen durch, je Fall still und
laut. Exit 1 nur, wenn das Melden selbst scheiterte.

> *Every five minutes: what is wrong right now? Compared with the previous run,
> anything new is reported as a fault and anything gone as an all-clear;
> unchanged stays silent. The table lists every finding and its threshold:
> crashed containers (any exit except 0 and 143), restart loops (at least three
> restarts and restarting or up for under ten minutes), failing health checks,
> disk and memory at 85 %, unfinished setup (port closed), failed units of
> this project with their last journal lines, and servers whose compose file
> does not govern (Palworld: the image applies no env vars, so a missing,
> password-less or diverging game configuration is reported — never with a
> value in the message). `--trocken` shows without
> reporting; `--selbsttest` runs the decisions on made-up numbers, one silent
> and one loud case each. Exit 1 only if reporting itself failed.*

### `platzwart-melden`

```
platzwart-melden stoerung "Titel" ["Text"]    -> Webhook WEBHOOK_STOERUNG
platzwart-melden meldung  "Titel" ["Text"]    -> Webhook WEBHOOK_MELDUNG
platzwart-melden --test                       beide Wege nachweisen
platzwart-melden ... --streng                 Fehler als Exit 1 statt 0
```

Schickt eine Meldung als Discord-Embed an einen von zwei Webhooks aus
`/etc/platzwart-melden.conf` (`0600 root`, von Hand angelegt; Vorlage
`etc/platzwart-melden.conf.beispiel`). Fehlt die Datei, tut es nichts und meldet
Erfolg. Vor dem Senden filtert es alles, was wie ein Passwort, Token oder eine
Webhook-URL aussieht. Derselbe Text aus demselben Anlass wird innerhalb der
Ruhezeit nicht wiederholt (Vorgabe 180 min, `PLATZWART_MELDEN_RUHE_MIN`;
Sicherungsbefunde 1440, Kanalbefunde 720; Gedächtnis
`/var/lib/platzwart-melden.gesehen`). `?wait=true` lässt Discord mit der
angelegten Nachricht antworten; bei 429 wird einmal gewartet. Exit immer 0,
außer mit `--streng` — ein Melder, der seinen Aufrufer scheitern lässt, macht
aus einer Meldung einen zweiten Ausfall.

> *Sends a Discord embed to one of two webhooks from a 0600 root file created by
> hand; with no file it does nothing and reports success. Everything that looks
> like a password, token or webhook URL is filtered before sending. The same
> text for the same cause is not repeated within the quiet period (180 minutes
> by default, 1440 for backup findings, 720 for channel findings). `?wait=true`
> makes Discord answer with the created message; on 429 it waits once. Exit is
> always 0 unless `--streng` — a notifier that fails its caller turns a message
> into a second outage.*

### `mod-verwalten`

```
mod-verwalten liste <stack>
mod-verwalten ziel  <stack>              wohin ginge es, und ist es gesichert?
mod-verwalten annehmen <stack> <name>    Datei über stdin
mod-verwalten entfernen <stack> <name>
mod-verwalten --selbsttest
```

Nimmt eine hochgeladene Moddatei an, prüft sie und legt sie ab. Wohin, steht je
Spiel in `/etc/spiele-mods.json` (`pfad` relativ zu `/srv/games/<stack>`,
`hinweis`, optional `voraussetzung` mit Pfad und Fehlermeldung — bei Valheim
`serverfiles/BepInEx/core`); steht ein Spiel nicht drin, wird abgewiesen statt
geraten. Schranken: Endungen `.zip .dll .jar .pak .json .cfg .txt .lua`, höchstens
512 MB (`MOD_MAX_BYTES`), mindestens 10 GB frei (`MOD_FREI_MIN_GB`), Dateiname
ohne Pfadanteile (abgewiesen, nicht zurechtgebogen). Archive werden **Eintrag
für Eintrag vor dem Entpacken** am aufgelösten Ziel geprüft (Zip Slip), Archive
mit Symlinks gar nicht angefasst, entpackt wird in ein Zwischenverzeichnis.
Eigentümer und Rechte kommen vom Zielverzeichnis. `ziel` sagt, ob das
Verzeichnis unter einen Sicherungsausschluss fällt (Borgs Musterregel).

> *Accepts an uploaded mod file, checks it and puts it in place. Where it goes
> is configured per game in `/etc/spiele-mods.json` (path, note, optional
> prerequisite — for Valheim `BepInEx/core`); an unlisted game is refused rather
> than guessed. Limits: eight extensions, 512 MB, 10 GB free, file names without
> path parts (refused, not sanitised). Archives are checked entry by entry
> against the resolved target before extraction (Zip Slip), archives containing
> symlinks are refused, extraction goes to a staging directory, and ownership is
> taken from the target directory. `ziel` tells whether the directory falls under
> a backup exclusion.*

#### Modpaket (#280)

```
mod-verwalten paket <stack>        packen und freigeben
mod-verwalten paket-weg <stack>    Freigabe zuruecknehmen
mod-verwalten paket-stand [stack]  was freigegeben ist
```

Packt das Modverzeichnis nach `/var/lib/platzwart-modpakete/<stack>.zip`
(`0644`), Stand daneben als `.json`. **Verknüpfungen werden ausgelassen** und im
Stand benannt; ein leeres Verzeichnis wird abgewiesen statt ein leeres Paket zu
erzeugen. Nach `annehmen` und `entfernen` packt das Werkzeug selbst neu, sofern
freigegeben. Caddy liefert das Verzeichnis unter `/modpaket/` ohne Listing.

> *Packs the mod directory into a zip with its state beside it; symlinks are left
> out and named, an empty directory is refused rather than producing an empty
> package, and uploads or removals repack automatically while released.*

### `workshop`

```
workshop kann    <stack>              unterstützt? Suche verfügbar?
workshop liste   <stack>              eingetragene Mods (ID, Titel, Größe, Stand)
workshop pruefen <stack> <eingabe>    Link, ID oder Sammlung -> je Element ok oder Grund
workshop suche   <stack> <text> [seite]
workshop hinzu   <stack> <id>
workshop weg     <stack> <id>
workshop --selbsttest
```

Pflegt die Workshop-Liste eines Servers an der Stelle, an der das Spiel sie
erwartet — je Spiel in `/etc/spiele-workshop.json` beschrieben (`art`, `datei`,
`inhalt`, gemessen am echten Server): Project Zomboid (`WorkshopItems=` und
`Mods=` in `servertest.ini`, Inhalt wird mit dem steamcmd des Images vorab
geladen, weil die Mod-ID aus `mod.info` kommt), Unturned (`File_IDs` in
`WorkshopDownloadConfig.json`), Don't Starve Together (`ServerModSetup` und
`modoverrides.lua`, nur Shard `Master`) und Killing Floor 2
(`ServerSubscribedWorkshopItems` in `LinuxServer-KFEngine.ini`, Downloadmanager
an erster Stelle, `KFGame/Cache` wird angelegt). **Jede ID wird bei Steam
nachgeschlagen** und muss zu genau diesem Spiel gehören (`consumer_app_id` bzw.
bei der Suche `consumer_appid` gleich der Katalog-`appid`); gesperrte, unbekannte
und über 2 GB große Elemente (`WORKSHOP_MAX_BYTES`) werden abgewiesen, eine
unbekannte Größe ebenfalls. Sammlungen werden in ihre Elemente aufgelöst. Die
Suche und die Größe über `IPublishedFileService/GetDetails` brauchen den
Steam-Web-API-Schlüssel aus `/opt/panel/daten/steam-api.conf`. Beim Speichern
wird der Inhalt jeder nicht eingetragenen ID gelöscht (nur reine Zahlennamen,
keine Symlinks). Ausgabe tabgetrennt, Zeile für Zeile.

> *Maintains a server's Workshop list where the game expects it, described per
> game in `/etc/spiele-workshop.json` and measured on real servers: Project
> Zomboid (both lines, content pre-fetched with the image's steamcmd because the
> mod id comes from `mod.info`), Unturned (`File_IDs`), Don't Starve Together
> (setup file plus `modoverrides.lua`, Master shard only) and Killing Floor 2
> (repeated key in one INI section, download manager first, cache folder
> created). Every id is looked up at Steam and must belong to exactly this game;
> banned, unknown, oversized or unknown-size items are refused; collections are
> expanded. Search and the keyed size lookup need the Steam Web API key. Saving
> deletes the content of every id not listed. Output is tab-separated.*

### `kanal-verwalten` (#137, #244, #247)

```
kanal-verwalten abgleich            Kanäle an die installierten Server angleichen
kanal-verwalten vorschau <stack>    was beim Entfernen mit den Kanälen geschieht
kanal-verwalten pruefen             TeamSpeak-Zugang prüfen (Benutzer, Passwort über stdin)
kanal-verwalten pruefen-discord     Discord-Bot prüfen (Token, Server-ID über stdin)
kanal-verwalten --selbsttest
```

Ein TeamSpeak-Kanal und je ein Discord-Text- und -Sprachkanal je Spielserver.
Läuft als `kanal-abgleich.service` (Timer alle fünf Minuten, dazu angestoßen
nach Installation und Entfernung), unter der Sperre `/run/kanal-verwalten.lock`.
Aus, bis auf der Seite Integrationen eingeschaltet; gibt es nichts zu tun,
verbindet es sich gar nicht erst. Welche Server es gibt, sagt `/opt/stacks`
(ohne `teamspeak` selbst).

**TeamSpeak** über ServerQuery auf `127.0.0.1:10011` (Befehle höchstens alle
0,6 s, `KANAL_PAUSE`; eine Verbindung je Lauf; ein Flutbann wird als solcher
benannt). **Discord** über die REST-Schnittstelle mit dem Bot-Token (bei 429
wird gewartet); die Belegung eines Sprachkanals liest es — nur wenn einer
gelöscht werden soll — über eine kurze Gateway-Sitzung (Intents `GUILDS` und
`GUILD_VOICE_STATES`). **Gelöscht wird nur Unberührtes:** von Platzwart
angelegt (gespeicherte ID), Name, Eltern und Rechte unverändert, keine
Unterkanäle, niemand drin, bei Discord nie eine Nachricht; ist die Belegung
nicht messbar, wird nicht gelöscht. Namen: `panel.json` → Katalog → Stackname mit
großem Anfangsbuchstaben, höchstens 40 Zeichen; umbenannt wird nur, was noch
Platzwarts Namen trägt. Nicht Gelöschtes wandert in `verwaist` und wird mit
720 min Ruhezeit nach `#platzwart-stoerung` gemeldet; jede Änderung steht im
Protokoll des Panels (Benutzer `platzwart`).

Daten: `/opt/panel/daten/kanaele.json` (Schalter, Oberkanal/Kategorie,
Namensmuster je Dienst), `teamspeak.conf` und `discord.conf` (Zugänge, `0600
panel`), `kanaele-zuordnung.json` (`{"teamspeak": {stack: {cid, name, cpid}},
"discord": {stack: {"text": {…}, "sprache": {…}}}, "verwaist": {…}}`).

> *One TeamSpeak channel plus one Discord text and one voice channel per game
> server, run by `kanal-abgleich.service` (every five minutes and after each
> install or removal) under a lock; off until switched on under Integrations,
> and it does not connect when there is nothing to do. TeamSpeak goes through
> ServerQuery on localhost, paced to one command per 0.6 s with one connection
> per run; Discord through REST with the bot token, and voice occupancy — only
> when a voice channel is due for deletion — through a short Gateway session.
> Only untouched channels are deleted: created by Platzwart (stored id), name,
> parent and permissions unchanged, no subchannels, nobody inside, never a
> message on Discord; unmeasurable occupancy means no deletion. Names come from
> panel.json, the catalogue or the capitalised stack name; only channels still
> bearing Platzwart's name are renamed. Kept channels move to `verwaist` and are
> reported with a 720-minute quiet period; every change is audited as user
> `platzwart`. The data files are listed above.*

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

### `compose-feld`

```
compose-feld lesen   <stack>
compose-feld setzen  <stack> <name>         (Wert über stdin)
compose-feld anlegen <stack> <name>         (Wert über stdin; nur für katalog-abgleich)
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

**`anlegen` gibt es nur für `spiel-verwalten katalog-abgleich`** und nicht über
`panel-aktion`: Das Panel darf setzen, was dasteht, aber keine Variable
erfinden. Angelegt wird nur ein Name, der im Katalog steht, mit seinem
wörtlichen Vorgabewert — mit demselben Gerüstvergleich wie beim Setzen.

**Bekannte Grenze:** Die zeilenweise Analyse findet einen `environment`-Block
nur in einfacher Form. Eine compose-Datei, die ihn über YAML-Anker aufbaut
(`x-image: &image`, `<<: *image`), zeigt ihre Variablen im Panel nicht — so war
es bei StarRupture, dem einzigen Stack, der das tat (entfernt am 2026-09-09).

> *Reads and writes a stack's environment variables — only the `environment`
> block; volumes, ports and image stay untouchable. Three barriers in ascending
> reliability: a name pattern plus deny-list, a no-newline rule on the value, and
> — the real protection — a before/after comparison of docker's rendered config
> that rolls back on any difference. `anlegen` exists only for the catalogue
> sync, never through `panel-aktion`: the panel may set what exists but not
> invent variables; only a name from the catalogue with its literal default is
> added, under the same structural check. Known limit: an `environment` block
> built through YAML anchors is not found line by line, so its variables do not
> appear — that was StarRupture, the only stack doing so (removed 2026-09-09).*

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
`/srv/games/starrupture/.wine/dosdevices/` lag ein Symlink `z:` auf `/`
(StarRupture ist inzwischen entfernt; jedes Wine-Präfix legt ihn wieder an).
Nachgemessen am 2026-09-07: `readlink -f` auf `…/z:/etc/passwd` ergibt
`/etc/passwd`. Ein Editor, der als root schreibt und vor dem Auflösen prüft,
wäre ein Schreibzugriff auf das gesamte Dateisystem.

Weitere Grenzen: nur bekannte Endungen (dazu einzelne volle Dateinamen wie
Unturneds `Commands.dat`, #223), 4 B bis 256 KB, ein Rauschfilter gegen
Manifeste, Lizenztexte, Absturzberichte und die eigenen Sicherungen, keine neuen
Dateien (nur bestehende ändern), Eigentümer und Rechte werden vom Original
übernommen — nie von root, sonst kann der Container seine eigene Datei nicht
mehr schreiben.

> *Lists, reads and writes the games' configuration files, invoked only through
> `panel-aktion`. Every path is resolved **first** and checked **afterwards** —
> non-negotiable, because a `z: -> /` symlink existed in StarRupture's Wine
> prefix (StarRupture is gone, but every Wine prefix creates one); checking
> before resolving would turn the editor into a root write to the entire
> filesystem. Further limits: known extensions only (plus single full file names
> such as Unturned's `Commands.dat`), 4 B to 256 KB, a noise filter against
> manifests, licences, crash reports and our own backups, no new files, and
> ownership inherited from the original, never root — otherwise the container
> could no longer write its own file.*

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

### `ttyd`

Das Webterminal, Version 1.7.7 als Release-Binary. Nicht aus Debian: bookworm
liefert 1.6, dessen `--base-path` sich anders verhält.
Eingerichtet in Stufe 40; `abgleich.sh` vergleicht die installierte Version mit
`TTYD_VERSION`. Läuft als `ttyd.service` unter `ADMIN_USER` auf `127.0.0.1:7681`
und hat **keine eigene Anmeldung** — Caddy lässt nur durch, was
`/auth-check` mit einer Admin-Sitzung bestätigt.

> *The web terminal, version 1.7.7 as a release binary rather than Debian's 1.6,
> whose `--base-path` behaves differently. Installed by stage 40 and compared
> against `TTYD_VERSION` by the comparison tool. It runs as `ADMIN_USER` on
> localhost and has no login of its own — Caddy only lets through what the
> panel's `/auth-check` confirms as an admin session.*

---

## Katalog- und Bildwerkzeuge (`werkzeuge/`)

Laufen auf dem Arbeitsrechner, nicht auf der Maschine. Sie erzeugen oder prüfen,
was dann über `ausrollen.sh` bzw. Stufe 30 eingesetzt wird.

> *These run on the workstation, not on the machine; they generate or check what
> `ausrollen.sh` or stage 30 then deploys.*

### `katalog-ergaenzen.py`, `katalog-lgsm.py`, `katalog-varianten.py`

```
werkzeuge/katalog-ergaenzen.py  <katalog.json> [--schreiben]   ich777-Vorlagen
werkzeuge/katalog-lgsm.py       <katalog.json> [--schreiben]   LinuxGSM
werkzeuge/katalog-varianten.py  <katalog.json> [--schreiben]   Varianten eines Images
```

Die drei Generatoren des Katalogs. Ohne `--schreiben` berichten sie nur, was
hinzukäme; **vorhandene Einträge fassen sie nie an**.

* `katalog-ergaenzen.py` liest die Unraid-Vorlagen von ich777 — verbindlich,
  weil im Image bei vielen Tags nur `GAME_ID=template` steht und ein Container
  daraus nichts herunterlädt. Bewusst nur diese eine Quelle für die Bauart
  `ich777`: einheitliche Variablen (`GAME_ID`, `GAME_PARAMS`, `UID`/`GID`), ein
  erprobter Einrichtungsschritt.
* `katalog-lgsm.py` liest LinuxGSMs `serverlist.csv` und die Vorlagen dazu —
  vorher an Ricochet durchgetestet, mit den vier Eigenheiten aus
  [04-spielekatalog.md](04-spielekatalog.md#vier-eigenheiten-von-linuxgsm). Die
  Portregeln übernimmt es aus `info_game.sh` (`port_regel`).
* `katalog-varianten.py` legt Spielarten an, die dasselbe Image über eine
  Variable anders starten — heute die sieben weiteren Minecraft-Varianten von
  `itzg/minecraft-server` (Paper, Fabric, Forge, NeoForge, Purpur, Spigot,
  Quilt), jede mit eigener Beschreibung statt eines Einheitstextes.

Duplikate werden über den **Namen** erkannt, nicht über die App-ID (13
GoldSrc-Spiele teilen sich die ID 90), und auch gegen die von Hand gebauten
Stacks. Die Portvergabe benutzen alle aus `katalog-ports.py`, damit die Regel
einmal steht. Nach einem Lauf gehören `katalog-kategorien.py`,
`katalog-beschreibungen.py`, `steam-appid.py`, `eigene-bilder.py` und
`katalog-doku.py` dazu — `vollstaendigkeit.sh` meldet, was fehlt.

> *The three catalogue generators; without `--schreiben` they only report, and
> they never touch existing entries. `katalog-ergaenzen.py` reads ich777's Unraid
> templates — authoritative because many image tags only say `GAME_ID=template`,
> and a container built from that downloads nothing. `katalog-lgsm.py` reads
> LinuxGSM's server list and templates, tested on Ricochet first, and copies the
> port rules from `info_game.sh`. `katalog-varianten.py` adds variants that start
> the same image differently — today the seven further Minecraft server types,
> each with its own description. Duplicates are matched by name, never by app id
> (13 GoldSrc games share id 90), including against the hand-built stacks; port
> allocation comes from `katalog-ports.py`. After a run, the categoriser,
> descriptions, app ids, artwork and doc generator follow — the completeness
> check reports what is missing.*

### `katalog-kategorien.py`

```
werkzeuge/katalog-kategorien.py <katalog.json>              Bericht
werkzeuge/katalog-kategorien.py <katalog.json> --schreiben  übernehmen
werkzeuge/katalog-kategorien.py <katalog.json> --pruefen    Exit 1, wenn ein Eintrag
                                                           keine gültige Kategorie hat
```

Ordnet jedem Katalogspiel eine von acht Kategorien zu (Aufbau & Simulation,
Survival & Koop, Sandbox & Rollenspiel, Shooter, Arena & Klassiker, Rennen &
Fahren, Dienste, Sonstiges) — **von Hand, Spiel für Spiel**, nicht aus Steams
Genres, die nichts darüber sagen, ob ein Spiel zu zweit an einem Abend Spaß
macht. Unbekannte landen sichtbar in „Sonstiges" und werden beim Lauf benannt;
Zuordnungen ohne Katalogeintrag (Tippfehler) ebenfalls. `--schreiben` legt
außerdem `_kategorien` (Reihenfolge und Anzeigenamen) in den Katalog.

`--pruefen` gibt es wegen #251: Die Generatoren legten 17 Spiele **ohne** das
Feld an, und dieses Werkzeug lief nur von Hand. Die Spiele fehlten danach in
jedem Kategoriefilter der Katalogseite, auch in „Sonstiges". `vollstaendigkeit.sh`
ruft `--pruefen` seither bei jedem Lauf.

> *Assigns each catalogue game one of eight categories, by hand and game by
> game rather than from Steam's genres, which say nothing about whether a game
> suits an evening for two. Unknown games land visibly in "Sonstiges" and are
> named; mappings without a catalogue entry (typos) too. `--schreiben` also
> stores the category order and display names in the catalogue. `--pruefen`
> exists because of #251: the generators created 17 entries without the field,
> this tool only ran by hand, and those games vanished from every category
> filter. The completeness check calls it on every run.*

### `steam-appid.py`

```
werkzeuge/steam-appid.py <katalog.json> [--schreiben]
```

Sucht zu jedem Katalogspiel die **Spiel**-App-ID bei Steam. In den Vorlagen
steht die **Server**-App-ID (Killing Floor 2: 232130), Titelbilder gibt es aber
nur zur Spiel-ID (232090) — 44 Kacheln blieben deshalb ohne Bild. Es zählen nur
**exakte** Namenstreffer: Die Store-Suche liefert zu „Ricochet" zuerst „Ricochet
Abyss" und zu „Squad" „Ore Factory Squad"; ein generisches Bild ist besser als
ein falsches.

> *Finds each catalogue game's GAME app id at Steam. The templates carry the
> SERVER app id, while artwork exists only for the game id, so 44 tiles had no
> image. Only exact name matches count — the store search is fuzzy, and a
> generic image beats a stranger's artwork.*

### `statistik-dashboards.py`

```
werkzeuge/statistik-dashboards.py               Dashboards schreiben
werkzeuge/statistik-dashboards.py --pruefen     nur berichten (Exit 1 = veraltet)
werkzeuge/statistik-dashboards.py --daten ZIEL  jede Tafel gegen die laufende
                                                Instanz abfragen (Exit 1 = leer)
```

Erzeugt die sieben Grafana-Dashboards des Statistik-Moduls nach
`etc/module/statistik/grafana/dashboards/` und die **Vorlage** für die
Dashboards je Spielserver nach `etc/module/statistik/grafana/server-vorlage.json`
(dort `__STACK__`, eingesetzt von `modul-verwalten dashboards`). Von Hand sind
das mehrere hundert Zeilen JSON, in denen Datenquelle, Einheit und Rasterlage
zwanzigmal wiederholt werden; hier steht je Tafel eine Zeile. `--pruefen` wird
von `vollstaendigkeit.sh` mitgeprüft.

`--daten <ssh-ziel>` führt **jede Abfrage jeder Tafel** gegen die laufende
Instanz aus, und zwar **durch Grafana hindurch** (dessen Datenquellen-Weiterleitung),
nicht direkt gegen Prometheus: Genau dieser Unterschied verdeckte einmal eine
Datenquelle, die auf einen Containernamen zeigte, den es nicht mehr gab — die
Tafeln waren leer und die Prüfung meldete „alles da". Die Vorlage je Server wird
mitgeprüft; `__STACK__` und die Auswahlvariablen werden dafür durch „irgendetwas"
ersetzt.

> *Generates the module's seven dashboards and the template for the per-server
> ones (`__STACK__`, filled in on the machine). `--pruefen` is part of the
> completeness check. `--daten <target>` runs every panel's query against the
> live instance through Grafana's datasource proxy rather than straight at
> Prometheus — that difference once hid a datasource pointing at a container name
> that no longer existed, with empty panels and a check reporting all good.*

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

> *Keeps the documentation in step with the catalogue: the total at four named
> places and the generated game list in the catalogue chapter; checked by the
> completeness run. It checks named places rather than "any number before the
> word games", because the docs contain several numbers counting something
> else, and every pattern must match exactly once — no match means "the place
> moved", not "fine".*

### `katalog-vorpruefung` (liegt in `bin/`, läuft auf der Maschine)

Ohne Parameter. Prüft alle Katalogeinträge **ohne Download**: Pflichtfelder,
Schlüsselform, Portkollisionen (installierte Spiele ausgenommen), erzeugt die
echte `compose.yaml` und lässt `docker compose config -q` darauf laufen, fragt
`docker manifest inspect` ab.

Ergebnis vom 2026-09-06 (damals 41 Einträge): 34 ohne Befund, 5 Hinweis, 0
Fehler, 2 installiert.

> *No parameters. Checks every catalogue entry without downloading anything:
> required fields, key shape, port collisions (installed games excepted), a real
> `compose.yaml` rendered and fed to `docker compose config -q`, and `docker
> manifest inspect` for the image. Result on 2026-09-06, with 41 entries at the
> time: 34 clean, 5 notes, 0 errors, 2 installed.*

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

---

## Prüfwerkzeuge (`werkzeuge/`)

**Auf dem Ziel braucht es root — per Anmeldung oder per `sudo` ohne Passwort**
(#192, #214). `ausrollen.sh`, `rueckbau.sh` und `aufraeumen.sh` schreiben nach
`/etc` und `/usr/local/bin` und rufen `systemctl` und `rm -rf`. Alle drei
ermitteln vorab über `werkzeuge/ziel.sh`, welcher Weg geht, und brechen sonst
mit einem Satz ab, der beide nennt. `abgleich.sh` liest nur: ohne beides läuft
es weiter und warnt, dass Dateien, die nur root lesen darf, dann als abweichend
erscheinen.

Gemessen mit einem Ziel ohne root: `ausgefuehrt: 12   fehlgeschlagen: 77`, und
das Werkzeug lief bis zum Ende durch — deshalb die Prüfung vorab.

**Weg 1 — root-Login per Schlüssel** (so läuft die Maschine heute):

```
Host gameserver
    HostName <maschine>
    User root
```

Verlangt, dass `PermitRootLogin` eine Schlüsselanmeldung zulässt — die Vorgabe
(`SSH_ROOT_LOGIN=prohibit-password`).

**Weg 2 — ein Benutzer mit `sudo` ohne Passwortabfrage** (Jens am 2026-09-11:
„auch ohne root sollte das möglich sein"). Dann läuft jeder Befehl als
`sudo -n bash -c <gequotet>`. Nur *passwortloses* sudo geht, weil die Werkzeuge
Dutzende einzelner Befehle über SSH ohne Terminal schicken. Auf der Maschine
etwa in `/etc/sudoers.d/`:

```
<benutzer> ALL=(ALL) NOPASSWD: ALL
```

**Sicherheitlich ist das gleichwertig mit Weg 1** — wer den Schlüssel dieses
Benutzers hat, ist root. Es ist der Weg für `SSH_ROOT_LOGIN=no`. Die Einrichtung
legt ihn nicht an; der Verwaltungsbenutzer hat heute sudo nur **mit** Passwort.

Nachgewiesen: Beide Wege liefern gegen die echte Maschine dieselben Ergebnisse
(`PLATZWART_MIT_SUDO=1` erzwingt Weg 2 auch bei root-Login; das Journal zeigte
194 `sudo … bash -c`-Aufrufe), auch der Rückspielzweig von `ausrollen.sh`.

> *Root is needed on the target, by login or by passwordless sudo (#192, #214).
> The three writing tools determine the way through `werkzeuge/ziel.sh` and stop
> with one sentence naming both; `abgleich.sh` only warns. Way 1: root key login
> (today's setup). Way 2: a user with `NOPASSWD` sudo — every command runs as
> `sudo -n bash -c <quoted>`; only passwordless sudo works over terminal-less
> SSH, and it is equivalent to way 1 security-wise. Both ways produce identical
> results against the real machine (`PLATZWART_MIT_SUDO=1` forces way 2).*

### `abgleich.sh <ssh-ziel>`

Vergleicht das Repositorium mit einer laufenden Maschine. Keine Zahl hier — sie
veraltet lautlos (die Liste wuchs von 22 auf über 100 Dateien); der Lauf nennt sie:

| Was | Wie verglichen |
|---|---|
| alle ausgerollten Dateien (Liste `PAARE`: Werkzeuge, `/etc`, Units, `app.py`) | byte-genau, nach Einsetzen der Platzhalter |
| Python-Umgebung des Panels | `pip list --format=freeze` gegen `panel/requirements.txt` |
| ttyd | installierte Version gegen `TTYD_VERSION` in Stufe 40 |
| 3 Symbole | byte-genau |
| selbst gezeichnete Titelbilder | byte-genau |
| Katalogbilder | nur Vollständigkeit — die Steam-Header liegen nicht im Repositorium |

**Nicht jede Datei gehört auf jede Maschine (#196).** Die Palworld-Neustartzeitgeber
müssen nur dort stehen, wo Palworld installiert ist, `dns-ziel.*` nur bei
`SERVER_IPV4=dynamic`. Fehlt so eine Datei, wo sie nicht gilt, meldet der
Abgleich `entfaellt hier` statt `FEHLT` — sonst wäre „fehlend: 0" auf den
meisten Maschinen unerreichbar gewesen, und „2, wie immer" übersieht die dritte.
Steht sie trotzdem da, wird sie verglichen wie jede andere. Alle `sort`/`comm`
laufen mit `LC_ALL=C`: Die deutsche Sortierung übergeht Bindestriche, und
`comm` warnte vorher bei jedem Lauf.

> *Not every file belongs on every machine: absent where it does not apply
> counts as "not applicable", not missing; present, it is compared. Sorting is
> pinned to C collation — comm used to warn on every run.*

Die letzten vier Punkte fehlten zunächst. Aufgefallen ist das erst, als ein
Dependabot-PR `requirements.txt` änderte und der Abgleich von Hand nachgezogen
werden musste — **eine Prüfung, die einen Bereich gar nicht ansieht, meldet ihn
als in Ordnung.**

Außer Dateien prüft es, dass die Sicherungs-Timer wirklich **laufen**, den
Fassungsstempel und die erzeugten Zertifikatsdateien gegen den eingestellten
Wert. Blöcke, die `spiel-verwalten` in `/etc/borg-ausschluss.txt` anhängt,
blendet es aus — sie beschreiben die Maschine, nicht den Bauplan.

Exit 0 = deckungsgleich, 1 = Abweichungen (mit Diff), 2 = nicht erreichbar.
Ändert nichts.

> *Compares the repository against a running machine. No number here, because
> numbers age silently (the list grew from 22 to over 100 files); the run
> prints it. Compared: every deployed file byte for byte after placeholder
> substitution, the panel's Python environment against `requirements.txt`, the
> ttyd version, the icons and self-drawn artwork byte for byte, and the
> catalogue artwork for completeness only. The environment, ttyd and icon
> checks were missing at first and only surfaced when a Dependabot PR changed
> `requirements.txt` — a check that never looks at an area reports it as fine.
> Beyond files it checks that the backup timers actually run, the version stamp,
> and the generated certificate files against the configured value. Exit 0
> identical, 1 drift with a diff, 2 unreachable; it changes nothing.*

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

**Nach Katalog und Ausschlussliste gleicht es die installierten Spiele an**
(`spiel-verwalten katalog-abgleich`). Die Ausschlussliste im Repositorium trägt
die Blöcke `# >>> panel:<spiel>` nicht; bis #250 ersetzte das Ausrollen sie
ersatzlos, `abgleich.sh` blendet genau diese Blöcke aus und merkte es nicht, und
der nächste Restore hätte die Installation dieser Spiele nicht mehr verschont.

> *After the catalogue or the exclusion list it aligns installed games. The
> repository's exclusion list carries no per-game blocks; until #250 a rollout
> dropped them, the comparison ignores exactly those blocks, and the next
> restore would no longer have spared those games' installations.*

**Drei Ziele fragt es nach dem Tausch den Dienst (#204):** die Caddyfile
(`caddy validate`), die sshd-Härtung (`sshd -t`) und die sudoers-Regel des
Panels (`visudo -c`). Lehnt der Dienst ab, kommt die gerade angelegte Sicherung
zurück, und der Lauf endet mit Fehler. Genau dort schlägt eine kaputte Datei
nämlich spät und hart zu: beim nächsten Neustart ist das Panel weg, die
SSH-Anmeldung gesperrt oder die sudo-Brücke gebrochen. Anlass war die
Caddyfile aus #202, die eine Datei importiert, die nur Stufe 40 anlegt.
Nachgewiesen mit einer absichtlich kaputten Caddyfile: abgelehnt, die gültige
Fassung stand danach wieder da, Caddy lief unberührt weiter.

> *Three targets are validated by their service after the swap — Caddyfile,
> sshd drop-in, sudoers — and the backup is restored if the service refuses.
> That is where a bad file bites late and hard. Proven with a deliberately
> broken Caddyfile.*

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
| erste (`1.x.x`) | eine der fünf nicht verhandelbaren Grenzen ändert sich, oder eine bestehende Einrichtung lässt sich nicht mehr ohne Handarbeit weiterbetreiben |
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
> moves when one of the five non-negotiables changes or an existing installation
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
`@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt — und halten die
Katalogports die vier Regeln aus `katalog-ports.py` ein.

Dazu kamen Prüfungen, jede aus einem echten Fund: Titelbild für jedes Spiel
ohne Steam-Eintrag (`eigene-bilder.py --pruefen`), Doku und Katalog stimmen
überein (`katalog-doku.py --pruefen`), jedes Katalogspiel hat eine Kategorie
(`katalog-kategorien.py --pruefen`, #251), jede ausgerollte Datei steht in der
Vergleichsliste von `abgleich.sh`, jedes Werkzeug aus `bin/` wird von Stufe 30
eingesetzt, jede Route aus `app.py` steht in der Routentabelle von
[03-panel.md](03-panel.md#alle-routen), in `app.py` wird kein aufgebauter
HTML-Schnipsel wieder überschrieben, keine Route benutzt die Sitzung vor der
`None`-Prüfung, kein HTML-Attribut trägt eine von Python ausgewertete Klammer,
keine echte IP-Adresse steht irgendwo, kein Wert der eigenen `konfiguration.env`
(Zone, Ziel, Panel-Domain, Weltname) und kein Wort aus der lokalen, nie
eingecheckten `.standortdaten` steht in einer verfolgten Datei, und jeder
Abschnitt der Dokumentation hat seinen englischen Absatz
(`werkzeuge/doku-englisch.py`, abschaltbar mit `PLATZWART_DOKU_ENGLISCH=aus`).

Als Bremse vor jedem Commit:
`ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit`.
Notausgang `GAMESERVER_KEIN_GATE=1`.

> *Verifies the repository holds everything the installation touches: every file
> referenced by `install/` exists and is tracked, all scripts parse, no secret is
> present, every placeholder is documented, and the catalogue ports follow the
> four rules in `katalog-ports.py`. Further checks were added, each from a real
> finding: artwork for every game without a Steam entry, docs matching the
> catalogue, a category for every catalogue game (#251), every deployed file in
> the comparison list, every tool in `bin/` installed by stage 30, every panel
> route in the route table, no HTML fragment overwritten after being built, no
> route touching the session before its None check, no Python-evaluated braces
> in HTML attributes, no real IP address, no value of the local
> `konfiguration.env` and no word from the local, never committed
> `.standortdaten` in any tracked file, and an English paragraph for every
> documentation section (`werkzeuge/doku-englisch.py`, switchable off with
> `PLATZWART_DOKU_ENGLISCH=aus`).
> Wire it in as a pre-commit hook via the symlink above; bypass with
> `GAMESERVER_KEIN_GATE=1`.*

### `katalog-ports.py`

```
werkzeuge/katalog-ports.py            Katalogports pruefen (Exit 1 = Verstoss)
PLATZWART_PORTPRUEFUNG=aus …          abschalten, nur wenn man weiss, warum
```

Vier Regeln: Verwaltungsports nur auf `127.0.0.1`, TCP und UDP eines
Containerports auf einem Hostport, die Beitrittsadresse auf einem Port, auf dem
das Spiel ankommt, kein Hostport doppelt (lokale eingeschlossen). Enthält
außerdem die Helfer, die `katalog-ergaenzen.py` und `katalog-lgsm.py` für die
Portvergabe benutzen — die Regel steht damit einmal, nicht in drei Kopien.
Hintergrund: [04-spielekatalog.md](04-spielekatalog.md#portregeln-im-katalog).

> *Four rules — management ports local only, TCP and UDP of a container port on
> one host port, a join port the game listens on, no host port used twice (local
> ones included). Also holds the helpers both catalogue generators use for port
> allocation, so the rule exists once rather than in three copies.*

---

### `katalog-ausschluesse.py`

```
werkzeuge/katalog-ausschluesse.py               Muster im Katalog ergaenzen
werkzeuge/katalog-ausschluesse.py --pruefen     Abweichungen melden (Exit 1)
werkzeuge/katalog-ausschluesse.py --selbsttest  die Regeln selbst pruefen
PLATZWART_KEIN_AUSSCHLUSS_GATE=1                Haken in vollstaendigkeit.sh aus
```

Hält das Feld `ausschluss` der 167 Katalogeinträge mit den Bauarten `ich777`
und `linuxgsm` vollständig (#221). Aufgenommen wird **nur**, wovon sich belegen
lässt, dass es kein Spielstand sein kann: geteilte Bibliotheken, Steams
Laufzeit und Manifeste, Unitys `*_Data`, Unreals `Engine`, `Binaries`,
`Content`, `Plugins`. Einträge mit eigenem Abbild bleiben unberührt — wo ein
fremdes Bild speichert, weiß nur die Messung. Jedes Muster, das ein
Modverzeichnis aus `etc/spiele-mods.json` verdecken würde, fällt für dieses
Spiel weg; verglichen wird großzügiger als borg selbst (ohne Rücksicht auf
Groß-/Kleinschreibung, `*` auch über `/`), denn ein zu Unrecht gestrichenes
Muster kostet Platz, ein zu Unrecht gesetztes einen Mod. Hintergrund und
Messwerte: [05-sicherung.md](05-sicherung.md).

> *Keeps the `ausschluss` field of the 167 `ich777`/`linuxgsm` catalogue entries
> complete (#221), admitting only what can be shown not to be a save — shared
> libraries, the Steam runtime and manifests, Unity's `*_Data`, Unreal's
> `Engine`, `Binaries`, `Content`, `Plugins`. Own-image entries are untouched,
> since only a measurement knows where a foreign image saves. Any pattern that
> would cover a mod directory from `etc/spiele-mods.json` is dropped for that
> game, compared more generously than borg itself (case-insensitive, `*` across
> `/`): a wrongly dropped pattern costs space, a wrongly kept one costs a mod.*

---

### `ziel.sh`

Kein eigenes Werkzeug, sondern der gemeinsame Teil von `ausrollen.sh`,
`rueckbau.sh`, `aufraeumen.sh` und `abgleich.sh`: Er stellt fest, ob das Ziel
per root-Login oder über einen Benutzer mit passwortlosem `sudo` erreichbar ist,
und verpackt im zweiten Fall jeden Befehl als `sudo -n bash -c <gequotet>`
(`printf %q`). `PLATZWART_MIT_SUDO=1` erzwingt den sudo-Weg auch bei root-Login
— so lässt sich die Verpackung gegen eine echte Maschine prüfen.

> *Not a tool of its own but the shared part of the four remote tools: it
> determines whether the target is reached by root login or by a user with
> passwordless sudo, and in the latter case wraps every command as
> `sudo -n bash -c <quoted>`. `PLATZWART_MIT_SUDO=1` forces the sudo path even
> with root login, so the wrapping can be tested against a real machine.*

### `dns-abnahme.sh`

```
werkzeuge/dns-abnahme.sh --selbsttest
werkzeuge/dns-abnahme.sh --anbieter <name> --zone <zone> --ip <ipv4> --token-datei <datei>
```

Die Abnahme eines DNS-Anbieters gegen eine echte Zone als **ein** Befehl —
neun Schritte, von denen zwei fehlschlagen müssen. Installiert nichts, fasst
`/etc/dns-gameserver.conf` nicht an, alle Testeinträge tragen einen zufälligen
Präfix und werden am Ende entfernt; der Token kommt aus einer Datei oder
`DNS_ABNAHME_TOKEN`, nie aus `argv`. Einzelheiten:
[06-netz-dns-firewall.md](06-netz-dns-firewall.md#die-abnahme-als-ein-befehl).

> *Acceptance test of a DNS provider against a real zone as one command — nine
> steps, two of which must fail. Installs nothing, never touches the real token
> file, prefixes every test record randomly and removes it afterwards; the token
> comes from a file or an environment variable, never from argv.*

### `git-hooks/pre-push`

```bash
ln -sf ../../werkzeuge/git-hooks/pre-push .git/hooks/pre-push
```

Lehnt einen Push auf `main` oder `master` ab und nennt den Weg: Issue, Zweig,
Pull Request. Vorbei mit `GIT_PUSH_MAIN_OK=1` — das Wiki hat keine Pull Requests
und braucht ihn.

Warum es ihn gibt: Die Regel stand in CLAUDE.md und wurde von nichts geprüft.
Der Ausrutscher ist immer derselbe — nach einem Merge steht der Arbeitszweig
wieder auf `main`, und die nächste Arbeit landet dort (#283).

> *Refuses a push to main or master and names the way round it. It exists because
> the rule was written down and never checked, and the slip is always the same:
> after a merge the working branch is main again.*

### `git-hooks/pre-commit`

```bash
ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit
```

Ruft vor jedem Commit `vollstaendigkeit.sh` und weist den Commit ab, wenn sie
nicht grün ist — mit Regel und Notausgang in der Meldung
(`GAMESERVER_KEIN_GATE=1 git commit …`). Bewusst als Symlink und **nicht** über
`git config core.hooksPath`: Das ersetzt das ganze Hook-Verzeichnis und schaltet
vorhandene Haken ab, etwa einen `commit-msg`-Haken.

> *Runs the completeness check before every commit and refuses the commit when
> it fails, naming the rule and the way around it. Wired in as a symlink, not
> via `core.hooksPath`, which replaces the whole hooks directory and disables
> hooks already there.*

---

## Einrichtung (`install/`)

| Skript | Aufruf | Zweck |
|---|---|---|
| `assistent.sh` | `sudo install/assistent.sh [--nur-konfiguration \| --selbsttest]` | geführte Einrichtung: Neueinrichtung, Wiederaufbau aus der Sicherung oder nur `konfiguration.env`; fragt, prüft, fasst zusammen, richtet erst nach Bestätigung ein ([11](11-neueinrichtung.md)) |
| `einrichten.sh` | `sudo install/einrichten.sh [--ja] [<stufe> …]` | die Stufen 10–50 (oder die genannten) in Reihenfolge; zeigt vorher, was es tun wird, und fragt — mit `--ja` ohne Rückfrage (so ruft der Assistent es auf) |
| `10-basis.sh` … `50-sicherung.sh` | über `einrichten.sh` oder einzeln | die Stufen, beschrieben in [02](02-installation.md) |
| `60-spiele.sh` | `sudo install/60-spiele.sh <stack> …` | handgepflegte Server aus `stacks/` |
| `70-dns.sh` | `sudo install/70-dns.sh` | ein CNAME je Server |
| `lib.sh` | wird eingebunden | liest und prüft `konfiguration.env`, `einsetzen`, `rendern`, `passwort`, `version_stempeln` |

**`assistent.sh` im Einzelnen.** Eigenständig, weil `lib.sh` ohne eine gültige
`konfiguration.env` abbricht — die es zu Beginn noch nicht gibt. Eingaben kommen
von stdin (Geheimnisse ohne Echo); endet die Eingabe, bricht er ab. Token,
Webhooks und Passwörter gehen nie als Argument durch ein Programm: `curl` liest
Kopfzeile bzw. URL aus einer `0600`-Datei (`-H @datei`, `-K`), das Passwort geht
über `chpasswd` von stdin. Für Tests lassen sich die Zielpfade umlenken:
`ASSISTENT_KONF` (sonst `konfiguration.env` im Klon), `ASSISTENT_DNS_KONF`,
`ASSISTENT_MELDEN_KONF`. `--selbsttest` prüft die Regeln mit festen Beispielen,
darunter die Archivwahl des Wiederaufbaus (neuestes Archiv **vor** dem Start) und
das Schreiben der Konfiguration aus der Vorlage (jede Variable genau einmal,
Rechte `0600`, ein fehlender Wert bricht ab).

> *Setup scripts: `assistent.sh` is the guided setup (new install, rebuild from
> backup, or configuration only — asks, checks, summarises, sets up only after
> confirmation); `einrichten.sh` runs stages 10–50 or the named ones, showing
> first what it will do and asking — `--ja` skips the question, which is how the
> assistant calls it; the stage scripts themselves; `60-spiele.sh` for the
> hand-maintained servers; `70-dns.sh` for one CNAME per server; `lib.sh`, which
> reads and validates the configuration. The assistant is standalone because
> `lib.sh` aborts without a valid `konfiguration.env`, which does not exist yet
> at the start. Input comes from stdin (secrets without echo), and end of input
> aborts. Tokens, webhooks and passwords never travel as arguments: curl reads
> header or URL from a 0600 file, the password goes to chpasswd on stdin. Target
> paths can be redirected for tests (`ASSISTENT_KONF`, `ASSISTENT_DNS_KONF`,
> `ASSISTENT_MELDEN_KONF`). `--selbsttest` checks the rules with fixed examples,
> including the rebuild's archive choice (newest before the start) and writing
> the configuration from the template (every variable exactly once, 0600, a
> missing value aborts).*

---

## systemd

| Unit | Zeitpunkt | Zweck |
|---|---|---|
| `panel.service` | dauerhaft | Weboberfläche, `User=panel`, uvicorn auf `127.0.0.1:8099` |
| `ttyd.service` | dauerhaft | Webterminal, `User=<admin>`, `127.0.0.1:7681` |
| `spiele-sicherung.timer` | `*:0/15`, ±60 s | Sicherung laufender Spiele (aus bei `BORG_REPO=aus`) |
| `platzwart-ereignisse.timer` | jede Minute, versetzt zum Spielerzähler | meldet Beitritte in den Kanal des Servers; tut ohne Schalter nichts |
| `platzwart-metriken.timer` | `*:0/5`, abschaltbar | Zahlen für Prometheus; **aus**, solange kein Modul installiert ist. Der Messabstand kommt aus einer Ergänzungsdatei (`30s`, `1min`, `5min`) |
| `spiele-sicherung-voll.timer` | täglich 04:00, ±300 s | Vollsicherung samt `config-*`, `etc-*`, `panel-*` (aus bei `BORG_REPO=aus`) |
| `spiel-einrichtung.timer` | alle 2 min, ab 3 min nach dem Start | Passwörter frischer Server setzen, Ports veröffentlichen |
| `kanal-abgleich.timer` | alle 5 min, ab 4 min nach dem Start | TeamSpeak- und Discord-Kanäle angleichen; zusätzlich nach Installation und Entfernung angestoßen |
| `spiele-autoupdate.timer` | täglich 05:15, ±30 min | freigeschaltete Server aktualisieren (`Persistent=false`) |
| `platzwart-wache.timer` | alle 5 min, ab 3 min | Lage prüfen, **Änderungen** nach Discord melden (`Persistent=false`) |
| `spieler-zaehlen.timer` | jede Minute, ab 90 s | Spielerzahlen abfragen (`Persistent=false`) |
| `platzwart-status.timer` | jede Minute, ab 2 min | öffentliche Statusseite neu schreiben (`Persistent=false`) |
| `platzwart-verlauf.timer` | alle 5 min, ab 4 min | Speicher, Last und Spielerzahl mitschreiben (`Persistent=false`) |
| `platzwart-schlaf.timer` | alle 10 min, ab 10 min | leere Server schlafen legen (`Persistent=false`) |
| `platzwart-wecken-<stack>.socket` | während des Schlafs | von `platzwart-schlaf` erzeugt, hält die Spielports |
| `platzwart-wecken@.service` | beim ersten Paket | Vorlage: `platzwart-schlaf --wecken %i`, beendet den Socket per `Conflicts=` |
| `spiele-wiederanlauf.service` | beim Hochfahren | startet die Server wieder, die `panel-aktion neustart` vorher angehalten hat (nur wenn die Liste existiert) |
| `palworld-neustart.timer` | 05:30 und 17:30 | gegen das Speicherleck; eingesetzt von Stufe 60 zusammen mit dem Palworld-Stack (#252) |
| `dns-ziel.timer` | alle 5 min, ab 2 min nach dem Start, ±30 s | öffentliche IPv4 messen und den A-Eintrag nachziehen (nur bei `SERVER_IPV4=dynamic`) |

`Persistent=true` bei allen Sicherungs- und Einrichtungs-Timern: Verpasste Läufe
werden nachgeholt. **`Persistent=false`** bei allen, deren nachgeholter Lauf
schadet: beim Palworld-Neustart und beim Auto-Update (liefe womöglich mitten in
einer Spielsitzung), beim Verlauf (ein nachgeholter Wert schüttete genau die
Lücke zu, die man sehen soll) und bei Wache, Spielerzahl, Statusseite und
Leerlauf (sie beschreiben „jetzt").

**`spiel-einrichtung.service` läuft bewusst ohne Härtung.** Er ruft
`docker compose` und schreibt nach `/srv/games`; Härtungsoptionen haben hier
schon einmal dazu geführt, dass Aufrufe still fehlschlugen.

> *The table lists every unit, when it runs and what it does. Backup and setup
> timers are `Persistent=true`, so missed runs catch up. Everything whose
> caught-up run would do harm is `Persistent=false`: the Palworld restart and the
> auto-update (they could fire mid-session), the history (a caught-up sample
> would fill the very gap one should see), and the watchdog, player count,
> status page and idle sleep (they describe "now"). The setup service
> deliberately runs without hardening: it calls docker compose and writes to
> `/srv/games`, and hardening options once made those calls fail silently.*

---

## Dateien

| Pfad | Rechte | Inhalt |
|---|---|---|
| `/etc/spiele-katalog.json` | `0644 root` | 179 installierbare Spiele |
| `/etc/spiele-adressen.json` | `0644 root` | Beitrittsadressen der von Hand gebauten Server; gelesen von Panel **und** Statusseite |
| `/etc/spiele-mods.json` | `0644 root` | wohin ein Mod je Spiel gehört; **fehlt der Eintrag, wird der Upload abgewiesen** statt geraten |
| `/etc/spiele-workshop.json` | `0644 root` | Workshop-Anbindung je Spiel: Art, Datei, Inhaltsordner, gemessen |
| `/etc/borg-ausschluss.txt` | `0644 root` | was nicht gesichert wird; Katalogspiele hängen Blöcke `# >>> panel:<spiel>` an |
| `/etc/module-katalog.json` | `0644 root` | die installierbaren Module samt Schaltern und erlaubten Werten — die Positivliste des Modulwegs |
| `/etc/module/<modul>/` | `0644 root` | Vorlagen eines Moduls: compose-Datei, Prometheus-Vorlage, Grafana-Bereitstellung, Dashboards |
| `/etc/caddy/module.conf` | `0644 root` | **erzeugt**: je installiertem Modul ein `handle`-Block; ohne Modul leer, von der Caddyfile fest eingebunden |
| `/opt/module/<modul>/modul.json` | `0640 root:panel` | Stand der Schalter und Einstellungen; die Oberfläche liest ihn, schreibt aber nie hinein |
| `/opt/module/<modul>/.env` | `0600 root` | Werte für compose (Aufbewahrung, Plattengrenze) und das gewürfelte Grafana-Administratorpasswort |
| `/var/lib/platzwart-metriken/*.prom` | `0644 root` | die Zahlen für Prometheus; `.platte.json` daneben merkt sich die stündliche Plattenmessung |
| `/etc/caddy/Caddyfile` | `0644 root` | HTTPS, Vorschaltung, Kopfzeilen, Statusseite |
| `/etc/caddy/zertifikat.conf` | `0644 root` | **erzeugt**: leer bei `http-01`, `acme_dns …` bei `dns-01` |
| `/etc/systemd/system/caddy.service.d/dns01.conf` | `0644 root` | **erzeugt**, nur bei `dns-01`: eigener Caddy, `EnvironmentFile`, **kein** `--environ` |
| `/usr/local/bin/caddy` | `0755 root` | nur bei `dns-01`: Bau mit `caddy-dns`-Modul; das Paket unter `/usr/bin/caddy` bleibt liegen |
| `/etc/fail2ban/jail.local` | `0644 root` | sshd-Jail, Ausnahmen |
| `/etc/ssh/sshd_config.d/99-gameserver.conf` | `0644 root` | SSH-Härtung aus `SSH_PASSWORT_AUTH` und `SSH_ROOT_LOGIN` |
| `/etc/sudoers.d/panel` | `0440 root` | die eine Rechteerweiterung |
| `/etc/dns-gameserver.conf` | `0600 root` | `ANBIETER=…`, `TOKEN=…` — von `install/assistent.sh` oder von Hand angelegt |
| `/etc/cloudflare-gameserver.conf` | — | älterer Ort; wird **nicht** mehr gelesen, sondern von Stufe 25/70 einmalig übernommen und nach `.vor-<datum>` verschoben |
| `/etc/platzwart-melden.conf` | `0600 root` | Discord-Webhooks. Von `install/assistent.sh` auf Wunsch angelegt, sonst von Hand; die Stufen legen sie **nicht** an; fehlt sie, meldet nichts |
| `/etc/gameserver-version` | `0644 root` | Fassung, Commit, Stand, Datum der Einrichtung |
| `/root/.borg-passphrase` | `0600 root` | Schlüssel zur Sicherung |
| `/root/platzwart-einrichtung-<zeit>.log` | `0600 root` | Ausgabe eines Laufs von `install/assistent.sh`; Erst- und Spielpasswörter schon beim Schreiben geschwärzt |
| `/opt/panel/app.py` | `0644 root` | die Oberfläche — der Dienst kann seinen eigenen Code nicht überschreiben |
| `/opt/panel/statisch/passkey.js` | `0644 root` | das einzige JavaScript des Panels (WebAuthn) |
| `/opt/panel/bilder/` | `panel` | Symbole, `katalog/` (Steam-Header), `eigene/` (selbst gezeichnet), `<stack>.jpg` |
| `/opt/panel/daten/nutzer.json` | `0600 panel` | Sitzungs-Secret und je Benutzer `passwort_hash`, `totp`, `rolle`, `totp_bestaetigt`, `codes` (Wiederherstellungscodes als Argon2id-Hashes, je 93,3 Bit), `passkeys` |
| `/opt/panel/daten/zugangsdaten.json` | `0600 panel` | selbst gepflegte Zugänge |
| `/opt/panel/daten/audit.jsonl` | `0644 panel` | Protokoll: wer hat wann was getan (Rotation bei 4 MB nach `.jsonl.1`), ohne Passwörter (#239) |
| `/opt/panel/daten/steam-api.conf` | `0600 panel` | Steam-Web-API-Schlüssel (Workshop-Suche) |
| `/opt/panel/daten/teamspeak.conf` | `0600 panel` | ServerQuery-Zugang für die Kanäle |
| `/opt/panel/daten/discord.conf` | `0600 panel` | `DISCORD_TOKEN`, `DISCORD_GUILD`, `DISCORD_BOT` |
| `/opt/panel/daten/kanaele.json` | `0600 panel` | Schalter, Oberkanal/Kategorie, Namensmuster je Dienst |
| `/opt/panel/daten/kanaele-zuordnung.json` | `0600 panel` | welcher Server welche Kanal-IDs hat, dazu `verwaist` |
| `/opt/panel/daten/netzstand.json` | `panel` | letzter Netzzählerstand je Server, für die Verkehrsrate |
| `/opt/panel/daten/konfigzahlen.json` | `0644 root` | Zahl der Konfigurationsdateien je Server, vom Einrichtungs-Timer |
| `/opt/stacks/<n>/compose.yaml` | `0600 root` | Serverdefinition mit Passwörtern |
| `/opt/stacks/<n>/panel.json` | `0640 root:panel` | Katalogserver: Anzeigedaten, Passwörter, Einrichtungsstand, `port_regel`, `ports_ausstehend`, `befehlsdatei` |
| `/var/lib/spiele-autoupdate.liste` | `0600 root` | freigeschaltete Server für nächtliche Updates, eine Zeile je Stack |
| `/var/lib/platzwart-schlaf.liste` | `0644 root` | für den Leerlauf freigeschaltete Server, eine Zeile je Stack |
| `/var/lib/platzwart-schlaf.json` | `0644 root` | seit wann leer, welche Ports, wie oft geweckt |
| `/var/lib/spiele-wiederanlauf` | `0600 root` | welche Stacks vor einem Neustart oder „alle anhalten" liefen |
| `/var/lib/platzwart-status/index.html` | `0644 root` | die öffentliche Seite; Caddy liefert sie unmittelbar aus |
| `/var/lib/platzwart-verlauf.json` | `0644 root` | Ringpuffer, 2016 Werte je Server = eine Woche; jeder Wert mit eigener Zeit, damit Lücken sichtbar bleiben |
| `/var/lib/platzwart-spieler.json` | `0644 root` | zuletzt gemessene Spielerzahlen; **kein Eintrag = keine Antwort**, nicht null |
| `/var/lib/platzwart-spieler.stumm` | `0644 root` | wer zuletzt nicht antwortete — Wiedervorlage nach 30 min |
| `/var/lib/platzwart-wache.zustand` | `0600 root` | welche Befunde beim letzten Lauf offen waren — daraus entsteht Störung vs. Entwarnung |
| `/var/lib/platzwart-melden.gesehen` | `0600 root` | zuletzt verschickte Meldungen, gegen Wiederholung |
| `/var/lib/spiele-sicherung.groessen` | `0600 root` | je Spiel: Archivgröße des letzten Laufs **und** Zeitpunkt der letzten echten Änderung |
| `/var/lib/spiele-sicherung.stoerung` | `0600 root` | Marke: die letzte Sicherung schlug fehl — der nächste Erfolg meldet Entwarnung |
| `/run/spiel-einrichtung.lock` · `/run/platzwart-schlaf.lock` · `/run/kanal-verwalten.lock` | root | Sperren: ein Lauf zur Zeit |

> *Every file this setup creates or reads, with its mode and content. Worth
> noting: the panel's code and its only JavaScript belong to root, so the
> service cannot overwrite what it serves; `nutzer.json` holds hashes, TOTP
> secrets, recovery codes as Argon2id hashes and passkeys; all credentials the
> panel stores for outside services (Steam key, TeamSpeak login, Discord bot)
> are 0600 panel under `/opt/panel/daten`, which the daily full backup archives;
> the old Cloudflare file is no longer read but migrated once by stage 25/70;
> the notifier's webhook file is created by hand; and the lists under
> `/var/lib` hold the per-server switches and the state of the timers.*

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

> *Three users: the human (web terminal, sudo, group `panel`), the `panel`
> service user that may only run `panel-aktion`, and `spiele` with the fixed UID
> 4711 that owns all game data. The containers run under that id; without a
> fixed value the save files belong to nobody after a rebuild and the server
> cannot write. Nobody is in the `docker` group.*

---

## Ports

| Port | Wo gebunden | Dienst |
|---|---|---|
| 22 | öffentlich, ufw nur aus `ADMIN_IP` | SSH (Anmeldung: `SSH_PASSWORT_AUTH`) |
| 80 | öffentlich | Caddy, für die Zertifikatsausstellung (`http-01`) |
| 443 | öffentlich | Caddy → Panel, Terminal, Statusseite |
| 8099 | `127.0.0.1` | Panel (uvicorn) |
| 7681 | `127.0.0.1` | ttyd |
| 10011 | `127.0.0.1` | TeamSpeak-ServerQuery (die Kanäle erreichen ihn über das Docker-Gateway) |
| Spielports | öffentlich, von Docker | je Stack, siehe compose; bei Katalogspielen erst nach bestätigtem Passwort |
| Verwaltungsports | `127.0.0.1` | RCON, Webkonsolen, ServerQuery — Grenze 4 |
| Weckposten | öffentlich, von systemd | nur während ein Server schläft, mit eigenen ufw-Regeln |

> *Ports: SSH from the admin address only, 80 for certificate issuance, 443 for
> panel, terminal and status page; the panel, ttyd and TeamSpeak's ServerQuery on
> localhost; game ports published by Docker (for catalogue games only after the
> join password is confirmed); management ports always on localhost; and wake
> sockets held by systemd, with ufw rules of their own, only while a server
> sleeps.*

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
| `ADMIN_NETZ` | `203.0.113.0/30` | nur `fail2ban` (`ignoreip`: nie gesperrt) — **nicht** der SSH-Zugang; ohne feste Adresse eng halten, nie `0.0.0.0/0` (#259) |
| `ADMIN_IP` | `203.0.113.1` | `ufw`-Regel auf Port 22 — Adresse oder Netz; ohne feste Adresse `0.0.0.0/0` |
| `SSH_PASSWORT_AUTH` | `no` (Vorgabe) **oder** `yes` | `sshd_config.d/99-gameserver.conf`: `PasswordAuthentication` **und** `KbdInteractiveAuthentication` |
| `ZERTIFIKAT_WEG` | `http-01` (Vorgabe) **oder** `dns-01` | Stufe 40: `/etc/caddy/zertifikat.conf`, bei `dns-01` zusätzlich ein Caddy-Bau mit DNS-Modul und ein systemd-Drop-in |
| `SSH_ROOT_LOGIN` | `prohibit-password` (Vorgabe), `no`, `forced-commands-only`, `yes` | `sshd_config.d/99-gameserver.conf`: `PermitRootLogin`; `yes` nur zusammen mit `SSH_PASSWORT_AUTH=yes` |
| `BORG_REPO` | `ssh://borg@…/…` **oder** `aus` | `spiele-sicherung`, `panel-aktion`, `spiel-verwalten`, `app.py`; `aus` schaltet die Sicherung ab |
| `FREMD_IPV4` | `198.51.100.10` | Kommentar in `dns-pflegen` (Wildcard-Ziel); ohne Wildcard eine beliebige Adresse aus einem Dokumentationsnetz — leer bricht die Einrichtung ab |

Bleibt beim Einbau ein `@@PLATZHALTER@@` stehen, bricht die Einrichtung ab.

> *All values live in `konfiguration.env` and are mandatory; a left-over
> placeholder aborts the installation. `ADMIN_IP` is the ufw rule on port 22 (an
> address or network, `0.0.0.0/0` without a static address); `ADMIN_NETZ` is only
> fail2ban's never-ban list — not SSH access — and must stay narrow, never
> `0.0.0.0/0` (#259).*

## Schalter der Werkzeuge

Jeder Wert hat eine Vorgabe im Code; die Umgebungsvariable ist der Weg, ihn für
einen Lauf oder in einer Unit zu ändern, ohne das Werkzeug anzufassen.

| Variable | Vorgabe | Werkzeug | Wirkung |
|---|---|---|---|
| `SICHERUNG_SPERRE_WARTEN` | 900 s | `spiele-sicherung` | wie lange auf die Borg-Sperre gewartet wird |
| `SICHERUNG_MIN_BYTES` | 51200 | `spiele-sicherung` | Untergrenze eines Spielarchivs |
| `SICHERUNG_EINBRUCH_ANTEIL` | 25 % | `spiele-sicherung` | Einbruch gegenüber dem letzten Lauf |
| `SICHERUNG_NEU_SCHWELLE` | 2048 B | `spiele-sicherung` | darunter gilt ein Lauf als „nichts Neues" |
| `SICHERUNG_STILL_STUNDEN` | 24 | `spiele-sicherung` | so lange darf ein laufender Server nichts schreiben |
| `SICHERUNG_OHNE_ALTERSPRUEFUNG` | `teamspeak` | `spiele-sicherung` | ausgenommen von der Stillstandsprüfung |
| `PROBE_LOCK_WAIT` · `PROBE_RESERVE_GB` | 900 s · 10 | `sicherung-probe` | Sperrwartezeit · Platz, der frei bleiben muss |
| `WACHE_PLATTE_WARN` · `WACHE_SPEICHER_WARN` | 85 · 85 | `platzwart-wache` | Prozent Belegung |
| `WACHE_NEUSTART_WARN` · `WACHE_FRISCH_MIN` | 3 · 10 | `platzwart-wache` | Neustartschleife |
| `PLATZWART_MELDEN_RUHE_MIN` | 180 | `platzwart-melden` | Ruhezeit gegen Wiederholung (Sicherungsbefunde 1440, Kanäle 720) |
| `PLATZWART_MELDEN_KONF` | `/etc/platzwart-melden.conf` | `platzwart-melden` | Webhook-Datei |
| `SCHLAF_LEER_MIN` · `SCHLAF_LEER_MIN_VERKEHR` | 30 · 180 | `platzwart-schlaf` | Minuten leer (Spielerzahl · nur Verkehr) |
| `SCHLAF_RUHE_BYTES` · `SCHLAF_FLATTER` | 1500 · 12 | `platzwart-schlaf` | Ruhe in B/s · Weckvorgänge je Tag bis zur Meldung |
| `SPIELER_TIMEOUT` · `SPIELER_STUMM_PAUSE` | 1,2 s · 1800 s | `spieler-zaehlen` | Antwortzeit · Wiedervorlage stummer Server |
| `VERLAUF_MAX` | 2016 | `platzwart-verlauf` | Werte je Server |
| `AU_RUHE_BYTES` · `AU_MESSDAUER` | 4000 · 20 s | `spiele-autoupdate` | „ruhig" und Messabstand |
| `MOD_MAX_BYTES` · `MOD_FREI_MIN_GB` | 512 MB · 10 | `mod-verwalten` | Größe eines Mods · freier Platz |
| `WORKSHOP_MAX_BYTES` | 2 GB | `workshop` | größtes Workshop-Element |
| `KANAL_PAUSE` | 0,6 s | `kanal-verwalten` | Abstand zwischen ServerQuery-Befehlen |
| `PLATZWART_PORTPRUEFUNG=aus` | an | `katalog-ports.py` | Portprüfung abschalten — nur, wenn man weiß, warum |
| `PLATZWART_DOKU_ENGLISCH=aus` | an | `doku-englisch.py` | Prüfung auf englische Absätze abschalten |
| `PLATZWART_KEIN_AUSSCHLUSS_GATE=1` | aus | `vollstaendigkeit.sh` | Prüfung der Katalog-Sicherungsausschlüsse überspringen |
| `PLATZWART_KEIN_SYSTEMCTL_GATE=1` | aus | `vollstaendigkeit.sh` | Prüfung, ob Selbsttests das System anfassen, überspringen |
| `GAMESERVER_KEIN_GATE=1` | aus | `pre-commit` | Commit trotz roter Vollständigkeitsprüfung |
| `PLATZWART_MIT_SUDO=1` | aus | `ziel.sh` | sudo-Weg erzwingen |
| `DNS_ABNAHME_TOKEN` | — | `dns-abnahme.sh` | Token statt Datei |

Pfadvariablen wie `SCHLAF_LISTE`, `SPIELER_STAND`, `WORKSHOP_KONF`,
`KANAL_DATEN` oder `STATUS_ZIEL` gibt es für die Selbsttests: Sie lenken ein
Werkzeug auf Wegwerfdateien um, statt die echten zu berühren.

> *Every value has a default in the code; the environment variable changes it for
> a run or in a unit without editing the tool. The table lists all of them with
> default, tool and effect. Path variables such as `SCHLAF_LISTE` or
> `WORKSHOP_KONF` exist for the self-tests: they redirect a tool to throwaway
> files instead of touching the real ones.*
