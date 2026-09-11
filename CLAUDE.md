# CLAUDE.md — Arbeitsanweisung für dieses Repositorium

Diese Datei wird von Claude Code automatisch gelesen und gilt für jede Arbeit
hier. Sie ist zugleich die Einarbeitung für Menschen.

> *Read automatically by Claude Code and binding for all work in this repository.
> It doubles as the onboarding document for humans.*

---

## Worum es geht

Dieses Repositorium beschreibt **eine konkrete, laufende Maschine** — einen
selbst gehosteten Spieleserver auf Debian 12 — und enthält alles, um sie von
Grund auf neu aufzubauen. Es ist kein allgemeines Werkzeug und will keins sein.

Daraus folgt die wichtigste Eigenschaft: **Das Repositorium ist eine Beschreibung
des Ist-Zustands, keine Wunschliste.** Was hier steht, muss auf der Maschine
genauso stehen. Weicht beides voneinander ab, ist die Dokumentation schlimmer als
keine — denn man handelt danach.

> *This repository describes one concrete, running machine and holds everything
> to rebuild it. It is not a general-purpose tool. Consequently: it documents
> what **is**, not what should be. Drift makes the documentation worse than
> nothing, because people act on it.*

Der Einstieg zum Verständnis ist `docs/01-architektur.md`, danach
`docs/10-entscheidungen.md` — dort steht zu jedem ungewöhnlichen Detail, welche
naheliegende Lösung verworfen wurde und warum.

---

## Sprache

* **Antworten, Commit-Nachrichten, Kommentare im Code: Deutsch.**
* **Issues und Pull Requests: Englisch.**
* **Dokumentation: zweisprachig.** Deutscher Abschnitt, danach ein englischer
  Absatz in Kursiv, der denselben Inhalt trägt — nicht eine Zusammenfassung.
* Umlaute in Skripten und Dateien auf dem Server: **umschrieben** (`ae`, `oe`,
  `ue`, `ss`). Die Maschine läuft nicht durchgängig mit UTF-8-Locale. In
  Markdown-Dateien sind Umlaute in Ordnung.

> *German for answers, commits and code comments; English for issues and pull
> requests; documentation bilingual (German section, then an italic English
> paragraph carrying the same content, not a summary). Transliterate umlauts in
> scripts and files deployed to the server — the machine does not run a UTF-8
> locale throughout. Markdown files may use umlauts.*

---

## Ablauf jeder Änderung

1. **GitHub-Issue** anlegen (englisch), das das Problem beschreibt — nicht die
   Lösung.
2. **Zweig** davon: `git checkout -b fix/<kurzname>`.
3. Arbeiten, **Dokumentation mitliefern** (siehe unten).
4. `werkzeuge/vollstaendigkeit.sh` muss grün sein.
5. **Pull Request** mit `Fixes #<nr>` im Text.
6. Mergen, Zweig löschen.

**Niemals direkt auf `main` pushen.** Auch nicht „nur schnell".

**Keine Werkzeug-Attribution in Commit-Nachrichten** — kein `Co-Authored-By:
Claude …`, kein „Generated with …". GitHub baut daraus seine
Contributor-Liste, und entfernen ließe sich das nur durch Umschreiben der ganzen
Historie. Ein lokaler `commit-msg`-Haken in der Arbeitskopie weist solche
Nachrichten ab; er wird nicht mitgeklont, die Regel gilt trotzdem. In
PR-Beschreibungen ist ein Hinweis erlaubt.

> *Every change: English issue describing the problem (not the solution), branch,
> work with documentation, green completeness check, pull request with
> `Fixes #<n>`, merge, delete branch. Never push to `main` directly. No tool
> attribution in commit messages — no `Co-Authored-By: Claude`, no "Generated
> with": GitHub builds its contributor list from them, and removing them would
> mean rewriting the entire history. A local commit-msg hook in the working copy
> rejects such messages; it is not cloned, but the rule applies regardless. A
> note in pull request descriptions is fine.*

---

## Dokumentation ist Pflicht, nicht Kür

Kein Pull Request ohne die passende Dokumentation. Bleibt etwas bewusst
undokumentiert, gehört der Grund in den PR-Text.

