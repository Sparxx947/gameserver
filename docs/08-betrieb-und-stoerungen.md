# 08 — Betrieb und Störungen

## Der Alltag in fünf Befehlen

```bash
systemctl is-active panel caddy ttyd docker fail2ban tailscaled
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung'
journalctl -u panel -n 50 --no-pager
df -h / && free -h
```

> *Everyday health check: services active, containers up, timers scheduled,
> recent panel log, disk and memory.*

---

## Speicher: die Grenzen sind überbucht

Die Summe aller `mem_limit` übersteigt den vorhandenen Arbeitsspeicher deutlich.
Das ist **beabsichtigt und funktioniert**, solange nicht alle Server gleichzeitig
laufen — nur eben nicht mehr, wenn doch.

Beispiel von der dokumentierten Maschine (23,5 GiB RAM):

| Container | Grenze |
|---|---|
| starrupture | 16 G |
| palworld | 12 G |
| satisfactory | 10 G |
| windrose | 8 G |
| foundry | 6 G |
| enshrouded | 6 G |
| teamspeak | 1 G |
| **Summe** | **59 G** |

Was dabei zu wissen ist: Der Kernel gibt nur her, was da ist. Wird es eng, greift
**nicht** die saubere Container-Grenze, sondern der OOM-Killer der Maschine — und
der trifft nicht unbedingt den Schuldigen.

Vor dem Start prüfen:

```bash
free -m | awk '/^Mem/ {print "frei:", $7 "M"}'
docker inspect -f '{{.Name}} {{.HostConfig.Memory}}' $(docker ps -q)
```

`spiel-verwalten` prüft das bei Katalog-Installationen selbst und startet nicht,
wenn der freie Speicher zum `mem_limit` nicht reicht.

> *Memory limits are deliberately oversubscribed and work fine until several
> servers run at once. Then it is not the clean per-container limit that applies
> but the host OOM killer, which does not necessarily hit the culprit. Check
> free memory before starting; the catalogue installer does this itself and
> refuses to start a server that does not fit.*

---

## Was sich von selbst meldet

Bis zum 2026-09-10 meldete sich **nichts**. Die Ereignisse gab es alle, sie
standen im Journal und warteten darauf, dass jemand nachsieht — der einzige
Melder war eine Prüfung, die montags 10:00 auf einem Desktop lief. Ein Server,
der Samstagnacht um drei stirbt, fiel damit am Montag auf.

Geschickt wird nach Discord, über zwei Webhooks:

| Kanal | Was dort landet |
|---|---|
| `#platzwart-stoerung` | Server abgestürzt, Sicherung fehlgeschlagen, Platte knapp, Server ohne Beitrittspasswort, Update fehlgeschlagen |
| `#platzwart-meldungen` | Update wirklich eingespielt, Entwarnung nach einer Störung |

**Zwei Kanäle, mit Absicht.** Ein Kanal, in dem täglich „Update geprüft, nichts
Neues" steht, wird nach einer Woche stummgeschaltet — und dann fällt auch die
Störung nicht mehr auf.

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

### Was ein Absturz ist und was nicht

Exit `0` ist ein sauberes Anhalten, Exit `143` ist SIGTERM — also ein
ausdrückliches `docker stop`. Beides wird **nicht** gemeldet. Alles andere gilt
als Absturz; `137` ist SIGKILL und damit fast immer der OOM-Killer, genau das
Bild, an dem StarRupture starb.

### Einrichten und prüfen

Die Ziele stehen in `/etc/platzwart-melden.conf` (Modus 600, root), Vorlage:
`etc/platzwart-melden.conf.beispiel`. Die Datei wird **nicht** von der
Einrichtung angelegt — sie enthält ein Geheimnis, und Geheimnisse entstehen auf
der Maschine. Fehlt sie, tut der Melder nichts und meldet Erfolg.

