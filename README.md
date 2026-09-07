# gameserver

Vollständiger Bausatz für einen selbst gehosteten **Spieleserver mit Weboberfläche**:
Docker-Serverstacks, ein Panel mit Zwei-Faktor-Anmeldung, ein Katalog von 41
installierbaren Spielen, Sicherung nach Borg mit Großvater-Vater-Sohn und
automatisch gepflegte DNS-Namen bei Cloudflare.

Dieses Repositorium beschreibt **den Ist-Zustand einer laufenden Maschine** und
enthält alles, um sie von einem leeren Debian 12 aus neu aufzubauen. Alle
standortbezogenen Angaben — Domains, Adressen, Netze, Passwörter — sind durch
`@@PLATZHALTER@@` ersetzt und stehen in einer einzigen, nicht eingecheckten
Datei.

> *Complete kit for a self-hosted **game server with a web panel**: Docker
> service stacks, a panel with two-factor login, a catalogue of 41 installable
> games, Borg backups on a grandfather-father-son rotation, and automatically
> maintained Cloudflare DNS records. This repository documents the actual state
> of a running machine and contains everything needed to rebuild it from a bare
> Debian 12. Every site-specific value — domains, addresses, networks,
> passwords — is replaced by an `@@PLACEHOLDER@@` and lives in a single file
> that is never committed.*

---

## Was hier läuft

| Bestandteil | Umsetzung |
|---|---|
| Betriebssystem | Debian 12 (bookworm), KVM-Gast |
| Container | Docker CE mit `compose`-Plugin, ein Stack je Spiel unter `/opt/stacks/<name>/` |
| Spieldaten | Bind-Mounts unter `/srv/games/<name>/`, Dienste unter `/srv/dienste/<name>/`, alles unter UID/GID **4711** |
| Weboberfläche | FastAPI/uvicorn auf `127.0.0.1:8099`, Benutzer `panel`, ohne Docker-Zugriff |
| Webterminal | `ttyd` auf `127.0.0.1:7681`, vorgeschaltete Prüfung der Panel-Sitzung durch Caddy |
| HTTPS | Caddy, Zertifikat automatisch, nur HTTP/1.1 |
| Rechteübergang | genau ein `sudo`-Eintrag: `panel` darf `panel-aktion` aufrufen, sonst nichts |
| Sicherung | Borg über Tailscale, alle 15 min inkrementell, täglich vollständig — mit `BORG_REPO=aus` abschaltbar |
| DNS | Cloudflare, ein CNAME je Spiel auf einen einzigen A-Eintrag |
| Firewall | ufw (alles zu) + fail2ban; Spielports macht Docker selbst auf |

> *What runs here: Debian 12 on KVM; Docker CE with one compose stack per game;
> game data bind-mounted under `/srv/games/` as UID/GID 4711; a FastAPI panel on
> localhost with no Docker access; a ttyd web terminal gated by Caddy against
> the panel session; automatic HTTPS; exactly one sudo rule as the privilege
> boundary; Borg backups over Tailscale; one Cloudflare CNAME per game; ufw
> plus fail2ban, with game ports opened by Docker itself.*

---

## Schnellstart

```bash
git clone <dieses-repo> gameserver && cd gameserver
cp konfiguration.env.beispiel konfiguration.env
$EDITOR konfiguration.env            # Domains, Adressen, Netze eintragen
sudo install/einrichten.sh           # Stufen 10–50
sudo install/60-spiele.sh teamspeak enshrouded palworld
sudo install/70-dns.sh               # optional, braucht ein Cloudflare-Token
```

Die Erstanmeldung des Panels wird **einmal** am Ende von Stufe 30 ausgegeben.
Der zweite Faktor wird beim ersten Anmelden im Browser als QR-Code eingerichtet.

> *Quick start: clone, copy `konfiguration.env.beispiel` to
> `konfiguration.env`, fill in domains and addresses, then run
> `install/einrichten.sh`. The initial panel login is printed **once** at the
> end of stage 30; the second factor is enrolled as a QR code on first login.*

Ausführlich: **[docs/02-installation.md](docs/02-installation.md)**.

---

## Aufbau des Repositoriums