Im Quelltext wird **nicht kommentiert, was der Code tut**, sondern **warum er so
ist**: welcher Fehlschlag ihn erzwungen hat, was man naheliegenderweise
stattdessen täte und warum das nicht geht. Diese Kommentare sind das, was später
Zeit spart. Beispiel aus `install/lib.sh`:

```bash
  verz.chmod(0o750)
  # chmod NACH mkdir: der mode-Parameter wird von der umask beschnitten. Mit
  # umask 077 entstand aus mkdir(mode=0o750) ein 0700, die Oberflaeche konnte
  # panel.json nicht lesen, und in der Uebersicht fehlte wortlos die
  # Beitrittsadresse (gemessen 2026-09-06).
```

> *No pull request without matching documentation; if something is deliberately
> left undocumented, the reason belongs in the PR text. Comments explain **why**

**Das Wiki mitpflegen.** Das
[Wiki](https://github.com/Sparxx947/gameserver/wiki) (eigenes Repositorium
`gameserver.wiki`) beschreibt jede Funktion für Mitspieler, Betreiber und
Mitentwickler — zweisprachig wie `docs/`, ohne Standortdaten, weil es öffentlich
ist. Maßgeblich bleibt `docs/`; wer eine Funktion ändert, die dort beschrieben ist,
passt die Wiki-Seite im selben Zug an. Ein Wiki kennt keine Pull Requests: Die
Änderung geht direkt auf `master` des Wiki-Repositoriums (`GIT_PUSH_MAIN_OK=1`),
das Issue im Hauptrepositorium bleibt Pflicht.

> *Keep the wiki in step: the wiki (its own repository) describes every function
> for players, operators and contributors — bilingual like `docs/`, without site
> data, since it is public. `docs/` stays authoritative; whoever changes a function
> described there updates the wiki page in the same go. A wiki has no pull
> requests, so changes go straight to the wiki repository's master
> (`GIT_PUSH_MAIN_OK=1`); the issue in the main repository is still required.*
> the code is the way it is — which failure forced it, what one would naively do
> instead and why that does not work — never what it does.*

---

## Die Grenzen, die nicht verhandelbar sind

Diese fünf Punkte tragen den ganzen Sicherheitsentwurf. Wer einen davon
aufweicht, macht aus einem abgesicherten System ein offenes. Begründung in
`docs/07-sicherheitsentwurf.md`.

1. **Die Weboberfläche bekommt niemals Zugriff auf `docker.sock`** und niemand
   kommt in die Gruppe `docker`. Wer mit dem Socket reden darf, ist root
   (`docker run -v /:/host`). Neue Fähigkeiten der Oberfläche gehen **immer**
   über `panel-aktion`.
2. **`panel-aktion` prüft jeden Parameter gegen eine Positivliste.** Kein `eval`,
   keine Shell-Expansion von Eingaben. Eine neue Aktion bekommt eine eigene
   Prüfung, nicht eine gelockerte bestehende.
3. **Bearbeitet werden einzelne FELDER, nie die compose.yaml als Ganzes.** Wer
   dort ein Volume `/:/host` eintragen kann, ist root.
4. **Verwaltungsports binden auf `127.0.0.1`.** RCON, Webkonsolen, ServerQuery,
   Telnet, API — dreiteilige Portform im Katalog: `127.0.0.1:8080:8080/tcp`.
   Geprüft von `werkzeuge/katalog-ports.py` (Teil von `vollstaendigkeit.sh`).
   Bis #163 stand die Regel nur als Kopie im Generator, verglich dort ihr
   Namensmuster mit der Portnummer und griff nie — die Serverkonsole von FiveM
   stand offen.
