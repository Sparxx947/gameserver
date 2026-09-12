# 01 — Architektur

## Das Bild in einem Absatz

Ein Debian-Gast trägt Docker. Jeder Spielserver ist ein eigener Compose-Stack
mit genau einem Container; seine Daten liegen **nicht** in einem Docker-Volume,
sondern als Bind-Mount im Dateisystem, damit Borg sie direkt sichern kann. Davor
sitzt Caddy als einziger nach außen offener Webdienst und reicht drei Dinge
weiter: die Weboberfläche, ein Webterminal und eine fertige, öffentliche
Statusseite. Die Oberfläche selbst hat keinerlei Rechte — sie ruft für alles,
was Wirkung hat, über `sudo` ein einziges Skript auf, das jeden Parameter gegen
Positivlisten prüft. Alles, was regelmäßig geschehen muss — sichern,
Passwörter setzen, Ports öffnen, Spieler zählen, melden, schlafen legen,
Kanäle pflegen —, erledigen systemd-Zeitgeber mit eigenen Werkzeugen, nie ein
Seitenaufruf.

> *A Debian guest runs Docker. Each game server is its own compose stack with a
> single container; its data lives in a bind mount rather than a Docker volume
> so Borg can back it up directly. Caddy is the only externally reachable web
> service and serves three things: the panel, a web terminal and a finished
> public status page. The panel itself holds no privileges — for anything with
> an effect it calls, through `sudo`, a single script that validates every
> parameter against allow-lists. Everything that has to happen regularly —
> backups, setting passwords, opening ports, counting players, reporting, idle
> sleep, maintaining channels — is done by systemd timers running dedicated
> tools, never by a page request.*

---

## Schichten

```
                    Internet
                       │
        ┌──────────────┼──────────────────────────────────────────┐
        │              ▼                                          │
        │   :80/:443  Caddy ── forward_auth ──┐                   │  ufw: 22 (ADMIN_IP),
        │     │          │         │          │                   │  80, 443, Tailnet
        │     │          ▼         ▼          │                   │
        │     │   127.0.0.1:8099  127.0.0.1:7681                  │
        │     │   Panel (FastAPI)  ttyd ◄─────┘                   │
        │     │   Benutzer: panel  Benutzer: <admin>              │
        │     │          │                                        │
        │     ▼          │ sudo -n panel-aktion ◄── die EINZIGE Rechteerweiterung
        │  /status       ▼                                        │
        │  (fertige  root: docker / borg / spiel-verwalten / …    │
        │   Datei)       │                                        │
        │     ▲          ▼                                        │
        │     │   Docker ──► Spielports direkt nach außen (DNAT, an ufw vorbei)
        │     │          │                                        │
        │     │          ▼                                        │
        │     │   /srv/games/<spiel>/    UID 4711                 │
        │     │   /srv/dienste/<dienst>/ UID 4711                 │
        │     │                                                   │
        │   systemd-Zeitgeber: Sicherung, Einrichtung, Wache,     │
        │   Spieler, Verlauf, Status, Leerlauf, Kanäle, Updates   │
        └──────┬──────────────┬──────────────┬──────────────────────┘
               ▼              ▼              ▼
        Borg über        Discord         TeamSpeak-
        Tailscale        (Webhooks,      ServerQuery,
        ──► Sicherungs-  Bot), Steam-    Cloudflare-API
            server       Web-API
```

> *Layers: Caddy terminates TLS on 80/443 and proxies to the panel (8099) and
> the terminal (7681), both bound to localhost, and serves the public status
> page as a finished file. The terminal is gated by `forward_auth` against the
> panel session. The panel escalates only through one sudo entry. Docker
> publishes game ports itself, bypassing ufw. All game data is owned by UID
> 4711. systemd timers do the recurring work. Outward connections: Borg over
> Tailscale to the backup host, Discord (webhooks and a bot), the Steam Web API,
> TeamSpeak's ServerQuery and the Cloudflare API.*

---

## Verzeichnisse

