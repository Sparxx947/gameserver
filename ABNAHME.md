# Abnahme — Einrichtung auf einer frischen Maschine prüfen

Anleitung für **Claude Code auf einem Wegwerf-Server**. Sie baut die Anlage von
einem leeren Debian 12 auf, prüft sie durch und baut sie wieder ab.

> *Runbook for Claude Code on a throwaway server: build from bare Debian 12,
> exercise everything, tear it down again.*

## Start

Auf dem Server, als `root`:

```bash
apt-get update && apt-get install -y git
git clone <repo-url> /root/gameserver
claude "Arbeite /root/gameserver/ABNAHME.md ab und halte dich an die Regeln darin."
```

> *Start on the server as root: install git, clone the repository and ask Claude
> Code to work through this file following its rules.*

---

## Regeln

Diese sechs gelten für den gesamten Lauf.

1. **Die Maschine ist ein Wegwerfstück.** Alles darf kaputtgehen. Läuft dort
   irgendetwas anderes, brich sofort ab und sag es.
2. **Nie die Produktivzone.** Für `DNS_ZONE` eine eigene Testzone oder mindestens
   eine Unterzone verlangen. Diese Anleitung legt echte DNS-Einträge an und
   löscht sie wieder. Steht keine Testzone bereit, frag — rate nicht.
3. **Nichts erfinden.** Jeder Befund kommt aus einer Ausgabe, die du gesehen
   hast. Ein Schritt, der nicht lief, ist „nicht gelaufen" — nicht „in Ordnung".
4. **Weitermachen nach Fehlern.** Ein fehlgeschlagener Prüfpunkt beendet den
   Lauf nicht. Notieren und zum nächsten. Nur Abschnitt 1 ist eine Sperre: ohne
   Einrichtung gibt es nichts zu prüfen.
5. **Mitschreiben.** Alles nach `/root/abnahme-bericht.md`, während du gehst,
   nicht am Ende aus dem Gedächtnis.
6. **Abschnitt 6 zuletzt.** Er baut die Anlage ab. Danach ist nichts mehr zu
   prüfen.

**Vorher zu erfragen:** DNS-Zone, Panel-Name, API-Token des DNS-Anbieters,
Admin-Benutzer, Admin-Netz (CIDR), und ob gesichert werden soll (`BORG_REPO`,
sonst `aus`). Geheimnisse nie in die Kommandozeile tippen lassen, sondern in
eine Datei mit `0600`.

> *Six rules for the whole run: the machine is disposable — abort at once if
> anything else runs there; never the production zone — insist on a test zone
> or at least a subzone, because real DNS records are created and deleted, and
> ask rather than guess; invent nothing — every finding comes from output you
> saw, and a step that did not run is "not run", not "fine"; carry on after
> failures, except in section 1, without which there is nothing to test; write
> the report as you go, not from memory at the end; and section 6 last, since it
> tears everything down. Ask beforehand for the DNS zone, panel name, DNS token,
> admin user, admin network and whether to back up; secrets go into a 0600
> file, never onto the command line.*

---

## 1 — Einrichten

```bash
cd /root/gameserver
cp konfiguration.env.beispiel konfiguration.env && chmod 600 konfiguration.env
# Werte mit sed setzen, nicht in einem Editor — und danach GEGENLESEN:
sed -i 's|^DNS_ZONE=.*|DNS_ZONE=<zone>|' konfiguration.env      # usw. je Wert
grep -E '^[A-Z][A-Z0-9_]*=' konfiguration.env                     # alles gefüllt? (mit Ziffern: SERVER_IPV4)
printf 'ANBIETER=cloudflare\nTOKEN=%s\n' '<token>' > /etc/dns-gameserver.conf
chmod 600 /etc/dns-gameserver.conf
install/einrichten.sh
```

| Prüfpunkt | Erwartet |
|---|---|
| 1.1 Vorab-Anzeige | Zeile `DNS-Zugang: cloudflare — /etc/dns-gameserver.conf`, **nicht** `KEIN TOKEN` |
| 1.2 Durchlauf | endet mit `Grundgeruest steht.`, keine Stufe bricht ab |
| 1.3 Erstzugang | Panel-Passwort erscheint **einmal** am Ende von Stufe 30 — notieren |

