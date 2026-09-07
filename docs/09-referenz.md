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

Ohne Parameter; wird vom Timer alle zwei Minuten gerufen. Sucht bei frisch
installierten Servern die Konfigurationsdatei und trägt Beitrittspasswort,
Adminpasswort und Spielerzahl ein. Erkennt `.ini`, `.json`, `.xml` und `.cfg`
über Feldnamensmuster. Gibt nach sechs Stunden auf und meldet das sichtbar.

### `spiele-sicherung`

```
spiele-sicherung                 nur laufende Spiele
spiele-sicherung --alle          auch gestoppte, dazu /opt/stacks und /etc
spiele-sicherung --nur <name>    ein einzelnes Spiel
```

Ein Archiv je Spiel, Name `<spiel>-JJJJMMTT-HHMMSS`. `prune` je Präfix,
anschließend `borg compact`. Rechte `0700 root` — die Datei enthält den Pfad zum
Repositorium.

### `cf-dns`

```
cf-dns setzen <name>        CNAME <name>.<zone> -> <ziel>, dns-only
cf-dns entfernen <name>
cf-dns liste
cf-dns pruefen              meldet Einträge, die fälschlich proxied sind
```

Fragt **nur die API**, nie die Namensauflösung — ein Wildcard in der Zone würde
jede Existenzprüfung per `dig` wertlos machen. Löscht nur Einträge, die
tatsächlich auf `DNS_ZIEL` zeigen. Erzwingt IPv4.

### `katalog-vorpruefung`

Ohne Parameter. Prüft alle Katalogeinträge **ohne Download**: Pflichtfelder,
Schlüsselform, Portkollisionen (installierte Spiele ausgenommen), erzeugt die
echte `compose.yaml` und lässt `docker compose config -q` darauf laufen, fragt
`docker manifest inspect` ab.

Ergebnis vom 2026-09-06: 34 ohne Befund, 5 Hinweis, 0 Fehler, 2 installiert.

### `ttyd`

Das Webterminal, Version 1.7.7 als Release-Binary. Nicht aus Debian: bookworm
liefert 1.6, dessen `--base-path` sich anders verhält.

---

## Prüfwerkzeuge (`werkzeuge/`)

### `abgleich.sh <ssh-ziel>`

Vergleicht das Repositorium mit einer laufenden Maschine — **27 Prüfpunkte**:

| Was | Wie verglichen |
|---|---|
| 22 Dateien (Werkzeuge, `/etc`, Units, `app.py`) | byte-genau, nach Einsetzen der Platzhalter |
| Python-Umgebung des Panels | `pip list --format=freeze` gegen `panel/requirements.txt` |
| ttyd | installierte Version gegen `TTYD_VERSION` in Stufe 40 |
| 3 Symbole | byte-genau |

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
| `panel.service` | dauerhaft | Weboberfläche, `User=panel`, uvicorn auf `127.0.0.1:8099` |
| `ttyd.service` | dauerhaft | Webterminal, `User=<admin>`, `127.0.0.1:7681` |
| `spiele-sicherung.timer` | `*:0/15`, ±60 s | Sicherung laufender Spiele |
| `spiele-sicherung-voll.timer` | täglich 04:00, ±300 s | Vollsicherung |
| `spiel-einrichtung.timer` | alle 2 min, ab 3 min nach dem Start | Passwörter frischer Server setzen |
| `palworld-neustart.timer` | 05:30 und 17:30 | gegen das Speicherleck |

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
| `/etc/spiele-katalog.json` | `0644 root` | 41 installierbare Spiele |
| `/etc/borg-ausschluss.txt` | `0644 root` | was nicht gesichert wird |
| `/etc/caddy/Caddyfile` | `0644 root` | HTTPS, Vorschaltung, Kopfzeilen |
| `/etc/fail2ban/jail.local` | `0644 root` | sshd-Jail, Ausnahmen |
| `/etc/sudoers.d/panel` | `0440 root` | die eine Rechteerweiterung |
| `/etc/cloudflare-gameserver.conf` | `0600 root` | `CF_TOKEN=…` |
| `/root/.borg-passphrase` | `0600 root` | Schlüssel zur Sicherung |
| `/opt/panel/app.py` | `0644 root` | die Oberfläche |
| `/opt/panel/daten/nutzer.json` | `0600 panel` | Benutzer, Hashes, TOTP |
| `/opt/panel/daten/zugangsdaten.json` | `0600 panel` | selbst gepflegte Zugänge |
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
| `DNS_ZONE` | `beispiel.de` | `cf-dns`, `app.py`, Beitrittsadressen |
| `DNS_ZIEL` | `gs.beispiel.de` | `cf-dns` (CNAME-Ziel) |
| `PANEL_DOMAIN` | `panel.beispiel.de` | `Caddyfile` |
| `SERVER_IPV4` | `203.0.113.10` | `cf-dns` (Kommentar/Prüfung) |
| `WELT_NAME` | `meinserver` | Server- und Weltnamen in den Spielen |
| `ADMIN_USER` | `admin` | `ttyd.service`, Benutzeranlage |
| `ADMIN_NETZ` | `203.0.113.0/30` | `fail2ban` |
| `ADMIN_IP` | `203.0.113.1` | `ufw`-Regel auf Port 22 |
| `BORG_REPO` | `ssh://borg@…/…` | `spiele-sicherung`, `panel-aktion` |
| `BORG_TAILSCALE_IP` | `100.100.100.100` | Dokumentation, Prüfungen |
| `FREMD_IPV4` | `198.51.100.10` | Kommentar in `cf-dns` (Wildcard-Ziel) |

Bleibt beim Einbau ein `@@PLATZHALTER@@` stehen, bricht die Einrichtung ab.

> *All values live in `konfiguration.env` and are mandatory; a left-over
> placeholder aborts the installation.*
