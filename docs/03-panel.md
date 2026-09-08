# 03 — Die Weboberfläche

`https://<PANEL_DOMAIN>/` — FastAPI auf uvicorn, gebunden an `127.0.0.1:8099`,
ausgeliefert durch Caddy. Ohne Rahmenwerk im Browser: kein JavaScript, keine
externen Ressourcen, alles serverseitig gerendert. Das ist kein Purismus,
sondern folgt aus der Sicherheitsrichtlinie (`default-src 'none'`) — siehe
[07-sicherheitsentwurf.md](07-sicherheitsentwurf.md).

> *FastAPI on uvicorn bound to localhost and served by Caddy. No client-side
> framework, no JavaScript, no external resources — everything is rendered
> server-side. That follows from the content security policy
> (`default-src 'none'`), not from purism.*

---

## Anmeldung

Zwei Faktoren, immer: Passwort (Argon2id) **und** ein TOTP-Code.

Der Ablauf beim ersten Mal weicht bewusst ab: Stimmt das Passwort, ist aber
`totp_bestaetigt` noch `false`, wird **keine Sitzung** vergeben. Stattdessen
setzt die Oberfläche ein kurzlebiges, mit eigenem Salt signiertes
Einrichtungs-Token (10 Minuten) und führt auf `/einrichten` mit QR-Code. Erst
der richtige Code dort schaltet das Konto frei.

Ein Einrichtungs-Token darf niemals als Sitzungscookie durchgehen — deshalb der
eigene Salt und nicht bloß eine kürzere Laufzeit.

> *Two factors, always. On first login the flow deliberately differs: a correct
> password with `totp_bestaetigt` still false grants no session but a short-lived
> enrolment token signed with its own salt, leading to a QR page. A separate
> salt — not merely a shorter lifetime — is what stops an enrolment token from
> passing as a session cookie.*

| Merkmal | Wert |
|---|---|
| Passwort-Hash | Argon2id (`argon2-cffi`) |
| Zweiter Faktor | TOTP, `pyotp`, Toleranz ±1 Zeitfenster |
| Sitzungsdauer | 8 Stunden |
| Cookie | signiert (`itsdangerous`), `HttpOnly`, `Secure`, `SameSite=strict` |
| CSRF | Token in der Sitzung, bei **jedem** Schreibzugriff geprüft (`hmac.compare_digest`) |
| Sperre | 5 Fehlversuche je IP → 15 Minuten |

**Die Rolle wird bei jeder Anfrage frisch aus der Datei gelesen**, nicht aus dem
Cookie. Sonst behielte ein herabgestufter oder gelöschter Benutzer seine Rechte
bis zum Ablauf des Cookies — bis zu acht Stunden.

> *The role is re-read from disk on every request rather than taken from the
> cookie: otherwise a demoted or deleted user would keep their rights until the
> cookie expired — up to eight hours.*

---

## Rollen

| | `admin` | `bedienen` |
|---|---|---|
| Übersicht sehen | ja | ja |
| Starten, Anhalten, Neustarten | ja | ja |
| Spiele installieren/entfernen | ja | **nein** |
| Zugangsdaten sehen | ja | **nein** |
| Konfiguration ändern | ja | **nein** |
| Wiederherstellen | ja | **nein** |
| Benutzerverwaltung | ja | **nein** |
| Webterminal | ja | **nein** |
| Server neu starten | ja | **nein** |

Die Navigation blendet für `bedienen` alles aus, was nicht erlaubt ist — die
Prüfung sitzt aber in jeder Route, nicht in der Anzeige. Ein direkt aufgerufener
Pfad landet auf der Übersicht, nicht auf der Seite.

> *Roles: `admin` may do everything, `bedienen` may only start, stop and restart.
> The navigation hides what is not permitted, but the check lives in every route,
> not in the rendering: a hand-typed path redirects to the overview.*

---

## Seiten

### Übersicht `/`

Kennzahlen der Maschine (Last, Speicher, Platte) und je Server eine Karte mit
Titelbild, Zustand, Speicherverbrauch, Beitrittsadresse und den Knöpfen.

Ist bei einem Katalogspiel die Passwort-Einrichtung noch offen oder gescheitert,
steht das als Warnung auf der Karte. Ohne diesen Hinweis liefe ein Server im
schlimmsten Fall **ohne Beitrittspasswort** und niemand würde es merken.

> *Overview: machine metrics plus one card per server with artwork, state, memory
> use, join address and controls. A pending or failed password setup is shown as
> a warning — without it a server could silently run with no join password.*