**1.4 — Ohne Token warnt es vorher.** Einmal gegenprobieren, bevor du die Datei
anlegst, oder hinterher mit verschobener Datei:

```bash
mv /etc/dns-gameserver.conf /tmp/ && install/einrichten.sh   # bei der Rückfrage abbrechen
mv /tmp/dns-gameserver.conf /etc/
```

Erwartet: `KEIN TOKEN` plus Warnblock **vor** der Rückfrage. Kommt die Warnung
erst mitten im Lauf, ist das ein Fehler — dann hat sie ihren Zweck verfehlt.

**Mit dem Assistenten** ([docs/11](docs/11-neueinrichtung.md)) statt der Befehle
oben gilt dasselbe, mit zwei Abweichungen: 1.1 liest man in seiner Zusammenfassung
(`DNS-Zugang`), weil `einrichten.sh --ja` keine Rückfrage stellt; und das
Erstpasswort (1.3) wiederholt er auf der Schlussseite. 1.4 prüft man dort, indem
man „keiner“ als DNS-Anbieter wählt: Dann muss **vor** der Zusammenfassung die
Warnung zu den Namen kommen.

> *Set up: copy the configuration template, fill in each value with sed and read
> it back, place the DNS token file, run the installer. Expected: the preview
> shows the DNS provider and file rather than "no token", the run ends with
> "Grundgeruest steht." and no stage aborts, and the panel password appears once
> at the end of stage 30. Cross-check 1.4: without the token file the installer
> must warn before its confirmation prompt — a warning halfway through the run
> has missed its purpose. With the assistant (docs/11) the same applies with two
> differences: read 1.1 from its summary, since `einrichten.sh --ja` asks nothing,
> and the initial password (1.3) is repeated on its final page; for 1.4 choose
> "none" as DNS provider — the warning about the names must come before the
> summary.*

---

## 2 — Läuft, was laufen soll

```bash
systemctl is-active panel caddy ttyd docker fail2ban
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung|platzwart|spieler|kanal|autoupdate|dns-ziel'
curl -sI https://<PANEL_DOMAIN>/ | head -3
curl -sI https://<PANEL_DOMAIN>/status | head -3
ufw status verbose
docker ps
```

| Prüfpunkt | Erwartet |
|---|---|
| 2.1 Dienste | alle `active` |
| 2.2 Panel über HTTPS | `200` oder `303`, **gültiges** Zertifikat (kein `curl -k`) |
| 2.3 Zeitgeber | Sicherung (ohne `BORG_REPO=aus`), Einrichtung, Kanäle, Wache, Spieler, Verlauf, Status, Leerlauf, Auto-Update mit `NEXT`; `dns-ziel.timer` an bei `SERVER_IPV4=dynamic`, sonst aus |
| 2.4 ufw | 22 nur aus `ADMIN_IP`, 80/443 offen, **keine** Spielports |
| 2.5 Neustartzähler | `systemctl show panel -p NRestarts` — muss klein sein |
| 2.6 Statusseite | `/status` antwortet **ohne** Anmeldung mit `200`, CSP `default-src 'none'` |
| 2.7 Erstanmeldung | im Browser: Passwort, QR-Code, Code, danach einmalig zehn Wiederherstellungscodes |

**2.5 ist eine bekannte Regression.** `panel.service` gibt
`/etc/borg-ausschluss.txt` über `ReadWritePaths` frei; fehlte die Datei,
verweigerte systemd den Start mit `226/NAMESPACE` und `Restart=on-failure`
machte eine Schleife daraus — der Zähler stand einmal bei 17790. Gegenprobe:

```bash
test -f /etc/borg-ausschluss.txt && echo "da"
systemctl show panel -p NRestarts
```

