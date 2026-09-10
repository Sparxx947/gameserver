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

> *Every change: English issue describing the problem (not the solution), branch,
> work with documentation, green completeness check, pull request with
> `Fixes #<n>`, merge, delete branch. Never push to `main` directly.*

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
5. **Ein Spielport wird erst veröffentlicht, wenn das Beitrittspasswort steht.**
   Das Eintragen des Ports ist der Schritt, der den Server nach außen öffnet;
   er gehört ans **Ende** der Einrichtung, nie an den Anfang. `port-ermitteln`
   trägt deshalb nur ein, wenn `einrichtung_offen` nicht mehr gesetzt ist, und
   einzeln aufgerufen übergibt es per `execv` an `spiel-einrichtung` — es soll
   genau **einen** Weg geben, der Ports veröffentlicht. Wer einen zweiten baut,
   baut die Lücke von E23 nach.

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
`@@PLATZHALTER@@` in `konfiguration.env.beispiel` erklärt?

Als automatische Bremse:

```bash
ln -sf ../../werkzeuge/git-hooks/pre-commit .git/hooks/pre-commit
```

Bewusst als Symlink und **nicht** über `git config core.hooksPath` — das ersetzt
das gesamte Hook-Verzeichnis und schaltet vorhandene Haken ab.

> *Run the completeness check before every commit; wire it in as a symlinked
> pre-commit hook, never via `core.hooksPath`, which would replace the entire
> hooks directory.*

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
  `@@PLATZHALTER@@` und `konfiguration.env`.
* **Bilder aus Steam.** Die Kopfgrafiken sind Werke Dritter und werden zur
  Laufzeit geladen. Nur die selbst erzeugten Symbole liegen hier.
* **Spielstände.** Die gehören in die Sicherung.

**Nach dem ersten Push an der Quelle gegenprüfen**, nicht lokal:

```bash
gh api repos/<owner>/<repo>/git/trees/main?recursive=1 --jq '.tree[].path'
```

Genau so wurde gefunden, dass die Regel `*.local` die Datei
`etc/fail2ban/jail.local` verschluckt hatte — lokal lag sie sichtbar da, sie war
nur nicht verfolgt.

> *Never commit secrets, site-specific values, Steam artwork or save games. After
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
| Funktionen in Bash | Werden beim **Aufruf** aufgelöst, nicht beim Einlesen. Steht die Definition hinter der Schleife, die sie benutzt, ist sie zur Laufzeit `command not found` (127) auf stderr — die Prüfung rechnet richtig und meldet an niemanden, während der Lauf Erfolg meldet. Am 2026-09-10 zweimal an einem Tag passiert (`in_bytes`, dann `melden`). Helfer **vor** ihre erste Benutzung, und vor dem Entfernen einer scheinbaren Doppelung prüfen, **wann** jede Fassung läuft. |
| `grep -q` in einer Pipe | Beendet sich beim ersten Treffer, die schreibende Seite bekommt `SIGPIPE`; mit `set -o pipefail` gilt die Pipeline als gescheitert. Here-String verwenden. |
| CSP-Schlüsselwörter | **Müssen** einfach gequotet sein. Ohne Anführungszeichen liest der Browser `'self'` als Hostnamen. |
| HTTP/2 und WebSockets | Caddy gab über h2 auf den Terminal-Upgrade `404`. Deshalb `protocols h1`. |
| `\s` in Zeilenregeln | Frisst den Zeilenumbruch; bei leerem Wert wird die Folgezeile als Wert verschluckt. `[ \t]*` und `[^\r\n]*` verwenden. |
| Feldnamen-Muster | Trennzeichen sind beliebig: `max-players`, `max_players`, `MaxPlayerCount`. Ein Muster, das nur Unterstrich kennt, lässt Minecraft still auf 20 Plätzen laufen. |
| Portkollisionen auflösen | Gegen die **tatsächlich gebundenen** Ports prüfen und installierte Spiele ausnehmen — sonst verschiebt man einen laufenden Server von seinem Port und jeder Client verliert ihn. |
| `dig` zur Existenzprüfung | Wertlos, wenn die Zone ein Wildcard hat: es beantwortet jeden erfundenen Namen. Immer die API fragen. |
| Cloudflare `proxied` | Der Proxy kann nur HTTP(S). Ein Spielport dahinter ist von außen tot. |
| `borg extract` | Läuft von `/` aus, weil die Archive absolute Pfade tragen. Aus einem anderen Verzeichnis entsteht ein Unterbaum an falscher Stelle, und der Server startet mit leerer Welt — ohne Fehlermeldung. |
| ich777-Images | Erwarten `UID`/`GID`, **nicht** `PUID`/`PGID`, und brauchen `steamcmd/` und `serverfiles/` vor dem ersten Start. |
| Pfadprüfung | **Erst auflösen, dann prüfen.** Unter StarRupture liegt ein Symlink `z: -> /`; eine Prüfung vor dem Auflösen macht aus jedem Editor einen Root-Schreibzugriff aufs ganze System. |
| Spielserver und ihre Konfiguration | Viele schreiben sie beim Start **selbst neu**. Bei Minecraft nachgemessen: geänderte Werte überleben, eigene Kommentare und unbekannte Zeilen verschwinden. |
| Dateien auf die Maschine bringen | Nie `scp` direkt — die `@@PLATZHALTER@@` gehen sonst mit. `werkzeuge/ausrollen.sh` benutzen; es bricht bei einem übrig gebliebenen Platzhalter ab. |
| `sudo` aus einem systemd-Dienst | Wechselt den Benutzer, **nicht den Mount-Namensraum**. `ProtectSystem=full` lässt Schreibzugriffe auf `/etc` auch als root scheitern. `/proc/<pid>/mountinfo` prüfen, nicht die Dateirechte. |

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
