# 08 — Betrieb und Störungen

## Der Alltag in fünf Befehlen

```bash
systemctl is-active panel caddy ttyd docker fail2ban tailscaled
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung|platzwart|spieler|kanal|autoupdate'
journalctl -u panel -n 50 --no-pager
df -h / && free -h
```

Dazu, wenn etwas unklar ist: `platzwart-wache --trocken` (was gerade nicht
stimmt, ohne zu melden), `systemctl --failed` und die Seite **Protokoll** im
Panel. Meist ist all das unnötig — Störungen melden sich von selbst in
`#platzwart-stoerung` (siehe unten).

> *Everyday health check: services active, containers up, timers scheduled,
> recent panel log, disk and memory. When something is unclear, add
> `platzwart-wache --trocken` (what is wrong right now, without reporting),
> `systemctl --failed` and the panel's audit log. Mostly none of this is needed —
> faults report themselves in the faults channel.*

---

## Speicher: die Grenzen sind überbucht

Die Summe aller `mem_limit` übersteigt den vorhandenen Arbeitsspeicher deutlich.
Das ist **beabsichtigt**. Getragen hat es bisher ein Satz, der hier stand:
*„solange nicht alle Server gleichzeitig laufen"*.

**Dieser Satz gilt nicht mehr.** Am 2026-09-10 nachgemessen: alle sieben laufen
gleichzeitig. Die Voraussetzung, auf der der Entwurf ruht, hat lautlos aufgehört
zu stimmen — sie wurde von nichts geprüft, also hat es niemand bemerkt.

Stand vom 2026-09-10, am 2026-09-11 unverändert nachgemessen, Maschine mit
**23 GiB** RAM:

| Container | Grenze | Herkunft |
|---|---|---|
| palworld | 12 G | `stacks/` |
| satisfactory | 10 G | `stacks/` |
| windrose | 8 G | `stacks/` |
| enshrouded | 6 G | `stacks/` |
| foundry | 6 G | `stacks/` |
| valheim | 4 G | Katalog |
| teamspeak | 1 G | `stacks/` |
| **Summe** | **47 G** | |

Was dabei zu wissen ist: Der Kernel gibt nur her, was da ist. Wird es eng, greift
**nicht** die saubere Container-Grenze, sondern der OOM-Killer der Maschine — und
der trifft nicht unbedingt den Schuldigen. So endete am 2026-09-09 Palworld mit
Exit 137, als StarRupture beim Hochfahren den Speicher füllte (StarRupture ist
seither entfernt, siehe unten).

Vor dem Start prüfen:

```bash
free -m | awk '/^Mem/ {print "frei:", $7 "M"}'
docker inspect -f '{{.Name}} {{.HostConfig.Memory}}' $(docker ps -q)
```

> *The sum of all memory limits clearly exceeds the machine's RAM, on purpose.
> What carried that was a sentence in this section, "as long as not all servers
> run at once" — and that sentence no longer holds: measured on 2026-09-10 (and
> unchanged on 2026-09-11), all seven run at once, 47 G of limits on a 23 GiB
> machine. The premise quietly stopped being true, and nobody noticed because
> nothing checked it. When memory runs short, it is not the clean per-container
> limit that applies but the host's OOM killer, which does not necessarily hit
> the culprit — that is how Palworld ended with exit 137 on 2026-09-09 while
> StarRupture filled the memory during boot. Check free memory and the limits
> before starting a server by hand.*

### Wer die Überbuchung bewacht — und wer nicht

`spiel-verwalten` prüft den freien Speicher vor einer **Katalog-Installation**
und startet nicht, wenn er zum `mem_limit` nicht reicht. Das ist eine Tür von
zweien: Die sechs Server aus `stacks/` haben keine `panel.json`, kommen nie an
dieser Prüfung vorbei — und stellen mit 43 der 47 G fast alles.

Die zweite Tür ist seit dem 2026-09-10 `platzwart-wache`. Sie misst alle fünf
Minuten den **tatsächlich belegten** Speicher und meldet ab 85 % nach
`#platzwart-stoerung`, mit der Entwarnung, wenn es sich wieder entspannt
(Schwelle: `WACHE_SPEICHER_WARN`). Gemessen wird über `docker ps`, nicht über den
Katalog — sonst fehlten genau die sechs, um die es geht.

**Gemessen wird der belegte Speicher, nicht die Summe der Grenzen.** Die Summe
liegt dauerhaft und mit Absicht über dem RAM; ein Alarm darauf stünde an jedem
einzelnen Tag im Kanal und wäre nach einer Woche stummgeschaltet. Die Summe steht
stattdessen **im Meldungstext**: Sie beantwortet die Frage, die man sich in
diesem Moment stellt — wie viel dürften die laufenden Server noch nehmen?

> *Who guards the oversubscription, and who does not: `spiel-verwalten` checks
> free memory before a catalogue installation and does not start when it does
> not cover the limit. That is one door of two — the six servers from `stacks/`
> have no `panel.json`, never pass it, and account for 43 of the 47 G. The
> second door, since 2026-09-10, is `platzwart-wache`: every five minutes it
> measures actually used memory and reports above 85 % to the faults channel,
> with an all-clear when it eases (`WACHE_SPEICHER_WARN`); it reads the limits
> from `docker ps`, not the catalogue, or exactly those six would be missing. It
> measures used memory, not the sum of limits, which permanently exceeds RAM by
> design — alarming on it would fill the channel every day and be muted within a
> week; the sum goes into the message text instead, answering the question one
> asks at that moment.*

### Was offen bleibt

