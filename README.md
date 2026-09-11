# Platzwart

*Der Platzwart bespielt den Platz nicht — er hält ihn instand.*

Vollständiger Bausatz für einen selbst gehosteten **Spieleserver mit Weboberfläche**:
Docker-Serverstacks, ein Panel mit Zwei-Faktor-Anmeldung, Rollen und Passkeys,
ein Katalog von 179 installierbaren Spielen, Sicherung nach Borg mit
Großvater-Vater-Sohn, Steam-Workshop und Mod-Upload, Kanäle auf TeamSpeak und
Discord je Spielserver, Meldungen nach Discord, eine öffentliche Statusseite und
automatisch gepflegte DNS-Namen.

Dieses Repositorium beschreibt **den Ist-Zustand einer laufenden Maschine** und
enthält alles, um sie von einem leeren Debian 12 aus neu aufzubauen. Alle
standortbezogenen Angaben — Domains, Adressen, Netze, Passwörter — sind durch
`@@PLATZHALTER@@` ersetzt und stehen in einer einzigen, nicht eingecheckten
Datei.

> *Complete kit for a self-hosted **game server with a web panel**: Docker
> service stacks, a panel with two-factor login, roles and passkeys,
> a catalogue of 179 installable games, Borg backups on a grandfather-father-son rotation,
> Steam Workshop and mod upload, TeamSpeak and Discord channels per game server,
> notifications to Discord, a public status page, and automatically maintained
> DNS records. This repository documents the actual state of a running machine
> and contains everything needed to rebuild it from a bare Debian 12. Every
> site-specific value — domains, addresses, networks, passwords — is replaced by
> an `@@PLACEHOLDER@@` and lives in a single file that is never committed.*

---

## Was hier läuft

| Bestandteil | Umsetzung |
|---|---|
| Betriebssystem | Debian 12 (bookworm), KVM-Gast |
| Container | Docker CE mit `compose`-Plugin, ein Stack je Spiel unter `/opt/stacks/<name>/` |
| Spieldaten | Bind-Mounts unter `/srv/games/<name>/`, Dienste unter `/srv/dienste/<name>/`, alles unter UID/GID **4711** |
| Weboberfläche | FastAPI/uvicorn auf `127.0.0.1:8099`, Benutzer `panel`, ohne Docker-Zugriff, ohne JavaScript (außer für Passkeys) |
| Webterminal | `ttyd` auf `127.0.0.1:7681`, vorgeschaltete Prüfung der Panel-Sitzung durch Caddy |
| HTTPS | Caddy, Zertifikat automatisch über `http-01` oder `dns-01`, nur HTTP/1.1 |
| Rechteübergang | genau ein `sudo`-Eintrag: `panel` darf `panel-aktion` aufrufen, sonst nichts |
| Sicherung | Borg über Tailscale, alle 15 min inkrementell, täglich vollständig — mit `BORG_REPO=aus` abschaltbar |
| DNS | Cloudflare (Hetzner vorbereitet), ein CNAME je Spiel auf einen einzigen A-Eintrag, bei wechselnder Adresse selbst nachgeführt |
| Firewall | ufw (alles zu) + fail2ban; Spielports macht Docker selbst auf |
| Zeitgeber | systemd-Timer für Sicherung, Einrichtung, Wache, Spielerzahlen, Verlauf, Statusseite, Leerlauf, Kanäle, Auto-Update, DNS und Palworld |

> *What runs here: Debian 12 on KVM; Docker CE with one compose stack per game;
> game data bind-mounted under `/srv/games/` as UID/GID 4711; a FastAPI panel on
> localhost with no Docker access and no JavaScript except for passkeys; a ttyd
> web terminal gated by Caddy against the panel session; automatic HTTPS via
> `http-01` or `dns-01`; exactly one sudo rule as the privilege boundary; Borg
> backups over Tailscale; one CNAME per game on a single A record, updated by
> the server itself when the address changes; ufw plus fail2ban, with game ports
> opened by Docker itself; and systemd timers doing the recurring work.*