5. **Ein Spielport wird erst veröffentlicht, wenn das Beitrittspasswort steht.**
   Das Eintragen des Ports ist der Schritt, der den Server nach außen öffnet;
   er gehört ans **Ende** der Einrichtung, nie an den Anfang. `port-ermitteln`
   trägt deshalb nur ein, wenn `einrichtung_offen` nicht mehr gesetzt ist, und
   einzeln aufgerufen übergibt es per `execv` an `spiel-einrichtung` — es soll
   genau **einen** Weg geben, der Ports veröffentlicht. Wer einen zweiten baut,
   baut die Lücke von E23 nach.

   **Das gilt auch für Katalogports.** Bis #156 schrieb die Installation sie
   schon beim Anlegen in die compose.yaml — ein zweiter Weg, den dieser Absatz
   nicht erwähnte und niemand bemerkte. Jetzt hält `spiel-verwalten` die
   öffentlichen Katalogports in `panel.json` unter `ports_ausstehend` zurück,
   und `port-ermitteln` trägt sie ein, nachdem das Passwort steht. Zwei
   Ausnahmen ohne Fenster: ein Passwort über die Umgebung (steht in der
   compose.yaml, bevor der Server zum ersten Mal startet) und Verwaltungsports
   auf `127.0.0.1` (öffnen nichts nach außen).

   **Beim Passwort als Startparameter (`params`) entscheidet der laufende
   Server**, nicht die Einrichtung: Erst wenn er per A2S „Passwort nötig“
   meldet, geht der Port auf (E27). Eine mitgelieferte `server.cfg` kann den
   Parameter überschreiben — „gesetzt“ ist dort kein Beweis.

   **Und nie „nach Ablauf trotzdem“:** Findet die Einrichtung in sechs Stunden
   kein Passwort und bestätigt der Server keins, bleibt der Port zu (E26,
   Jens am 2026-09-11: „Ein Server ohne Passwort darf nicht automatisch ans
   Netz gehen.“).

> *Five non-negotiables carrying the whole security design: the panel never gets
> the Docker socket and nobody joins the `docker` group; `panel-aktion` validates
> every parameter against an allow-list with no eval; only individual fields are
> editable, never the compose file as a whole; management ports bind to
> localhost; and a game port is published only once the join password is in
> place — one code path, at the end of setup, never at the start.*

---

## Vor jedem Commit

```bash
werkzeuge/vollstaendigkeit.sh      # muss grün sein
```