### Spiele `/spiele`

Der Katalog: 41 Einträge mit Titelbild, Kurzbeschreibung, Speicher- und
Plattenbedarf. Installieren mit einem Klick, Entfernen mit Rückfrage.

Übergeben wird **nur der Schlüssel**. Alles andere — Image, Ports, Volumes,
Umgebung — kommt aus `/etc/spiele-katalog.json`, das die Oberfläche nur lesen
kann. Siehe [04-spielekatalog.md](04-spielekatalog.md).

> *The catalogue: 41 entries with artwork, blurb and resource needs. Install with
> one click, remove with a confirmation. Only the key is passed; everything else
> comes from the catalogue file, which the panel can only read.*

### Suche, Kategorien und Sortierung auf der Katalogseite

Bei 154 Einträgen ist Blättern keine Bedienung mehr. Die Seite hat deshalb:

* **Textsuche** über Name, Schlüssel **und** Kurzbeschreibung — wer `koop`
  eintippt, meint eine Eigenschaft, keinen Titel. Mehrere Wörter müssen **alle**
  vorkommen; sonst lieferte `koop survival` mehr Treffer als `koop` allein, was
  niemand erwartet.
* **Acht Kategorien** mit Trefferzahl. Die Zahl zählt die Suche mit, aber nicht
  den Kategoriefilter — sie beantwortet „wie viele davon passen zu dem, was ich
  gerade suche".
* **Eine Buchstabenleiste** `alle · 0-9 · A … Z`. Jeder Buchstabe zeigt seine
  Trefferzahl als Kurzinfo; Buchstaben ohne Treffer bleiben stehen, sind aber
  ausgegraut und nicht anklickbar. Sie wegzulassen ließe die Leiste bei jeder
  Suche die Breite wechseln, und man müsste jedes Mal neu suchen, wo das M nun
  steht — ein graues M sagt außerdem etwas: dass es dort nichts gibt.
  `0-9` ist eine eigene Gruppe, weil genau ein Spiel mit einer Ziffer anfängt
  (7DaysToDie) und sonst unter keinem Buchstaben zu finden wäre.

**Die Katalogseite ist breiter als der Rest der Oberfläche.** 1000 Pixel sind für
Fließtext richtig und für 154 Kacheln viel zu wenig — auf einem breiten
Bildschirm standen drei Spalten neben zwei Dritteln leerem Grau. Der Katalog
bekommt deshalb eine eigene Spalte bis 2400 px und ein engeres Raster (240 statt
300 px Mindestbreite, flachere Bilder). Gemessen: aus 3 Spalten werden 7 auf Full
HD und 9 bis 11 auf breiteren Schirmen. Die Kopfleiste bleibt bei 1000 px — sie
soll nicht über den ganzen Schirm wandern.

Über 2400 px wird nicht weiter aufgezogen: Eine Kachelreihe, die breiter ist als
das Blickfeld, liest niemand mehr als Reihe.

> *The catalogue page is wider than the rest: 1000px is right for prose and far
> too little for 154 tiles, which left three columns beside two thirds of empty
> background. It gets its own column up to 2400px and a tighter grid — measured,
> 3 columns become 7 on Full HD and 9–11 on wider screens. Beyond 2400px nothing
> is gained: a row wider than the field of view stops reading as a row.*

Die Sortierung ist **fest alphabetisch**. Vorher gab es A → Z, Z → A und „größte
zuerst"; an ihre Stelle ist die Buchstabenleiste getreten. Eine umgekehrte
Reihenfolge neben einer Buchstabenauswahl hilft niemandem: Wer unter „M"
nachsieht, will die M-Spiele, nicht ihre Richtung.

| Kategorie | Einträge |
|---|---|
| Aufbau & Simulation | 8 |
| Survival & Koop | 40 |
| Sandbox & Rollenspiel | 10 |
| Shooter | 72 |
| Arena & Klassiker | 20 |
| Rennen & Fahren | 3 |
| Dienste | 1 |

**Alles läuft serverseitig über GET-Parameter — kein JavaScript.** Das ist keine
Vorliebe, sondern folgt aus `default-src 'none'`: ein Filter im Browser wäre
schlicht tot. Der Nebeneffekt ist angenehm: Die Zurück-Taste funktioniert, und
jede Auswahl lässt sich als Lesezeichen ablegen.

Die aktuelle Auswahl wandert als verstecktes Feld mit, damit eine Suche den
Kategoriefilter nicht wegwirft und umgekehrt.

