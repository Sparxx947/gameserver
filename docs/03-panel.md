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

### Konfiguration `/konfig/<stack>`

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