```
bin/          Werkzeuge nach /usr/local/bin
etc/          Konfigurationsdateien nach /etc
systemd/      Dienste und Zeitpläne nach /etc/systemd/system
panel/        Die Weboberfläche (app.py, Abhängigkeiten, Symbole)
stacks/       compose-Vorlagen der sieben handgepflegten Server
install/      Einrichtung in Stufen, jede einzeln aufrufbar
werkzeuge/    Abgleich Repo ↔ Server, Ausrollen, Vollständigkeit, Titelbilder
docs/         Diese Dokumentation
```

### Bleibt das Repositorium ehrlich?

```bash
werkzeuge/abgleich.sh gameserver
```

Setzt die Platzhalter aus `konfiguration.env` ein und vergleicht das Ergebnis
mit der laufenden Maschine — 33 Prüfpunkte: 23 Dateien byte-genau, dazu die
Python-Umgebung des Panels gegen `requirements.txt`, die ttyd-Version gegen die
in Stufe 40 festgeschriebene, die selbst erzeugten Symbole und Titelbilder sowie
die Vollständigkeit der Katalogbilder. Exit 0 =
deckungsgleich, 1 = Abweichungen (mit Diff), 2 = nicht erreichbar. Ändert nichts.

Eine Dokumentation, die vom System abweicht, ist schlimmer als keine — man
handelt danach. Dieses Werkzeug findet die Abweichung, statt darauf zu hoffen,
dass jemand sie bemerkt.

> *Does the repository still match reality? `werkzeuge/abgleich.sh <ssh-target>`
> substitutes the placeholders and compares every file against the running
> machine. Exit 0 means identical, 1 means drift (with a diff), 2 means
> unreachable; it changes nothing. Documentation that has drifted is worse than
> none, because people act on it — this finds the drift instead of hoping someone
> notices.*

### Welcher Stand läuft da eigentlich?

```bash
cat /etc/gameserver-version        # auf der Maschine
werkzeuge/abgleich.sh gameserver   # vergleicht ihn mit diesem Repositorium
```

`VERSION` nennt die Fassung des Bausatzes; beim Einrichten entsteht daraus ein
Stempel auf der Maschine mit Fassung, Commit, Datum und der Angabe, ob seither
einzelne Dateien von Hand nachgerollt wurden.

> *`VERSION` names the release; installing writes a stamp on the machine holding
> the release, the commit, the date, and whether single files have been rolled
> out by hand since. `abgleich.sh` compares it.*

### Ist das Repositorium vollständig?

```bash
werkzeuge/vollstaendigkeit.sh
```

