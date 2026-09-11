# 11 — Neueinrichtung von Grund auf

Diese Anleitung führt von **nichts** — kein Server, keine Domain, keine
Sicherung — bis zu einem laufenden Platzwart mit Panel, Sicherung und den ersten
Spielen. Sie ist für jemanden geschrieben, der das zum ersten Mal macht, und
lässt deshalb keinen Schritt aus, auch nicht die außerhalb der Maschine.

Die Arbeit auf der Maschine selbst übernimmt der **Assistent**
`install/assistent.sh`: Er fragt alles ab, prüft Zugänge und Voraussetzungen,
zeigt eine Zusammenfassung und richtet erst nach der Bestätigung ein. Wer lieber
jeden Schritt einzeln geht, findet die Stufen in
[02-installation.md](02-installation.md) — der Assistent ruft genau diese Stufen
auf, er ersetzt sie nicht (E34).

> *This guide goes from **nothing** — no server, no domain, no backup — to a
> running Platzwart with panel, backups and the first games. It is written for
> someone doing it for the first time and therefore skips no step, including the
> ones outside the machine. The work on the machine itself is done by the
> **assistant** `install/assistent.sh`: it asks for everything, checks access and
> prerequisites, shows a summary and sets up only after confirmation. Anyone who
> prefers to go step by step finds the stages in 02-installation.md — the
> assistant calls exactly those stages and does not replace them (E34).*

---

## Der Weg im Überblick