Ob die Grenzen selbst richtig sind, ist damit **nicht** beantwortet. Dafür
bräuchte man, was jeder Server unter Last tatsächlich als Spitze zieht, nicht im
Leerlauf — `platzwart-verlauf` schreibt das seit Kurzem mit. Eine Grenze zu tief
macht aus einem vollen Abend einen Kill, eine zu hoch einen OOM, der einen
*anderen* Server trifft. Zahlen ohne diese Messung zu ändern hieße, eine
Vermutung durch die nächste zu ersetzen.

> *What remains open is whether the limits themselves are right. That needs each
> server's real peak under load, not at idle — `platzwart-verlauf` records it
> since 2026-09-10. A limit set too low turns a busy evening into a kill; one set
> too high turns it into an OOM that hits a different server. Changing the
> numbers without that measurement would only swap one guess for another.*

---

## Was sich von selbst meldet

Bis zum 2026-09-10 meldete sich **nichts**. Die Ereignisse gab es alle, sie
standen im Journal und warteten darauf, dass jemand nachsieht — der einzige
Melder war eine Prüfung, die montags 10:00 auf einem Desktop lief. Ein Server,
der Samstagnacht um drei stirbt, fiel damit am Montag auf.

Geschickt wird nach Discord, über zwei Webhooks:

| Kanal | Was dort landet |
|---|---|
| `#platzwart-stoerung` | Server abgestürzt, **Server in der Neustartschleife**, **Server meldet sich als ungesund**, **Dienst fehlgeschlagen** (Sicherung, Einrichtung, Wache …), Sicherung fehlgeschlagen, Sicherungsinhalt unplausibel (zu klein, eingebrochen, seit 24 h unverändert), Platte knapp, Arbeitsspeicher knapp, Einrichtung nicht abgeschlossen, Update fehlgeschlagen, Leerlauf (läuft ohne Ports, ließ sich nicht wecken oder schlafen legen, wird ständig geweckt), Kanäle (kein Zugriff, Abgleich gescheitert, Kanal nicht gelöscht) |
| `#platzwart-meldungen` | Update wirklich eingespielt, Server geweckt, Entwarnung nach einer Störung |

**Zwei Kanäle, mit Absicht.** Ein Kanal, in dem täglich „Update geprüft, nichts
Neues" steht, wird nach einer Woche stummgeschaltet — und dann fällt auch die
Störung nicht mehr auf.

Die Namen der Kanäle sind die Vorschläge der Vorlage; maßgeblich ist, wohin die
beiden Webhooks in `/etc/platzwart-melden.conf` zeigen. Diese Meldekanäle sind
etwas anderes als die Kanäle je Spielserver, die `kanal-verwalten` pflegt.

> *What reports itself: until 2026-09-10 nothing did — the events all existed in
> the journal, waiting for somebody to look, and the only reporter was a check
> running Mondays at 10:00 on a desktop, so a server dying on Saturday night
> surfaced on Monday. Reports go to Discord through two webhooks: the faults
> channel gets crashes, restart loops, failing health checks, failed units,
> failed or implausible backups, low disk or memory, unfinished setups, failed
> updates, idle-sleep problems and channel problems; the notices channel gets
> applied updates, wake-ups and all-clears. Two channels on purpose: one carrying
> "checked, nothing new" daily gets muted within a week, and the outage stops
> being noticed with it. The channel names are the template's suggestion; what
> counts is where the two webhooks point. These notification channels are
> something other than the per-server channels `kanal-verwalten` maintains.*

### Ein laufender Container ist kein laufender Server

Bis zum 2026-09-10 sah die Wache ausschließlich nach Containern im Zustand
`exited`. Das findet genau die Fälle **nicht**, in denen ein Server tot ist, der
Container aber lebt:

| Lage | Was `docker ps` sagt | Was `--filter status=exited` findet |
|---|---|---|
| Neustartschleife | `Restarting (1) 4 seconds ago` | nichts |
| Gesundheitstest schlägt fehl | `Up 37 minutes (unhealthy)` | nichts |

Beim ersten Aufbau auf einer frischen Maschine gemessen: Ein Spielserver lief
zwanzig Minuten in der Schleife, ein zweiter war sechsunddreißig Minuten
`unhealthy` — die Wache meldete keinen von beiden.

Sie prüft deshalb zusätzlich `docker inspect`. Bei der Schleife müssen **zwei**
Bedingungen zusammenkommen:

* mindestens `WACHE_NEUSTART_WARN` Neustarts (Vorgabe 3) — und
* der Container startet **gerade** neu oder ist erst seit weniger als
  `WACHE_FRISCH_MIN` Minuten (Vorgabe 10) oben.

Die zweite Bedingung ist nicht Zierat: `RestartCount` fällt nie wieder. Ohne sie
stünde ein Container, der vorletzte Woche fünfmal abstürzte und seither
durchläuft, dauerhaft als Störung im Kanal — und ein Alarm, der nie endet, wird
stummgeschaltet. Beruhigt er sich, wächst die Laufzeit über die Frist und die
Entwarnung geht von selbst hinaus.

`RestartCount` zählt nur, was die Neustartregel ausgelöst hat. Ein `docker
restart` von Hand erhöht ihn **nicht** — der Zähler beschreibt Abstürze, nicht
Bedienung.

> *Until 2026-09-10 the watchdog only looked for containers in state `exited`,
> which finds neither of the two cases where the server is dead but the container
> is alive: a restart loop shows as `Restarting`, and a failing health check
> shows as `Up (unhealthy)`. Measured on a first install: one server looped for
> twenty minutes, another was unhealthy for thirty-six, and neither was
> reported. It now also reads `docker inspect`. A restart loop needs two
> conditions together — at least `WACHE_NEUSTART_WARN` restarts (default 3)
> **and** the container is restarting right now or has been up for less than
> `WACHE_FRISCH_MIN` minutes (default 10). The second is not decoration:
> `RestartCount` never falls, so without it a container that crashed a fortnight
> ago would sit in the channel forever, and an alarm that never ends gets muted.
> Once it settles, uptime grows past the window and the all-clear goes out by
> itself. `RestartCount` counts only policy restarts — a manual `docker restart`
> does not raise it.*

