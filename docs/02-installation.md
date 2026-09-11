# 02 — Installation

Von einer leeren Debian-12-Maschine zum laufenden Panel. Die Einrichtung läuft
in Stufen; jede ist einzeln aufrufbar und mehrfach ausführbar.

> *From a bare Debian 12 machine to a running panel. Installation runs in
> stages; each can be invoked on its own and re-run safely.*

**Geführt geht es mit `install/assistent.sh`:** Er fragt jeden Wert ab, prüft
Zugänge (DNS-Token, Sicherungsziel, SSH-Schlüssel) und ruft danach genau die
Stufen dieses Kapitels auf. Die vollständige Anleitung von der leeren Maschine
bis zur Abnahme — samt Domain, Sicherungsziel und Wiederaufbau aus der
Sicherung — steht in [11-neueinrichtung.md](11-neueinrichtung.md). Dieses Kapitel
beschreibt die Stufen selbst und den Weg von Hand.

> *Guided: `install/assistent.sh` asks for every value, checks access (DNS
> token, backup target, SSH key) and then calls exactly the stages in this
> chapter. The complete guide from an empty machine to acceptance — domain,
> backup target and rebuild from backup included — is 11-neueinrichtung.md. This
> chapter describes the stages themselves and the manual path.*

---

## Vorher prüfen

| Voraussetzung | Prüfung |
|---|---|
| Debian 12, root | `. /etc/os-release; echo $VERSION_CODENAME` → `bookworm` |
| Öffentliche IPv4 | `curl -s https://api.ipify.org` |
| DNS-Token liegt bereit | `test -s /etc/dns-gameserver.conf` — dann macht Stufe 25 die Namen |
| Panel-Name zeigt darauf | `host <PANEL_DOMAIN>` — nur nötig, wenn es keinen Token gibt |
| Tailscale verbunden | `tailscale status` (nur wenn übers Tailnet gesichert wird) |
| Borg-Ziel erreichbar | `ssh borg@<ziel> true` |
| Platz | mindestens 50 GB frei, besser 100 |

**Der Panel-Name muss öffentlich auflösen, bevor Stufe 40 läuft.** Caddy holt
das Zertifikat über HTTP-01: Let's Encrypt ruft `http://<name>/.well-known/…`
auf. Zeigt der Name noch nirgends hin oder ist Port 80 zu, scheitert das —
und zwar mit Rate-Limits, die eine Wiederholung für Stunden sperren können.

**Darum genügt es, den Cloudflare-Token vorher hinzulegen.** Liegt
`/etc/dns-gameserver.conf` bereit, legt Stufe 25 `DNS_ZIEL` und
`PANEL_DOMAIN` selbst an, bevor Stufe 40 an der Reihe ist — dann bleibt vom DNS
nur die Zone selbst Handarbeit. Ohne Token überspringt sich die Stufe und sagt,
was stattdessen von Hand zu tun ist.

```bash
printf 'ANBIETER=cloudflare\nTOKEN=%s\n' '<token>' > /etc/dns-gameserver.conf
chmod 600 /etc/dns-gameserver.conf
```