**Die Kategorien sind von Hand vergeben** (`werkzeuge/katalog-kategorien.py`),
nicht aus Steam übernommen: Dort steht Terraria unter „Action, Abenteuer, Indie,
Rollenspiel" und Killing Floor 2 unter „Action" — beides sagt nichts darüber, ob
ein Spiel zu zweit an einem Abend Spaß macht. Wer eine Zuordnung für falsch
hält, ändert eine Zeile; ein Spiel ohne Zuordnung landet sichtbar in
„Sonstiges" und wird beim Lauf benannt.

> *At 154 entries, scrolling is not an interface. The page offers a text search
> across name, key and blurb (multiple words must all match, or a longer query
> would return more results than a shorter one), eight categories with counts
> that respect the search but not the category filter, and a letter bar.
> Everything is server-side via GET parameters — not a preference but a
> consequence of `default-src 'none'`, where client-side filtering would be dead.
> Categories are assigned by hand rather than taken from Steam, whose genres say
> nothing about whether a game suits an evening for two.*

### Zugangsdaten `/passwoerter`

Beitritts- und Adminpasswörter aller Server, an einer Stelle. Zwei Quellen,
sichtbar getrennt:

* **Automatisch gelesen** — aus den compose-Dateien und den `panel.json`.
  Immer aktuell, weil direkt aus der Quelle.
* **Selbst gepflegt** — für Server, deren Passwort sich nicht auslesen lässt:
  Satisfactory (Hash und Salt in einer binären `.sav`), TeamSpeak (Hash in
  SQLite), StarRupture (RSA-verschlüsselt). Diese Einträge **können veralten**
  und sind deshalb gekennzeichnet.

> *All join and admin passwords in one place, from two visibly separated
> sources: read automatically from the compose files, and kept by hand for
> servers whose password cannot be read back (stored hashed or encrypted). The
> hand-kept entries can go stale and are marked as such.*

### Benutzer `/nutzer`

Anlegen, Rolle setzen, zweiten Faktor zurücksetzen, löschen.

Beim Anlegen entsteht ein TOTP-Geheimnis, das **niemandem angezeigt wird** —
auch nicht dem Administrator. Der neue Benutzer bekommt es bei seiner ersten
Anmeldung selbst als QR-Code. So muss es nie über einen Kanal weitergegeben
werden.

Das eigene Konto lässt sich nicht löschen: sonst sperrt man sich mit einem Klick
aus, und ohne Administrator käme niemand mehr an die Benutzerverwaltung.

> *Users: create, set role, reset the second factor, delete. A new TOTP secret is
> shown to nobody, not even the administrator — the new user receives it as a QR
> code on their first login, so it never travels over a channel. Deleting your
> own account is blocked: it would lock the last administrator out of user
> management.*

### Terminal `/terminal/`

Ein vollwertiges Webterminal (`ttyd`), das als der Mensch läuft, **nicht** als
root. Für privilegierte Befehle verlangt `sudo` erneut das Passwort — eine
zweite Hürde, falls jemand eine offene Sitzung übernimmt.

Caddy fragt vor jedem Aufruf beim Panel nach (`forward_auth` auf `/auth-check`).
Nur eine gültige Admin-Sitzung bekommt `204`, alles andere `401`. `ttyd` selbst
hat keine Anmeldung; die Absicherung sitzt vollständig davor.

> *A full web terminal running as the human, not root: sudo asks for the password
> again, a second hurdle if a session is hijacked. Caddy checks with the panel
> before every request; ttyd itself has no authentication at all.*

### Konfigurationsdateien `/dateien/<stack>` und `/datei/<stack>`

Hier werden die Konfigurationsdateien **des Spielservers** bearbeitet —
`server.properties`, `PalWorldSettings.ini`, `enshrouded_server.json` und so
weiter. Zwei Ansichten derselben Datei:

* **Felder** — die Datei wird zerlegt, jeder Schlüssel bekommt ein Eingabefeld.
  `true`/`false` wird zur Auswahlliste, weil das der häufigste Wert ist und der,
  bei dem man sich am leichtesten vertippt (`True`, `yes`, `1` …). Beim
  Speichern wird die Datei **zeilenweise** geändert: Kommentare, Reihenfolge und
  Formatierung bleiben erhalten. Ein Neuschreiben aus dem geparsten Zustand
  würde jeden Kommentar vernichten — und in `server.properties` oder
  `PalWorldSettings.ini` steht die halbe Dokumentation in den Kommentaren.