Prüft: Existiert jede von `install/` referenzierte Datei **und wird sie von git
verfolgt**? Parsen alle Skripte? Steckt irgendwo ein Geheimnis? Ist jeder
`@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt? Dazu Katalogports,
Kategorien und Titelbilder, Doku gegen Katalog und Routen, die Vergleichsliste
von `abgleich.sh`, typische Fehler in `app.py` — und ob jeder Abschnitt der
Dokumentation seinen englischen Absatz hat. Die vollständige Liste steht in
`docs/09-referenz.md`.

Als automatische Bremse:

```bash
ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit
```

Bewusst als Symlink und **nicht** über `git config core.hooksPath` — das ersetzt
das gesamte Hook-Verzeichnis und schaltet vorhandene Haken ab.

> *Run the completeness check before every commit — it checks files, syntax,
> secrets and placeholders, and also catalogue ports, categories and artwork,
> docs against catalogue and routes, the comparison list, typical `app.py`
> mistakes and whether every documentation section has its English paragraph.
> Wire it in as a symlinked pre-commit hook, never via `core.hooksPath`, which
> would replace the entire hooks directory.*

---

## Vor und nach jeder Arbeit an einer laufenden Maschine

```bash
werkzeuge/abgleich.sh gameserver                      # vergleichen
werkzeuge/ausrollen.sh gameserver bin/panel-aktion    # ausrollen
```

Vergleicht **jede Datei, die `install/` ausrollt**, und muss `abweichend: 0`
melden. Keine Zahl hier, weil eine Zahl lautlos altert: Die Liste in
`abgleich.sh` wird von Hand geführt und wuchs zweimal nicht mit — neun
ausgerollte Dateien wurden nie verglichen, während der Lauf `abweichend: 0`
meldete. `vollstaendigkeit.sh` prüft seit dem 2026-09-10, dass die Liste
vollständig ist. Weicht etwas ab, ist **zuerst zu
klären, welche Seite recht hat** — nicht blind in eine Richtung angleichen.

**Voraussetzung:** eine ausgefüllte `konfiguration.env` (Vorlage:
`konfiguration.env.beispiel`). Sie enthält Domains, Adressen und Netze, steht in
`.gitignore` und wird **niemals** eingecheckt.

> *Run the comparison before and after touching a live machine; it must report
> zero deviations. If something differs, first work out which side is right —
> do not blindly sync in one direction. Requires a filled-in `konfiguration.env`,
> which is never committed.*

---

## Was niemals ins Repositorium gehört

* **Geheimnisse jeder Art.** Passwörter, Hashes, TOTP-Geheimnisse, das
  Sitzungs-Secret, die Borg-Passphrase, das Cloudflare-Token. Alle entstehen bei
  der Einrichtung auf der Zielmaschine.
* **Standortdaten.** Domains, IP-Adressen, Netze, Benutzernamen — dafür gibt es
  `@@PLATZHALTER@@` und `konfiguration.env`. Auch nicht als Beispiel in einem
  Kommentar oder einer Messung: `vollstaendigkeit.sh` sucht die Werte der
  eigenen `konfiguration.env` und die Wörter aus `.standortdaten` (lokal, nie
  eingecheckt — dort Kontonamen und Ähnliches eintragen) in jeder verfolgten
  Datei. Ein echter Kontoname kam so schon einmal zurück, nachdem er entfernt
  worden war.
* **Bilder aus Steam.** Die Kopfgrafiken sind Werke Dritter und werden zur
  Laufzeit geladen. Nur die selbst erzeugten Symbole liegen hier.
* **Spielstände.** Die gehören in die Sicherung.

**Geheimnisse gehen nie als Kommandozeilenargument** durch ein Werkzeug —
Argumente stehen für jeden Benutzer der Maschine in der Prozessliste. Sie kommen
über stdin (`panel-aktion kanaele pruefen`, `compose-setzen`,
`konfig-datei-schreiben`) oder aus einer `0600`-Datei (`dns-abnahme.sh
--token-datei`).

**Nach dem ersten Push an der Quelle gegenprüfen**, nicht lokal:

```bash
gh api repos/<owner>/<repo>/git/trees/main?recursive=1 --jq '.tree[].path'
```

Genau so wurde gefunden, dass die Regel `*.local` die Datei
`etc/fail2ban/jail.local` verschluckt hatte — lokal lag sie sichtbar da, sie war
nur nicht verfolgt.

> *Never commit secrets, site-specific values, Steam artwork or save games — not
> even as an example in a comment or a measurement: the completeness check
> searches every tracked file for the values of the local `konfiguration.env`
> and the words in the local, never committed `.standortdaten` (put account
> names there); a real account name once came back after being removed.
> Secrets never travel as a command-line argument — arguments are visible to
> every user in the process list — but on stdin or from a 0600 file. After
> the first push, verify at the source rather than locally: that is how a
> `*.local` rule swallowing `etc/fail2ban/jail.local` was caught — the file sat
> visibly in the working tree, it just was not tracked.*

---

## Testen

**Ein Trockenlauf beweist nichts.** Er lässt genau die riskanten Schritte aus.
`katalog-vorpruefung` fischt billige Fehler heraus, ersetzt aber keinen echten
Durchlauf.

**Am regulären Einstiegspunkt reproduzieren**, nicht an einer nachgebauten
Abkürzung. Eine Installation wird mit `panel-aktion installieren <schluessel>`
getestet, so wie das Panel es tut — nicht mit einem selbst zusammengesetzten
`docker compose up`.

**Der OK-Fall beweist nichts.** Zu jeder neuen Prüfung gehört der Nachweis, dass
sie auch anschlägt: Fehler künstlich erzeugen, Meldung zeigen, zurücknehmen,
wieder grün. Ohne diesen Nachweis ist eine Prüfung eine Vermutung.

**Kontrollwert mitmessen.** Wer prüft, ob ein Port offen ist, misst gleichzeitig
einen Port, der offen sein *muss*, und einen, der zu sein *muss*. Sonst
untersucht man am Ende den Messpunkt statt das Ziel — ein Fernmesspunkt kann
selbst blockiert sein.

**Von außen messen, was von außen erreichbar sein soll.** `ss -tulpn` auf dem
Server sagt nichts darüber, was durch Firewall und Provider hindurchkommt.

> *A dry run proves nothing — it skips exactly the risky steps. Reproduce through
> the regular entry point, not a hand-built shortcut. The OK case proves nothing:
> every new check needs proof that it fires, by breaking something on purpose.
> Always measure a control value alongside — a remote probe can itself be
> blocked. And measure from outside what is meant to be reachable from outside.*

---

## Fallstricke, die schon Zeit gekostet haben

Jeder Punkt ist ein realer Vorfall, nicht eine Vermutung.

| Falle | Was passiert |
|---|---|
| `mkdir(mode=…)` | Der `mode` wird von der `umask` beschnitten. `chmod` muss **nach** `mkdir` kommen. |
| systemd-Härtung | `LockPersonality`, `ProtectKernelTunables`, `ProtectControlGroups` setzen `NoNewPrivileges` **implizit** — dann kann `sudo` nicht mehr nach root, und die Oberfläche zeigt einfach leere Listen. |
| `ProtectSystem=strict` | Borg kann seinen Cache nicht anlegen, die Archivliste bleibt leer. |
| Funktionen in Bash | Werden beim **Aufruf** aufgelöst, nicht beim Einlesen. Steht die Definition hinter der Schleife, die sie benutzt, ist sie zur Laufzeit `command not found` (127) auf stderr — die Prüfung rechnet richtig und meldet an niemanden, während der Lauf Erfolg meldet. Am 2026-09-10 zweimal an einem Tag passiert. Helfer **vor** ihre erste Benutzung, und vor dem Entfernen einer scheinbaren Doppelung prüfen, **wann** jede Fassung läuft. |
| `grep -q` in einer Pipe | Beendet sich beim ersten Treffer, die schreibende Seite bekommt `SIGPIPE`; mit `set -o pipefail` gilt die Pipeline als gescheitert. Here-String verwenden. |
| CSP-Schlüsselwörter | **Müssen** einfach gequotet sein. Ohne Anführungszeichen liest der Browser `'self'` als Hostnamen. |
| HTTP/2 und WebSockets | Caddy gab über h2 auf den Terminal-Upgrade `404`. Deshalb `protocols h1`. |
| `\s` in Zeilenregeln | Frisst den Zeilenumbruch; bei leerem Wert wird die Folgezeile als Wert verschluckt. `[ \t]*` und `[^\r\n]*` verwenden. |
| Feldnamen-Muster | Trennzeichen sind beliebig: `max-players`, `max_players`, `MaxPlayerCount`. Ein Muster, das nur Unterstrich kennt, lässt Minecraft still auf 20 Plätzen laufen. |
| Feldnamen-Muster, die andere Hälfte | Dasselbe Muster weit genug für alle Schreibweisen trifft auch `_comment_max_players` und `ignore_player_limit_for_returning_players` — ein Erklärtext und ein **Boolean**. Factorio startete danach nicht mehr, während die Einrichtung Erfolg meldete. In JSON deshalb **nur Gleiches durch Gleiches** ersetzen und den vorhandenen Wert ansehen, bevor man ihn überschreibt. |
| Portkollisionen auflösen | Gegen die **tatsächlich gebundenen** Ports prüfen und installierte Spiele ausnehmen — sonst verschiebt man einen laufenden Server von seinem Port und jeder Client verliert ihn. |
| „Lokal kollidiert mit nichts" | Falsch. `127.0.0.1:N` und `0.0.0.0:N` schließen sich aus, in beiden Richtungen, für TCP wie UDP (gemessen, #163) — `docker-proxy` bindet echte Sockets. Lokale Ports gehören in jede Kollisionsprüfung. |
| TCP und UDP getrennt verschieben | Derselbe Containerport landet auf zwei Hostports; die Beitrittsadresse zeigt dann auf den falschen, und Spiele wie FiveM, die beide auf einem Port brauchen, sind tot. Immer **einen** Hostport für beide. |
| `dig` zur Existenzprüfung | Wertlos, wenn die Zone ein Wildcard hat: es beantwortet jeden erfundenen Namen. Immer die API fragen. |
| Cloudflare `proxied` | Der Proxy kann nur HTTP(S). Ein Spielport dahinter ist von außen tot. |
| `borg extract` | Läuft von `/` aus, weil die Archive absolute Pfade tragen. Aus einem anderen Verzeichnis entsteht ein Unterbaum an falscher Stelle, und der Server startet mit leerer Welt — ohne Fehlermeldung. |
| ich777-Images | Erwarten `UID`/`GID`, **nicht** `PUID`/`PGID`, und brauchen `steamcmd/` und `serverfiles/` vor dem ersten Start. |
| Pfadprüfung | **Erst auflösen, dann prüfen.** Unter StarRupture lag ein Symlink `z: -> /` (jedes Wine-Präfix legt ihn an); eine Prüfung vor dem Auflösen macht aus jedem Editor einen Root-Schreibzugriff aufs ganze System. |
| Spielserver und ihre Konfiguration | Viele schreiben sie beim Start **selbst neu**. Bei Minecraft nachgemessen: geänderte Werte überleben, eigene Kommentare und unbekannte Zeilen verschwinden. |
| Dateien auf die Maschine bringen | Nie `scp` direkt — die `@@PLATZHALTER@@` gehen sonst mit. `werkzeuge/ausrollen.sh` benutzen; es bricht bei einem übrig gebliebenen Platzhalter ab. |
| `sudo` aus einem systemd-Dienst | Wechselt den Benutzer, **nicht den Mount-Namensraum**. `ProtectSystem=full` lässt Schreibzugriffe auf `/etc` auch als root scheitern. `/proc/<pid>/mountinfo` prüfen, nicht die Dateirechte. |
| Borg-Sperre | Der Viertelstundenlauf hält das Repository rund vier Minuten gesperrt; Borg gibt ohne `--lock-wait` nach **einer Sekunde** auf. Vollsicherung, Endsicherung vor dem Entfernen, Archivliste und Wiederherstellung scheiterten daran (#171, #234). Jeder Borg-Aufruf braucht `--lock-wait`, und die Meldung muss „Sicherung läuft" sagen, nicht „nicht erreichbar". |
| Borgs `sh:`-Muster | `*` überspringt kein `/`. Wer Ausschlüsse mit `startswith` vergleicht oder Zeilen wörtlich verschiebt, trifft Platzhalterzeilen nie — ein Restore hätte Enshrouded 32 Spieldateien gekostet (#231). Muster wie Borg auflösen, an denselben **relativen** Ort zurücklegen. |
| TeamSpeak-ServerQuery | Verbindungen über das Docker-Gateway stehen nicht auf der Allowlist: drei schnelle Anmeldungen, und der Flutschutz sperrt rund zehn Minuten — jeder weitere Versuch verlängert. Befehle takten, eine Verbindung je Lauf, bei einer Sperre **warten**. |
| `pkill -f` / `pgrep -f` mit Muster | Trifft die eigene Befehlszeile mit: Ein Muster, das im SSH-Befehl selbst steht, beendete die eigene Shell, und eine Warteschleife fand sich selbst und wartete ewig. Nach PID beenden (`ss -ltnpH "sport = :PORT"`). |
| `echo "…\t…"` | Gibt `\t` wörtlich aus; das Panel zeigte beim ersten echten Restore „ok\tIst-Stand …". `printf` benutzen. |
| `docker compose stop` | Ist ein **ausdrückliches** Anhalten und schaltet `restart: unless-stopped` über den Neustart hinweg ab. Und `restart: on-failure` startet nach einem `docker stop` (Exit 143) doch wieder. |
| A2S-Abfragen | Die erste `A2S_INFO` bekommt seit 2020 einen Challenge (`0x41`), erst die Wiederholung Daten. Ohne das wirkt ein antwortender Server stumm. |
| Spiele, die ihren Port selbst melden | KF2 meldete der Serverliste den Port **im** Container; die Abbildung `30116:7777` ist für Docker korrekt und für Spieler tot. Solche Server im Container schon auf dem Hostport lauschen lassen (#228). |
| Server über Steams Relay | Unturned ist per „Server Code" erreichbar, **ohne** dass ein Port veröffentlicht ist — dort ist das Passwort die einzige Sperre und muss vor dem ersten Start stehen (E31). |
| Steams Workshop-API | Die Detailabfrage heißt das Feld `consumer_app_id`, die Suche `consumer_appid`; und ohne Schlüssel meldet sie bei manchen Spielen `file_size: 0`. Beides führte zu falschen Urteilen. |
| Discord prüfen | Ein Bot ohne Message-Content-Intent sieht bei fremden Nachrichten leeren Inhalt — das sieht aus wie ein Zustellfehler. Webhooks mit `?wait=true` aufrufen und die Antwort prüfen. |
| Generatoren und Handwerkzeuge | Was ein Generator anlegt, bekommt nicht von selbst, was ein Handwerkzeug später setzt: 17 Katalogspiele standen ohne Kategorie da (#251). Solche Felder gehören in `vollstaendigkeit.sh`. |

> *Traps that have already cost time, each a real incident: mkdir's mode is
> masked by the umask; some systemd hardening options imply NoNewPrivileges and
> break sudo silently; ProtectSystem=strict stops borg's cache; bash resolves
> functions at call time, so a helper defined after its loop is "command not
> found" while the run reports success; `grep -q` in a pipe with pipefail fails
> valid input; CSP keywords need single quotes; HTTP/2 broke the terminal's
> WebSocket; `\s` swallows newlines; field-name patterns must allow any
> separator and then hit comment fields and booleans; resolve port collisions
> against really bound ports, local ones included, and never split TCP and UDP;
> `dig` is worthless with a wildcard; Cloudflare's proxy kills game ports; borg
> extract must run from `/`; ich777 images want UID/GID and pre-created folders;
> resolve paths before checking them; game servers rewrite their configs; never
> scp files with placeholders; sudo from a unit keeps its mount namespace. Newer
> ones: the borg lock needs `--lock-wait` everywhere and an honest message;
> borg's `sh:` patterns do not cross `/`; TeamSpeak's ServerQuery flood ban
> after three quick logins; `pkill -f`/`pgrep -f` match their own command line;
> `echo` prints `\t` literally; `docker compose stop` disables unless-stopped
> and `on-failure` restarts after a stop; A2S needs the challenge step; some
> games announce their container port; relay-capable servers are reachable
> without a published port; Steam's Workshop API names one field two ways and
> reports size 0 without a key; a Discord bot without the message content intent
> sees empty messages; and generators do not set what hand tools add later.*

---

## Wenn etwas kaputtgeht

Jede Einrichtungsstufe sichert eine vorhandene Zieldatei vor dem Überschreiben
nach `<datei>.vor-<datum>`. Zurück geht es dateiweise. `docs/02-installation.md`
beschreibt den vollständigen Rückbau.

**Vor riskanten Schritten** eine Sicherung ziehen:

```bash
ssh gameserver 'spiele-sicherung --nur <spiel>'
```

Störungsbilder und ihre Ursachen: `docs/08-betrieb-und-stoerungen.md`.

> *Every stage backs up an existing target before replacing it, so reverting is
> per file; the full teardown is documented. Take a backup before risky steps.*

---

## Fragen, die man stellen sollte, statt sie zu raten

* **Datenverlust droht?** Löschen, Überschreiben, Formatieren ohne Sicherung.
* **Dienstunterbrechung?** Neustart, Container anhalten, einen laufenden
  Langlauf abbrechen.
* **Wirkung nach außen?** DNS- und Firewall-Änderungen an öffentlich
  erreichbaren Systemen.
* **Sicherheitsgrenzen aufweichen?** Zugänge öffnen, Rechte ausweiten.

Alles andere — Diagnose, Messungen, reversible Änderungen mit dokumentiertem
Rückweg — ohne Rückfrage machen, die Annahme benennen, das Ergebnis berichten.

> *Ask before: risking data loss, interrupting a service, changing DNS or
> firewall on publicly reachable systems, or weakening a security boundary.
> Everything else — diagnosis, measurement, reversible changes with a documented
> way back — proceed, state the assumption, report the result.*