> *The panel hostname must resolve publicly before stage 40. Caddy uses HTTP-01,
> so Let's Encrypt fetches `http://<name>/.well-known/…`. If the name does not
> resolve or port 80 is closed this fails — and hits rate limits that can block
> retries for hours. Putting the Cloudflare token in place beforehand is enough:
> stage 25 then creates both records before stage 40 runs. Without a token that
> stage skips itself and says what to do by hand instead.*

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
sudo install/einrichten.sh          # 10 bis 50 der Reihe nach (25 nur mit Token)
sudo install/einrichten.sh 30-panel # oder eine einzelne Stufe
```

Jede Stufe liest `konfiguration.env` über `install/lib.sh`, bricht bei einer
leeren Pflichtvariable, einem unzulässigen Wert (`SERVER_IPV4`,
`ZERTIFIKAT_WEG`, `SSH_*`) oder einem übrig gebliebenen Platzhalter ab und
sichert jede vorhandene Zieldatei vor dem Überschreiben nach
`<datei>.vor-<datum>`. Jede eingesetzte Datei setzt außerdem den Stempel
`/etc/gameserver-version`.

> *Every stage reads `konfiguration.env` through `install/lib.sh`, aborts on an
> empty mandatory variable, an invalid value or a left-over placeholder, backs
> up every existing target to `<file>.vor-<date>` before overwriting it, and
> updates the version stamp `/etc/gameserver-version` with each file it
> installs.*

### 10 — Grundsystem

Pakete, die drei Benutzer (`<admin>`, `panel`, `spiele` mit UID 4711),
SSH-Härtung, ufw und fail2ban.

**Was ufw hier öffnet:** Port 22 nur aus `ADMIN_IP`, Port 80 und 443 für alle,
und alles auf `tailscale0`. **Spielports stehen bewusst nicht drin** — die macht
Docker selbst auf, und zwar an ufw vorbei (siehe
[06-netz-dns-firewall.md](06-netz-dns-firewall.md)).

**Was die SSH-Härtung setzt:** `SSH_PASSWORT_AUTH` und `SSH_ROOT_LOGIN` aus
`konfiguration.env`, Vorgabe `no` und `prohibit-password` — Anmeldung nur mit
Schlüssel. Lehnt `sshd -t` die Datei ab, nimmt die Stufe sie zurück und bricht
ab, statt weiterzulaufen. Die Werte und ihre Folgen stehen in
[06-netz-dns-firewall.md](06-netz-dns-firewall.md#ssh).

> *Stage 10: packages, the three users, SSH hardening, ufw and fail2ban. ufw
> opens 22 from `ADMIN_IP` only, 80/443 for everyone, and everything on
> `tailscale0`. Game ports are deliberately absent — Docker opens those itself,
> bypassing ufw. SSH hardening takes its two values from `konfiguration.env`,
> defaulting to key-only login; a config `sshd -t` rejects is rolled back and
> aborts the stage.*

### 20 — Docker

Docker CE aus dem Hersteller-Repositorium. Debians eigenes `docker.io` ist zu
alt für `docker compose` in Plugin-Form.

**Niemand kommt in die Gruppe `docker`.** Wer mit dem Socket sprechen darf, kann
sich mit einem Einzeiler root verschaffen (`docker run -v /:/host`). Für die
Oberfläche gibt es stattdessen die enge sudo-Brücke.

> *Stage 20: Docker CE from upstream, because Debian's `docker.io` is too old
> for the compose plugin. Nobody joins the `docker` group — socket access is
> equivalent to root.*

### 25 — DNS-Grundgerüst (übersprungen ohne Token)

Legt bei Cloudflare an, was **vor** dem Zertifikat da sein muss: den A-Eintrag
`DNS_ZIEL` und, wenn er innerhalb der Zone liegt, `PANEL_DOMAIN`.

Angelegt wird ausschließlich, **was fehlt**. Ein vorhandener Eintrag bleibt
unangetastet, auch wenn er woandershin zeigt — er gehört dann einem Menschen
(siehe [E21](10-entscheidungen.md)). Das Nachführen bleibt Sache von
`ziel-setzen` und des Zeitgebers aus Stufe 70.

Ohne `/etc/dns-gameserver.conf` wird die Stufe übersprungen, nicht abgebrochen.
Liegt noch die alte `/etc/cloudflare-gameserver.conf` da, übernimmt die Stufe
sie **einmal** in die neue Datei und verschiebt die alte nach `.vor-<datum>` —
`dns-pflegen` selbst liest den alten Ort nicht mehr. Übersprungen ist die Stufe
kein Fehler: DNS von Hand zu pflegen ist ein zulässiger Betrieb. Nachholen
lässt sie sich einzeln:

```bash
sudo install/einrichten.sh 25-dns-grundgeruest
```

> *Stage 25 creates what must exist before the certificate: the `DNS_ZIEL` A
> record and `PANEL_DOMAIN` if it lies inside the zone. Only missing records are
> created — an existing one is never touched, even pointing elsewhere. Skipped
> without a token, since hand-maintained DNS is legitimate; an old
> `/etc/cloudflare-gameserver.conf` is migrated once into the new file and moved
> aside, since `dns-pflegen` no longer reads it. It also installs the
> `dns-ziel` timer and switches it according to `SERVER_IPV4`.*

### 30 — Panel

Die größte Stufe. Sie setzt ein:

* die virtuelle Python-Umgebung unter `/opt/panel/venv` aus
  `panel/requirements.txt`, `app.py`, `passkey.js` und die Symbole;
* **alle Werkzeuge** aus `bin/` nach `/usr/local/bin` (außer
  `spiele-sicherung`, das Stufe 50 einsetzt) — `vollstaendigkeit.sh` prüft, dass
  keines fehlt;
* den Katalog `/etc/spiele-katalog.json` und gleich danach
  `spiel-verwalten katalog-abgleich`, damit schon installierte Server
  Katalogänderungen mitbekommen (Sicherungsausschlüsse, neue Variablen);
* `/etc/spiele-adressen.json`, `/etc/spiele-mods.json`,
  `/etc/spiele-workshop.json`;
* die sudo-Regel `/etc/sudoers.d/panel`, **vorher** mit `visudo -c` geprüft;
* `/etc/borg-ausschluss.txt`, falls sie noch fehlt — `panel.service` gibt genau
  diese Datei über `ReadWritePaths` frei, und systemd verweigert den Start, wenn
  der Pfad nicht existiert (`226/NAMESPACE`, mit `Restart=on-failure` eine
  Neustartschleife);
* die Units und Zeitgeber: `panel.service`, `spiel-einrichtung`,
  `kanal-abgleich`, `spiele-wiederanlauf` (nur `enable`, es gehört zum nächsten
  Hochfahren), `platzwart-schlaf` samt `platzwart-wecken@.service`,
  `platzwart-verlauf`, `platzwart-status`, `spieler-zaehlen`, `platzwart-wache`
  und `spiele-autoupdate`. Die Zeitgeber laufen sofort; die Automatiken
  (Auto-Update, Leerlauf, Kanäle) bleiben trotzdem aus, bis sie je Server bzw.
  auf der Seite Integrationen eingeschaltet werden;
* den ersten Benutzer (Rolle `admin`) samt Sitzungs-Secret und TOTP-Geheimnis,
  eine leere `zugangsdaten.json`;
* zuletzt die Titelbilder der Katalogseite (`katalogbilder-holen`) — ein
  Fehlschlag ist erlaubt, die Kacheln bleiben dann blass.

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

> *Stage 30 is the largest: the Python venv, the app, the passkey script and
> icons; every tool from `bin/` except the backup tool; the catalogue, followed
> by the catalogue sync so installed servers pick up changes; the address, mod
> and Workshop files; the sudo rule, validated first; the backup exclusion list
> if missing, because `panel.service` opens exactly that file via
> `ReadWritePaths` and systemd refuses to start without it; all units and timers
> (the timers run at once, the automations stay off until switched on); the
> first user; and finally the catalogue artwork, allowed to fail. The initial login
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

**Zertifikat:** `ZERTIFIKAT_WEG` entscheidet, ob Caddy es über Port 80 holt
(`http-01`, Vorgabe) oder über einen TXT-Eintrag in der Zone (`dns-01`, ohne
jeden eingehenden Port). `dns-01` baut beim ersten Mal mit `xcaddy` einen Caddy
mit dem DNS-Modul — das dauert einige Minuten und braucht Go auf der Maschine.
Einzelheiten und die Fallstricke: [06-netz-dns-firewall.md](06-netz-dns-firewall.md).

> *`ZERTIFIKAT_WEG` picks between port 80 and a TXT record; the latter needs no
> inbound port but builds a Caddy with the DNS module on first run.*

### 50 — Sicherung

Borg, Passphrase, Ausschlussliste, beide Zeitpläne — und ein **Probelauf**, der
tatsächlich ausgeführt und dessen Ergebnis angesehen wird. Scheitert er, bricht
die Stufe ab.

Eine nie geprüfte Sicherung ist eine Vermutung, keine Sicherung.

Die Passphrase in `/root/.borg-passphrase` ist der **einzige** Schlüssel zum
Repositorium. Eine Kopie gehört an einen zweiten Ort außerhalb dieses Servers —
geht die Maschine verloren, ist ein verschlüsseltes Repositorium ohne sie
wertlos.

**Mit `BORG_REPO=aus`** entfällt all das: kein `borg`, keine Passphrase, kein
Probelauf, die Timer bleiben abgeschaltet. Eingesetzt werden trotzdem die
Ausschlussliste — `spiel-verwalten` braucht sie bei jeder Installation und
Deinstallation — und die systemd-Einheiten, damit das Einschalten später eine
Zeile in `konfiguration.env` und ein erneuter Lauf dieser Stufe ist. Einzelheiten
in `docs/05-sicherung.md`.

> *Stage 50: Borg, passphrase, exclusion list, both schedules — and a real test
> run whose result is inspected. If it fails, the stage aborts: an unverified
> backup is a guess. The passphrase is the only key to the repository; keep a
> copy off this machine, or an encrypted repository becomes worthless when the
> host is lost. With `BORG_REPO=aus` none of this happens and the timers stay
> off; the exclusion list and the units are still installed, so switching on
> later is one line plus a re-run of this stage.*

### 60 — Die handgepflegten Server

```bash
sudo install/60-spiele.sh                         # zeigt die Liste
sudo install/60-spiele.sh teamspeak enshrouded
```

Verfügbar sind `enshrouded`, `foundry`, `palworld`, `satisfactory`,
`teamspeak` und `windrose`. Erzeugt je Stack frische Passwörter, schreibt die
compose-Datei (`0600 root`) und legt das Datenverzeichnis unter UID 4711 an
(`/srv/dienste/` für TeamSpeak). Ein bereits eingerichteter Stack wird
**übersprungen**, nicht überschrieben — sonst wären beim zweiten Lauf alle
Passwörter neu und niemand käme mehr auf den Server.

**Palworld bekommt dabei seinen Neustart-Zeitgeber** (`palworld-neustart.timer`,
05:30 und 17:30, gegen das Speicherleck des Spiels) — auch dann, wenn der Stack
schon eingerichtet war. Bis #252 setzte ihn keine Stufe ein; die laufende
Maschine hatte ihn von Hand, ein Neuaufbau hätte ihn still verloren.

Gestartet wird von Hand oder über das Panel. Die Beitrittsadressen dieser
Server stehen in `/etc/spiele-adressen.json` (Stufe 30).

> *Stage 60 sets up the six hand-maintained stacks: fresh passwords per stack,
> compose file at 0600 root, data directory as UID 4711 (`/srv/dienste/` for
> TeamSpeak). An already configured stack is skipped, not overwritten — a second
> run would otherwise change every password and lock everyone out. Palworld also
> gets its restart timer, even when the stack already existed; until #252 no
> stage installed it, so a rebuild would have silently lost it. Start by hand or
> from the panel; the join addresses come from `/etc/spiele-adressen.json`.*

### 70 — DNS (optional)

Braucht `/etc/dns-gameserver.conf` mit `ANBIETER=` und einem Token, das **nur**
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

**Den Zeitgeber setzt schon Stufe 25 ein (#195)**, mit derselben Funktion
`dns_ziel_zeitgeber()` aus `install/lib.sh`. Bis dahin tat es nur diese Stufe —
und die läuft in der dokumentierten Einrichtung nicht mit. Mit
`SERVER_IPV4=dynamic` versprach `konfiguration.env` einen Zeitgeber, den niemand
anlegte; alle Stufen meldeten „fertig", und die Adresse veraltete still (auf einer
frischen Maschine gemessen). Optional ist Stufe 70 jetzt nur
noch für die DNS-Namen je Spiel.

> *Stage 25 now installs and switches the timer (#195), through the same
> `dns_ziel_zeitgeber()` in `install/lib.sh`. Before, only this optional stage
> did, so "dynamic" promised a timer the documented install never created.
> Stage 70 remains optional for the per-game names only.*

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
systemctl list-timers --no-pager | grep -E 'sicherung|einrichtung|platzwart|spieler|kanal|autoupdate|palworld|dns-ziel'
curl -sI https://<PANEL_DOMAIN>/ | head -3        # 200 oder 303
curl -sI https://<PANEL_DOMAIN>/status | head -1  # 200, ohne Anmeldung
borg list --short "$BORG_REPO" | tail -5
ufw status verbose
docker ps
spiele-sicherung --selbsttest && platzwart-wache --selbsttest && kanal-verwalten --selbsttest
```

