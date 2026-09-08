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
sonst `aus`).

---

## 1 — Einrichten

```bash
cd /root/gameserver
cp konfiguration.env.beispiel konfiguration.env && chmod 600 konfiguration.env
# Werte mit sed setzen, nicht in einem Editor — und danach GEGENLESEN:
sed -i 's|^DNS_ZONE=.*|DNS_ZONE=<zone>|' konfiguration.env      # usw. je Wert
grep -E '^[A-Z_]+=' konfiguration.env                            # alles gefüllt?
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

---

## 2 — Läuft, was laufen soll

```bash
systemctl is-active panel caddy ttyd docker fail2ban
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung|dns-ziel'
curl -sI https://<PANEL_DOMAIN>/ | head -3
ufw status verbose
docker ps
```

| Prüfpunkt | Erwartet |
|---|---|
| 2.1 Dienste | alle `active` |
| 2.2 Panel über HTTPS | `200` oder `303`, **gültiges** Zertifikat (kein `curl -k`) |
| 2.3 Zeitgeber | Sicherungs-Timer mit `NEXT`; `dns-ziel.timer` an bei `SERVER_IPV4=dynamic`, sonst aus |
| 2.4 ufw | 22 nur aus `ADMIN_NETZ`, 80/443 offen, **keine** Spielports |
| 2.5 Neustartzähler | `systemctl show panel -p NRestarts` — muss klein sein |

**2.5 ist eine bekannte Regression.** `panel.service` gibt
`/etc/borg-ausschluss.txt` über `ReadWritePaths` frei; fehlte die Datei,
verweigerte systemd den Start mit `226/NAMESPACE` und `Restart=on-failure`
machte eine Schleife daraus — der Zähler stand einmal bei 17790. Gegenprobe:

```bash
test -f /etc/borg-ausschluss.txt && echo "da"
systemctl show panel -p NRestarts
```

---

## 3 — Die Werkzeuge einzeln

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

### 3.2 Ein Spiel, ganz herum

```bash
spiel-verwalten installieren teeworlds     # klein und schnell
docker ps | grep teeworlds
dns-pflegen liste | grep teeworlds
spiel-verwalten deinstallieren teeworlds
dns-pflegen liste | grep teeworlds         # muss leer sein
```

| Prüfpunkt | Erwartet |
|---|---|
| 3.2.1 | Container läuft, Port offen, Verzeichnis unter `/srv/games/` |
| 3.2.2 | CNAME wird angelegt und beim Entfernen wieder gelöscht |
| 3.2.3 | Bei aktiver Sicherung: Endsicherung **vor** dem Löschen |
| 3.2.4 | Bei `BORG_REPO=aus`: Deinstallation läuft trotzdem durch |
| 3.2.5 | Danach kein Rest in `/opt/stacks`, `/srv/games`, `/etc/borg-ausschluss.txt` |

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

### 3.4 Sicherung

```bash
spiele-sicherung --alle
borg list --short "$BORG_REPO" | tail -5
```

Bei `BORG_REPO=aus` erwartet: sagt deutlich, dass nichts gesichert wird, Exit 0.

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

`abgleich.sh` spricht über SSH — auf der Maschine selbst also `root@localhost`,
wofür ein Schlüssel in `authorized_keys` liegen muss. Geht das nicht, ist der
Punkt **nicht gelaufen**; das ist ein zulässiges Ergebnis, „bestanden" wäre es
nicht.
| 4.3 | `katalog-doku.py --pruefen` meldet `Doku stimmt.` |

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

## Was diese Abnahme nicht prüft

Ehrlichkeitshalber mitschreiben, damit niemand mehr Deckung annimmt als da ist:

* **Dauerbetrieb** — Neustart der Maschine, Zertifikatserneuerung nach 60 Tagen,
  Sicherungsrotation über Wochen
* **Last** — mehrere Spielserver gleichzeitig, Plattendruck, RAM-Grenzen
* **Wiederherstellung aus Borg** über einen echten Datenverlust hinaus
* **Der Anbieter `hetzner`** — er ist nach Dokumentation geschrieben und nie
  gegen eine echte Zone gelaufen (Issue #60). Wer eine Hetzner-Zone hat: die
  Prüfliste in `docs/06-netz-dns-firewall.md` gilt genau dafür.