> *Is everything running: services active; the panel over HTTPS with a valid
> certificate; every timer scheduled (backup unless switched off, setup,
> channels, watchdog, players, history, status, idle sleep, auto-update), the
> dynamic DNS timer only with `SERVER_IPV4=dynamic`; ufw with SSH from the admin
> network only, 80/443 open and no game ports; a small restart counter for the
> panel; the status page answering without login under the strictest CSP; and
> the first login in a browser — password, QR code, code, then ten recovery
> codes shown once. 2.5 is a known regression: the panel unit opens the backup
> exclusion file via `ReadWritePaths`, and when it was missing systemd refused
> to start with 226/NAMESPACE, which `Restart=on-failure` turned into a loop —
> the counter once stood at 17790.*

---

## 3 — Die Werkzeuge einzeln

> *Each tool on its own, subsections 3.1 to 3.5.*

### 3.1 DNS

```bash
dns-pflegen anbieter          # richtiger Anbieter, richtige Datei
dns-pflegen liste
dns-pflegen ziel-zeigen       # misst und vergleicht, ändert nichts
dns-pflegen grundgeruest      # zweiter Lauf: darf NICHTS ändern
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.1.1 | `grundgeruest` zum zweiten Mal meldet `0 Eintrag/Eintraege angelegt` |
| 3.1.2 | Kein Eintrag ist `proxied` (`dns-pflegen pruefen`, Exit 0) |
| 3.1.3 | **Fremder Eintrag ist geschützt** — s.u., muss fehlschlagen |

```bash
# Von Hand im Dashboard einen CNAME "fremd.<zone>" auf irgendetwas anderes
# anlegen, dann:
dns-pflegen entfernen fremd     # MUSS abbrechen, Exit 1
```

Löscht es den Eintrag trotzdem, ist das der schwerste denkbare Fehler in diesem
Werkzeug — sofort melden.

> *DNS: provider and file, the list, a measuring comparison that changes
> nothing, and a second `grundgeruest` that must create nothing. No record may
> be proxied. A foreign record — a CNAME pointing elsewhere, created by hand —
> must refuse deletion with exit 1; deleting it anyway would be the worst
> possible fault in this tool.*

### 3.2 Ein Spiel, ganz herum

```bash
panel-aktion installieren teeworlds       # klein und schnell, so wie das Panel es tut
docker ps | grep teeworlds
python3 -c "import json;print(json.load(open('/opt/stacks/teeworlds/panel.json'))['einrichtung_stand'])"
grep -c 30131 /opt/stacks/teeworlds/compose.yaml   # 0, solange das Passwort nicht steht
# einige Minuten warten, bis spiel-einrichtung das Passwort gesetzt hat:
journalctl -u spiel-einrichtung -n 20 --no-pager
grep -c 30131 /opt/stacks/teeworlds/compose.yaml   # jetzt > 0
dns-pflegen liste | grep teeworlds
panel-aktion deinstallieren teeworlds
dns-pflegen liste | grep teeworlds         # muss leer sein
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.2.1 | Container läuft, Verzeichnis unter `/srv/games/` mit UID 4711 |
| 3.2.2 | **Der Spielport steht erst nach dem Passwort** in der compose-Datei — vorher `ports_ausstehend` in `panel.json` (Grenze 5) |
| 3.2.3 | CNAME wird angelegt und beim Entfernen wieder gelöscht |
| 3.2.4 | Bei aktiver Sicherung: Endsicherung **vor** dem Löschen |
| 3.2.5 | Bei `BORG_REPO=aus`: Deinstallation läuft trotzdem durch |
| 3.2.6 | Danach kein Rest in `/opt/stacks`, `/srv/games`, `/etc/borg-ausschluss.txt`, Zugangsdaten |

> *One game all the way round, through the same entry point the panel uses:
> install teeworlds, confirm the container runs with its data directory as UID
> 4711, confirm the game port is absent from the compose file until the setup
> timer has set the join password (it waits in `panel.json` as pending —
> boundary 5) and present afterwards, the CNAME appearing and disappearing, the
> final backup before deletion when backups are on, a clean removal when they
> are off, and no leftovers in stacks, data, exclusion list or credentials.*