Erwartet: alle Dienste `active`, jeder Zeitgeber mit einem `NEXT`, das Panel und
die Statusseite antworten über HTTPS, im Borg-Repositorium liegen Archive, die
Selbsttests sind grün. Vom Arbeitsrechner aus muss danach
`werkzeuge/abgleich.sh <ziel>` ohne Abweichung durchlaufen. Die vollständige
Prüfliste für einen Neuaufbau steht in [ABNAHME.md](../ABNAHME.md).

> *Post-install checks: all services active, every timer scheduled, panel and
> status page answering over HTTPS, archives in the Borg repository, the
> self-tests green, and afterwards `werkzeuge/abgleich.sh <target>` from the
> workstation reporting no deviation. The full acceptance list for a rebuild is
> `ABNAHME.md`.*

---

## Was danach von Hand bleibt

Die Einrichtung legt bewusst **kein** Geheimnis an, das von außen kommt. Diese
Schritte bleiben — alle optional bis auf den ersten:

| Schritt | Wo | Wozu |
|---|---|---|
| Erstanmeldung, zweiten Faktor einrichten, Wiederherstellungscodes aufheben | Panel, `/einrichten` | ohne das kommt niemand hinein |
| weitere Benutzer mit Rolle anlegen | Panel, **Benutzer** | jeder richtet seinen zweiten Faktor selbst ein |
| `/etc/platzwart-melden.conf` mit zwei Discord-Webhooks anlegen (`0600 root`, Vorlage `etc/platzwart-melden.conf.beispiel`), danach `platzwart-melden --test` | Maschine | Störungen und Mitteilungen nach Discord; ohne Datei meldet nichts |
| Steam-Web-API-Schlüssel eintragen | Panel, **Integrationen** | Workshop-Suche und Größen |
| TeamSpeak-ServerQuery-Zugang und Discord-Bot eintragen, Kanäle einschalten | Panel, **Integrationen** | ein Kanal je Spielserver |
| Auto-Update und Leerlauf je Server einschalten | Panel, Einstellungen des Servers | aus per Voreinstellung |
| Spiele ohne Beitrittspasswort freigeben (Minecraft, TeamSpeak) | Panel, Einstellungen des Servers | ihr Port bleibt sonst zu |
| Kopie von `/root/.borg-passphrase` außer Haus | Passwortmanager, Papier | ohne sie ist das Repositorium wertlos |