```bash
platzwart-melden --test      # schickt in beide Kanäle und weist nach,
                             # dass eine ungültige URL erkennbar scheitert
platzwart-wache --trocken    # zeigt die Lage, ohne zu melden
platzwart-wache --selbsttest # spielt den Vergleich mit erfundenen Lagen durch
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
| Exit 1 direkt nach dem Start, keine Meldung | meist Rechte: `chown -R 4711:4711 /srv/games/<name>` |
| „port is already allocated" | ein anderer Container hält den Port; `ss -tulpn \| grep <port>` |

### Kein Beitrittspasswort gesetzt

```bash
journalctl -u spiel-einrichtung -n 50 --no-pager
```

Steht dort **„KEIN Passwortfeld gefunden"**, hat der Einrichtungsschritt sechs
Stunden lang keine passende Konfigurationsdatei gefunden. Dann von Hand: die
Konfigurationsdatei des Servers suchen, Feld eintragen, Container neu starten —
und den Fund als `passwort.pfad`/`passwort.feld` in den Katalog nachtragen,
damit es beim nächsten Mal klappt.

> *If the setup step reports "no password field found" after six hours, set it by
> hand and record the path and field name in the catalogue so the next install
> works.*

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

### StarRupture läuft nicht — am 2026-09-08 durchgemessen

Der Server ist auf dieser Maschine nicht zu betreiben. Er steht auf
`restart: on-failure:3` und ist angehalten.

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

> *Measured on 2026-09-08: memory grows linearly at ~152 MiB/s after start —
> that is procedural world generation, not steady-state play. Alone on the
> machine it reached 19.76 GiB and held, but only because the limit throttled it
> (`memory.events` counted 22,985 `max` events; `oom_kill` was 0 — it is
> throttled, not killed). No save file was ever produced despite a 300 s
> autosave interval, and the settings still say StartNewGame, so every start
> begins again from scratch.*

**Wenn er laufen soll,** braucht er die Maschine praktisch für sich, mit einer
Grenze oberhalb von 20 GB — bei 24 GB Gesamtspeicher und rund 8 GB für die
übrigen Server geht das im Parallelbetrieb nicht auf.

**Nachtrag 2026-09-09: `restart: on-failure:3` war die falsche Wahl.** Die
Absicht war richtig — nach dem 32-fachen Neustart am 06.09. sollte er nicht mehr
von selbst hochkommen. Nur erreicht `on-failure` das Gegenteil: Ein per
`docker stop` beendeter Container endet mit SIGTERM, also **Exit 143**, und das
ist für Docker ein *non-zero exit*, mithin ein „failure". Beim nächsten Hochfahren
der Maschine startet der Daemon ihn deshalb wieder.

Genau das geschah beim Neustart um 14:17: StarRupture kam von selbst hoch,
wuchs mit den gemessenen ~152 MiB/s, und **Palworld endete mit Exit 137** — dem
OOM-Killer. Der Wert steht jetzt auf `restart: "no"`, dem einzigen, der wirklich
„startet nie von selbst" bedeutet. Von Hand starten geht weiterhin.

### Palworld hat ein Speicherleck

Bekanntes Problem des Spiels, nicht des Aufbaus. Umgangen durch einen Timer, der
den Container zweimal täglich neu startet (05:30 und 17:30):

```
palworld-neustart.timer  →  docker restart palworld
```

`Persistent=false` mit Absicht: Ein verpasster Neustart soll **nicht** beim
nächsten Hochfahren nachgeholt werden — dann liefe er womöglich mitten in einer
Spielsitzung.

> *StarRupture fills any memory limit and is currently stopped; testing it
> without a limit requires briefly stopping the others. Palworld has a known
> memory leak, worked around by a twice-daily restart timer with
> `Persistent=false` on purpose: a missed restart must not fire mid-session
> after a boot.*

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
— außer StarRupture (`on-failure`, bewusst).

> *Reboot through the panel or by hand. The panel records which containers were
> running so the same state is restored. Check first whether a backup is in
> flight and who is online. Everything is `unless-stopped` and returns on its
> own, except StarRupture.*

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