### 3.3 Titelbilder — reden sie?

```bash
katalogbilder-holen --pruefen
katalogbilder-holen --alle | head -20
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.3.1 | Zeile **je Bild** (`[ 12/179] name  Steam`), nicht Schweigen bis zum Schluss |
| 3.3.2 | Der Spielname steht **vor** dem Abruf da, nicht danach |

**Auch das ist eine Regression.** Ohne Weg zu Steam schwieg die Einrichtung bis
zu 43 Minuten an dieser Stelle. Wenn du es hart prüfen willst: den CDN per
`/etc/hosts` auf `127.0.0.1` umbiegen und erneut laufen lassen — nach fünf
Netzfehlern hintereinander muss Schluss sein, nicht nach 128.

> *Catalogue artwork: the tool must print one line per image, with the game's
> name before the fetch, rather than staying silent until the end. This too is a
> regression: without a route to Steam the installer once sat silent for up to 43
> minutes here. For a hard test, point the CDN at 127.0.0.1 in `/etc/hosts` — it
> must give up after five network errors in a row, not after 128.*

### 3.4 Sicherung

```bash
spiele-sicherung --alle
borg list --short "$BORG_REPO" | tail -5
sicherung-probe teamspeak            # probeweise zurückspielen, ohne den Server anzufassen
```

Bei `BORG_REPO=aus` erwartet: sagt deutlich, dass nichts gesichert wird, Exit 0.
Mit Sicherung: Archive `config-*`, `etc-*`, `panel-*` und je Spiel eines; die
Probe packt aus, vergleicht und räumt ihr Wegwerfverzeichnis weg.

> *Backup: a full run, the newest archives and a test restore. With
> `BORG_REPO=aus` it must say plainly that nothing is backed up and exit 0.
> Otherwise expect `config-*`, `etc-*`, `panel-*` and one archive per game, and
> a probe that extracts, compares and removes its scratch directory.*

### 3.5 Selbsttests

```bash
for w in spiele-sicherung platzwart-wache platzwart-schlaf platzwart-verlauf \
         spieler-zaehlen sicherung-probe mod-verwalten workshop kanal-verwalten \
         modul-verwalten platzwart-metriken; do
  echo "== $w"; $w --selbsttest >/dev/null 2>&1 && echo gruen || echo ROT
done
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.5.1 | alle `gruen` — jeder Selbsttest prüft neben dem stillen Fall einen, der anschlagen **muss** |

> *Self-tests: every tool with a `--selbsttest` must pass; each self-test checks,
> beside the quiet case, one that must fire.*

---

### 3.5b Modpaket für Mitspieler (nur wenn Mods im Spiel sind)