Prüft in einem Lauf: Ist jede von `install/` angefasste Datei vorhanden **und von
git verfolgt**? Sind alle Skripte syntaktisch heil? Steckt irgendwo ein
Geheimnis? Ist jeder `@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt?

Anlass war ein echter Fund: Die `.gitignore`-Regel `*.local` schluckte
`etc/fail2ban/jail.local` — eine Datei, die Stufe 10 zwingend braucht. Der Push
war grün, die Dateiliste sah vollständig aus, und aufgefallen wäre es erst bei
der nächsten Neueinrichtung.

Als Bremse vor jedem Commit:

```bash
ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit
```

Bewusst als Symlink und **nicht** über `git config core.hooksPath`: Das ersetzt
das gesamte Hook-Verzeichnis und schaltet alle bereits vorhandenen Haken ab. Ein
Schutz, der einen anderen Schutz abräumt, ist keiner.

Notausgang: `GAMESERVER_KEIN_GATE=1 git commit …`

> *Is the repository complete? `werkzeuge/vollstaendigkeit.sh` checks in one run
> whether every file `install/` touches exists **and is tracked by git**, whether
> all scripts parse, whether any secret slipped in, and whether every
> `@@PLACEHOLDER@@` is documented. It exists because of a real find: a
> `.gitignore` rule of `*.local` swallowed `etc/fail2ban/jail.local`, which stage
> 10 requires — the push was green and it would only have surfaced at the next
> fresh install. Wire it in as a pre-commit gate with the symlink above —
> deliberately not via `core.hooksPath`, which replaces the whole hooks directory
> and would disable any hook already present; bypass with
> `GAMESERVER_KEIN_GATE=1`.*

> *Repository layout: tools, `/etc` files, systemd units, the panel itself,
> compose templates for the seven hand-maintained servers, staged installation
> scripts, and this documentation.*

---

## Dokumentation

**Wer hier mitentwickelt, liest zuerst [CLAUDE.md](CLAUDE.md)** — Arbeitsweise,
die vier nicht verhandelbaren Sicherheitsgrenzen und die Fallstricke, die schon
Zeit gekostet haben.

> *Anyone contributing should start with [CLAUDE.md](CLAUDE.md): working
> practices, the four non-negotiable security boundaries, and the traps that have
> already cost time.*

| Kapitel | Inhalt |
|---|---|
| [01 Architektur](docs/01-architektur.md) | Wie die Teile zusammenhängen, Datenflüsse, Verzeichnisse |
| [02 Installation](docs/02-installation.md) | Von der leeren Maschine zum laufenden Panel |
| [03 Panel](docs/03-panel.md) | Bedienung, Rollen, alle Routen, Datenhaltung |
| [04 Spielekatalog](docs/04-spielekatalog.md) | Wie Installation und Deinstallation funktionieren, Katalog erweitern |
| [05 Sicherung](docs/05-sicherung.md) | Borg, Aufbewahrung, Wiederherstellung, Prüfung |
| [06 Netz, DNS, Firewall](docs/06-netz-dns-firewall.md) | Ports, Docker und ufw, Cloudflare |
| [07 Sicherheitsentwurf](docs/07-sicherheitsentwurf.md) | Wo die Grenzen verlaufen und warum |
| [08 Betrieb und Störungen](docs/08-betrieb-und-stoerungen.md) | Alltag, Fehlerbilder, bekannte Fallen |
| [09 Referenz](docs/09-referenz.md) | Jedes Werkzeug, jede Unit, jede Datei |
| [10 Entscheidungen](docs/10-entscheidungen.md) | Warum es so ist und nicht anders |

---

## Was hier bewusst **nicht** drin steht

* **Keine Geheimnisse.** Panel-Hash, TOTP-Geheimnis, Sitzungs-Secret,
  Borg-Passphrase, Cloudflare-Token und alle Spiel-Passwörter entstehen bei der
  Einrichtung auf der Zielmaschine und werden nie eingecheckt.
* **Keine Standortdaten.** Domains, IP-Adressen, Netze und der Benutzername
  stehen ausschließlich in `konfiguration.env`.
* **Keine Bilder aus Steam.** Die Kopfgrafiken der Spiele sind Werke Dritter;
  sie werden zur Laufzeit geladen und liegen deshalb nicht im Repositorium.
  Enthalten sind nur die selbst erzeugten Symbole (`favicon.svg`, `favicon.ico`,
  `apple-touch-icon.png`).
* **Keine Spielstände.** Die gehören in die Sicherung, nicht in die Versionsverwaltung.

> *Deliberately absent: any secret (all are generated on the target machine),
> any site-specific value (they live in `konfiguration.env` only), Steam
> artwork (third-party works, fetched at runtime — only the self-made icons are
> included), and save games (those belong in the backup, not in version
> control).*

---

## Voraussetzungen

* Debian 12 (bookworm) mit root-Zugang
* Eine öffentliche IPv4 und ein DNS-Name, der darauf zeigt (für das Zertifikat)
* Für die Sicherung: ein erreichbares Borg-Ziel, empfohlen über ein privates
  Netz wie Tailscale — oder `BORG_REPO=aus`, dann wird nicht gesichert
* Für DNS: ein Cloudflare-Token mit `Zone / DNS / Bearbeiten`, begrenzt auf die
  eigene Zone

Als Anhalt: Die dokumentierte Maschine hat 6 vCPU, 23,5 GiB RAM und 200 GB SSD.
Damit laufen zwei bis drei Spielserver gleichzeitig bequem.

> *Requirements: Debian 12 with root, a public IPv4 with a DNS name pointing at
> it, a reachable Borg target (ideally over a private network such as
> Tailscale), and a scoped Cloudflare token. For scale: the documented machine
> has 6 vCPU, 23.5 GiB RAM and a 200 GB SSD, which comfortably runs two to three
> game servers at once.*