### Die drei Regeln, an denen das hängt

**Gemeldet werden Änderungen, nicht Zustände.** `platzwart-wache` läuft alle fünf
Minuten und vergleicht die Lage mit der des letzten Laufs: neu dazugekommen ist
eine Störung, weggefallen eine Entwarnung, unverändert ist Schweigen. Ein Timer,
der jedes Mal dieselbe Störung schickt, ist nach einem Tag 288-mal dasselbe.

**Die Entwarnung gehört dazu.** Ein Alarm, dessen Ende man nicht sieht, wird zum
Dauerzustand — man weiß nie, ob das Problem noch besteht.

**Der Meldungstext trägt keinen Zeitstempel.** `platzwart-melden` unterdrückt
Wiederholungen über einen Abgleich des Textes. Die Sicherung läuft alle 15
Minuten; stünde die Uhrzeit in der Meldung, wäre jeder Lauf ein neuer Text und
die Sperre wirkungslos.

> *Three rules carry it. Changes are reported, not states: `platzwart-wache`
> runs every five minutes and compares with the previous run — newly appeared is
> a fault, disappeared an all-clear, unchanged is silence; a timer sending the
> same fault every time is the same message 288 times after a day. The all-clear
> belongs to it: an alarm whose end nobody sees becomes a permanent state. And
> message texts carry no timestamp, because `platzwart-melden` suppresses
> repeats by comparing the text — with the time in it, every 15-minute backup run
> would be a new text and the lock would do nothing.*

### Fehlgeschlagene Dienste