---

## Was es kann

### Spielserver

* **179 Spiele mit einem Klick installieren** — aus einem Katalog, nie aus einem
  Formular: Die Oberfläche übergibt nur einen Schlüssel. Suche, acht
  Kategorien, Buchstabenleiste; Titelbilder von Steam oder selbst gezeichnet.
* **Kein Server geht ohne Beitrittspasswort ans Netz.** Passwort und
  Spielerzahl setzt ein Timer in die Konfiguration, die der erste Start
  schreibt; der Spielport wird erst danach veröffentlicht — bei Startparametern
  erst, wenn der laufende Server per A2S „Passwort nötig" meldet. Spiele ohne
  Passwort (Minecraft, TeamSpeak) gibt ein Mensch von Hand frei.
* **Starten, anhalten, neu starten**, einzeln oder gesammelt („alle laufenden
  anhalten", „zuletzt laufende starten"); Neustart der ganzen Maschine, nach dem
  genau die Server zurückkommen, die vorher liefen.
* **Einstellungen je Server:** alle Umgebungsvariablen (gefährliche gesperrt,
  jede Änderung gegen das von Docker erzeugte Gerüst geprüft), die
  Konfigurationsdateien des Spiels als Felder oder Rohtext, Speichergrenze,
  Serverprotokoll, Minecraft-Whitelist.
* **Aktualisieren** auf Knopfdruck oder nachts automatisch — immer erst nach
  einer Sicherung, nur wenn gerade niemand spielt.
* **Leerlauf:** Leere Server legen sich schlafen und wachen beim ersten Paket
  eines Mitspielers wieder auf; systemd hält derweil die Ports.
* **Spielerzahlen** per A2S, wo der Server antwortet, sonst der Netzverkehr;
  dazu ein Speicherverlauf der letzten 24 Stunden auf jeder Karte.