* **Rohtext** — die ganze Datei in einem Textfeld. Für alles, was sich nicht in
  Felder zerlegen lässt: verschachteltes JSON, XML, ungewöhnliche Formate.

Vor jedem Schreiben entsteht eine Sicherung `<datei>.vor-panel-<zeit>` neben der
Datei. JSON wird vor dem Speichern auf Gültigkeit geprüft — eine kaputte
JSON-Datei lässt den Server kommentarlos nicht starten, und den Zusammenhang zur
letzten Änderung stellt später niemand mehr her.

> *Two views of the same file: a field view that decomposes it (booleans become a
> dropdown — the most common value and the easiest to mistype) and writes back
> line by line so comments, order and formatting survive, and a raw editor for
> anything that cannot be decomposed. A backup is written before every save, and
> JSON is validated first: broken JSON makes the server fail to start silently.*

**Der Unterschied zu `/konfig/<stack>` ist der ganze Sicherheitsentwurf:**

| | `/konfig/<stack>` | `/dateien/<stack>` |
|---|---|---|
| Datei | `compose.yaml` | Konfiguration des Spiels |
| Was sie beschreibt | den **Container** | die **Spielregeln** |
| Wer sie liest | Docker, als root | der Spielprozess als UID 4711 |
| Schlimmster Fall | `/:/host` gemountet = **root auf der Maschine** | der Server startet nicht |
| Bearbeitbar | 12 Felder aus einer Positivliste | frei |

Deshalb darf das eine frei bearbeitet werden und das andere nicht.

> *The distinction carries the whole security design: a compose file describes
> the container and a volume of `/:/host` means root on the machine; a game
> config is read by an unprivileged process inside the container, so the worst
> case is a server that will not start.*

**Bei einem frisch installierten Server ist die Liste zunächst leer.** Das ist
kein Fehler: Die meisten Server laden erst mehrere Gigabyte herunter und
schreiben ihre Konfiguration beim ersten Start. Die Seite unterscheidet die
beiden Fälle und sagt, welcher vorliegt — sonst sieht eine frische Installation
aus wie ein Defekt, und man sucht nach etwas, das noch nicht existiert.

Auf der Übersicht steht die **Anzahl** neben dem Knopf, gepflegt vom
Einrichtungs-Timer alle zwei Minuten. Gemessen: das Zählen kostet 27 bis 88 ms
je Server, zusammen eine halbe Sekunde.

Nachgemessen an Astroneer (frisch installiert, ich777-Bauart wie 37 der 41
Katalogspiele):

| Zeitpunkt | Umgebungsvariablen | Konfigurationsdateien |
|---|---|---|
| direkt nach dem Klick | 1 frei, 5 gesperrt | **0** — lädt noch |
| nach 60 s, 4,1 GB geladen | 1 frei, 5 gesperrt | **2**, mit 19 Einstellungen |

Die Felder entstehen dabei **allein aus der Datei** — im Katalog ist dafür
nichts hinterlegt.

> *A freshly installed server shows an empty list at first, and that is not a
> fault: most download gigabytes before writing any configuration. The page tells
> the two cases apart, and the overview carries the count. Measured on Astroneer:
> nothing at install time, two files with 19 settings a minute later — and the
> fields come from the file alone, with nothing in the catalogue describing
> them.*

**Was der Editor nicht verhindern kann:** Viele Spielserver schreiben ihre
Konfiguration beim Start **selbst neu**. Bei Minecraft nachgemessen: geänderte
Werte überleben, eigene Kommentare und unbekannte Zeilen verschwinden. Wo es
darauf ankommt, den Server vorher anhalten.

> *What the editor cannot prevent: many game servers rewrite their configuration
> on start. Measured on Minecraft: changed values survive, own comments and
> unknown lines disappear.*

### Container-Einstellungen `/konfig/<stack>`

Zeigt **alle Umgebungsvariablen** des Stacks. Bis zum 2026-09-07 standen hier
nur 12 Felder aus einer festen Liste — von den 69 Variablen der acht Server
waren 15 erreichbar, alles andere ging nur per SSH.

Einige Variablen erscheinen **fest** und nicht bearbeitbar. Sie werden trotzdem
angezeigt, damit sichtbar ist, dass es sie gibt:

| Variable | Warum fest |
|---|---|
| `UID`, `GID`, `PUID`, `PGID` | Ändern bricht die Rechte an den Spielständen |
| `GAME_ID`, `APPID` | Das wäre ein anderes Spiel |
| `EULA`, `TS3SERVER_LICENSE` | Eine Zustimmung, kein Schalter |
| `PATH`, `LD_PRELOAD`, … | Ausführungsumgebung des Containers |

> *Shows every environment variable of the stack; until 2026-09-07 only 12
> allow-listed fields appeared, leaving 54 of 69 reachable only over SSH. Some
> are shown but locked — changing them would break file ownership, install a
> different game, or amount to accepting a licence.*

Änderbar sind **einzelne Felder** aus einer Positivliste (Servername,
Beitrittspasswort, Adminpasswort, Spielerzahl, Speichergrenze) — nie die
compose-Datei als Ganzes. Wer dort ein Volume `/:/host` eintragen könnte, wäre
root auf der Maschine.

> *Configuration: individual fields from an allow-list only (server name, join
> and admin password, player count, memory limit) — never the compose file as a
> whole, since a volume entry of `/:/host` would mean root on the machine.*

### Archive und Wiederherstellung `/archive/<stack>`, `/restore`

Listet die Borg-Archive dieses Servers und stellt eines mit Rückfrage wieder
her. Details in [05-sicherung.md](05-sicherung.md).

---

## Alle Routen

| Methode | Pfad | Rolle | Zweck |
|---|---|---|---|
| GET | `/` | beide | Übersicht |
| GET | `/login` · POST `/login` | — | Anmeldung |
| GET | `/einrichten` · POST `/einrichten` | — | zweiten Faktor einrichten |
| GET | `/qr` | — | QR-Code (nur mit Einrichtungs-Token) |
| GET | `/abmelden` | beide | Sitzung beenden |
| POST | `/aktion` | beide | starten / anhalten / neu starten |
| GET | `/bild/{stack}` | beide | Titelbild eines Servers |
| GET | `/katalogbild/{schluessel}` | admin | Titelbild aus dem Katalog |
| GET | `/spiele` | admin | Katalog |
| POST | `/installieren` | admin | Spiel installieren |
| GET | `/deinstallieren-fragen/{stack}` | admin | Rückfrage |
| POST | `/deinstallieren` | admin | Spiel entfernen |
| GET | `/konfig/{stack}` · POST `/konfig-setzen` | admin | Felder ändern |
| GET | `/archive/{stack}` | admin | Archivliste |
| GET | `/restore-fragen/{…}` · POST `/restore` | admin | Wiederherstellung |
| GET | `/passwoerter` | admin | Zugangsdaten |
| POST | `/zugang-anlegen` · `/zugang-loeschen` | admin | selbst gepflegte Einträge |
| GET | `/nutzer` | admin | Benutzerverwaltung |
| POST | `/nutzer-anlegen` · `/mfa-zuruecksetzen` · `/nutzer-loeschen` | admin | Benutzer ändern |
| GET | `/neustart-fragen` · POST `/neustart` | admin | Maschine neu starten |
| GET | `/auth-check` | admin | interne Prüfung für Caddy |
| GET | `/favicon.ico` · `/favicon.svg` · `/apple-touch-icon.png` | — | Symbole |

`docs_url`, `redoc_url` und `openapi_url` sind abgeschaltet: eine
Schnittstellenbeschreibung, die jeder abrufen kann, verrät den Aufbau ohne
Gegenwert.

> *All routes are listed above. FastAPI's docs, redoc and OpenAPI endpoints are
> switched off: a publicly readable API description gives away the structure for
> nothing in return.*

---

## Datenhaltung

| Datei | Inhalt |
|---|---|
| `/opt/panel/daten/nutzer.json` | `{"secret": …, "nutzer": {"<name>": {"passwort_hash", "totp", "rolle", "totp_bestaetigt"}}}` |
| `/opt/panel/daten/zugangsdaten.json` | Liste selbst gepflegter Zugänge |
| `/opt/panel/konfig.json` | **veraltet** — Einzelnutzer-Fassung, wird beim ersten Start einmalig nach `nutzer.json` übernommen |

Geschrieben wird immer über eine `.tmp`-Datei mit anschließendem `replace()`.
Ein Absturz mitten im Schreiben hinterlässt sonst eine halbe JSON-Datei, und
dann kommt niemand mehr an die Oberfläche.

> *Writes always go through a `.tmp` file followed by an atomic `replace()`: a
> crash mid-write would otherwise leave half a JSON file behind and lock everyone
> out of the panel.*