Bis zum 2026-09-11 stand in der Tabelle oben „Sicherung fehlgeschlagen" — gemeldet
wurde das aber von niemandem. `spiele-sicherung` gibt nur „MIT FEHLERN" aus, und
die Wache sah Container, Platte und Speicher, keine Dienste. Aufgefallen ist es,
als die tägliche Vollsicherung an der Borg-Sperre scheiterte (#171). Jetzt
meldet die Wache jeden **fehlgeschlagenen eigenen Dienst** (`spiele-*`,
`platzwart-*`, `spiel-*`, `sicherung-*`, Panel, Caddy, ttyd) mit den letzten
Journalzeilen. Ein fehlgeschlagener Dienst bleibt `failed`, bis er wieder
gelingt — der Zustandsvergleich meldet das Scheitern also einmal und das
Gelingen als Entwarnung. Nachgewiesen mit einem absichtlich scheiternden
`systemd-run`-Dienst.

**„Einrichtung nicht abgeschlossen" heißt: der Port ist zu.** Früher lautete die
Meldung „Server ohne Beitrittspasswort". Seit #156 hält die Installation die
öffentlichen Ports zurück, solange die Einrichtung offen ist — der alte Wortlaut
alarmierte in die falsche Richtung.

> *Until 2026-09-11 the table above listed "backup failed", but nobody reported
> it: the backup only printed "MIT FEHLERN" and the wache looked at containers,
> disk and memory, not services. Found when the daily full backup failed on the
> Borg lock (#171). The wache now reports every failed unit of this project with
> its last journal lines — once on failure, and as all-clear when it succeeds
> again. "Setup not finished" now says the port is closed; the old "server
> without join password" alarmed in the wrong direction since #156.*

### Was ein Absturz ist und was nicht

Exit `0` ist ein sauberes Anhalten, Exit `143` ist SIGTERM — also ein
ausdrückliches `docker stop`. Beides wird **nicht** gemeldet. Alles andere gilt
als Absturz; `137` ist SIGKILL und damit fast immer der OOM-Killer — das Bild,
mit dem Palworld endete, als StarRupture den Speicher füllte.

> *What a crash is and what not: exit 0 is a clean stop, exit 143 is SIGTERM —
> an explicit `docker stop`. Neither is reported. Everything else counts as a
> crash; 137 is SIGKILL and almost always the OOM killer — the picture Palworld
> ended with when StarRupture filled the memory.*

### Einrichten und prüfen

Die Ziele stehen in `/etc/platzwart-melden.conf` (Modus 600, root), Vorlage:
`etc/platzwart-melden.conf.beispiel`. Die Datei wird **nicht** von der
Einrichtung angelegt — sie enthält ein Geheimnis, und Geheimnisse entstehen auf
der Maschine. Fehlt sie, tut der Melder nichts und meldet Erfolg.

```bash
platzwart-melden --test      # schickt in beide Kanäle und weist nach,
                             # dass eine ungültige URL erkennbar scheitert
platzwart-wache --trocken    # zeigt die Lage, ohne zu melden
platzwart-wache --selbsttest # spielt Vergleich und Speicherpruefung mit
                             # erfundenen Zahlen durch, je Fall still und laut
```

**Die URL ist das Geheimnis.** Discords Webhook-Endpunkt prüft keine Signatur;
wer sie hat, kann in den Kanal schreiben. Deshalb 600 und root — und deshalb
filtert `platzwart-melden` vor dem Senden nach Passwörtern und Token: Meldungen
entstehen oft aus Fehlerausgaben, und in Fehlerausgaben stehen Passwörter.
Discord ist ein fremder Dienst; was einmal dort steht, steht da.

**Zum Nachprüfen nicht den Bot fragen.** Ein Bot sieht ohne den
Message-Content-Intent bei fremden Nachrichten leeres `content` und `embeds` —
die Nachricht steht da, die Abfrage zeigt sie nur nicht. Genau daran ist die
erste Kontrolle hier gescheitert, und es sah aus wie ein Zustellfehler. Der
Melder hängt deshalb `?wait=true` an: Discord antwortet dann mit der
**angelegten** Nachricht statt mit einem bloßen `204`.

> *Until 2026-09-10 nothing on this machine reported anything; the events existed
> and sat in the journal. Two Discord channels, deliberately: one carrying
> "nothing new" daily gets muted within a week, and the outage stops being
> noticed with it. Three rules carry it — changes are reported rather than
> states, the all-clear is reported too (an alarm whose end is invisible becomes
> permanent), and message texts carry no timestamp, or the repeat guard would
> never match. Exit 0 and 143 are deliberate stops and stay silent; 137 is the
> OOM killer. The webhook URL is the secret — Discord verifies no signature — so
> mode 600, root, and secret filtering before sending. Do not verify via the
> bot: without the Message Content intent it sees empty content and embeds,
> which looks exactly like a delivery failure.*

---

## Fehlerbilder

### Panel antwortet nicht

```bash
systemctl status panel --no-pager
journalctl -u panel -n 100 --no-pager
curl -sI http://127.0.0.1:8099/login          # antwortet die App selbst?
systemctl status caddy --no-pager
```

Antwortet die App auf `127.0.0.1:8099`, aber nicht über HTTPS, liegt es an
Caddy — meist am Zertifikat. `journalctl -u caddy | grep -i acme`.

**Zwei Meldungen, zwei Bedeutungen (#197):**

| Im Journal | Bedeutet | Tun |
|---|---|---|
| `panel: noch kein Benutzer (… nutzer.json fehlt)` | frische Maschine, erster Benutzer noch nicht angelegt — das Panel **läuft** | Einrichtung abschließen (`install/30-panel.sh`) |
| `… nutzer.json ist vorhanden, aber nicht lesbar` | echter Vorfall: Datei kaputt oder falscher Eigentümer — das Panel **startet nicht** | Eigentümer `panel:panel`, Modus `600`, Inhalt prüfen; notfalls aus der Sicherung |

Bis #197 sahen beide Fälle gleich aus: ein Traceback über
`/opt/panel/konfig.json` — die alte Einzelbenutzer-Datei, deren Fehlen auf einer
neuen Maschine genau richtig ist.

> *Two messages, two meanings: "no user yet" is a fresh machine and the panel
> runs; "present but unreadable" is a real incident and the panel stops. Until
> #197 both produced the same traceback about the legacy `konfig.json`.*

### Übersicht ist leer, aber die Anmeldung geht

Fast immer die sudo-Brücke. Typische Ursachen:

```bash
sudo -u panel sudo -n /usr/local/bin/panel-aktion status    # muss Ausgabe liefern
```

* **„The 'no new privileges' flag is set"** → in `panel.service` steht eine
  Härtungsoption, die `NoNewPrivileges` implizit setzt (`LockPersonality`,
  `ProtectKernelTunables`, `ProtectControlGroups`). Raus damit.
* **`sudo: a password is required`** → `/etc/sudoers.d/panel` fehlt oder hat
  falsche Rechte (`0440 root:root`).
* Nichts im Protokoll → genau das ist das Fehlerbild. Diese Störung meldet sich
  nicht, sie zeigt leere Listen.

> *An empty overview with a working login is almost always the sudo bridge. Test
> it directly. The three usual causes are listed above; note that this failure
> does not announce itself — it shows empty lists.*

### Keine Beitrittsadresse auf einer Karte

Die Oberfläche liest sie aus `/opt/stacks/<name>/panel.json`. Kann sie die Datei
nicht lesen, bleibt das Feld leer — **ohne Fehlermeldung**.

```bash
ls -l /opt/stacks/<name>/          # Verzeichnis muss 0750 root:panel sein
sudo -u panel cat /opt/stacks/<name>/panel.json
```

Die Ursache war einmal `mkdir(mode=0o750)` unter `umask 077`: Der `mode` wird
von der `umask` beschnitten, es entstand `0700`, und der Benutzer `panel` kam
nicht ins Verzeichnis. `chmod` muss **nach** `mkdir` kommen.

> *A missing join address means the panel cannot read `panel.json` — silently.
> The cause once was `mkdir(mode=0o750)` under `umask 077`: the mode is masked,
> yielding 0700. `chmod` must follow `mkdir`.*

### Container startet nicht

```bash
docker compose -f /opt/stacks/<name>/compose.yaml logs --tail 100
docker inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}}' <name>
```

| Bild | Ursache |
|---|---|
| Neustartschleife, „SteamCMD not found!" | Die Unterverzeichnisse `steamcmd` und `serverfiles` fehlen. Anlegen, `chown 4711:4711`. |
| `OOMKilled: true` | `mem_limit` zu klein oder die Maschine zu voll |
| Exit 1 direkt nach dem Start, keine Meldung | meist Rechte: `chown -R 4711:4711 /srv/games/<name>` (FOUNDRY: uid 1000) |
| „port is already allocated" | ein anderer Container hält den Port; `ss -tulpn \| grep <port>` — auch ein lokal gebundener, auch der Weckposten eines schlafenden Servers |
| Container „Up", aber niemand kommt hin | keine veröffentlichten Ports: Einrichtung noch offen (Karte zeigt es), oder er wurde gestartet, während ein Weckposten die Ports hielt — `docker compose up -d --force-recreate` |
| Container schläft für immer (`sleep infinity`) | Don't Starve Together ohne `.klei/DoNotStarveTogether`: das Startskript ruft `mkdir` ohne `-p`; der Katalog legt den Ordner an (`ordner`) |
| Project Zomboid startet alle 45 s neu | zu wenig Speicher für `-Xmx8g`; der Katalog hat 10 GB |

> *Container does not start: read its log and exit code. "SteamCMD not found!"
> in a loop means the `steamcmd` and `serverfiles` subdirectories are missing;
> `OOMKilled` means the limit is too small or the machine too full; exit 1 right
> after start is usually ownership (FOUNDRY runs as uid 1000); "port is already
> allocated" means another container, a locally bound port or a sleeping
> server's wake socket holds it; "Up" but unreachable means no published ports —
> setup still pending, or started while a wake socket held the ports (recreate
> it); Don't Starve Together sleeping forever lacks its `.klei` folder; Project
> Zomboid restarting every 45 s needs more memory than 4 GB.*

### Kein Beitrittspasswort gesetzt

```bash
journalctl -u spiel-einrichtung -n 50 --no-pager
```

Steht dort **„kein Passwortfeld gefunden … der Port bleibt zu"**, hat der
Einrichtungsschritt sechs Stunden lang keine passende Konfigurationsdatei
gefunden, und der Server hat kein Passwort bestätigt. Seit E26 geht er dann
**nicht** ans Netz. Von Hand: die Konfigurationsdatei des Servers suchen, Feld
eintragen (Konfigdateien im Panel), Container neu starten. Findet der nächste
Lauf das Feld — oder meldet der Server per A2S „Passwort nötig" —, gibt die
Einrichtung den Port selbst frei. Den Fund als `passwort.pfad`/`passwort.feld`
in den Katalog nachtragen, damit es beim nächsten Mal von selbst klappt.

> *"No password field found … the port stays closed" means six hours without a
> matching config file and no password confirmed by the server. Since E26 it
> does not go online. Set the field by hand and restart; the next run that
> finds it, or an A2S "password required", releases the port. Record path and
> field in the catalogue.*

### Sicherung läuft nicht

```bash
journalctl -u spiele-sicherung -n 50 --no-pager
borg list --short "$REPO" | tail -5        # ist ein Archiv von HEUTE dabei?
tailscale status                            # ist das Ziel erreichbar?
ssh borg@<ziel> true                        # geht der Schlüssel?
```

Häufigste Ursache in dieser Bauweise: Das Tailnet ist unten, und `borg` läuft in
den Zeitüberschreitungswert (15 s). Der Timer meldet dann einen Fehlschlag, ohne
dass an Borg etwas defekt wäre.

Zweithäufigste: die **Sperre** eines anderen Laufs. Alle Borg-Aufrufe warten
darauf (Sicherung 900 s, Liste und Größe 150 s, Auspacken 600 s, Download
900 s); scheitert einer trotzdem daran, sagt die Meldung „Gerade läuft eine
Sicherung". Eine **verwaiste** Sperre — nach einem harten Abbruch — löst
`borg break-lock "$REPO"`, aber **nur**, wenn sicher kein Borg-Prozess mehr
läuft (`pgrep -a borg`, auf der Maschine **und** auf dem Sicherungsserver).

> *Backup not running: check the unit's journal, whether today's archive exists,
> whether the tailnet is up and the key works. The most common cause here is the
> tailnet being down, with borg hitting its 15 s timeout — the timer reports a
> failure although nothing is wrong with borg. Second most common is another
> run's lock: every borg call waits for it (backup 900 s, list and size 150 s,
> extraction 600 s, download 900 s), and if one still fails on it the message
> says "a backup is running". An orphaned lock after a hard abort is cleared with
> `borg break-lock`, but only when certainly no borg process is running, on the
> machine and on the backup host.*

### Kanäle werden nicht angelegt oder nicht gelöscht

```bash
journalctl -u kanal-abgleich -n 30 --no-pager
kanal-verwalten vorschau <stack>          # was mit den Kanälen eines Servers geschähe
```

| Meldung | Bedeutung | Tun |
|---|---|---|
| `TeamSpeak-Kanaele: kein Zugriff` mit `client is flooding` / Sperre | ServerQuery-Flutschutz: drei schnelle Anmeldungen von außerhalb der Allowlist sperren rund zehn Minuten | **warten**, nicht erneut versuchen — jeder Versuch verlängert die Sperre |
| `… kein Zugriff` mit falschem Login | Passwort von `serveradmin` geändert | auf der Seite Integrationen neu eintragen (wird dort geprüft) |
| `Kanal nicht geloescht: umbenannt / verschoben / Rechte geändert / Nachricht / belegt` | ein Mensch hat den Kanal benutzt | gewollt — der Kanal bleibt; löschen von Hand, wenn er weg soll |
| `Belegung nicht messbar` | die Gateway-Sitzung zu Discord kam nicht zustande | nichts; der nächste Lauf fragt erneut |
| Discord `429` | Discords Ratenbegrenzung | nichts; das Werkzeug wartet selbst |

> *Channels not created or not deleted: read the sync unit's journal and use
> `kanal-verwalten vorschau`. "No access" with flooding means TeamSpeak's
> ServerQuery flood protection — three quick logins from outside its allow-list
> lock it for about ten minutes; wait rather than retry, since each attempt
> extends it. "No access" with a failed login means the `serveradmin` password
> changed; enter it again under Integrations. "Channel not deleted" because it
> was renamed, moved, had its permissions changed, received a message or is
> occupied is intended — a person used it. "Occupancy not measurable" means the
> Discord Gateway session failed; the next run asks again. Discord's 429 is
> handled by the tool itself.*

### Workshop-Mod wird nicht geladen

Eingetragene Mods lädt der Server **beim nächsten Start** — nach dem Eintragen
also neu starten. Dann im **Serverprotokoll** nach dem Mod suchen
(Project Zomboid `loading <Mod>`, Unturned `Installed workshop item`, Don't
Starve Together `Loading mod: workshop-<id>`, Killing Floor 2 Ordner
`KFGame/Cache/<id>`). Killing Floor 2 lädt ohne `KFGame/Cache` gar nichts und
sagt es nicht — `workshop` legt den Ordner beim Eintragen an. Karten und
Mutatoren müssen danach von Hand in den Kartenzyklus bzw. die Startparameter,
bei Unturned eine Karte über `Map` in `Config.txt`.

> *A Workshop mod does not load: listed mods are loaded at the next start, so
> restart after adding one, then look for it in the server log (the message
> differs per game). Killing Floor 2 downloads nothing without `KFGame/Cache` and
> says nothing — `workshop` creates the folder. Maps and mutators still have to
> go into the map cycle or start parameters by hand, and an Unturned map into
> `Config.txt`.*

### Ein schlafender Server wacht nicht auf

```bash
systemctl status platzwart-wecken-<stack>.socket --no-pager
platzwart-schlaf --liste
ufw status | grep platzwart-schlaf
```

Der Weckposten muss lauschen, und ufw muss die Ports durchlassen — sonst kommt
ein Paket von außen nie an, während es von der Maschine selbst sofort weckt.
Von Hand wecken: `platzwart-schlaf --wecken <stack>`; die Automatik abschalten
(Einstellungsseite, `leerlauf aus`) weckt ebenfalls sofort.

> *A sleeping server does not wake: the wake socket must listen and ufw must pass
> the ports, or a packet from outside never arrives while one from the machine
> itself wakes it at once. Wake by hand with `platzwart-schlaf --wecken`;
> switching idle sleep off on the settings page also wakes it immediately.*

### Anmeldung scheitert

„Anmeldung fehlgeschlagen" sagt bewusst nicht, ob der Name, das Passwort oder
der zweite Faktor falsch war. Groß- und Kleinschreibung des Namens spielt seit
#248 keine Rolle. Nach fünf Fehlversuchen von einer Adresse ist sie 15 Minuten
gesperrt. Das Protokoll zeigt jeden Fehlversuch mit dem eingetippten Namen. Wer
den zweiten Faktor verloren hat, meldet sich mit einem Wiederherstellungscode an
oder lässt ihn von einem Administrator zurücksetzen.

> *Login fails: "login failed" deliberately does not say whether name, password
> or second factor was wrong. Case no longer matters for the name since #248.
> After five failures from one address it is locked for 15 minutes. The audit log
> shows every failed attempt with the name as typed. Whoever lost the second
> factor logs in with a recovery code or has an administrator reset it.*

### Zertifikat läuft ab

```bash
journalctl -u caddy | grep -i acme | tail -20
curl -sI http://<PANEL_DOMAIN>/.well-known/acme-challenge/test    # Port 80 offen?
```

Fast immer: Port 80 ist zu, oder der Name zeigt nicht mehr auf diese Maschine.
Beides fällt erst auf, wenn das Zertifikat abläuft — bis dahin sieht alles gut
aus.

> *An expiring certificate almost always means port 80 is closed or the name no
> longer points here. Both stay invisible until expiry.*

---

## Bekannte offene Punkte

### Palworld hat ein Speicherleck

Bekanntes Problem des Spiels, nicht des Aufbaus. Umgangen durch einen Timer, der
den Container zweimal täglich neu startet (05:30 und 17:30):

```
palworld-neustart.timer  →  docker restart palworld
```

`Persistent=false` mit Absicht: Ein verpasster Neustart soll **nicht** beim
nächsten Hochfahren nachgeholt werden — dann liefe er womöglich mitten in einer
Spielsitzung. Eingesetzt wird der Timer von Stufe 60 zusammen mit dem
Palworld-Stack (#252).

> *Palworld has a known memory leak — the game's problem, not the setup's —
> worked around by a timer restarting the container twice a day, at 05:30 and
> 17:30, with `Persistent=false` on purpose: a missed restart must not fire after
> the next boot, possibly mid-session. Stage 60 installs it with the Palworld
> stack (#252).*

---

## Geschichte: was erledigt ist, aber lehrreich bleibt

### StarRupture — am 2026-09-08 durchgemessen, am 2026-09-09 entfernt

Der Server war auf dieser Maschine nicht zu betreiben; Jens hat ihn am
2026-09-09 über den Weg für von Hand gebaute Server entfernt (Endsicherung,
21,1 GB gelöscht). Die Messung bleibt hier, weil sie zeigt, wie ein Server
aussieht, der an der Speichergrenze gedrosselt statt beendet wird.

**Was gemessen wurde.** Der Speicher wächst nach dem Start **linear mit rund
152 MiB/s** — das ist die prozedurale Weltgenerierung, nicht der laufende
Betrieb. Ein kurzes Abflachen bei 3 GiB täuscht: danach geht es ungebremst
weiter.

| | mit den anderen Servern | allein auf der Maschine |
|---|---|---|
| verfügbar | 14 GB | 23 GB |
| erreicht | 14,5 GiB nach 137 s | 19,76 GiB nach 150 s |
| Ausgang | abgebrochen, sonst hätte der Kernel-OOM fremde Container getroffen | stabil am Limit, aber **98,8 % ausgelastet** |

Im Alleingang lief der Server technisch an: `OnUpdateSessionComplete
GameSession bWasSuccessful: 1`, Ports 7779 und 27017 veröffentlicht. Er läuft
dort aber **nur, weil die Grenze ihn bremst**: `memory.events` zählte
**22 985** Mal `max`, also erzwungenes Freigeben an der Obergrenze. Der
tatsächliche Bedarf liegt darüber.

**Zwei Korrekturen an der bisherigen Beschreibung:**

* Er wird **nicht** vom OOM-Killer beendet — `oom_kill` stand auf 0. Er wird
  gedrosselt, nicht getötet. Die Neustarts kamen zustande, weil ihm im
  Parallelbetrieb der Systemspeicher unter den Füßen wegging.
* Eine Momentaufnahme des **gestoppten** Containers ("17 GB frei, also kein
  Speicherproblem") beweist nichts. Der Bedarf entsteht erst beim Start.

**Der eigentliche Befund:** Es existiert **kein einziger Spielstand**
(`find -iname '*.sav'` → 0), obwohl `SAVE_GAME_INTERVAL` auf 300 s steht und
der Test 353 s lief. `DSSettings.txt` und die Umgebung stehen weiterhin auf
`StartNewGame: true` / `LoadSavedGame: false` — der Kommentar in der
`compose.yaml` sagt „ERSTSTART … danach zurück auf false". Da nie eine Welt
fertig wurde, beginnt jeder Start von vorn. Von außen antwortete `27017/udp`
nicht.

> *StarRupture could not be run on this machine; Jens removed it on 2026-09-09
> through the path for hand-built servers (final backup, 21.1 GB deleted). The
> measurement stays here because it shows what a server throttled at its memory
> limit, rather than killed, looks like. Measured on 2026-09-08: memory grows
> linearly at ~152 MiB/s after start — procedural world generation, not
> steady-state play. Alone on the machine it reached 19.76 GiB and held, but only
> because the limit throttled it (`memory.events` counted 22,985 `max` events;
> `oom_kill` was 0 — throttled, not killed). No save file was ever produced
> despite a 300 s autosave interval, and the settings still said StartNewGame, so
> every start began again from scratch.*

**Wer ihn wieder aufsetzen will,** braucht die Maschine praktisch für ihn allein,
mit einer Grenze oberhalb von 20 GB — bei 24 GB Gesamtspeicher und rund 8 GB für
die übrigen Server geht das im Parallelbetrieb nicht auf.

**Nachtrag 2026-09-09: `restart: on-failure:3` war die falsche Wahl.** Die
Absicht war richtig — nach dem 32-fachen Neustart am 06.09. sollte er nicht mehr
von selbst hochkommen. Nur erreicht `on-failure` das Gegenteil: Ein per
`docker stop` beendeter Container endet mit SIGTERM, also **Exit 143**, und das
ist für Docker ein *non-zero exit*, mithin ein „failure". Beim nächsten Hochfahren
der Maschine startet der Daemon ihn deshalb wieder.

Genau das geschah beim Neustart um 14:17: StarRupture kam von selbst hoch,
wuchs mit den gemessenen ~152 MiB/s, und **Palworld endete mit Exit 137** — dem
OOM-Killer. Der Wert stand danach auf `restart: "no"`, dem einzigen, der wirklich
„startet nie von selbst" bedeutet — bis der Server entfernt wurde. Die Lehre
gilt für jeden Stack: `on-failure` startet auch nach einem `docker stop` wieder.

> *Addendum 2026-09-09: `restart: on-failure:3` was the wrong choice. The intent
> was right — after 32 restarts on 06.09. it should not come up by itself any
> more — but `on-failure` achieves the opposite: a container ended by `docker
> stop` exits with SIGTERM, exit 143, which Docker counts as a failure, so the
> daemon starts it again at the next boot. That happened at the reboot at 14:17:
> StarRupture came up by itself, grew at ~152 MiB/s, and Palworld ended with exit
> 137, the OOM killer. The value was then `restart: "no"`, the only one really
> meaning "never starts by itself", until the server was removed. The lesson
> holds for every stack: `on-failure` restarts after a `docker stop` too.*

### FOUNDRY: aufgeklärt und behoben (2026-09-08)

Der Verdacht „der Download lief nie durch" war **falsch**. Die Logs des ersten
Starts zeigen `Success! App '2915550' fully installed` und
`Dedicated server is now running!` — FOUNDRY lief am 06.09. korrekt.

Verloren gingen die Daten bei der **Wiederherstellung**. `panel-aktion restore`
löschte mit `rm -rf $basis/*` alles unter `/srv/games/foundry`, spielte dann das
Archiv zurück — und das enthält `server/` gar nicht, denn dieser Pfad steht
bewusst in `/etc/borg-ausschluss.txt` (Zeile 27, Spieldateien sind groß und
jederzeit neu ladbar). Danach fehlte der Mountpunkt vollständig; Docker hätte
ihn beim nächsten Start als `root` angelegt.

Dazu kam ein zweiter Schaden: das pauschale `chown -R 4711:4711` am Ende. Alle
Katalogspiele laufen als 4711, FOUNDRYs Fremdimage aber fest als **uid 1000** —
nach der Wiederherstellung konnte es sein eigenes Datenverzeichnis nicht mehr
beschreiben.

**Beides ist behoben:** `restore` verschont jetzt die ausgeschlossenen Pfade und
übernimmt den Eigentümer aus dem gesicherten Ist-Stand, statt 4711 zu erzwingen.
FOUNDRY läuft wieder (2,4 GB neu geladen, `Dedicated server is now running`,
bei Steam registriert).

> *The suspicion that the download never finished was wrong: the first run
> installed and ran correctly. The data was lost during a **restore** — the
> excluded `server/` path was deleted and could not be replaced, because the
> archive deliberately does not contain it. A blanket `chown -R 4711` then locked
> the image (fixed to uid 1000) out of its own data. Restore now spares excluded
> paths and inherits ownership from the saved pre-restore state.*

---

## Neustart der Maschine

Über die Oberfläche (`Neustart`) oder von Hand. Die Oberfläche merkt sich
vorher, **welche Container liefen** (`panel-aktion laufende-vorher`), damit nach
dem Hochfahren derselbe Zustand hergestellt wird.

Vor einem Neustart prüfen:

```bash
systemctl list-timers --no-pager | grep sicherung   # läuft gerade eine Sicherung?
docker ps                                            # wer ist online?
```

Alle Container stehen auf `restart: unless-stopped` und kommen von allein zurück
— sofern sie niemand ausdrücklich angehalten hat (siehe unten). Das Panel bricht
den Neustart ab, wenn gerade `borg create`, `prune` oder `compact` läuft; ein
unterbrochener Borg-Lauf hinterlässt eine Sperre, die man von Hand lösen muss.

> *Reboot through the panel or by hand. The panel records which containers were
> running so the same state is restored, and refuses while borg create, prune or
> compact runs, since an interrupted borg run leaves a lock to clear by hand.
> Check first whether a backup is in flight and who is online. Everything is
> `unless-stopped` and returns on its own unless explicitly stopped (see
> below).*

---

### Warum die Server danach wiederkommen

`panel-aktion neustart` hält die Container vor dem Reboot an, damit die Spiele
ihre Stände schreiben. Das ist richtig — hat aber einen Nebeneffekt, der am
2026-09-09 **zweimal** dazu führte, dass nach dem Neustart **kein einziger**
Server zurückkam:

`docker compose stop` ist ein **ausdrückliches** Anhalten, und genau das schaltet
`restart: unless-stopped` ab. Die Regel bedeutet „starte wieder, außer es wurde
ausdrücklich angehalten", und Docker merkt sich das über den Neustart hinweg.

Deshalb schreibt `panel-aktion` die Liste der laufenden Stacks vor dem Anhalten
nach `/var/lib/spiele-wiederanlauf`, und die Einheit
`spiele-wiederanlauf.service` startet sie nach `docker.service` wieder. Die Liste
liegt in `/var/lib` und nicht in `/tmp` — **`/tmp` ist nach einem Neustart leer**,
also genau dann, wenn die Liste gebraucht wird.

Aufgeräumt wird sie **nach** dem Lauf, nicht vorher: Bricht er mittendrin ab,
steht sie beim nächsten Hochfahren noch da, und ein zweiter Durchlauf überspringt,
was schon läuft.

Nachgewiesen am dritten Neustart desselben Tages: alle drei Server kamen nach
rund 30 Sekunden von selbst zurück, StarRupture blieb aus, Exit-Code 0, Liste
weggeräumt.

> *Stopping the containers before a reboot is right — the games must write their
> saves — but an explicit stop is exactly what disables `unless-stopped`, and
> Docker remembers that across the reboot, so nothing came back. The running
> stacks are therefore recorded in `/var/lib` (not `/tmp`, which is empty after a
> reboot) and restarted by a unit ordered after `docker.service`. The list is
> removed after the run, so an interrupted run still has it next boot.*

## Alte Kopien wegräumen

Jede Einrichtungsstufe, jedes `ausrollen.sh` und jede Änderung über die
Oberfläche legt vor dem Überschreiben eine Kopie an. Das ist der Rückweg — aber
er wächst. Drei Sorten sammeln sich an:

| Muster | Woher | Größe |
|---|---|---|
| `<datei>.vor-<datum>` | Einrichtungsstufen, `ausrollen.sh` | klein |
| `<datei>.vor-panel-<datum>` | Oberfläche (Konfigdateien, compose-Felder) | klein, aber viele |
| `<verz>.vor-restore-<datum>` | vor jedem Zurückspielen | **Gigabytes** |

```bash
werkzeuge/aufraeumen.sh gameserver                          # zeigt nur den Plan
werkzeuge/aufraeumen.sh gameserver --wirklich               # Dateikopien
werkzeuge/aufraeumen.sh gameserver --mit-restore-kopien --wirklich
```

Behalten werden je Datei die **drei jüngsten** Kopien, und gelöscht wird nur,
was älter als **14 Tage** ist — beides über `--behalte` und `--aelter-als`
einstellbar. Die Regel „behalte N" schlägt dabei das Alter: eine Datei mit nur
zwei uralten Kopien behält beide.

**Entschieden wird nach dem Zeitstempel im Namen, nie nach der `mtime`.** Die
Kopien entstehen mit `cp -a` und `shutil.copy2`; beide übernehmen die `mtime`
der Quelldatei. Eine gestern angelegte Kopie einer ein Jahr alten Datei sieht in
der `mtime` ein Jahr alt aus — ein Aufräumen nach `mtime` würde also
ausgerechnet den frischesten Rückweg zuerst wegwerfen.

Der Lauf ist **bewusst kein Timer**. Diese Kopien sind der Rückweg; sie
unbeaufsichtigt verschwinden zu lassen ist genau das, was man nicht will. Wer
Platz braucht, sieht erst nach, wie viel es bringt, und entscheidet dann.

> *Every stage, every rollout and every change through the panel leaves a copy
> behind. That is the way back, and it grows — the restore copies most of all,
> since each is a full copy of a game's data directory. The tool keeps the three
> newest copies per file and deletes only what is older than 14 days, both
> adjustable; "keep N" beats age, so a file with only two ancient copies keeps
> both. Decisions are made on the timestamp in the name, never on `mtime`: the
> copies are created with `cp -a` and `shutil.copy2`, which carry the source's
> mtime across, so cleaning by mtime would discard the freshest way back first.
> Deliberately not a timer: letting the way back vanish unattended is exactly
> what one does not want.*

---

## Aktualisieren

```bash
apt update && apt upgrade                          # System (Sicherheit läuft automatisch)
docker compose -f /opt/stacks/<name>/compose.yaml pull
docker compose -f /opt/stacks/<name>/compose.yaml up -d
```

Vor einem Image-Wechsel eine Sicherung ziehen:

```bash
spiele-sicherung --nur <name>
```

Spielserver-Images ändern gelegentlich das Format der Spielstände. Der Rückweg
ist dann das Archiv, nicht das alte Image — das kann den neuen Stand nicht mehr
lesen.

> *Update the system with apt (security updates run automatically) and images per
> stack. Take a backup first: game server images occasionally change the save
> format, and the way back is the archive, not the old image — which can no
> longer read the new state.*