```bash
mod-verwalten paket <stack>                      # freigeben
curl -sI https://<PANEL_DOMAIN>/modpaket/<stack>.zip | head -1
curl -s -o /dev/null -w "%{http_code}\n" https://<PANEL_DOMAIN>/modpaket/
mod-verwalten paket-weg <stack>                  # zurücknehmen
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.5b.1 Freigabe | nennt Dateizahl und Größe; leeres Modverzeichnis wird **abgewiesen** |
| 3.5b.2 Abruf | `200`, und das ZIP enthält genau die Moddateien |
| 3.5b.3 Listing | `/modpaket/` antwortet **404** |
| 3.5b.4 Rücknahme | danach `404`, Verzeichnis leer |
| 3.5b.5 Statusseite | zeigt den Link nur, solange freigegeben ist |

> *Modpack check: releasing names file count and size and refuses an empty
> directory; the package is fetchable and contains exactly the mod files; the
> directory itself gives 404; withdrawing leaves 404 and an empty directory; and
> the status page links it only while released.*

---

### 3.6 Modul „Statistik" (nur wenn es installiert werden soll)

Optional — das Modul kostet rund 0,5 GB Arbeitsspeicher. Wer es nicht will,
überspringt diesen Abschnitt; die Abnahme gilt trotzdem.

```bash
modul-verwalten katalog                       # statistik ... frei
# Im Panel: Module -> installieren. Danach auf der Maschine:
modul-verwalten status statistik
cd /opt/module/statistik && docker compose ps
curl -sI https://<PANEL_DOMAIN>/statistik/ | head -1     # ohne Anmeldung: 401
grep -c . /etc/caddy/module.conf; ls /var/lib/platzwart-metriken/
systemctl is-active platzwart-metriken.timer
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.6.1 Installation | drei Container laufen (`prometheus`, `grafana`, `node-exporter`), cAdvisor **nicht** |
| 3.6.2 Ohne Anmeldung | `/statistik/` antwortet **401**, nicht 200 |
| 3.6.3 Mit Anmeldung | im Browser: Grafana öffnet sich **ohne zweite Anmeldung**, Ordner „Platzwart" mit zwei Dashboards |
| 3.6.4 Rolle `verwalten` | sieht die Dashboards, hat in Grafana die Rolle `Viewer`; `admin` hat `Admin` |
| 3.6.5 Zahlen | `platzwart_spieler`, `platzwart_sicherung_groesse_bytes` und `node_load1` liefern Werte |
| 3.6.5b Tafeln | `werkzeuge/statistik-dashboards.py --daten <ziel>` meldet **keine** leere Tafel |
| 3.6.5c Dashboards | im Browser: Ordner *Platzwart* mit acht Seiten, Ordner *Spielserver* mit einer je Server |
| 3.6.5d Protokolle (falls eingeschaltet) | `curl -s http://127.0.0.1:19310/loki/api/v1/label/stack/values` nennt Server; `systemctl is-active platzwart-protokolle` = active; eine Zeile mit `password` im Protokoll erscheint **geschwärzt** |
| 3.6.6 Schalter mit Warnung | „cAdvisor einschalten" führt auf eine Bestätigungsseite, die den Docker-Socket nennt |
| 3.6.7 Ports | `ss -tulnH \| grep 19030` zeigt **nur** `127.0.0.1` |
| 3.6.8 Keine Spielsicht | das Modul steht **nicht** in `panel-aktion status`, nicht in der Übersicht und nicht in `platzwart_server_laeuft` |
| 3.6.9 Entfernen | danach ist `/etc/caddy/module.conf` leer, `/statistik` antwortet 404, der Zeitgeber ist aus, `/opt/module` ist leer, Spielstände sind unberührt |

> *Optional module check: install from the panel, three containers running and no
> cAdvisor; `/statistik/` answers 401 without a session and opens Grafana without
> a second login with one; roles map to Grafana Admin and Viewer; the metrics
> deliver values; a warned switch leads to its confirmation page; the published
> port is localhost only; the module appears in no game view; and after removal
> the route file is empty, the path answers 404, the timer is off and the game
> saves are untouched.*

---

## 4 — Die Prüfwerkzeuge selbst

```bash
werkzeuge/vollstaendigkeit.sh
werkzeuge/abgleich.sh root@localhost  # das Repo liegt hier, das Ziel ist diese Maschine
python3 werkzeuge/katalog-doku.py --pruefen
```

| Prüfpunkt | Erwartet |
|---|---|
| 4.1 | `vollstaendigkeit.sh` endet mit `vollstaendig.` |
| 4.2 | `abgleich.sh` meldet 0 abweichend, 0 fehlend |
| 4.3 | `katalog-doku.py --pruefen` meldet `Doku stimmt.` |

`abgleich.sh` spricht über SSH — auf der Maschine selbst also `root@localhost`,
wofür ein Schlüssel in `authorized_keys` liegen muss. Geht das nicht, ist der
Punkt **nicht gelaufen**; das ist ein zulässiges Ergebnis, „bestanden" wäre es
nicht.

**4.4 — Merken die Prüfer überhaupt etwas?** Ein Prüfwerkzeug, das nie anschlägt,
ist ununterscheidbar von einem kaputten. Also absichtlich brechen:

```bash
touch /usr/local/bin/attrappe                                     # verwaistes Werkzeug
sed -i 's/179 installierbare/41 installierbare/' docs/09-referenz.md   # veraltete Zahl
```