| Pfad | Inhalt | Eigentümer |
|---|---|---|
| `/opt/stacks/<name>/compose.yaml` | Serverdefinition, enthält Klartext-Passwörter | `root:root`, `0600` |
| `/opt/stacks/<name>/panel.json` | Anzeige- und Einrichtungsdaten für Katalog-Installationen | `root:panel`, `0640` |
| `/opt/panel/app.py` | die Weboberfläche | `root:root` — die App darf ihren eigenen Code **nicht** überschreiben |
| `/opt/panel/statisch/passkey.js` | das einzige JavaScript (Passkeys) | `root:root` |
| `/opt/panel/daten/` | Benutzer, Protokoll, selbst gepflegte Zugangsdaten, Schlüssel fremder Dienste, Kanalzuordnung | `panel:panel`, `0600` |
| `/opt/panel/bilder/` | Symbole und Spieltitelbilder | `panel:panel` |
| `/srv/games/<name>/` | Spielstände und Installation | `4711:4711`, `0770` |
| `/srv/dienste/<name>/` | Dienste, die keine Spiele sind (TeamSpeak) | `4711:4711`, `0770` |
| `/etc/spiele-katalog.json` | die 185 installierbaren Spiele | `root:root`, `0644` |
| `/etc/spiele-adressen.json` · `spiele-mods.json` · `spiele-workshop.json` | Beitrittsadressen der Handbauten · wohin Mods gehören · Workshop je Spiel | `root:root`, `0644` |
| `/etc/borg-ausschluss.txt` | was **nicht** gesichert wird | `root:root` |
| `/root/.borg-passphrase` | Schlüssel zur Sicherung | `root:root`, `0600` |
| `/var/lib/spiele-autoupdate.liste` · `platzwart-schlaf.liste` | Schalter je Server: Auto-Update, Leerlauf | `root` |
| `/var/lib/platzwart-*` | Zustand der Zeitgeber: Spielerzahlen, Verlauf, Statusseite, Wache, Schlaf, Meldegedächtnis | `root` |

**Warum `/srv/dienste` getrennt von `/srv/games`:** Die Prüfung der Sicherungen
verlangt für jedes Verzeichnis unter `/srv/games` Spielstand-Dateien. TeamSpeak
hat keine und hätte dauerhaft Alarm ausgelöst.

**Warum die Schalter in eigenen Listen stehen und nicht in `panel.json`:** Eine
`panel.json` haben nur Katalog-Installationen. Der Auto-Update-Schalter lag
zuerst dort und erreichte damit einen von acht Servern — ausgerechnet die von
Hand gebauten, die laufend Patches bekommen, nicht.

> *Directories: stacks with their compose file (0600, cleartext passwords) and,
> for catalogue installs, a `panel.json`; the panel's code and its only
> JavaScript owned by root; the panel's data (users, audit log, hand-kept
> credentials, outside-service keys, channel mapping) 0600 panel; game data and
> services as UID 4711; the catalogue and three smaller configuration files under
> `/etc`; the backup exclusions and passphrase; and under `/var/lib` the
> per-server switches and the timers' state. `/srv/dienste` is separate because
> the backup check expects save files under every `/srv/games` directory and
> TeamSpeak has none. The switches live in lists of their own because only
> catalogue installs have a `panel.json` — the auto-update switch once lived
> there and reached one server out of eight.*

---

## Warum Bind-Mounts und keine Docker-Volumes

Ein Docker-Volume liegt unter `/var/lib/docker/volumes/<hash>/_data`. Um es zu
sichern, müsste Borg entweder diesen Pfad kennen (er ändert sich beim
Neuanlegen) oder ein Hilfscontainer müsste es herauskopieren. Ein Bind-Mount
liegt an einer Stelle, die ein Mensch benennen kann, lässt sich ohne Docker
lesen und überlebt `docker system prune`.

Der Preis: Die Rechte muss man selbst setzen. Deshalb die feste UID/GID 4711 für
alle Spieldaten — ohne festen Wert gehören die Spielstände nach einem Neuaufbau
plötzlich niemandem.

> *Why bind mounts, not Docker volumes: a volume lives under a hash-named path
> that changes when recreated, and backing it up needs either that path or a
> helper container. A bind mount has a name a human can say, is readable without
> Docker, and survives `docker system prune`. The price is managing ownership
> yourself — hence the fixed UID/GID 4711 for all game data.*

---

## Zwei Sorten Server

**Handgepflegt** (`stacks/*.yaml` in diesem Repositorium, eingerichtet mit
`install/60-spiele.sh`): Enshrouded, Palworld, Satisfactory, FOUNDRY, Windrose
und TeamSpeak. Jeder braucht ein eigenes Image mit eigenen Umgebungsvariablen.
Ihre Beitrittsadressen stehen in `/etc/spiele-adressen.json`, weil die
veröffentlichten Ports teils vom Spielstandard abweichen (Satisfactory hat 7777,
deshalb liegt Windrose auf 7780) und sich nicht aus der compose-Datei erraten
lassen. StarRupture stand bis zum 2026-09-09 hier; es lief nie stabil und wurde
entfernt.

