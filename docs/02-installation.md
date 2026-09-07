# 02 — Installation

Von einer leeren Debian-12-Maschine zum laufenden Panel. Die Einrichtung läuft
in Stufen; jede ist einzeln aufrufbar und mehrfach ausführbar.

> *From a bare Debian 12 machine to a running panel. Installation runs in
> stages; each can be invoked on its own and re-run safely.*

---

## Vorher prüfen

| Voraussetzung | Prüfung |
|---|---|
| Debian 12, root | `. /etc/os-release; echo $VERSION_CODENAME` → `bookworm` |
| Öffentliche IPv4 | `curl -s https://api.ipify.org` |
| Panel-Name zeigt darauf | `host <PANEL_DOMAIN>` — **muss** die IPv4 liefern |
| Tailscale verbunden | `tailscale status` (nur wenn übers Tailnet gesichert wird) |
| Borg-Ziel erreichbar | `ssh borg@<ziel> true` |
| Platz | mindestens 50 GB frei, besser 100 |

**Der Panel-Name muss öffentlich auflösen, bevor Stufe 40 läuft.** Caddy holt
das Zertifikat über HTTP-01: Let's Encrypt ruft `http://<name>/.well-known/…`
auf. Zeigt der Name noch nirgends hin oder ist Port 80 zu, scheitert das —
und zwar mit Rate-Limits, die eine Wiederholung für Stunden sperren können.

> *The panel hostname must resolve publicly before stage 40. Caddy uses HTTP-01,
> so Let's Encrypt fetches `http://<name>/.well-known/…`. If the name does not
> resolve or port 80 is closed this fails — and hits rate limits that can block
> retries for hours.*

---

## Konfiguration ausfüllen

```bash
cp konfiguration.env.beispiel konfiguration.env
chmod 600 konfiguration.env
$EDITOR konfiguration.env
```

Jeder Wert ist in der Vorlage erklärt. Die Datei steht in `.gitignore` und wird
nie eingecheckt. Sie ist die **einzige** Stelle mit Standortdaten: alle Skripte,
Units und Konfigurationsdateien tragen `@@PLATZHALTER@@`, die beim Einbau
ersetzt werden.

Bleibt ein Platzhalter übrig, **bricht die Einrichtung ab**. Das ist Absicht:
eine Datei mit unersetztem `@@NAME@@` fällt sonst erst im Betrieb auf, meist als
leerer Wert an einer Stelle, an der niemand ihn sucht.

> *Fill in `konfiguration.env`. It is the only place holding site-specific
> values; every script, unit and config file carries `@@PLACEHOLDERS@@`
> substituted at install time. A left-over placeholder aborts the run
> deliberately — otherwise it surfaces only at runtime, usually as an empty
> value nobody thinks to check.*

---

## Die Stufen

```bash
sudo install/einrichten.sh          # 10 bis 50 der Reihe nach
sudo install/einrichten.sh 30-panel # oder eine einzelne Stufe
```

### 10 — Grundsystem

Pakete, die drei Benutzer (`<admin>`, `panel`, `spiele` mit UID 4711),
SSH-Härtung, ufw und fail2ban.

**Was ufw hier öffnet:** Port 22 nur aus `ADMIN_NETZ`, Port 80 und 443 für alle,
und alles auf `tailscale0`. **Spielports stehen bewusst nicht drin** — die macht
Docker selbst auf, und zwar an ufw vorbei (siehe
[06-netz-dns-firewall.md](06-netz-dns-firewall.md)).

> *Stage 10: packages, the three users, SSH hardening, ufw and fail2ban. ufw
> opens 22 from `ADMIN_NETZ` only, 80/443 for everyone, and everything on
> `tailscale0`. Game ports are deliberately absent — Docker opens those itself,
> bypassing ufw.*

### 20 — Docker

Docker CE aus dem Hersteller-Repositorium. Debians eigenes `docker.io` ist zu
alt für `docker compose` in Plugin-Form.

**Niemand kommt in die Gruppe `docker`.** Wer mit dem Socket sprechen darf, kann
sich mit einem Einzeiler root verschaffen (`docker run -v /:/host`). Für die
Oberfläche gibt es stattdessen die enge sudo-Brücke.