> *Game servers: 179 games installable with one click from a catalogue, never a
> form — the panel passes a key only — with search, eight categories, a letter
> bar and artwork from Steam or self-drawn. No server goes online without a join
> password: a timer writes password and player count into the config the first
> start creates, and the game port is published only afterwards; for
> start-parameter passwords only once the running server reports "password
> required" via A2S, and games without a password (Minecraft, TeamSpeak) are
> released by a human. Start, stop and restart singly or all at once, and a
> machine reboot after which exactly the previously running servers return.
> Per-server settings: every environment variable (dangerous ones locked, every
> change checked against Docker's rendered result), the game's config files as
> fields or raw text, memory limit, server log, Minecraft whitelist. Updates on
> demand or nightly, always after a backup and only when nobody is playing. Idle
> sleep with wake on the first packet, systemd holding the ports meanwhile.
> Player counts via A2S where the server answers, traffic otherwise, plus a
> 24-hour memory history on every card.*

### Mods

* **Steam-Workshop** für Project Zomboid, Unturned, Don't Starve Together und
  Killing Floor 2: Link, ID oder Sammlung einfügen oder im Panel suchen; jede ID
  wird bei Steam geprüft und muss zu genau diesem Spiel gehören. Die Server
  laden selbst.
* **Mod-Upload** (Administratoren) für FOUNDRY und Valheim (über BepInEx) —
  jeder Archiveintrag vor dem Entpacken geprüft, gegen Zip Slip.

> *Mods: Steam Workshop for Project Zomboid, Unturned, Don't Starve Together
> and Killing Floor 2 — paste a link, id or collection or search in the panel;
> every id is checked at Steam and must belong to exactly this game, and the
> servers download themselves. Mod upload (administrators) for FOUNDRY and
> Valheim (through BepInEx), every archive entry checked before extraction,
> against Zip Slip.*

### Sicherung

* Ein Borg-Archiv **je Spiel**, alle 15 Minuten für laufende Server, täglich
  alles samt compose-Dateien, `/etc` und den Panel-Daten.
* **Drei Prüfungen nach jedem Archiv:** zu klein, eingebrochen, seit 24 Stunden
  nichts Neues — ein Netz, das sich heil meldet und nichts fängt, fällt auf.
* **Zurückspielen** über das Panel, mit Kopie des Ist-Stands vorher, bei
  laufendem Server vorbereitet; **herunterladen** als tar-Strom; **probeweise
  zurückspielen**, ohne den Server anzufassen.
* **Wiederaufbau einer verlorenen Maschine**, geführt: `install/assistent.sh`
  holt Konfiguration, Benutzer samt zweiten Faktoren und jeden Spielstand auf
  eine frische Maschine zurück ([docs/11](docs/11-neueinrichtung.md#9-wiederaufbau-aus-der-sicherung)).

> *Backup: one Borg archive per game, every 15 minutes for running servers,
> daily everything including compose files, `/etc` and the panel data. Three
> checks after every archive — too small, collapsed, nothing new for 24 hours —
> so a safety net that reports itself intact while catching nothing is noticed.
> Restore through the panel with a copy of the current state taken first and the
> extraction prepared while the server still runs; download as a tar stream;
> test restores that never touch the server. Rebuilding a lost machine is
> guided: `install/assistent.sh` brings configuration, users with their second
> factors and every save back onto a fresh machine.*

### Gemeinschaft

* **Kanäle je Spielserver** auf TeamSpeak und Discord (Text und Sprache),
  angelegt beim Installieren, gelöscht beim Entfernen — aber nur, wenn niemand
  sie angefasst hat.
* **Meldungen nach Discord** in zwei Kanäle: Störungen (Absturz,
  Neustartschleife, Sicherung, Platte, Speicher, fehlgeschlagener Dienst) und
  Mitteilungen (Update eingespielt, Entwarnung) — gemeldet werden Änderungen,
  nicht Zustände.
* **Öffentliche Statusseite** `/status`: welcher Server läuft, wie man beitritt,
  wie viele drauf sind — ohne Anmeldung und ohne das Panel je zu erreichen.

> *Community: channels per game server on TeamSpeak and Discord (text and
> voice), created on install and deleted on removal — but only if nobody touched
> them. Discord notifications in two channels: faults (crash, restart loop,
> backup, disk, memory, failed unit) and notices (update applied, all-clear);
> changes are reported, not states. A public status page `/status`: which server
> runs, how to join, how many are on — without a login and without ever reaching
> the panel.*

### Zugang

* **Anmeldung mit Passwort (Argon2id) und zweitem Faktor:** TOTP, Passkey oder
  einer von zehn Wiederherstellungscodes. Benutzernamen ohne Groß- und
  Kleinschreibung.
* **Drei Rollen:** `bedienen` (starten, anhalten), `verwalten` (alles rund um die
  Spiele), `admin` (dazu Benutzer, Protokoll, Terminal, Integrationen,
  Maschinenneustart).
* **Protokoll** jeder schreibenden Aktion und jeder Anmeldung, ohne Passwörter.
* **Als App installierbar** auf dem Telefon, dort mit Fingerabdruck statt Code.

> *Access: login with a password (Argon2id) and a second factor — TOTP, a
> passkey or one of ten recovery codes; user names are case-insensitive. Three
> roles: `bedienen` (start, stop), `verwalten` (everything about the games),
> `admin` (plus users, audit log, terminal, integrations, machine reboot). An
> audit log of every writing action and every login, without passwords.
> Installable as a phone app, with a fingerprint instead of a code.*

---

## Schnellstart

**Geführt** — der Assistent fragt alles ab, prüft Zugänge und richtet erst nach
Bestätigung ein; die ganze Anleitung von der leeren Maschine an steht in
**[docs/11-neueinrichtung.md](docs/11-neueinrichtung.md)**:

```bash
git clone https://github.com/Sparxx947/gameserver.git /root/platzwart && cd /root/platzwart
sudo install/assistent.sh            # Neueinrichtung, Wiederaufbau oder nur Konfiguration
```

> *Guided: the assistant asks for everything, checks access and sets up only
> after confirmation; the full guide from an empty machine is
> docs/11-neueinrichtung.md.*

**Von Hand:**

```bash
git clone <dieses-repo> gameserver && cd gameserver
cp konfiguration.env.beispiel konfiguration.env
$EDITOR konfiguration.env            # Domains, Adressen, Netze eintragen
sudo sh -c "printf 'ANBIETER=cloudflare\nTOKEN=%s\n' '<tok>' > /etc/dns-gameserver.conf"
sudo chmod 600 /etc/dns-gameserver.conf          # optional, aber dann macht 25 das DNS
sudo install/einrichten.sh           # Stufen 10–50
sudo install/60-spiele.sh teamspeak enshrouded palworld
sudo install/70-dns.sh               # optional, braucht ein Cloudflare-Token
```

Die Erstanmeldung des Panels wird **einmal** am Ende von Stufe 30 ausgegeben.
Der zweite Faktor wird beim ersten Anmelden im Browser als QR-Code eingerichtet;
danach zeigt das Panel einmalig zehn Wiederherstellungscodes.

> *Quick start: clone, copy `konfiguration.env.beispiel` to `konfiguration.env`,
> fill in domains and addresses, optionally place the DNS token, then run
> `install/einrichten.sh` and set up the hand-maintained stacks you want. The
> initial panel login is printed **once** at the end of stage 30; the second
> factor is enrolled as a QR code on first login, after which the panel shows
> ten recovery codes once.*

Ausführlich: **[docs/02-installation.md](docs/02-installation.md)**.

---

## Aufbau des Repositoriums

```
bin/          Werkzeuge nach /usr/local/bin, jedes in docs/09-referenz.md
etc/          Konfigurationsdateien nach /etc: Katalog, Mods, Workshop, Adressen,
              Caddy, fail2ban, sshd, sudoers, Vorlagen für die Geheimnisdateien
systemd/      Dienste und Zeitpläne nach /etc/systemd/system
panel/        Die Weboberfläche (app.py, Abhängigkeiten, Symbole, passkey.js)
stacks/       compose-Vorlagen der sechs handgepflegten Server
install/      Einrichtung in Stufen, jede einzeln aufrufbar; assistent.sh führt hindurch
werkzeuge/    Abgleich Repo ↔ Server, Ausrollen, Rückbau, Aufräumen,
              Vollständigkeit, Katalog-Generatoren, Titelbilder
docs/         Diese Dokumentation
```

> *Repository layout: tools for `/usr/local/bin` (each documented in the
> reference chapter), `/etc` files including the catalogue and the templates for
> secret files, systemd units, the panel itself, compose templates for the six
> hand-maintained servers, staged installation scripts, workstation tools for
> comparing, deploying, tearing down and generating, and this documentation.*

### Bleibt das Repositorium ehrlich?

```bash
werkzeuge/abgleich.sh gameserver
```

Setzt die Platzhalter aus `konfiguration.env` ein und vergleicht das Ergebnis
mit der laufenden Maschine: **jede Datei, die `install/` ausrollt**, byte-genau,
dazu die Python-Umgebung des Panels gegen `requirements.txt`, die ttyd-Version
gegen die in Stufe 40 festgeschriebene, die selbst erzeugten Symbole und
Titelbilder, die Vollständigkeit der Katalogbilder, ob die Sicherungs-Timer
wirklich laufen und den Fassungsstempel. Keine Zahl hier: Die Liste wächst mit
jedem Werkzeug, und eine Zahl in der Doku altert lautlos — der Lauf nennt sie
selbst. Exit 0 = deckungsgleich, 1 = Abweichungen (mit Diff), 2 = nicht
erreichbar. Ändert nichts.

Eine Dokumentation, die vom System abweicht, ist schlimmer als keine — man
handelt danach. Dieses Werkzeug findet die Abweichung, statt darauf zu hoffen,
dass jemand sie bemerkt.

> *Does the repository still match reality? `werkzeuge/abgleich.sh <ssh-target>`
> substitutes the placeholders and compares every file `install/` deploys, byte
> for byte, plus the panel's Python environment, the ttyd version, the self-made
> icons and artwork, the completeness of the catalogue artwork, whether the
> backup timers actually run, and the version stamp. No number here: the list
> grows with every tool and a number in the docs ages silently — the run prints
> it. Exit 0 means identical, 1 means drift (with a diff), 2 means unreachable;
> it changes nothing. Documentation that has drifted is worse than none, because
> people act on it — this finds the drift instead of hoping someone notices.*

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

### Einzelne Dateien ausrollen

```bash
werkzeuge/ausrollen.sh gameserver bin/panel-aktion panel/app.py
```

Setzt die Platzhalter ein, sichert die Zieldatei nach `.vor-<datum>` und
ersetzt atomar. Bricht ab, wenn ein Platzhalter übrig bleibt. Caddyfile,
sshd-Härtung und sudoers-Regel werden danach vom jeweiligen Dienst geprüft und
bei Ablehnung zurückgerollt; nach dem Katalog oder der Ausschlussliste läuft
der Katalog-Abgleich der installierten Server. Nie `scp` — die Platzhalter gingen mit.

> *Deploys single files with placeholders substituted, backing up the target and
> replacing atomically; aborts on a left-over placeholder. Caddyfile, sshd
> hardening and the sudoers rule are validated by their service afterwards and
> rolled back if refused; after the catalogue or the exclusion list, installed
> servers are aligned with the catalogue. Never scp — the placeholders would travel along.*

### Wieder abbauen

```bash
werkzeuge/rueckbau.sh gameserver              # zeigt nur den Plan
werkzeuge/rueckbau.sh gameserver --wirklich   # führt ihn aus
```

Das Gegenstück zur Einrichtung. Ohne `--wirklich` ändert es nichts. Spielstände
und Systembenutzer bleiben stehen, solange man sie nicht ausdrücklich mit
`--mit-spielstaenden` und `--mit-benutzern` dazunimmt; das Borg-Repositorium und
seine Passphrase werden **nie** angefasst.

Die Listen der systemd-Einheiten und Werkzeuge entstehen aus dem Repositorium
selbst. Die frühere Anleitung zum Abtippen war abgedriftet — sie löschte keine
einzige Unit-Datei — und wer sie befolgte, hielt die Maschine danach für sauber.

> *Teardown is the counterpart to the installer and changes nothing without
> `--wirklich`. Save games and system users stay unless explicitly included, and
> the Borg repository and its passphrase are never touched. The unit and tool
> lists come from the repository itself: the earlier hand-typed instructions had
> drifted and removed no unit file at all, leaving people believing the machine
> was clean.*

### Alte Kopien wegräumen

```bash
werkzeuge/aufraeumen.sh gameserver              # zeigt nur den Plan
werkzeuge/aufraeumen.sh gameserver --wirklich
```

Vor jedem Überschreiben entsteht eine `.vor-<datum>`-Kopie — das ist der
Rückweg, aber er wächst. Behalten werden je Datei die drei jüngsten, gelöscht
nur, was älter als 14 Tage ist. Die vollen Verzeichniskopien vor einem
Zurückspielen (Gigabytes) hängen an `--mit-restore-kopien`.

> *Every overwrite leaves a `.vor-<date>` copy: that is the way back, and it
> grows. The tool keeps the three newest per file and deletes only what is older
> than 14 days; the multi-gigabyte pre-restore directory copies need their own
> flag.*

### Ist das Repositorium vollständig?

```bash
werkzeuge/vollstaendigkeit.sh
```

Prüft in einem Lauf: Ist jede von `install/` angefasste Datei vorhanden **und von
git verfolgt**? Sind alle Skripte syntaktisch heil? Steckt irgendwo ein
Geheimnis? Ist jeder `@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt?
Halten die Katalogports die Sicherheitsregeln ein, hat jedes Katalogspiel eine
Kategorie und ein Titelbild, stimmt die Doku mit Katalog und Routen überein, und
hat jeder Doku-Abschnitt seinen englischen Absatz?

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
> all scripts parse, whether any secret slipped in, whether every
> `@@PLACEHOLDER@@` is documented, whether the catalogue ports follow the
> security rules, whether every catalogue game has a category and artwork,
> whether the docs match catalogue and routes, and whether every documentation
> section has its English paragraph. It exists because of a real find: a
> `.gitignore` rule of `*.local` swallowed `etc/fail2ban/jail.local`, which stage
> 10 requires — the push was green and it would only have surfaced at the next
> fresh install. Wire it in as a pre-commit gate with the symlink above —
> deliberately not via `core.hooksPath`, which replaces the whole hooks directory
> and would disable any hook already present; bypass with
> `GAMESERVER_KEIN_GATE=1`.*

---

## Dokumentation

**Wer hier mitentwickelt, liest zuerst [CLAUDE.md](CLAUDE.md)** — Arbeitsweise,
die fünf nicht verhandelbaren Sicherheitsgrenzen und die Fallstricke, die schon
Zeit gekostet haben. Eine lesbare Einführung für Betreiber und Mitspieler steht
im [Wiki](../../wiki); maßgeblich bleibt diese
Dokumentation hier.

> *Anyone contributing should start with [CLAUDE.md](CLAUDE.md): working
> practices, the five non-negotiable security boundaries, and the traps that
> have already cost time. A readable introduction for operators and players
> lives in the wiki; this documentation remains authoritative.*

| Kapitel | Inhalt |
|---|---|
| [01 Architektur](docs/01-architektur.md) | Wie die Teile zusammenhängen, Datenflüsse, Verzeichnisse, alle Dienste |
| [02 Installation](docs/02-installation.md) | Von der leeren Maschine zum laufenden Panel |
| [03 Panel](docs/03-panel.md) | Bedienung, Rollen, jede Seite, alle Routen, Datenhaltung |
| [04 Spielekatalog](docs/04-spielekatalog.md) | Wie Installation, Passwort-Einrichtung und Deinstallation funktionieren, Katalog erweitern |
| [05 Sicherung](docs/05-sicherung.md) | Borg, Aufbewahrung, Prüfungen, Wiederherstellung, Probe |
| [06 Netz, DNS, Firewall](docs/06-netz-dns-firewall.md) | Ports, Docker und ufw, SSH, Zertifikat, DNS-Anbieter |
| [07 Sicherheitsentwurf](docs/07-sicherheitsentwurf.md) | Wo die Grenzen verlaufen und warum |
| [08 Betrieb und Störungen](docs/08-betrieb-und-stoerungen.md) | Alltag, Meldungen, Fehlerbilder, bekannte Fallen |
| [09 Referenz](docs/09-referenz.md) | Jedes Werkzeug, jede Unit, jede Datei, jeder Schalter |
| [10 Entscheidungen](docs/10-entscheidungen.md) | Warum es so ist und nicht anders |
| [11 Neueinrichtung](docs/11-neueinrichtung.md) | Von nichts zum laufenden Server: Maschine, Domain, Sicherung, der Assistent, Wiederaufbau |
| [ABNAHME](ABNAHME.md) | Prüfliste für einen Neuaufbau auf einer frischen Maschine |

---

## Was hier bewusst **nicht** drin steht

* **Keine Geheimnisse.** Panel-Hash, TOTP-Geheimnis, Sitzungs-Secret,
  Borg-Passphrase, Cloudflare-Token, Webhook-URLs, Bot-Token und alle
  Spiel-Passwörter entstehen bei der Einrichtung auf der Zielmaschine und werden
  nie eingecheckt.
* **Keine Standortdaten.** Domains, IP-Adressen, Netze und der Benutzername
  stehen ausschließlich in `konfiguration.env`.
* **Keine Bilder aus Steam.** Die Kopfgrafiken der Spiele sind Werke Dritter;
  sie werden zur Laufzeit geladen und liegen deshalb nicht im Repositorium.
  Enthalten sind nur die selbst erzeugten Symbole (`favicon.svg`, `favicon.ico`,
  `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`) und die selbst
  gezeichneten Titelbilder für Spiele ohne Steam-Eintrag.
* **Keine Spielstände.** Die gehören in die Sicherung, nicht in die Versionsverwaltung.

> *Deliberately absent: any secret (all are generated on the target machine,
> including webhook URLs and bot tokens), any site-specific value (they live in
> `konfiguration.env` only), Steam artwork (third-party works, fetched at runtime
> — only the self-made icons and self-drawn artwork are included), and save games
> (those belong in the backup, not in version control).*

---

## Voraussetzungen

* Debian 12 (bookworm) mit root-Zugang
* Eine öffentliche IPv4 und ein DNS-Name, der darauf zeigt (für das Zertifikat)
  — oder `dns-01`, dann braucht es keinen eingehenden Port
* Für die Sicherung: ein erreichbares Borg-Ziel, empfohlen über ein privates
  Netz wie Tailscale — oder `BORG_REPO=aus`, dann wird nicht gesichert
* Für DNS: ein Cloudflare-Token mit `Zone / DNS / Bearbeiten`, begrenzt auf die
  eigene Zone
* Für Kanäle und Meldungen (optional): ein TeamSpeak-ServerQuery-Zugang, ein
  Discord-Bot mit „Kanäle verwalten", zwei Discord-Webhooks; für die
  Workshop-Suche ein Steam-Web-API-Schlüssel

Als Anhalt: Die dokumentierte Maschine hat 6 vCPU, 23,5 GiB RAM und 200 GB SSD.
Darauf laufen sieben Server gleichzeitig; die Summe ihrer Speichergrenzen liegt
mit Absicht über dem RAM, und die Wache meldet, wenn es eng wird.

> *Requirements: Debian 12 with root, a public IPv4 with a DNS name pointing at
> it (or `dns-01`, which needs no inbound port), a reachable Borg target (ideally
> over a private network such as Tailscale), and a scoped Cloudflare token.
> Optional for channels and notifications: a TeamSpeak ServerQuery login, a
> Discord bot allowed to manage channels and two webhooks; a Steam Web API key
> for the Workshop search. For scale: the documented machine has 6 vCPU, 23.5
> GiB RAM and a 200 GB SSD and runs seven servers at once; their memory limits
> deliberately add up to more than the RAM, and the watchdog reports when it gets
> tight.*

---

## Lizenz

**MIT** — siehe [`LICENSE`](LICENSE). Benutzen, ändern, weitergeben, auch
gewerblich; einzige Bedingung ist, dass der Lizenztext mitgeht. Ohne
Gewährleistung: Das hier beschreibt eine Maschine, die jemand betreibt, und
niemand haftet dafür, was sie auf einer anderen tut.

MIT und nicht etwas anderes hat einen Grund aus diesem Repositorium: 85 der
179 Katalogeinträge sind aus **[LinuxGSM](https://github.com/GameServerManagers/LinuxGSM)**
abgeleitet, und LinuxGSM steht ebenfalls unter MIT. Dieselbe Lizenz heißt,
dass niemand je eine Verträglichkeitsfrage klären muss. Was von dort stammt
und was hier entstanden ist, steht einzeln in [`NOTICE`](NOTICE).

> *MIT (see `LICENSE`): use, modify and redistribute, commercially too, as long
> as the licence text travels along, and without warranty — this describes a
> machine somebody runs, and nobody is liable for what it does on a different
> one. MIT rather than something else for a reason that comes from this
> repository: 85 of the 179 catalogue entries derive from LinuxGSM, which is
> MIT as well, so nobody ever has to work out compatibility. `NOTICE` lists
> item by item what came from there and what originated here.*