**Aus dem Katalog** (`/etc/spiele-katalog.json`, 179 Einträge): Werden über die
Oberfläche installiert und wieder entfernt. Drei Bauarten: 82 Einträge nach den
Vorlagen von ich777 (die meisten auf demselben Image `ghcr.io/ich777/steamcmd`,
unterschieden nur durch `GAME_ID` und `GAME_PARAMS`), 85 nach LinuxGSM
(`gameservermanagers/gameserver`) und 12 mit eigenem Image (Minecraft Java in
acht Varianten und Bedrock, Factorio, Vintage Story, TeamSpeak). Sie legen beim Installieren
eine `panel.json` an, aus der die Oberfläche Adresse, Hinweis und
Einrichtungsstand liest. Auf der laufenden Maschine ist Valheim so installiert.

Der Unterschied ist auch eine **Schutzgrenze**: `spiel-verwalten deinstallieren`
verlangt zwingend eine `panel.json`. Die handgepflegten Server haben keine und
können über diesen Weg nicht gelöscht werden; für sie gibt es einen eigenen,
nur für Administratoren erreichbaren Weg (`fremd-entfernen`), der nichts über
den Katalog annimmt.

> *Two kinds of server. Hand-maintained: Enshrouded, Palworld, Satisfactory,
> FOUNDRY, Windrose and TeamSpeak, each needing its own image and environment,
> set up by stage 60, with join addresses in `/etc/spiele-adressen.json` because
> the published ports deviate from the game defaults (StarRupture was here until
> 2026-09-09 and was removed). Catalogue: 179 entries installed and removed
> through the panel, in three build styles — 82 from ich777's templates (most on
> the same steamcmd image, differing only in `GAME_ID`/`GAME_PARAMS`), 85 from
> LinuxGSM and 12 with images of their own (Minecraft Java in eight variants
> plus Bedrock, Factorio, Vintage Story, TeamSpeak); they write a `panel.json` holding
> address, note and setup state. Valheim runs this way on the live machine. The
> distinction is also a safety boundary: catalogue removal requires a
> `panel.json`, so it cannot delete the hand-maintained stacks; those have a
> separate, admin-only path that assumes nothing about the catalogue.*

---

## Datenfluss einer Installation

1. Die Oberfläche übergibt **nur einen Schlüssel** (`necesse`), niemals Image,
   Ports oder Volumes. Wer diese Werte setzen könnte, könnte `/:/host` mounten.
2. `spiel-verwalten` schlägt den Schlüssel im Katalog nach, prüft freien Platz
   (10 GB Reserve) und Portkollisionen gegen die **tatsächlich belegten** Ports,
   lokale eingeschlossen.
3. Es würfelt ein Beitritts- und ein Adminpasswort, schreibt `compose.yaml`
   (`0600`) — **ohne** die öffentlichen Spielports, die als `ports_ausstehend`
   in der `panel.json` (`0640 root:panel`) warten —, ergänzt den
   Ausschlussblock der Sicherung, die Zugangsdaten und lädt das Titelbild.
4. Spiele, deren Passwort in einer Befehlsdatei steht (Unturned), bekommen diese
   Datei **vor** dem ersten Start; scheitert das, startet nichts.
5. Gestartet wird nur, wenn der freie Arbeitsspeicher zum `mem_limit` reicht.
6. `panel-aktion` stößt den Kanal-Abgleich an (TeamSpeak, Discord) und legt den
   DNS-Namen an.
7. Der Timer `spiel-einrichtung` prüft alle zwei Minuten, ob der Server seine
   Konfigurationsdatei angelegt hat, und trägt Passwort und Spielerzahl ein —
   bei Startparametern fragt er den laufenden Server per A2S, ob er ein Passwort
   verlangt.
8. **Erst dann** trägt `port-ermitteln` die Spielports in die compose-Datei ein
   und startet den Container neu; von da an ist der Server erreichbar. Findet
   die Einrichtung nach sechs Stunden nichts und bestätigt der Server kein
   Passwort, bleibt der Port **zu** (E26). Spiele ohne Passwort bleiben zu, bis
   ein Mensch sie freigibt.