> *Stage 20: Docker CE from upstream, because Debian's `docker.io` is too old
> for the compose plugin. Nobody joins the `docker` group — socket access is
> equivalent to root.*

### 30 — Panel

Virtuelle Python-Umgebung, `app.py`, die Werkzeuge nach `/usr/local/bin`, der
Katalog, die sudo-Regel und die Dienste.

Am Ende erscheint **einmal** die Erstanmeldung:

```
   Erstanmeldung / initial login
     https://panel.example.de/
     Benutzer / user:  admin
     Passwort / pass:  <16 Zeichen, hier einmalig sichtbar>
```

Das Passwort steht nur hier — gespeichert wird ausschließlich der
Argon2id-Hash. Das TOTP-Geheimnis entsteht ebenfalls hier, wird aber **nicht**
ausgegeben: es käme sonst ins Sitzungsprotokoll und wäre kein zweiter Faktor
mehr. Beim ersten Anmelden führt die Oberfläche auf eine Einrichtungsseite mit
QR-Code.

Die sudo-Regel wird mit `visudo -c` geprüft, **bevor** sie eingebaut wird. Eine
kaputte Datei in `/etc/sudoers.d` legt sudo systemweit lahm — auch für den
Menschen, der sie reparieren müsste.

> *Stage 30: venv, app, tools, catalogue, sudo rule, services. The initial login
> is printed once; only the Argon2id hash is stored. The TOTP secret is created
> but never printed — printing it would put it in the session log. The sudo rule
> is validated with `visudo -c` before installation: a broken file in
> `/etc/sudoers.d` disables sudo system-wide, including for whoever would fix
> it.*

### 40 — Caddy und Webterminal

Caddy aus dem Hersteller-Repositorium, `ttyd` als Release-Binary (bookworm
liefert 1.6, dessen `--base-path` sich anders verhält).

Die Caddy-Konfiguration wird mit `caddy validate` geprüft, bevor der laufende
Dienst sie bekommt. Ein Tippfehler nähme sonst das Panel **und** das Terminal
vom Netz, über das man es reparieren würde.

> *Stage 40: Caddy from upstream, ttyd as a release binary (bookworm's 1.6
> handles `--base-path` differently). The config is validated before reload: a
> typo would take down the panel and the very terminal used to fix it.*

### 50 — Sicherung

Borg, Passphrase, Ausschlussliste, beide Zeitpläne — und ein **Probelauf**, der
tatsächlich ausgeführt und dessen Ergebnis angesehen wird. Scheitert er, bricht
die Stufe ab.

Eine nie geprüfte Sicherung ist eine Vermutung, keine Sicherung.

Die Passphrase in `/root/.borg-passphrase` ist der **einzige** Schlüssel zum
Repositorium. Eine Kopie gehört an einen zweiten Ort außerhalb dieses Servers —
geht die Maschine verloren, ist ein verschlüsseltes Repositorium ohne sie
wertlos.

> *Stage 50: Borg, passphrase, exclusion list, both schedules — and a real test
> run whose result is inspected. If it fails, the stage aborts: an unverified
> backup is a guess. The passphrase is the only key to the repository; keep a
> copy off this machine, or an encrypted repository becomes worthless when the
> host is lost.*

### 60 — Die handgepflegten Server

```bash
sudo install/60-spiele.sh                         # zeigt die Liste
sudo install/60-spiele.sh teamspeak enshrouded
```

Erzeugt je Stack frische Passwörter, schreibt die compose-Datei (`0600 root`)
und legt das Datenverzeichnis unter UID 4711 an. Ein bereits eingerichteter
Stack wird **übersprungen**, nicht überschrieben — sonst wären beim zweiten Lauf
alle Passwörter neu und niemand käme mehr auf den Server.

Gestartet wird von Hand oder über das Panel.

> *Stage 60: fresh passwords per stack, compose file at 0600 root, data
> directory as UID 4711. An already configured stack is skipped, not
> overwritten — a second run would otherwise change every password and lock
> everyone out.*