Den Katalog selbst dabei **nicht** anfassen — er ist die Quelle, gegen die
geprüft wird. Wer ihn verstellt, prüft die Prüfung gegen sich selbst.

| Prüfpunkt | Erwartet |
|---|---|
| 4.4.1 | `abgleich.sh` listet `HINWEIS /usr/local/bin/attrappe` |
| 4.4.2 | `katalog-doku.py --pruefen` meldet `41 statt 179`, Exit 1 |
| 4.4.3 | Danach `katalog-doku.py` richtet es, `--pruefen` ist wieder still |

Alles wieder herstellen (`rm /usr/local/bin/attrappe`, `git checkout -- docs/`).

> *The checking tools themselves: the completeness check must end with
> "vollstaendig.", the comparison must report zero deviations and zero missing,
> and the catalogue doc check "Doku stimmt.". The comparison talks SSH, so on
> the machine itself it needs a key for root@localhost; if that is not possible
> the point is "not run", a legitimate result — "passed" would not be. 4.4: does
> a checker notice anything at all? A checker that never fires is
> indistinguishable from a broken one, so break things on purpose — an orphaned
> tool and a stale number in the docs, never the catalogue itself, which is the
> source being checked against. Expected: the comparison lists the orphan, the
> doc check reports "41 instead of 179" with exit 1, and after the fix it is
> quiet again. Restore everything afterwards.*

---

## 5 — Übergänge und Kanten

**5.1 Alter Konfigpfad wird übernommen.**

```bash
printf 'CF_TOKEN=%s\n' '<token>' > /etc/cloudflare-gameserver.conf
rm /etc/dns-gameserver.conf
install/einrichten.sh 25-dns-grundgeruest
```

Erwartet: Protokoll nennt **beide** Pfade, die neue Datei hat `ANBIETER=` und
`TOKEN=` mit `0600`, die alte liegt als `.vor-<datum>` daneben.

**5.2 Zweiter Lauf ändert nichts.** `install/einrichten.sh` noch einmal ganz
durch. Erwartet: läuft durch, das Panel-Passwort wird **nicht** neu erzeugt,
keine Geheimnisse gewürfelt, keine Flut neuer `.vor-`Kopien.

**5.3 Einzelne Stufe.** `install/einrichten.sh 30-panel` — läuft allein und
zeigt bei `DNS-Zugang` „Stufe 25 ist nicht dabei", ohne Warnblock.

**5.4 Aufräumen.** `werkzeuge/aufraeumen.sh <ziel>` erst im Planlauf, dann mit
`--wirklich`. Erwartet: je Datei bleiben die neuesten Kopien stehen.