> *What remains manual: the setup deliberately creates no secret that comes from
> outside. The first login with second-factor enrolment and keeping the recovery
> codes is mandatory; everything else is optional — further users, the Discord
> webhook file for notifications (test with `platzwart-melden --test`), the
> Steam Web API key, the TeamSpeak and Discord credentials for channels,
> per-server auto-update and idle sleep, releasing games without a join
> password, and an off-machine copy of the Borg passphrase.*

---

## Rückweg

Jede Stufe sichert eine vorhandene Zieldatei vor dem Überschreiben nach
`<datei>.vor-<datum>`. Zurück geht es also datei­weise:

```bash
ls /etc/caddy/Caddyfile.vor-*
cp /etc/caddy/Caddyfile.vor-20260907-101500 /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

Vollständig zurückbauen: **`werkzeuge/rueckbau.sh`**, nicht von Hand.

```bash
werkzeuge/rueckbau.sh gameserver                        # zeigt nur den Plan
werkzeuge/rueckbau.sh gameserver --wirklich             # Dienste und Programme
werkzeuge/rueckbau.sh gameserver --mit-spielstaenden \
                                 --mit-benutzern \
                                 --mit-dns --wirklich   # alles
```

Hier stand früher eine abzutippende Befehlsliste. Sie war abgedriftet: sie
löschte **keine einzige systemd-Einheit**, ließ Caddyfile, fail2ban-Regel,
Cloudflare-Token und die Systembenutzer stehen, und in der Werkzeugliste fehlten
zwei Einträge. Wer sie abtippte, hielt die Maschine danach für sauber. Das
Skript leitet beide Listen aus dem Repositorium ab und kann deshalb nicht mehr
auseinanderlaufen.

Das Borg-Repositorium und `/root/.borg-passphrase` bleiben unangetastet — die
Spielstände sind danach noch da, und ohne die Passphrase wären sie es nicht.
Einzelheiten und die übrigen Ausnahmen in `docs/09-referenz.md`.

> *Full teardown: use `werkzeuge/rueckbau.sh`, not a hand-typed list. What stood
> here before had drifted — it removed no systemd unit at all, left the
> Caddyfile, the fail2ban rule, the Cloudflare token and the system users behind,
> and its tool list was missing two entries, so anyone following it believed the
> machine was clean afterwards. The script derives both lists from the repository
> and cannot drift again. The Borg repository and its passphrase are untouched,
> so the saves survive — and without the passphrase they would not.*