### 70 — DNS (optional)

Braucht `/etc/cloudflare-gameserver.conf` mit einem Token, das **nur**
`Zone / DNS / Bearbeiten` in der eigenen Zone darf. Nie der globale Schlüssel.

Legt für jeden vorhandenen Stack einen CNAME auf `DNS_ZIEL` an und prüft
anschließend, dass kein Eintrag `proxied` ist: Cloudflares Proxy kann nur HTTP
und HTTPS, ein Spielport dahinter ist von außen tot.

Setzt außerdem `dns-ziel.service` und `dns-ziel.timer` ein. Ob der Timer läuft,
entscheidet `SERVER_IPV4`:

* **feste IPv4** — der Timer bleibt aus, und der A-Eintrag `DNS_ZIEL` wird
  **nicht** automatisch angelegt. Er ist dann der einzige Ort mit der Adresse und
  gehört in die Hand eines Menschen.
* **`dynamic`** — die Stufe misst die öffentliche IPv4 einmal sofort, legt den
  A-Eintrag an oder zieht ihn nach und schaltet den Timer ein. Ab da geschieht
  das alle fünf Minuten. Begründung in `docs/10-entscheidungen.md`, E21.

Der Timer liegt in beiden Fällen auf der Maschine; ein Wechsel ist eine Zeile in
`konfiguration.env` und ein erneuter Lauf dieser Stufe.

> *Stage 70: needs a scoped Cloudflare token (Zone / DNS / Edit, own zone only —
> never the global key). Creates one CNAME per stack pointing at `DNS_ZIEL` and
> verifies nothing is proxied: Cloudflare's proxy only speaks HTTP(S), so a game
> port behind it is dead. It also installs `dns-ziel.service` and its timer.
> With a fixed `SERVER_IPV4` the timer stays off and the `DNS_ZIEL` A record is
> deliberately not automated — it is the single place holding the IP. With
> `SERVER_IPV4=dynamic` the stage measures the public IPv4 once, creates or
> updates the record and enables the timer, which then repeats every five
> minutes. The timer is installed either way, so switching is one line in
> `konfiguration.env` plus a re-run of this stage.*

---

## Nach der Installation prüfen

```bash
cat /etc/gameserver-version                        # welche Fassung liegt hier
systemctl is-active panel caddy ttyd docker fail2ban
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung'
curl -sI https://<PANEL_DOMAIN>/ | head -3        # 200 oder 303
borg list --short "$BORG_REPO" | tail -5
ufw status verbose
docker ps
```

Erwartet: alle Dienste `active`, beide Sicherungs-Timer mit einem `NEXT`, das
Panel antwortet über HTTPS, im Borg-Repositorium liegen Archive.

> *Post-install checks: all services active, both backup timers scheduled, the
> panel answering over HTTPS, and archives present in the Borg repository.*

---

## Rückweg

Jede Stufe sichert eine vorhandene Zieldatei vor dem Überschreiben nach
`<datei>.vor-<datum>`. Zurück geht es also datei­weise:

```bash
ls /etc/caddy/Caddyfile.vor-*
cp /etc/caddy/Caddyfile.vor-20260907-101500 /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

Vollständig zurückbauen (Achtung, löscht Spielstände):

```bash
docker compose -f /opt/stacks/<name>/compose.yaml down
systemctl disable --now panel ttyd spiele-sicherung.timer \
                        spiele-sicherung-voll.timer spiel-einrichtung.timer
rm -rf /opt/panel /opt/stacks /srv/games /srv/dienste
rm -f /etc/sudoers.d/panel /etc/spiele-katalog.json /etc/borg-ausschluss.txt
rm -f /usr/local/bin/{cf-dns,katalog-vorpruefung,panel-aktion,spiel-einrichtung,spiel-verwalten,spiele-sicherung,ttyd}
```

Das Borg-Repositorium bleibt dabei unangetastet — die Spielstände sind danach
noch da.

> *Rollback: every stage backs up an existing target to `<file>.vor-<date>`, so
> reverting is per file. The full teardown is listed above and deletes save
> games; the Borg repository is untouched, so the saves still exist there.*