> *Install data flow: the panel passes only a key — never image, ports or
> volumes, since anyone who could set those could mount `/:/host`. The installer
> looks the key up, checks free space and real port collisions (local ones
> included), generates two passwords, writes the compose file without the public
> game ports — they wait in `panel.json` as pending — adds the backup exclusion
> block and the credentials, and fetches the artwork. Games whose password lives
> in a command file get that file before the first start. The server starts only
> if free RAM covers its limit. `panel-aktion` then triggers the channel sync and
> creates the DNS name. The setup timer waits for the server's own config file
> and writes password and player count into it, or asks the running server via
> A2S whether it requires a password. Only then does `port-ermitteln` publish
> the game ports and restart the container — from that moment the server is
> reachable. Without a password after six hours, and without the server
> confirming one, the port stays closed (E26); games without a password stay
> closed until a person releases them.*

---

## Was von selbst läuft

| Wann | Werkzeug | Aufgabe |
|---|---|---|
| alle 15 min, täglich 04:00 | `spiele-sicherung` | Borg-Archive je Spiel, prüfen, melden |
| alle 2 min | `spiel-einrichtung` | Passwörter frischer Server setzen, dann Ports öffnen |
| jede Minute | `spieler-zaehlen` | Spielerzahlen per A2S |
| jede Minute | `platzwart-status` | öffentliche Statusseite schreiben |
| alle 5 min | `platzwart-verlauf` | Speicher, CPU, Spieler in einen Ringpuffer |
| alle 5 min | `platzwart-wache` | Lage prüfen, Änderungen nach Discord melden |
| alle 5 min | `kanal-verwalten` | TeamSpeak- und Discord-Kanäle angleichen |
| alle 10 min | `platzwart-schlaf` | leere Server schlafen legen |
| täglich 05:15 | `spiele-autoupdate` | freigeschaltete Server aktualisieren |
| 05:30 und 17:30 | `docker restart palworld` | gegen Palworlds Speicherleck |
| alle 5 min (nur `dynamic`) | `dns-pflegen ziel-setzen` | öffentliche IPv4 in den A-Eintrag |
| beim Hochfahren | `spiele-wiederanlauf` | vorher laufende Server wieder starten |
| beim ersten Paket | `platzwart-wecken@` | schlafenden Server wecken |

**Kein Seitenaufruf wartet auf einen fremden Dienst.** Die Übersicht liest nur,
was die Zeitgeber geschrieben haben; Kanäle entstehen im Dienst, nicht im Klick
auf „installieren". Ein Panel, das auf TeamSpeak, Discord oder einen
Spielserver wartet, hängt, wenn der hängt.

> *What runs by itself: the table lists every timer with its schedule and task —
> backups, setup, player counts, status page, history, watchdog, channels, idle
> sleep, nightly updates, the Palworld restart, the dynamic DNS record, the
> post-reboot restart and the wake-on-join unit. No page request waits for an
> outside service: the overview only reads what the timers wrote, and channels
> are created by the service, not by the click on "install" — a panel that
> waits for TeamSpeak, Discord or a game server hangs when they hang.*

---

## Wege nach außen

| Ziel | Wer | Wozu | Geheimnis |
|---|---|---|---|
| Borg-Sicherungsserver über Tailscale | `spiele-sicherung`, `panel-aktion` | Archive | `/root/.borg-passphrase`, SSH-Schlüssel von root |
| Cloudflare-API | `dns-pflegen`, Caddy bei `dns-01` | DNS-Namen, Zertifikat | `/etc/dns-gameserver.conf` |
| Discord-Webhooks | `platzwart-melden` | Störungen und Mitteilungen | `/etc/platzwart-melden.conf` |
| Discord-API und -Gateway | `kanal-verwalten` | Kanäle, Belegung der Sprachkanäle | `/opt/panel/daten/discord.conf` |
| TeamSpeak-ServerQuery (lokal) | `kanal-verwalten` | Kanäle | `/opt/panel/daten/teamspeak.conf` |
| Steam-Web-API | `workshop` | Workshop-Details, Suche | `/opt/panel/daten/steam-api.conf` |
| Steam, Docker-Registries, Thunderstore | die Container selbst | Spieldateien, Images, BepInEx | — |

Jedes Geheimnis liegt `0600` an genau einer Stelle, keines im Repositorium, und
keines geht je als Kommandozeilenargument durch die Prozessliste.

> *Ways out: the table lists every outward connection with its user, purpose and
> the file holding its secret — the backup host over Tailscale, the Cloudflare
> API, Discord webhooks, Discord's API and Gateway, TeamSpeak's local
> ServerQuery, the Steam Web API, and the containers' own downloads. Every secret
> is 0600 in exactly one place, none is in the repository, and none ever travels
> as a command-line argument through the process list.*