**5.5 Palworld bekommt seinen Zeitgeber.** `install/60-spiele.sh palworld`,
danach `systemctl is-enabled palworld-neustart.timer` → `enabled` (#252).

> *Transitions and edges: the old DNS config path is migrated once (both paths
> logged, new file 0600 with provider and token, old one moved aside); a second
> full run changes nothing — no new panel password, no new secrets, no flood of
> backup copies; a single stage runs on its own and reports stage 25 as not
> included, without a warning block; the cleanup tool keeps the newest copies per
> file; and setting up the Palworld stack enables its restart timer (#252).*

---

## 6 — Rückbau (zuletzt)

```bash
werkzeuge/rueckbau.sh <ssh-ziel>                                  # Planlauf
werkzeuge/rueckbau.sh <ssh-ziel> --mit-spielstaenden --mit-benutzern --mit-dns --wirklich
```

| Prüfpunkt | Erwartet |
|---|---|
| 6.1 | Ohne `--wirklich` ändert sich nichts |
| 6.2 | Bestätigung verlangt den **Namen des Ziels**, ein „ja" genügt nicht |
| 6.3 | Gegenprobe endet mit `nichts.` |
| 6.4 | Kontrollwert: `docker`, `ADMIN_USER` und die Borg-Passphrase sind **noch da** |
| 6.5 | Kein `dns-pflegen`, kein `cf-dns` mehr in `/usr/local/bin` |
| 6.6 | Die DNS-Einträge sind bei `--mit-dns` weg |

**6.4 ist der Punkt, an dem der Rückbau beweist, dass er misst und nicht rät.**
Meldet die Gegenprobe „nichts", aber der Kontrollwert fehlt ebenfalls, dann hat
die Maschine nur aufgehört zu antworten — dann untersucht man den Messpunkt
statt das Ziel.

> *Teardown, last: without `--wirklich` nothing changes; confirmation demands
> the target's name, not "yes"; the cross-check ends with "nichts."; the control
> value — docker, the admin user and the Borg passphrase — is still there; no DNS
> tool remains in `/usr/local/bin`; and the DNS records are gone with
> `--mit-dns`. 6.4 is where the teardown proves it measures rather than guesses:
> if the cross-check reports "nothing" but the control value is missing too, the
> machine has merely stopped answering, and one would be examining the probe
> instead of the target.*

---

## Bericht

Nach `/root/abnahme-bericht.md`, und im Terminal zusammenfassen:

```markdown
# Abnahme <datum> — <hostname>, Debian <fassung>, Commit <sha>
Konfiguration: SERVER_IPV4=<...>, BORG_REPO=<...>, Anbieter=<...>

## Ergebnis
<n> Prüfpunkte: <n> bestanden, <n> gescheitert, <n> nicht gelaufen

## Gescheitert
### <Nummer> <Titel>
Befehl:    <was du getippt hast>
Erwartet:  <was dastehen sollte>
Bekommen:  <die tatsächliche Ausgabe, gekürzt>
Journal:   <journalctl -xeu <dienst>, die entscheidenden Zeilen>

## Nicht gelaufen
<Nummer> — <warum: fehlende Voraussetzung, kein Token, keine Testzone>
```

Für jeden gescheiterten Punkt ein GitHub-Issue anlegen. Titel benennt die Wirkung,
nicht die Vermutung. Im Text: Befehl, Erwartet, Bekommen, Journal — und was du
**nicht** ausschließen konntest. Keine Vermutung als Befund verkaufen.

Beim Anlegen: `Closes #N` nur, wenn wirklich etwas geschlossen wird — und keine
echte Domäne im Text, für Beispiele `beispiel.de`.

> *Report to `/root/abnahme-bericht.md` in the shape above and summarise in the
> terminal. One GitHub issue per failed point, titled by the effect rather than
> the suspicion, with command, expected, received and journal — and what you
> could not rule out; never sell a guess as a finding. `Closes #N` only when
> something is really closed, and no real domain in the text — use
> `beispiel.de` for examples.*

## Was diese Abnahme nicht prüft

Ehrlichkeitshalber mitschreiben, damit niemand mehr Deckung annimmt als da ist:

* **Dauerbetrieb** — Neustart der Maschine, Zertifikatserneuerung nach 60 Tagen,
  Sicherungsrotation über Wochen
* **Last** — mehrere Spielserver gleichzeitig, Plattendruck, RAM-Grenzen
* **Wiederherstellung aus Borg** über einen echten Datenverlust hinaus
* **Alles mit fremden Zugängen** — Meldungen nach Discord (`platzwart-melden
  --test` braucht zwei Webhooks), Kanäle auf TeamSpeak und Discord, die
  Workshop-Suche mit einem Steam-Schlüssel. Wer die Zugänge hat, prüft sie
  nach [03-panel.md](docs/03-panel.md) und schreibt sie als eigene Punkte in den
  Bericht.
* **Passkeys und Leerlauf** — beide brauchen einen echten Browser bzw. einen
  echten Spielclient von außen.

> *What this acceptance run does not test, stated so nobody assumes more
> coverage than there is: long-term operation (reboots, certificate renewal
> after 60 days, backup rotation over weeks), load (several servers at once, disk
> pressure, memory limits), restores beyond a real data loss, anything needing
> outside
> credentials (Discord notifications, TeamSpeak and Discord channels, the
> Workshop search), and passkeys and idle sleep, which need a real browser and a
> real game client from outside.*
