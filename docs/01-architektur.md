# 01 — Architektur

## Das Bild in einem Absatz

Ein Debian-Gast trägt Docker. Jeder Spielserver ist ein eigener Compose-Stack
mit genau einem Container; seine Daten liegen **nicht** in einem Docker-Volume,
sondern als Bind-Mount im Dateisystem, damit Borg sie direkt sichern kann. Davor
sitzt Caddy als einziger nach außen offener Webdienst und reicht zwei Dinge
weiter: die Weboberfläche und ein Webterminal. Die Oberfläche selbst hat
keinerlei Rechte — sie ruft für alles, was Wirkung hat, über `sudo` ein einziges
Skript auf, das jeden Parameter gegen Positivlisten prüft.

> *A Debian guest runs Docker. Each game server is its own compose stack with a
> single container; its data lives in a bind mount rather than a Docker volume
> so Borg can back it up directly. Caddy is the only externally reachable web
> service and proxies two things: the panel and a web terminal. The panel itself
> holds no privileges — for anything with an effect it calls, through `sudo`, a
> single script that validates every parameter against allow-lists.*

---

## Schichten

```
                    Internet
                       │
        ┌──────────────┼──────────────────────────────┐
        │              ▼                              │
        │   :80/:443  Caddy  ──── forward_auth ───┐   │   ufw: nur 22 (Heimnetz),
        │              │                          │   │   80, 443 und Tailnet
        │      ┌───────┴────────┐                 │   │
        │      ▼                ▼                 │   │
        │  127.0.0.1:8099   127.0.0.1:7681        │   │
        │   Panel (FastAPI)   ttyd ◄──────────────┘   │
        │   Benutzer: panel   Benutzer: <admin>       │
        │      │                                      │
        │      │ sudo -n panel-aktion  ◄── die EINZIGE Rechteerweiterung
        │      ▼                                      │
        │   root: docker / borg / spiel-verwalten     │
        │      │                                      │
        │      ▼                                      │
        │   Docker ──► Spielports direkt nach außen (DNAT, an ufw vorbei)
        │      │                                      │
        │      ▼                                      │
        │   /srv/games/<spiel>/      UID 4711         │
        │   /srv/dienste/<dienst>/   UID 4711         │
        │      │                                      │
        └──────┼──────────────────────────────────────┘
               ▼
        Borg über Tailscale ──► Sicherungsserver
```

> *Layers: Caddy terminates TLS on 80/443 and proxies to the panel (8099) and
> the terminal (7681), both bound to localhost. The terminal is gated by
> `forward_auth` against the panel session. The panel escalates only through one
> sudo entry. Docker publishes game ports itself, bypassing ufw. All game data
> is owned by UID 4711 and backed up over Tailscale.*

---

## Verzeichnisse

| Pfad | Inhalt | Eigentümer |
|---|---|---|
| `/opt/stacks/<name>/compose.yaml` | Serverdefinition, enthält Klartext-Passwörter | `root:root`, `0600` |
| `/opt/stacks/<name>/panel.json` | Anzeigedaten für Katalog-Installationen | `root:panel`, `0640` |
| `/opt/panel/app.py` | die Weboberfläche | `root:root` — die App darf ihren eigenen Code **nicht** überschreiben |
| `/opt/panel/daten/` | Benutzer, selbst gepflegte Zugangsdaten | `panel:panel`, `0600` |
| `/opt/panel/bilder/` | Symbole und Spieltitelbilder | `panel:panel` |
| `/srv/games/<name>/` | Spielstände und Installation | `4711:4711`, `0770` |
| `/srv/dienste/<name>/` | Dienste, die keine Spiele sind (TeamSpeak) | `4711:4711`, `0770` |
| `/etc/spiele-katalog.json` | die 179 installierbaren Spiele | `root:root`, `0644` |
| `/etc/borg-ausschluss.txt` | was **nicht** gesichert wird | `root:root` |
| `/root/.borg-passphrase` | Schlüssel zur Sicherung | `root:root`, `0600` |

**Warum `/srv/dienste` getrennt von `/srv/games`:** Die Prüfung der Sicherungen
verlangt für jedes Verzeichnis unter `/srv/games` Spielstand-Dateien. TeamSpeak
hat keine und hätte dauerhaft Alarm ausgelöst.

> *Why `/srv/dienste` is separate from `/srv/games`: the backup check expects
> save files under every `/srv/games` directory. TeamSpeak has none and would
> have raised a permanent false alarm.*

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

**Handgepflegt** (`stacks/*.yaml` in diesem Repositorium): Enshrouded, Palworld,
Satisfactory, FOUNDRY, StarRupture, Windrose, TeamSpeak. Jeder braucht ein
eigenes Image mit eigenen Umgebungsvariablen. Ihre Beitrittsadressen stehen fest
verdrahtet in `app.py`, weil die veröffentlichten Ports teils vom Spielstandard
abweichen und sich nicht aus der compose-Datei erraten lassen.

**Aus dem Katalog** (`/etc/spiele-katalog.json`, 41 Einträge): Werden über die
Oberfläche installiert und wieder entfernt. Fast alle laufen auf demselben
Image (`ghcr.io/ich777/steamcmd`), unterschieden nur durch `GAME_ID` und
`GAME_PARAMS`. Sie legen beim Installieren eine `panel.json` an, aus der die
Oberfläche Adresse und Hinweis liest.

Der Unterschied ist auch eine **Schutzgrenze**: `spiel-verwalten deinstallieren`
verlangt zwingend eine `panel.json`. Die sieben handgepflegten Server haben
keine und können deshalb über die Oberfläche nicht gelöscht werden.

> *Two kinds of server: seven hand-maintained stacks, each needing its own image
> and env, with join addresses hard-wired in `app.py` because the published
> ports deviate from the game defaults; and 41 catalogue entries installed and
> removed through the panel, nearly all sharing one image and differing only in
> `GAME_ID`/`GAME_PARAMS`. The distinction is also a safety boundary:
> uninstalling requires a `panel.json`, which the hand-maintained stacks do not
> have — so the panel cannot delete them.*

---

## Datenfluss einer Installation

1. Die Oberfläche übergibt **nur einen Schlüssel** (`necesse`), niemals Image,
   Ports oder Volumes. Wer diese Werte setzen könnte, könnte `/:/host` mounten.
2. `spiel-verwalten` schlägt den Schlüssel im Katalog nach, prüft freien Platz
   (10 GB Reserve) und Portkollisionen gegen die **tatsächlich belegten** Ports.
3. Es würfelt ein Beitritts- und ein Adminpasswort, schreibt `compose.yaml`
   (`0600`) und `panel.json` (`0640 root:panel`), ergänzt den Ausschlussblock
   der Sicherung und lädt das Titelbild.
4. Gestartet wird nur, wenn der freie Arbeitsspeicher zum `mem_limit` reicht.
5. Der Timer `spiel-einrichtung` prüft alle zwei Minuten, ob der Server seine
   Konfigurationsdatei angelegt hat, und trägt Passwort und Spielerzahl ein.
   Nach sechs Stunden gibt er auf und meldet das sichtbar in der Oberfläche.

> *Install data flow: the panel passes only a key — never image, ports or
> volumes, since anyone who could set those could mount `/:/host`. The installer
> looks the key up, checks free space and real port collisions, generates two
> passwords, writes the compose and panel files, extends the backup exclusion
> list, fetches the artwork, and starts the server only if free RAM covers the
> memory limit. A timer then waits for the server's own config file to appear
> and writes the join password and player count into it, giving up visibly after
> six hours.*