| Schritt | Wo | Pflicht? | Dauer |
|---|---|---|---|
| [1. Maschine besorgen](#1-die-maschine) | beim Anbieter | ja | Bestellung |
| [2. Domain und DNS-Token](#2-domain-und-dns) | beim DNS-Anbieter | Domain ja, Token empfohlen | Minuten |
| [3. Sicherungsziel vorbereiten](#3-das-sicherungsziel) | zweiter Rechner | empfohlen | Minuten bis eine Stunde |
| [4. Discord-Webhooks anlegen](#4-discord-webhooks) | Discord | nein | Minuten |
| [5. SSH-Schlüssel bereitlegen](#5-ssh-schlüssel) | eigener Rechner | ja | Minuten |
| [6. Repositorium auf die Maschine holen](#6-das-repositorium-holen) | Maschine | ja | Minuten |
| [7. Den Assistenten laufen lassen](#7-der-assistent) | Maschine | ja | Fragen: Minuten; Einrichtung: je nach Leitung |
| [8. Nacharbeiten und Abnahme](#8-nach-der-einrichtung) | Panel, Arbeitsrechner | ja | eine Stunde |

Wer eine **verlorene Maschine** aus der Sicherung zurückholen will, liest
Schritt 1, 2, 5 und 6 und springt dann zu [Wiederaufbau](#9-wiederaufbau-aus-der-sicherung).

> *The path at a glance: get a machine (mandatory), a domain with a DNS token
> (domain mandatory, token recommended), prepare a backup target (recommended),
> Discord webhooks (optional), an SSH key (mandatory), fetch the repository onto
> the machine, run the assistant, then the follow-up work and acceptance. To
> bring back a **lost machine** from backup, read steps 1, 2, 5 and 6 and jump to
> the rebuild section.*

---

## 1. Die Maschine

**Betriebssystem: Debian 12 „bookworm", minimal, frisch.** Gebaut und geprüft ist
alles genau dafür. Der Assistent warnt bei allem anderen und fragt, ob er
trotzdem weitermachen soll — die Antwort sollte „nein" sein, außer man weiß, was
man tut. Ein Desktop, ein vorinstalliertes Panel des Anbieters oder ein
vorhandener Webserver auf Port 80/443 stören.

**Echte virtuelle Maschine (KVM) oder eigene Hardware, kein Container.** Docker
braucht einen eigenen Kernel mit cgroups und Netzfiltern; in einem LXC- oder
OpenVZ-„vServer" läuft es nicht oder nur mit Verrenkungen.

**Größe.** Maßgeblich ist, was gleichzeitig laufen soll:

| Mittel | Untergrenze | Empfehlung | Warum |
|---|---|---|---|
| Arbeitsspeicher | 8 GB | 16–32 GB | jedes Katalogspiel nennt seinen Bedarf (`mem_gb`); gestartet wird nur, wenn danach noch 2 GB frei bleiben. Palworld und Satisfactory brauchen allein 10–12 GB |
| Platte | 50 GB frei | 100 GB und mehr, SSD | Spiele sind groß, und jede Installation hält 10 GB Reserve. Unter 30 GB bricht der Assistent ab |
| Prozessor | 4 Kerne | 6 und mehr, hoher Takt | viele Spielserver rechnen auf einem Kern — Takt schlägt Kernzahl |
| Adresse | eine öffentliche IPv4 | fest | Spieler verbinden sich über IPv4; eine wechselnde Adresse geht auch (`SERVER_IPV4=dynamic`) |

Als Anhalt: Die dokumentierte Maschine hat 6 vCPU, 23,5 GiB Arbeitsspeicher und
200 GB SSD und trägt sieben Server gleichzeitig.

**Die Adresse muss von außen erreichbar sein.** Spieler kommen direkt auf die
Spielports. Hinter einem Anschluss ohne öffentliche IPv4 (CGNAT) sind
Spielserver von außen nicht erreichbar, egal wie man das Zertifikat bekommt.

**Firewall des Anbieters.** Manche Anbieter filtern vor der Maschine. Dort
müssen offen sein: **22/tcp** (SSH, besser nur von der eigenen Adresse),
**80/tcp** und **443/tcp** (Zertifikat und Panel) und die **Spielports** der
Server, die laufen sollen — welche das sind, steht je Spiel im Katalog
([04](04-spielekatalog.md)) und nach der Installation in der Übersicht des
Panels. Auf der Maschine selbst regelt ufw nur SSH, 80 und 443; Spielports gehen
an ufw vorbei (E8).

**Zugang.** Der Anbieter liefert einen Zugang als root — ein Passwort oder, besser,
den eigenen öffentlichen Schlüssel (Schritt 5). Die **Notfallkonsole** des
Anbieters (VNC, „KVM-Konsole", „Rescue") sollte man einmal gefunden haben: Sie
ist der Rückweg, wenn man sich per SSH aussperrt.

> *The machine: Debian 12 "bookworm", minimal and fresh — everything is built and
> tested for exactly that; the assistant warns on anything else. A real virtual
> machine (KVM) or hardware, not a container — Docker needs its own kernel. Size
> depends on what runs at once: RAM from 8 GB, 16–32 recommended (each catalogue
> game states its need, and a game only starts if 2 GB remain free afterwards);
> disk from 50 GB free, 100+ recommended, below 30 GB the assistant aborts; 4+
> cores, 6+ recommended, clock speed beats core count (for scale: the documented
> machine has 6 vCPU, 23.5 GiB and 200 GB SSD and runs seven servers at once); one public IPv4, fixed or changing
> (`SERVER_IPV4=dynamic`). The address must be reachable from outside — behind
> CGNAT game servers cannot be reached, however the certificate is obtained. If
> the provider filters in front of the machine, open 22/tcp (ideally only from
> your address), 80 and 443/tcp, and the game ports of the servers you run (per
> game in the catalogue and later on the panel overview); on the machine ufw only
> handles SSH, 80 and 443, game ports bypass it (E8). Root access comes from the
> provider — password or, better, your public key; find the provider's emergency
> console once, it is the way back if you lock yourself out of SSH.*

---

## 2. Domain und DNS

Platzwart braucht eine **eigene Domain**, deren Zone man verwalten darf. Darin
entstehen:

| Name | Beispiel | Art | Wofür |
|---|---|---|---|
| `DNS_ZIEL` | `gs.beispiel.de` | A-Eintrag | trägt die Adresse der Maschine; auf ihn zeigen die Spielnamen |
| `PANEL_DOMAIN` | `panel.beispiel.de` | A-Eintrag | die Weboberfläche, mit Zertifikat (liegt er außerhalb der Zone, bleibt er Handarbeit) |
| je Spiel | `valheim.beispiel.de` | CNAME auf `DNS_ZIEL` | die Beitrittsadresse |

Ein Umzug der Maschine ändert so zwei Einträge — `DNS_ZIEL` und `PANEL_DOMAIN` —,
nie die der Spiele (E17). **Ohne Wolke:**
Bei Cloudflare muss der Proxy („orange Wolke") für alle diese Namen **aus** sein —
der Proxy kann nur HTTP, ein Spielport dahinter ist tot. Die Werkzeuge legen
Einträge ohne Proxy an.

**Der DNS-Token (empfohlen).** Mit ihm legt die Einrichtung `DNS_ZIEL` und
`PANEL_DOMAIN` selbst an — **vor** dem Zertifikat —, später je Spiel den CNAME,
und bei `SERVER_IPV4=dynamic` führt sie beide A-Einträge nach.

* **Cloudflare** (im Betrieb erprobt): *Mein Profil → API-Tokens → Token
  erstellen*, Vorlage **„Edit zone DNS"**, bei *Zonenressourcen*
  „Einschließen → Bestimmte Zone → `beispiel.de`". **Nie den globalen
  API-Schlüssel** — der darf alles im ganzen Konto.
* **Hetzner DNS** (nach Dokumentation gebaut, noch nicht gegen eine echte Zone
  gelaufen, #60): *DNS Console → API Tokens*.

Den Token nicht irgendwo ablegen; der Assistent fragt ihn **unsichtbar** ab,
prüft ihn beim Anbieter und schreibt ihn nach `/etc/dns-gameserver.conf`
(`0600 root`). Er geht nie als Kommandozeilenargument durch ein Programm.

**Ohne Token** müssen `DNS_ZIEL` und `PANEL_DOMAIN` **vor** der Einrichtung von
Hand angelegt sein und auf die Maschine zeigen. Der Assistent prüft das und
warnt. Schlägt das Zertifikat mehrfach fehl, sperrt Let's Encrypt weitere
Versuche für Stunden.

**Wildcard.** Hat die Zone einen Eintrag `*.beispiel.de`, beantwortet sie jeden
erfundenen Namen — `dig` beweist dann nichts mehr. Der Assistent fragt danach
und trägt dessen Ziel als `FREMD_IPV4` ein; ohne Wildcard steht dort eine
Adresse aus einem Dokumentationsnetz.

> *Platzwart needs its own domain with a zone you control. It holds `DNS_ZIEL`
> (A record carrying the machine's address, target of the game names),
> `PANEL_DOMAIN` (A record for the web UI; outside the zone it stays manual) and
> one CNAME per game pointing to `DNS_ZIEL`, so moving the machine changes two
> records, never the games' (E17). On
> Cloudflare the proxy must be off for all of them — it only speaks HTTP; the
> tools create records unproxied. The DNS token (recommended) lets the setup
> create `DNS_ZIEL` and `PANEL_DOMAIN` itself before the certificate, later the
> per-game CNAMEs, and keep both A records current with `SERVER_IPV4=dynamic`.
> Cloudflare (proven in operation): My Profile → API Tokens → Create Token,
> template "Edit zone DNS", zone resources limited to your zone — never the
> global API key. Hetzner DNS (built from the documentation, not yet run against
> a real zone, #60): DNS Console → API Tokens. The assistant asks for the token
> invisibly, checks it with the provider and writes it to
> `/etc/dns-gameserver.conf` (0600 root); it never travels as an argument.
> Without a token both names must exist and point at the machine before setup;
> the assistant checks and warns — repeated certificate failures make Let's
> Encrypt block retries for hours. If the zone has a wildcard, every invented
> name resolves and `dig` proves nothing; the assistant asks and stores its
> target as `FREMD_IPV4`, otherwise a documentation address.*

---

## 3. Das Sicherungsziel

Borg sichert jeden laufenden Spielstand **alle 15 Minuten** verschlüsselt auf
einen zweiten Rechner — dazu **täglich um 4 Uhr** eine Vollsicherung mit allen
Servern, der Konfiguration, `/etc` und den Panel-Daten ([05](05-sicherung.md)). Ohne Ziel geht es auch
(`BORG_REPO=aus`), dann liegt jeder Spielstand nur auf dieser einen Maschine; das
Panel zeigt das dauerhaft an (E22).

**Was der zweite Rechner braucht:**

1. **Borg 1.x** (1.2 wie Debian 12). Borg 2 ist nicht kompatibel.
2. Einen **eigenen Benutzer**, zum Beispiel `borg`, und ein Verzeichnis, etwa
   `/backup/platzwart`.
3. **Tailscale** (empfohlen, E18): auf beiden Rechnern installiert und im selben
   Tailnet. Dann braucht der Sicherungsserver keinen offenen Port, und das
   Tailnet ist zugleich der Notzugang zur Spielmaschine. Die Adresse im Tailnet
   (`100.x.y.z`) steht in `tailscale ip -4`.
4. Später den **öffentlichen Schlüssel von root** der Spielmaschine in
   `~borg/.ssh/authorized_keys` — eingeschränkt auf Borg:

   ```text
   command="borg serve --restrict-to-path /backup/platzwart",restrict ssh-ed25519 AAAA… platzwart-borg@…
   ```

   Diesen Schlüssel **erzeugt und zeigt der Assistent**; man trägt ihn ein,
   während er wartet, und lässt ihn dann die Verbindung prüfen.

Das Repositorium selbst legt man **nicht** an — das macht Stufe 50
(`borg init --encryption repokey-blake2`), samt der Passphrase in
`/root/.borg-passphrase`. Die Adresse für den Assistenten hat die Form

```text
ssh://borg@100.64.0.10/backup/platzwart/platzwart.borg
```

Jedes andere Borg-Ziel über SSH geht genauso (auch mit Port:
`ssh://benutzer@wirt:23/./pfad`), ebenso ein lokaler Pfad — der schützt aber
nicht gegen den Verlust der Maschine.

> *Borg backs up every running game every 15 minutes, encrypted, to a second
> machine — plus a full run at 4 a.m. daily with all servers, configuration,
> `/etc` and panel data. Without a target
> (`BORG_REPO=aus`) every save lives only on this machine, which the panel shows
> permanently (E22). The second machine needs Borg 1.x (Borg 2 is incompatible),
> its own user such as `borg` with a directory, ideally Tailscale on both
> machines (no open port, and the tailnet doubles as emergency access, E18), and
> later the game machine's root public key in the borg user's authorized_keys,
> restricted with `command="borg serve --restrict-to-path …",restrict`. The
> assistant creates and shows that key, waits while you add it, then checks the
> connection. Do not create the repository yourself — stage 50 does, with the
> passphrase in `/root/.borg-passphrase`. The address looks like
> `ssh://borg@100.64.0.10/backup/platzwart/platzwart.borg`; any SSH borg target
> works (with a port too), as does a local path, which does not protect against
> losing the machine.*

---

## 4. Discord-Webhooks

Platzwart meldet sich selbst in **zwei** Discord-Kanälen: **Störungen**
(Absturz, gescheiterte Sicherung, volle Platte, Server ohne Passwort …) und
**Mitteilungen** (Updates, Entwarnungen). Beides ist optional; ohne meldet
nichts ([08](08-betrieb-und-stoerungen.md)).

Je Kanal: *Kanal bearbeiten → Integrationen → Webhooks → Neuer Webhook → URL
kopieren*. Die beiden Adressen fragt der Assistent unsichtbar ab, schickt auf
Wunsch je eine Testnachricht und schreibt sie nach
`/etc/platzwart-melden.conf` (`0600 root`). **Private Kanäle** nehmen — die
Meldungen nennen Server und Zustände.

Der **Discord-Bot** für einen Kanal je Spielserver und der **TeamSpeak-Zugang**
sind etwas anderes; sie kommen nach der Einrichtung im Panel unter
*Integrationen* dazu ([03](03-panel.md)).

> *Platzwart reports into two Discord channels: faults (crash, failed backup,
> full disk, server without password …) and notices (updates, all-clears). Both
> optional; without them nothing is reported. Per channel: Edit Channel →
> Integrations → Webhooks → New Webhook → Copy URL. The assistant asks for both
> invisibly, optionally sends a test message to each and writes them to
> `/etc/platzwart-melden.conf` (0600 root). Use private channels — messages name
> servers and states. The Discord bot for a channel per game server and the
> TeamSpeak access are separate and are added in the panel under Integrations
> after setup.*

---

## 5. SSH-Schlüssel

Stufe 10 **schaltet die Passwortanmeldung per SSH ab** (Vorgabe, auf einer
öffentlichen IPv4 dringend empfohlen) und lässt SSH nur noch von einer Adresse
herein. Ohne hinterlegten Schlüssel sperrt man sich damit aus. Deshalb vorher:

```bash
# auf dem eigenen Rechner
ssh-keygen -t ed25519            # falls noch keiner da ist
cat ~/.ssh/id_ed25519.pub        # diese EINE Zeile ist der öffentliche Schlüssel
```

Den öffentlichen Schlüssel entweder beim Anbieter für root hinterlegen oder ihn
dem Assistenten geben: Findet er für den Admin-Benutzer und root keinen
Schlüssel und ist die Passwortanmeldung aus, **verlangt** er einen und legt ihn
für den Admin-Benutzer ab, bevor Stufe 10 die Tür schließt. **Nie den privaten
Schlüssel** (`id_ed25519` ohne `.pub`) irgendwo einfügen — der Assistent weist
alles ab, was nicht wie ein öffentlicher Schlüssel aussieht.

> *Stage 10 turns off SSH password login (the default, strongly recommended on a
> public IPv4) and admits SSH from one address only — without a key on file you
> lock yourself out. So first create a key on your own computer
> (`ssh-keygen -t ed25519`) and print the one-line public key. Either put it on
> file for root at the provider or give it to the assistant: if it finds no key
> for the admin user or root while password login is off, it demands one and
> installs it for the admin user before stage 10 closes the door. Never paste the
> private key; the assistant rejects anything that does not look like a public
> key.*

---

## 6. Das Repositorium holen

Auf der neuen Maschine, als root:

```bash
apt-get update && apt-get install -y git tmux
git clone https://github.com/Sparxx947/gameserver.git /root/platzwart
cd /root/platzwart
tmux new -s einrichtung          # empfohlen, siehe unten
```

**tmux**, weil eine abreißende SSH-Verbindung die Einrichtung mittendrin
beendet. In tmux läuft sie weiter; nach dem Wiederverbinden holt
`tmux attach -t einrichtung` die Sitzung zurück. Der Assistent warnt, wenn er per
SSH ohne tmux oder screen gestartet wird.

Der Klon **bleibt** auf der Maschine: Dort entsteht `konfiguration.env`
(steht in `.gitignore`), und von dort laufen spätere Stufen. Für die Pflege vom
Arbeitsrechner aus (`ausrollen.sh`, `abgleich.sh`) braucht der Arbeitsrechner
einen eigenen Klon **und** eine Kopie dieser Datei — siehe
[Schritt 8](#8-nach-der-einrichtung).

> *On the new machine as root: install git and tmux, clone the repository to
> `/root/platzwart`, change into it and start tmux — a dropped SSH connection
> would end the setup midway; in tmux it continues and `tmux attach` brings it
> back. The assistant warns when started over SSH outside tmux or screen. The
> clone stays on the machine: `konfiguration.env` is created there (ignored by
> git) and later stages run from there. Maintaining from a workstation needs its
> own clone and a copy of that file — see step 8.*

---

## 7. Der Assistent

```bash
sudo install/assistent.sh                      # fragen, prüfen, einrichten
sudo install/assistent.sh --nur-konfiguration  # nur konfiguration.env + Zugangsdateien
install/assistent.sh --selbsttest              # die Prüfregeln mit Beispielen
```

**Bedienung.** Eckige Klammern zeigen die Vorgabe; Eingabe übernimmt sie.
Auswahlfragen nehmen eine Nummer, Ja/Nein-Fragen `j` oder `n`, Geheimnisse werden
**ohne Echo** gelesen. Jede Eingabe wird geprüft; eine ungültige wird mit einer
Erklärung neu gefragt. Liegt schon eine `konfiguration.env`, sind ihre Werte die
Vorgaben — ein zweiter Lauf ist also schnell. **Strg+C** bricht jederzeit ab;
bis zur Bestätigung ist dann nichts eingerichtet.

> *Usage: square brackets show the default and Enter accepts it; choices take a
> number, yes/no questions `j` or `n`, secrets are read without echo. Every input
> is validated and an invalid one is asked again with an explanation. An existing
> `konfiguration.env` supplies the defaults, so a second run is quick. Ctrl+C
> aborts at any time; before the confirmation nothing has been set up.*

### Die drei Wege

| Wahl | Wann | Was am Ende passiert |
|---|---|---|
| **1 Neueinrichtung** | eine leere Maschine | Stufen 10–50, die gewählten handgepflegten Server (60), DNS-Namen (70), gewählte Katalogspiele |
| **2 Wiederaufbau** | die alte Maschine ist verloren, die Sicherung nicht | Stufen 10–40, Zurückspielen, Stufe 50 — siehe [Abschnitt 9](#9-wiederaufbau-aus-der-sicherung) |
| **3 nur Konfiguration** | vorbereiten, ohne einzurichten — auch ohne root | schreibt `konfiguration.env` (und als root die Zugangsdateien); sonst nichts |

> *The three paths: 1 new install on an empty machine (stages 10–50, chosen
> hand-maintained servers, DNS names, chosen catalogue games); 2 rebuild when the
> old machine is lost but the backup is not (stages 10–40, restore, stage 50);
> 3 configuration only, to prepare without setting up — also without root; it
> writes `konfiguration.env` (and as root the credential files) and nothing
> else.*

### Die Vorabprüfung

| Prüfung | Folge |
|---|---|
| Debian 12? | sonst Warnung und Rückfrage |
| Arbeitsspeicher, freier Platz, Kerne | unter 8 GB Warnung; unter 50 GB Warnung, unter 30 GB Abbruch |
| schon eingerichtet (`/etc/gameserver-version`)? | Rückfrage; die Stufen sind wiederholbar, Geheimnisse bleiben |
| `curl`, `python3`, `ssh-keygen`, `borg` da? | Angebot, sie sofort zu installieren (Stufe 10 täte es ohnehin, die Prüfungen brauchen sie aber vorher) |
| per SSH ohne tmux/screen? | Warnung und Rückfrage |
| Internet (`deb.debian.org`)? | sonst Warnung — ohne scheitern die Stufen |

> *Pre-checks: Debian 12 (otherwise warning and question); RAM, free disk, cores
> (below 8 GB a warning; below 50 GB a warning, below 30 GB abort); already set
> up (question — stages are repeatable, secrets stay); curl, python3, ssh-keygen,
> borg present (offer to install them now, since the checks need them before
> stage 10 would); over SSH without tmux or screen (warning and question);
> internet reachable (otherwise warning).*

### Die Fragen

| Abschnitt | Frage | Variable | Vorgabe | Geprüft wird |
|---|---|---|---|---|
| Namen | DNS-Zone | `DNS_ZONE` | — | Form einer Domain |
| | Name, der die Adresse trägt | `DNS_ZIEL` | `gs.<zone>` | liegt in der Zone |
| | Name der Weboberfläche | `PANEL_DOMAIN` | `panel.<zone>` | Form; außerhalb der Zone nur mit Warnung |
| | Name der Welt | `WELT_NAME` | `platzwart` | 2–32 Zeichen, Buchstaben, Ziffern, `. _ -`, keine Leerzeichen |
| Adresse | fest (gemessen), fest (andere) oder wechselnd | `SERVER_IPV4` | die gemessene | IPv4-Form; Abweichung von der gemessenen wird angesagt |
| DNS | Anbieter und Token | `/etc/dns-gameserver.conf` | Cloudflare | Token sieht die Zone beim Anbieter; ohne Token: lösen die Namen auf diese Adresse auf? |
| | Wildcard in der Zone? | `FREMD_IPV4` | nein | IPv4-Form |
| Zertifikat | `http-01` oder `dns-01` | `ZERTIFIKAT_WEG` | `http-01` | `dns-01` nur mit Cloudflare-Token |
| Zugang | Benutzer für den Menschen | `ADMIN_USER` | der `sudo`-Aufrufer oder der erste Benutzer | nicht `root`, `panel`, `spiele` |
| | SSH erlauben von: dieser Adresse / einer Adresse oder einem Netz / überall | `ADMIN_IP`, `ADMIN_NETZ` | die Adresse, von der man gerade verbunden ist | IPv4 oder CIDR; **Warnung, wenn die eigene Verbindung danach nicht mehr passt** |
| | Anmeldung per SSH | `SSH_PASSWORT_AUTH` | nur Schlüssel | — |
| | root per SSH | `SSH_ROOT_LOGIN` | nur mit Schlüssel | `yes` nur zusammen mit Passwortanmeldung |
| | öffentlicher Schlüssel | `authorized_keys` des Admins | — | **Pflicht, wenn es sonst keinen Weg hinein gäbe**; nur öffentliche Schlüssel |
| | Passwort des Admins (für `sudo` im Webterminal) | — | anlegen | mindestens 10 Zeichen, zweimal |
| Sicherung | Borg-Ziel oder aus | `BORG_REPO` | ja | Form; Verbindung, Host-Schlüssel, Zustand des Repositoriums (siehe unten) |
| Meldungen | zwei Discord-Webhooks | `/etc/platzwart-melden.conf` | nein | Form; auf Wunsch Testnachricht |
| Server | handgepflegte Server | Stufe 60 | keine | Nummern aus der Liste |
| | Katalogspiele (`?wort` sucht) | `panel-aktion installieren` | keine | Schlüssel im Katalog |
| | DNS-Namen je Server | Stufe 70 | ja, wenn ein Token da ist | — |

> *The questions: zone, the address-carrying name (default `gs.<zone>`, must be
> inside the zone), the panel name (default `panel.<zone>`), the world name
> (2–32 letters, digits, `. _ -`); the address — measured fixed, another fixed or
> changing; DNS provider and token (checked against the zone at the provider;
> without a token the assistant checks whether the names resolve here); wildcard;
> certificate path (`dns-01` only with a Cloudflare token); the human's user (not
> root, panel or spiele); where SSH is allowed from — this address, an address or
> network, or everywhere — with a warning if your current connection would no
> longer fit; password or key-only SSH; root login (`yes` only with passwords);
> a public key, mandatory if there would otherwise be no way in; the admin's
> password for sudo in the web terminal; the backup target or off (connection,
> host key and repository state are checked); two Discord webhooks with an
> optional test; the hand-maintained servers, catalogue games (`?word` searches)
> and per-server DNS names.*

### SSH-Zugang: die drei Möglichkeiten

| Wahl | `ADMIN_IP` (ufw, Port 22) | `ADMIN_NETZ` (fail2ban sperrt nie) |
|---|---|---|
| nur diese Adresse | die Adresse der laufenden Verbindung | dieselbe als `/32` |
| eine Adresse oder ein Netz | die eingegebene | dieselbe (Einzeladresse als `/32`) |
| überall | `0.0.0.0/0` | `127.0.0.1/32` — **nie** `0.0.0.0/0` |

Bei „überall" trägt allein die Anmeldung den Schutz, deshalb gehört „nur
Schlüssel" dazu. fail2ban sperrt dann jeden, der sich dreimal vertut, **auch
einen selbst** — der Rückweg ist das Tailnet oder die Notfallkonsole. Warum
`ADMIN_NETZ` dann eng bleiben muss: [06](06-netz-dns-firewall.md#ssh) (#259).

> *SSH access, three choices: only this address (ADMIN_IP = the current
> connection's address, ADMIN_NETZ the same as /32); an address or network (both
> the entered value); everywhere (ADMIN_IP `0.0.0.0/0`, ADMIN_NETZ `127.0.0.1/32`,
> never `0.0.0.0/0`). With "everywhere" only the login protects, so key-only
> belongs with it; fail2ban then bans anyone failing three times, yourself
> included — the way back is the tailnet or the emergency console. Why ADMIN_NETZ
> must stay narrow: 06, #259.*

### Die Prüfung der Sicherung

Liegt das Ziel im Tailnet (`100.64.0.0/10` oder `*.ts.net`), prüft der Assistent
zuerst Tailscale und bietet an, es zu installieren und anzumelden (der
Anmeldelink erscheint im Terminal). Dann legt er — falls root noch keinen hat —
einen SSH-Schlüssel für root an und **zeigt den öffentlichen Teil**. Nachdem man
ihn beim Sicherungsserver eingetragen hat, spricht er das Repositorium mit
`borg info` an und **merkt sich dabei den Host-Schlüssel des Servers**
(`StrictHostKeyChecking=accept-new`). Das ist nicht Kosmetik: Stufe 50 arbeitet
mit `BatchMode`, und auf einer frischen Maschine scheiterte `borg init` genau an
dem unbekannten Host-Schlüssel.

| Ergebnis | Bedeutung |
|---|---|
| erreichbar, noch kein Repositorium | richtig für eine Neueinrichtung — Stufe 50 legt es an |
| Repositorium vorhanden, lesbar | eine frühere Einrichtung dieser Maschine |
| vorhanden, andere Passphrase | hier liegt die Sicherung einer **anderen** Maschine — gemeint ist vermutlich der Wiederaufbau |
| nicht erreichbar | Schlüssel nicht eingetragen, Tailnet nicht verbunden, Pfad falsch — erneut prüfen oder ohne Bestätigung weiter |

> *Checking the backup: for a tailnet target the assistant first checks Tailscale
> and offers to install and log in. It then creates a root SSH key if none
> exists and shows the public part; once you have added it on the backup server,
> it contacts the repository with `borg info` and records the server's host key
> (`accept-new`) — not cosmetic: stage 50 uses BatchMode, and on a fresh machine
> `borg init` failed on exactly that unknown host key. Results: reachable without
> repository (right for a new install), repository present and readable (an
> earlier setup of this machine), present with a different passphrase (another
> machine's backup — you probably want the rebuild), unreachable (key missing,
> tailnet down, wrong path — check again or continue unconfirmed).*

### Zusammenfassung und Einrichtung

Am Ende zeigt der Assistent **alle Werte** — Geheimnisse nur mit den letzten vier
Zeichen — und fragt: *Jetzt einrichten?* Die Vorgabe ist **nein**. Mit „ja"
geschieht der Reihe nach:

1. `konfiguration.env` wird aus der Vorlage geschrieben: Alle Erklärungen der
   Vorlage bleiben, nur die Wertzeilen tragen die Antworten; eine vorhandene
   Datei wird nach `.vor-<zeit>` gesichert, die neue ist `0600`. Eine
   Gegenprobe prüft, dass jede Variable genau einmal mit dem gewählten Wert
   dasteht.
2. `/etc/dns-gameserver.conf` und `/etc/platzwart-melden.conf`, beide `0600 root`.
3. Der Admin-Benutzer wird angelegt — genau wie Stufe 10 es täte, ohne Passwort,
   in der Gruppe `sudo` —, dann Schlüssel und Passwort (über `chpasswd` von
   stdin, nie in der Prozessliste).
4. `install/einrichten.sh --ja` — die Stufen 10 bis 50 ohne weitere Rückfrage.
5. Stufe 60 für die gewählten handgepflegten Server, auf Wunsch ihr Start.
6. Stufe 70, dann die Katalogspiele über `panel-aktion installieren` — denselben
   Weg, den das Panel nimmt; ihre Passwörter erscheinen nicht im Terminal, sie
   stehen im Panel unter *Zugangsdaten*.
7. Die Schlussseite: die **Erstanmeldung noch einmal** (Stufe 30 zeigt sie genau
   einmal, mitten in einer langen Ausgabe), Adressen, was noch zu tun ist, und
   auf Wunsch einmal die Borg-Passphrase zum Abschreiben.

Die ganze Ausgabe steht zusätzlich in `/root/platzwart-einrichtung-<zeit>.log`
(`0600`) — **geschwärzt**: Erstpasswort und Spielpasswörter werden schon beim
Schreiben ersetzt.

**Scheitert eine Stufe,** hält der Assistent an und nennt sie. Ursache beheben,
den Assistenten erneut starten: Die Antworten stehen als Vorgaben bereit, und
jede Stufe ist wiederholbar — vorhandene Dateien werden gesichert, Geheimnisse
(Panel-Zugang, Passphrase, Spielpasswörter) bleiben.

> *Summary and setup: the assistant shows every value (secrets only by their last
> four characters) and asks "set up now?", defaulting to no. With yes, in order:
> `konfiguration.env` is written from the template — all explanations kept, only
> value lines carry the answers, an existing file backed up to `.vor-<time>`, the
> new one 0600, and a cross-check that every variable appears exactly once with
> the chosen value; the two credential files (0600 root); the admin user is
> created exactly as stage 10 would, then key and password (via chpasswd on
> stdin, never in the process list); `install/einrichten.sh --ja` runs stages
> 10–50; stage 60 for the chosen hand-maintained servers and optionally their
> start; stage 70, then the catalogue games through `panel-aktion installieren`,
> the same path the panel takes — their passwords stay in the panel under
> Credentials; finally the initial login once more (stage 30 prints it once, in
> the middle of long output), addresses, what is left to do, and optionally the
> Borg passphrase for copying. All output also goes to a 0600 log file under
> /root, redacted as it is written. If a stage fails the assistant stops and
> names it; fix the cause and run it again — answers are the defaults and every
> stage is repeatable.*

### Was der Assistent vorher schon tut

„Bis zur Bestätigung wird nichts eingerichtet" heißt: keine Konfiguration, kein
Benutzer, keine Stufe. Was die **Prüfungen** brauchen, geschieht aber vorher,
damit sie überhaupt prüfen können:

* auf Nachfrage: fehlende Werkzeuge (`curl`, `python3`, `openssh-client`,
  `borgbackup`) installieren, Tailscale installieren und anmelden;
* ohne Nachfrage: einen SSH-Schlüssel für root anlegen, wenn keiner da ist, und
  den Host-Schlüssel des Sicherungsservers in `/root/.ssh/known_hosts` merken.

Nichts davon ist schädlich, wenn man danach abbricht; alles davon hätte Stufe 10
bzw. 50 ohnehin getan oder gebraucht.

> *What the assistant does beforehand: "nothing is set up before confirmation"
> means no configuration, no user, no stage. What the checks need happens
> earlier: on request, installing missing tools and Tailscale; without asking,
> creating a root SSH key if none exists and recording the backup server's host
> key. None of it harms an abort, and all of it stage 10 or 50 would have done or
> needed anyway.*

### Ohne Terminal, und zum Vorbereiten

Die Fragen kommen von der Standardeingabe; ein Lauf lässt sich deshalb auch mit
vorbereiteten Antworten füttern (so ist er getestet). Das ist **keine**
zugesicherte Schnittstelle — die Reihenfolge der Fragen hängt von den Antworten
ab. Endet die Eingabe mitten in den Fragen, bricht der Assistent ab, statt eine
Frage endlos zu wiederholen.

`--nur-konfiguration` schreibt nur `konfiguration.env` — auch als normaler
Benutzer, etwa auf dem Arbeitsrechner, um die Datei vorzubereiten. Schlüssel- und
Sicherungsprüfung entfallen dann; sie folgen beim eigentlichen Lauf auf der
Maschine. `--selbsttest` prüft die Regeln des Assistenten (Adressen, Netze,
Namen, Schlüssel, Archivwahl, das Schreiben der Konfiguration) mit festen
Beispielen, ohne etwas anzufassen.

> *Answers come from standard input, so a run can be fed prepared answers (that
> is how it is tested) — not a guaranteed interface, since the order of questions
> depends on the answers. If input ends mid-way the assistant aborts rather than
> repeating a question forever. `--nur-konfiguration` writes only
> `konfiguration.env`, also as a normal user, e.g. on the workstation; key and
> backup checks are skipped and follow on the real run. `--selbsttest` checks
> the assistant's rules — addresses, networks, names, keys, archive choice,
> writing the configuration — with fixed examples, touching nothing.*

---

## 8. Nach der Einrichtung

**Sofort:**

1. **Anmelden** unter `https://<PANEL_DOMAIN>/` mit dem Erstpasswort, den
   **zweiten Faktor** per QR-Code einrichten (jede TOTP-App), die **zehn
   Wiederherstellungscodes** sicher aufheben — sie erscheinen genau einmal.
   Später lässt sich ein **Passkey** hinzufügen (Fingerabdruck statt Code).
2. **Passphrase außer Haus:** `/root/.borg-passphrase` in einen Passwortmanager
   oder auf Papier. Ohne sie ist jede Sicherung wertlos, wenn die Maschine
   verloren geht — und genau dafür gibt es sie.
3. **Hoster-Firewall** (falls vorhanden): die Spielports der laufenden Server
   öffnen.

**Im Panel, nach Bedarf** ([03](03-panel.md)):

* *Benutzer*: weitere Menschen mit Rolle (`bedienen`, `verwalten`, `admin`);
  jeder richtet seinen zweiten Faktor selbst ein.
* *Integrationen*: Steam-Web-API-Schlüssel (Workshop-Suche), TeamSpeak-
  ServerQuery-Zugang und Discord-Bot, dann die Kanäle je Server einschalten.
* je Server: **Auto-Update** und **Leerlauf** (aus per Voreinstellung); Spiele
  ohne Beitrittspasswort (Minecraft, TeamSpeak) bewusst **freigeben**, sonst
  bleibt ihr Port zu (E26).
* `platzwart-melden --test` auf der Maschine, wenn Webhooks eingetragen sind.

**Der Arbeitsrechner** — für Pflege und Abgleich ([02](02-installation.md)):

```bash
git clone https://github.com/Sparxx947/gameserver.git && cd gameserver
scp root@<maschine>:/root/platzwart/konfiguration.env .   # bleibt lokal, nie einchecken
chmod 600 konfiguration.env
ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit
werkzeuge/abgleich.sh <ssh-ziel>                          # muss 0 Abweichungen melden
```

**Die Abnahme.** [ABNAHME.md](../ABNAHME.md) ist die vollständige Prüfliste —
Dienste, Zertifikat, Zeitgeber, ufw, Statusseite, Erstanmeldung, eine
Testinstallation, Sicherung und Probe. Erst wenn sie durch ist, gilt die
Maschine als eingerichtet.

> *Right away: log in with the initial password, enrol the second factor by QR
> code, keep the ten recovery codes (shown once), optionally add a passkey later;
> put a copy of `/root/.borg-passphrase` off the machine; open the game ports in
> the provider's firewall if there is one. In the panel as needed: further users
> with roles, the integrations (Steam key, TeamSpeak, Discord bot, then channels
> per server), per server auto-update and idle sleep, and a deliberate release
> for games without a join password (E26); `platzwart-melden --test` if webhooks
> are set. The workstation: clone, copy `konfiguration.env` over (stays local,
> never committed), wire in the pre-commit hook, run the comparison — zero
> deviations. Acceptance: ABNAHME.md is the full checklist; only when it passes is
> the machine set up.*

---

## 9. Wiederaufbau aus der Sicherung

Die Maschine ist weg — abgebrannt, gekündigt, kaputtkonfiguriert —, die
Sicherung nicht. **Weg 2** des Assistenten stellt den letzten Stand auf einer
frischen Debian-12-Maschine wieder her.

**Was man dafür braucht:**

* die **Adresse des Repositoriums** und die **Passphrase** (deshalb die Kopie
  außer Haus);
* Zugang zum Sicherungsserver für den **neuen** root-Schlüssel — der Assistent
  zeigt ihn, er muss dort eingetragen werden, bevor die Prüfung gelingt;
* dieselbe `PANEL_DOMAIN` wie vorher, wenn **Passkeys** weiter gelten sollen —
  sie sind an diesen Namen gebunden.

**Was zurückkommt:**

| Aus dem Archiv | Inhalt |
|---|---|
| `config-…` | alle `/opt/stacks/<server>/compose.yaml` mit ihren Passwörtern, `panel.json` der Katalogserver (Adressen, Freigaben, zurückgehaltene Ports) |
| `panel-…` | Benutzer mit Passwort-Hashes, zweiten Faktoren, Passkeys, Wiederherstellungscodes; Protokoll; Integrationen; Zugangsdaten |
| `<server>-…` | der Spielstand jedes Servers |
| `etc-…` | auf Rückfrage: DNS-Token und Discord-Webhooks — man muss sie nicht neu besorgen |

**Was nicht zurückkommt:** die Listen für **Auto-Update und Leerlauf** (sie
liegen unter `/var/lib` und stehen in keinem Archiv) — je Server im Panel wieder
einschalten; und `konfiguration.env` selbst, deren Werte der Assistent neu
abfragt.

**Stand:** Spielstände sind höchstens eine Viertelstunde alt, Konfiguration und
Panel-Daten vom letzten Vollauf um 4 Uhr — was danach im Panel geändert wurde
(ein neuer Benutzer, ein installiertes Spiel), fehlt; der Spielstand eines
solchen Spiels kommt dann ohne seine compose-Datei nicht zurück.

**Welches Archiv:** je Präfix das **neueste, das älter ist als der Start des
Assistenten**. Das „älter als" ist Absicht: Jede Einrichtung legt beim ersten
Sicherungslauf frische Archive an, und die wären sonst die „neuesten".

**Die Reihenfolge**, und warum:

1. Stufen **10–40** — Grundsystem, Docker, DNS, Panel, Caddy. Die Passphrase
   aus der Eingabe liegt schon in `/root/.borg-passphrase`.
2. **Zurückspielen**, jeweils von `/` aus (die Archive tragen absolute Pfade):
   `config`, dann `panel` (bei angehaltenem Panel), dann jeder Spielstand —
   dieser mit `--numeric-ids`, weil Borg Eigentümer sonst nach Namen herstellt
   und ein gleichnamiger Benutzer mit anderer UID auf der neuen Maschine die Welt
   übernähme; Container mit fester UID könnten dann nicht mehr schreiben.
3. `spiel-verwalten katalog-abgleich` — gleicht die zurückgekommenen
   Katalogserver an den Katalog dieses Klons an (Sicherungsausschlüsse,
   fehlende Variablen).
4. Stufe **60** für die handgepflegten Server — ihre compose-Dateien sind schon da,
   die Stufe setzt nur noch ein, was außerhalb liegt (etwa den
   Palworld-Neustart-Zeitgeber).
5. Stufe **50** — **erst jetzt**: Ihr Probelauf sicherte sonst eine leere
   Maschine, und diese fast leeren Archive lösten die Einbruchsprüfung aus und
   lägen beim nächsten Wiederaufbau obenauf. So sichert er gleich den
   zurückgeholten Stand.
6. Auf Wunsch die Server starten, dann Stufe 70.

Danach gilt: anmelden **wie vor dem Verlust** (das Erstpasswort aus Stufe 30 ist
durch die zurückgespielten Benutzer überholt), prüfen, ob jeder Server seine Welt
hat, Auto-Update und Leerlauf einschalten, DNS prüfen (bei fester neuer Adresse
den A-Eintrag), vom Arbeitsrechner abgleichen. Einzelne Spiele von Hand
zurückholen: [05](05-sicherung.md).

> *Rebuild from backup: the machine is gone, the backup is not — path 2 restores
> the last state on a fresh Debian 12 machine. You need the repository address
> and passphrase, access to the backup server to add the new root key, and the
> same `PANEL_DOMAIN` if passkeys are to keep working. Coming back: `config-…`
> (all compose files with passwords, catalogue servers' panel.json), `panel-…`
> (users with hashes, second factors, passkeys, recovery codes, audit log,
> integrations, credentials), each server's save, and on request DNS token and
> Discord webhooks from `etc-…`. Not coming back: the auto-update and idle lists
> (in /var/lib, in no archive) and `konfiguration.env`, which the assistant asks
> for again. Saves are at most a quarter of an hour old, configuration and panel
> data from the last full run at 4 a.m. — changes made in the panel after that (a
> new user, a newly installed game) are missing, and such a game's save does not
> come back without its compose file. Per prefix it takes the newest archive
> older than the assistant's start — every setup creates fresh archives on its first backup run, which
> would otherwise be "newest". Order: stages 10–40; restore from `/` (config,
> panel with the panel stopped, each save — the saves with `--numeric-ids`, since
> by name a same-named user with another uid would take over the world); `katalog-abgleich`; stage 60 for the
> hand-maintained servers (only what lies outside their compose files, such as
> the Palworld restart timer); stage 50 only now — its test run would otherwise
> back up an empty machine, tripping the drop check and sitting on top at the
> next rebuild; then optionally start the servers and stage 70. Afterwards log
> in as before the loss, check each world, re-enable auto-update and idle, check
> DNS, compare from the workstation. Restoring single games by hand: 05.*

---

## 10. Wenn etwas schiefgeht

| Bild | Ursache | Weg |
|---|---|---|
| „Eingabe beendet — abgebrochen" | die Standardeingabe ist zu (Pipe zu Ende, Terminal weg) | im Terminal neu starten; nichts war eingerichtet |
| „Nicht erreichbar" bei der Sicherung | root-Schlüssel nicht eingetragen, Tailnet nicht verbunden, Pfad falsch | Schlüssel eintragen, `tailscale status`, „noch einmal prüfen" |
| „andere Passphrase" bei der Neueinrichtung | im Ziel liegt eine fremde Sicherung | anderes Verzeichnis nehmen — oder Weg 2 |
| Token „sieht die Zone nicht" | Token für eine andere Zone, zu wenig Rechte, Tippfehler | Token neu anlegen, Zonenressource prüfen |
| Stufe 40: Zertifikat scheitert | Name zeigt nicht auf die Maschine, Port 80 zu (auch beim Anbieter) | DNS und Firewall prüfen, **warten** (Let's Encrypt sperrt nach Fehlschlägen), dann `sudo install/einrichten.sh 40-caddy-ttyd` — oder `ZERTIFIKAT_WEG=dns-01` |
| Stufe 50 scheitert | Sicherungsziel nicht erreichbar | wie oben, dann `sudo install/einrichten.sh 50-sicherung` |
| per SSH ausgesperrt | Adresse gewechselt, Schlüssel fehlt, fail2ban | Tailnet oder Notfallkonsole; `ufw status`, `fail2ban-client status sshd` |
| `sudo` im Webterminal will ein Passwort, das es nicht gibt | Admin ohne Passwort angelegt | als root `passwd <admin>` |
| Katalogspiel „angelegt, aber NICHT gestartet" | zu wenig freier Arbeitsspeicher | andere Server anhalten, im Panel starten |
| ein Spiel ist von außen nicht erreichbar | Port beim Anbieter zu, Passwort noch nicht bestätigt (E26) | Übersicht im Panel, [08](08-betrieb-und-stoerungen.md) |

Alles, was eine Stufe ersetzt hat, liegt daneben als `<datei>.vor-<datum>`; den
vollständigen Rückbau beschreibt [02](02-installation.md#rückweg).

> *When things go wrong: "input ended" — standard input closed, restart in a
> terminal, nothing was set up; backup unreachable — add the root key, check the
> tailnet and path, check again; "different passphrase" on a new install — a
> foreign backup in the target, use another directory or path 2; token cannot see
> the zone — wrong zone, too few rights or a typo; stage 40 certificate failure —
> name not pointing here or port 80 closed (also at the provider), fix, wait out
> Let's Encrypt's block, rerun stage 40 or switch to dns-01; stage 50 failure —
> as above, rerun stage 50; locked out of SSH — tailnet or emergency console,
> check ufw and fail2ban; sudo in the web terminal wants a password that does not
> exist — set one with `passwd` as root; catalogue game "created but NOT started"
> — not enough free RAM; a game unreachable from outside — port closed at the
> provider or password not yet confirmed (E26). Everything a stage replaced sits
> next to it as `.vor-<date>`; the full teardown is in 02.*

---

## Was nicht getestet ist

Ehrlich festgehalten: Die Fragen, Prüfregeln, das Schreiben der Konfiguration,
das Anlegen von Benutzer, Schlüssel und Passwort, die geschwärzte Protokolldatei
und der ganze Wiederaufbau-Pfad bis zum Zurückspielen (mit einem echten
Borg-Repositorium, falscher und richtiger Passphrase und einem „Probelauf"-Archiv,
das nicht gewählt werden darf) sind in einem frischen Debian-12-Container
durchgelaufen — die Stufen selbst dort als Attrappe, weil ein Container weder
systemd noch Docker hat. **Ein vollständiger Lauf auf einer echten, frischen
Maschine steht noch aus**; die Stufen, die er aufruft, sind dieselben, mit denen
die laufende Maschine gebaut wurde.

> *What is not tested, stated plainly: questions, validation rules, writing the
> configuration, creating user, key and password, the redacted log file and the
> whole rebuild path up to the restore (with a real Borg repository, a wrong and
> a right passphrase and a "test run" archive that must not be chosen) ran in a
> fresh Debian 12 container — the stages there as stand-ins, since a container
> has neither systemd nor Docker. A complete run on a real fresh machine is still
> outstanding; the stages it calls are the same ones the running machine was
> built with.*
