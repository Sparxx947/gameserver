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

### StarRupture läuft nicht

Der Server füllt jede gesetzte Speichergrenze und wird vom OOM-Killer beendet;
zuletzt 32 Neustarts in Folge. Er steht deshalb auf `restart: on-failure` statt
`unless-stopped` und ist angehalten.

Ein Versuch ohne Speichergrenze setzt voraus, dass die übrigen Server kurz
angehalten werden — sonst trifft der OOM-Killer sie.

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

### FOUNDRY hat keine Serverdaten

`/srv/games/foundry` ist mit 56 KB praktisch leer, der Container beendet. Der
Download ist offenbar nie durchgelaufen. Noch nicht untersucht.

> *FOUNDRY's data directory holds 56 KB and the container is stopped — the
> download evidently never completed. Not yet investigated.*

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
