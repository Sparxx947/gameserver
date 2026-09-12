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

Zwei Faktoren, immer: Passwort (Argon2id) **und** ein zweiter Faktor — einer
von dreien:

* ein **TOTP-Code** aus einer Authenticator-App (sechs Ziffern, ±1 Zeitfenster);
* ein **Passkey** (Knopf „mit Passkey anmelden"; Windows Hello, Touch ID,
  Android, Sicherheitsschlüssel) — das Passwort wird trotzdem vorher geprüft;
* ein **Wiederherstellungscode** (16 Zeichen, mit oder ohne Bindestriche) im
  selben Feld wie der TOTP-Code. Die **Form** entscheidet, welcher Weg geprüft
  wird: sechs Ziffern sind TOTP, 16 Zeichen ein Code. Ein eingelöster Code wird
  gelöscht und die Einlösung protokolliert, samt der Zahl der verbleibenden.

Der Benutzername ist unabhängig von Groß- und Kleinschreibung (#248). Jeder
Fehlversuch steht im Protokoll — mit dem eingetippten Namen, aber ohne Angabe,
ob Passwort oder zweiter Faktor falsch war.

> *Two factors, always: a password (Argon2id) and one of three second factors —
> a TOTP code (six digits, ±1 time step), a passkey (the password is still
> checked first), or a recovery code typed into the same field. The input's
> shape decides the path: six digits are TOTP, 16 characters a recovery code; a
> redeemed code is deleted and the redemption audited with the number left. User
> names are case-insensitive (#248). Every failed attempt is audited with the
> name as typed, but without saying whether the password or the second factor
> was wrong.*

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

| | `admin` | `verwalten` | `bedienen` |
|---|---|---|---|
| Übersicht sehen | ja | ja | ja |
| Starten, Anhalten, Neustarten | ja | ja | ja |
| Spiele installieren/entfernen | ja | ja | **nein** |
| Zugangsdaten sehen | ja | ja | **nein** |
| Konfiguration ändern | ja | ja | **nein** |
| Wiederherstellen | ja | ja | **nein** |
| Benutzerverwaltung | ja | **nein** | **nein** |
| Protokoll lesen | ja | **nein** | **nein** |
| Webterminal | ja | **nein** | **nein** |
| Maschine neu starten | ja | **nein** | **nein** |

**Die Trennlinie liegt zwischen Spielen und Maschine.** `verwalten` darf alles,
was die Spieleserver betrifft; `admin` zusätzlich alles, was die Maschine und
die Menschen betrifft.

Vorher gab es dazwischen nichts: Wer ein Spiel installieren können sollte,
musste Administrator werden — und bekam Benutzerverwaltung, Webterminal und den
Maschinenneustart gleich mit.

**Die Rolle öffnet nur die Route, sie ersetzt keine Prüfung.** Was tatsächlich
ausgeführt wird, entscheidet weiterhin die Positivliste in `panel-aktion`. Eine
neue Rolle darf niemals durch Lockern einer bestehenden Prüfung entstehen —
siehe die nicht verhandelbaren Grenzen in `CLAUDE.md`.

Die Navigation blendet aus, was nicht erlaubt ist — die Prüfung sitzt aber in
jeder Route, nicht in der Anzeige. Ein direkt aufgerufener Pfad landet auf der
Übersicht. Eine unbekannte Rolle in `nutzer.json` bekommt **keine** Rechte
(`ist_admin` und `darf_verwalten` sind beide falsch), nicht etwa die des
niedrigsten Niveaus.

> *Three roles, with the line drawn between games and machine: `verwalten`
> covers everything about the game servers, `admin` additionally the machine and
> the people. Previously nothing sat in between, so anyone who needed to install
> a game had to become an administrator. The role only gates the route — the
> allow-list in `panel-aktion` still gates the action, and a new role must never
> be created by loosening an existing check. An unknown role gets no rights at
> all rather than the lowest tier.*

---

## Mein Konto `/konto`

Für **jede** Rolle erreichbar — es geht um den eigenen Zugang, nicht um die
Verwaltung anderer. Zeigt Benutzername, Rolle und den Vorrat an
Wiederherstellungscodes, und erlaubt neue zu erzeugen.

Ohne diesen Weg wäre man nach zehn Einlösungen wieder da, wo man ohne Codes war.
Bei drei oder weniger verbleibenden Codes steht eine Warnung auf der Seite, bei
null eine deutliche.

Dort werden auch **Passkeys** verwaltet: anlegen, auflisten, entfernen. Ein
Passkey tritt an die Stelle der sechs Ziffern und liegt im Gerät des Benutzers —
Windows Hello, Touch ID, Android oder ein Sicherheitsschlüssel. Der Knopf dafür
ist zunächst verborgen und wird erst sichtbar, wenn der Browser WebAuthn
beherrscht; ohne JavaScript steht dort stattdessen ein `<noscript>`-Hinweis, dass
Passwort, Einmalcode und Wiederherstellungscodes unverändert funktionieren.

Die neue Liste erscheint auf `/codes` — **einmal**. Sie reist in einem eigens
signierten, 15 Minuten gültigen Cookie dorthin: nicht im Sitzungscookie, das acht
Stunden lebt und bei jeder Anfrage mitgeht, und nicht in der URL, wo sie im
Verlauf und in jedem Log stünde. Nach dem Anzeigen wird das Cookie sofort
gelöscht, damit auch ein zweiter Aufruf aus dem Verlauf nichts mehr zeigt.

> *Reachable for every role, since it concerns one's own access. Shows the
> remaining recovery codes and allows generating new ones — without that, ten
> redemptions would put the user back where they started. The new list is shown
> once, travelling in a separately signed 15-minute cookie rather than the
> eight-hour session cookie or the URL, and the cookie is dropped immediately
> after rendering.*

---

## Automatisch aktualisieren

Ein Schalter je Server, auf dessen Einstellungsseite (Karte → **Einstellungen**):
**autoupdate an** / **autoupdate aus**. Aus per
Voreinstellung, und es gibt **keinen globalen Schalter** — eine Automatik, die
alles auf einmal betrifft, ist genau die, die man später nicht mehr zuordnen kann.

Für **jeden** Server, auch die von Hand gebauten. Der Schalter lag zunächst in
der `panel.json` — und erreichte damit **einen von acht**, weil nur über den
Katalog installierte Stacks eine haben. Ausgerechnet Palworld und Enshrouded, die
laufend Patches bekommen, waren außen vor. Die `panel.json` beschreibt, *was der
Katalog installiert hat*; ob ein Server sich nachts selbst aktualisiert, hat
damit nichts zu tun. Die Freischaltung steht deshalb in
`/var/lib/spiele-autoupdate.liste`, eine Zeile je Server.

Nachts um 05:15 (±30 min) geht `spiele-autoupdate` die freigeschalteten Server
durch. **Vier Bedingungen, jede einzeln geprüft und einzeln protokolliert:**

| | |
|---|---|
| **freigeschaltet** | der Server steht in `/var/lib/spiele-autoupdate.liste` |
| **sicherbar** | die Sicherung erzwingt `panel-aktion`; scheitert sie, unterbleibt das Update |
| **ruhig** | unter 4 kB/s Netzverkehr, gemessen über 20 s — ein Update mitten in einem Spielabend ist schlimmer als eines, das eine Nacht später kommt |
| **wirklich neu** | `panel-aktion` meldet selbst, ob etwas geholt wurde |

Ein **gestoppter** Server wird ohne Verkehrsprüfung aktualisiert: Da ist niemand
drauf, und es bewegt sich kein Spielstand — der beste Zeitpunkt überhaupt.

Ein **fallender Zähler** bedeutet Container-Neustart, nicht Ruhe: Der Server
wird übersprungen.

Der Timer ist `Persistent=false`. Ein verpasstes Update soll nicht beim nächsten
Hochfahren mitten am Tag losgehen — dieselbe Überlegung wie beim
Palworld-Neustart.

**Das Fehlerbild, gegen das hier gebaut wurde:** ein Update, das still einen
Spielstand bricht und erst Tage später auffällt — dann ist die Sicherung von
davor längst durch die Rotation gefallen.

Ein eingespieltes Update geht nach `#platzwart-meldungen`, ein gescheitertes nach
`#platzwart-stoerung`.

**Wird ein Server entfernt, fällt er aus der Liste** — beide Entfernwege tun das
über denselben Helfer in `spiel-verwalten`, neben der Bereinigung der
Borg-Ausschlüsse. Das war zunächst nicht so, und der übrig gebliebene Eintrag ist
nicht das eigentliche Problem: `spiele-autoupdate` überspringt Namen ohne
Verzeichnis. Das Problem ist der Rückweg. Wird später ein Server unter *demselben
Namen* angelegt, aktualisiert er sich ab der ersten Nacht von selbst, ohne dass
jemand den Schalter angefasst hätte — und die Oberfläche zeichnet ihn zu Recht
als „an", weil die Liste das sagt. Aus „aus per Voreinstellung" wird damit
stillschweigend „an, wegen eines Servers, den es nicht mehr gibt". Gemessen am
2026-09-09: `starrupture` stand nach dem Entfernen weiter drin.

> *Removing a server takes it out of the list; both removal paths do it through
> one helper, next to the Borg-exclusion cleanup. The stale entry itself is
> harmless — `spiele-autoupdate` skips names without a directory — but the way
> back is not: a server later created under the same name updates itself from
> the first night with nobody having touched the switch, and the panel draws it
> as on, correctly, because the list says so.*

> *A switch per server, off by default, with no global one. Four conditions,
> each checked and logged separately: enabled, backup possible, quiet (under
> 4 kB/s measured over 20 s), and something actually new. A stopped server is
> updated without the traffic check — nobody is on it and no save is moving. A
> falling counter means a restart, not quiet. The timer is not persistent, so a
> missed run does not fire mid-day. The failure mode designed against: an update
> that silently breaks a save and surfaces days later, once the backup predating
> it has rotated out. A successful update is reported to the notices channel, a
> failed one to the faults channel.*

---

## Steam-Workshop `/workshop/{stack}` (#130)

Bei Spielen mit Workshop-Anbindung zeigt die Einstellungsseite einen Abschnitt
**Workshop**: die eingetragenen Mods mit Titel, Größe und Link, ein Feld für
**Link, ID oder ganze Sammlung** und — sobald ein Steam-Web-API-Schlüssel
hinterlegt ist — eine **Suche**. Entscheidungen von Jens (in #130 festgehalten):
`verwalten` darf das auch, und Mods werden **mitgesichert**.

**Jede ID wird bei Steam nachgeschlagen** und muss zu **genau** dem Spiel dieses
Servers gehören (`consumer_app_id` = `appid` des Katalogs; die Suche nennt
dasselbe Feld `consumer_appid` — nur den ersten Namen zu kennen, wies anfangs
jeden Suchtreffer als „anderes Spiel" ab, aufgefallen mit dem echten Schlüssel). Eine eingefügte Zahl
eines Mods für ein anderes Spiel, ein gesperrter oder ein unbekannter Eintrag
kommt nicht in die Konfiguration; die Prüfseite nennt den Grund. Größer als 2 GB
nimmt das Panel nichts an.

**Die Server laden selbst.** `bin/workshop` pflegt die Liste an der Stelle, an der
das Spiel sie erwartet; beim nächsten Start lädt der Server. Wo das ist, steht je
Spiel in `/etc/spiele-workshop.json`, jede Angabe am echten Server gemessen.

**Project Zomboid** braucht zwei Zeilen: `WorkshopItems=` (was geladen wird) und
`Mods=` (was davon aktiv ist). Die Mod-ID steht erst in der `mod.info` im
heruntergeladenen Inhalt — bei Build 42 unter `mods/<Name>/42/` oder
`mods/<Name>/common/`. Damit nicht zwei Neustarts nötig sind, lädt `workshop`
den Inhalt beim Eintragen mit dem steamcmd des Images vorab, als Eigentümer der
Daten, genau dorthin, wo der Server sucht (gemessen: 7–11 s für kleine Mods).
Von Hand eingetragene Mods in `Mods=` bleiben stehen. Nachgewiesen am
Testserver: eingetragen, ausgetragen, neu gestartet — das Log zeigt genau die
eingetragenen Mods (`loading AreaTasks`, `loading BetterFireExtinguishers`).

**Unturned** hat nur eine Liste: `File_IDs` in
`Servers/Default/WorkshopDownloadConfig.json` (`Default`, weil das Startskript
des Images keinen Namen übergibt). Der Server lädt beim Start jede eingetragene
ID selbst herunter und installiert sie nach
`Servers/Default/Workshop/Steam/content/304930/<id>` — kein Vorabladen nötig.
Alle anderen Felder der Datei bleiben, wie sie sind, ebenso Einträge, die nicht
nach Workshop-ID aussehen. Workshop-**Karten** lädt der Server so auch; spielen
muss man sie über `Map` in `Config.txt`, das bleibt Handarbeit. Nachgewiesen am
Testserver: zwei aktuelle Mods eingetragen, neu gestartet — `2 workshop item(s)
requested … Installed workshop item` für beide; eine Project-Zomboid-ID wird
abgewiesen („gehört zu einem anderen Spiel (App 108600)").

**Don't Starve Together** braucht wie Project Zomboid zwei Stellen:
`ServerModSetup("<id>")` in `serverfiles/mods/dedicated_server_mods_setup.lua`
(was der Server beim Start herunterlädt) und `["workshop-<id>"]={ enabled=true }`
in `Cluster_1/Master/modoverrides.lua` (was er davon lädt). Die ID ist hier
schon der Name — kein Vorabladen. `modoverrides.lua` ist Lua-Code, in dem ein
Eintrag Moduleinstellungen tragen kann; `workshop` fügt deshalb nur fehlende
Einträge ein und entfernt beim Austragen genau den eigenen Block, mit
Klammerzählung, die Zeichenketten und Kommentare überspringt. Handeinstellungen
(`configuration_options`), Kommentare und `ServerModCollectionSetup`-Zeilen
bleiben stehen; ein vorhandener, abgeschalteter Eintrag wird eingeschaltet. Der
Server lädt und aktiviert Mods schon **vor** der Anmeldung bei Klei; der Inhalt
landet unter `serverfiles/ugc_mods/Cluster_1/Master/content/322330/<id>`.
Nachgewiesen am Testserver, auch über den Panel-Weg nach einer frischen
Installation (`Loading mod: workshop-374550642 (Increased Stack size)`, `…
(Global Positions)`). Nur der Shard `Master`: Die Höhlen sind im Katalog aus und
nicht gemessen — wer sie einschaltet, muss dort `modoverrides.lua` von Hand
pflegen.

**Killing Floor 2** führt seine Liste in `LinuxServer-KFEngine.ini`, Sektion
`[OnlineSubsystemSteamworks.KFWorkshopSteamworks]`, eine Zeile
`ServerSubscribedWorkshopItems=<id>` je Element — dieselbe Taste mehrfach,
deshalb eigene Sektionslogik. Für die Spieler steht
`DownloadManagers=OnlineSubsystemSteamworks.SteamWorkshopDownload` als **erster**
Downloadmanager in `[IpDrv.TcpNetDriver]` (Tripwire-Wiki). Und: **Linux-Server
legen ihren Cache-Ordner nicht an** — ohne `KFGame/Cache` lädt der Server nichts
und sagt es nicht (Steam führte die IDs nicht einmal als benötigt). `workshop`
legt ihn an. Gemessen: zwei Elemente in unter 40 s nach
`KFGame/Cache/<id>/0/BrewedPC/`; die INI bleibt über einen Neustart unverändert,
auch wenn sie bei laufendem Server geändert wurde (Tripwires Warnung davor traf
dieses Build nicht). Karten müssen danach in den Kartenzyklus, Mutatoren in die
Startparameter — das bleibt Handarbeit.

**Größe.** Für manche Elemente nennt Steams schlüssellose Detailabfrage
`file_size: 0` — bei Killing Floor 2 für jedes gemessene, während die Suche
3,6 MB meldet. Die 2-GB-Grenze liefe dort ins Leere. Mit Schlüssel fragt
`workshop` bei `IPublishedFileService/GetDetails` nach (ohne antwortet sie mit
401); bleibt die Größe unbekannt, wird das Element **abgewiesen**, nicht
durchgewunken.

**Aufräumen.** Beim Speichern löscht `workshop` den Inhalt **jeder** nicht
eingetragenen ID, nicht nur der gerade ausgetragenen — Mods werden mitgesichert,
und die Sicherung soll nicht mit Totem wachsen. Alle, weil Steam am
Unturned-Testserver einen gelöschten Ordner beim nächsten Start einmal
wiederhergestellt hat (einer von drei Versuchen, in dem Lauf, in dem ein anderer
Download scheiterte). Geladen wird so ein Ordner nicht; das nächste Speichern
räumt ihn weg. Nur Ordner mit reinem Zahlennamen, keine Symlinks.

> *Workshop section for games with a binding: installed mods, a field for a
> link, id or whole collection, and a search once a Steam Web API key is set.
> verwalten may use it and mods are backed up (Jens' decisions in #130). Every
> id is looked up at Steam and must belong to exactly this game. The servers
> download themselves; `bin/workshop` maintains the list where each game
> expects it (`/etc/spiele-workshop.json`, measured per game). Project Zomboid
> needs both `WorkshopItems=` and `Mods=`; the mod id comes from `mod.info`, so
> the content is pre-fetched with the image's steamcmd. Unturned has one list,
> `File_IDs` in `WorkshopDownloadConfig.json`, and downloads itself at start.
> Don't Starve Together needs `ServerModSetup` in the setup file and an enabled
> entry in `modoverrides.lua` (Lua: only missing entries are added, only our
> own block is removed, by brace counting that skips strings and comments;
> the Master shard only). Killing Floor 2 uses a repeated key in one INI
> section plus the Workshop download manager first; Linux servers need
> `KFGame/Cache` created or they download nothing, silently. Where Steam's
> keyless details report size 0, the size is fetched with the key; unknown
> size is refused.
> Saving deletes the content of every id not listed (Steam once restored a
> deleted folder). Both proven end to end on test servers.*

### Integrationen `/integrationen` (nur admin)

Schlüssel fremder Dienste — bisher der **Steam-Web-API-Schlüssel** für die
Workshop-Suche (ohne ihn antwortet Steam auf eine Suche mit 403; Details und
Sammlungen gehen ohne). Jens: *„der Steam-API-Key muss irgendwo im Panel
hinterlegbar sein."* Das Feld ist **nur zum Schreiben**: angezeigt wird nie der
Wert, nur ob einer gesetzt ist und seine letzten vier Zeichen. Beim Speichern
wird er bei Steam geprüft; ein abgelehnter Schlüssel wird nicht gespeichert.
Er liegt in `/opt/panel/daten/steam-api.conf` (`0600 panel`) — nicht in `/etc`,
dort darf das Panel nicht schreiben — und ist damit Teil der Sicherung (#218).
Setzen und Entfernen stehen im Protokoll, mit den letzten vier Zeichen.

> *Keys for outside services, admin only — so far the Steam Web API key for the
> Workshop search. Write-only: never shown, only whether one is set and its last
> four characters. Checked at Steam before saving; stored under
> `/opt/panel/daten` (backed up), logged without the value.*

#### TeamSpeak: ein Kanal je Spielserver (#137)

Jens' Wunsch: Jeder installierte Spielserver bekommt einen Kanal auf dem
TeamSpeak-Server, automatisch, und der Kanal verschwindet wieder, wenn der
Server entfernt wird. **Aus, bis er hier eingeschaltet wird.** Einzustellen sind
der Zugang (ServerQuery-Benutzer und -Passwort, nur zum Schreiben, beim Speichern
bei TeamSpeak geprüft — über stdin, nie als Argument), der **Oberkanal**, unter
dem die Kanäle entstehen (Vorgabe „Spieleserver"), und das **Namensmuster**
(`{name}` = Name des Servers). Die Tabelle darunter zeigt, welcher Server welchen
Kanal hat.

Angelegt und gelöscht wird **nie im Seitenaufruf**, sondern von
`kanal-verwalten` im Dienst `kanal-abgleich` — angestoßen nach jeder Installation
und Entfernung, dazu alle fünf Minuten. Welche Server es gibt, sagt
`/opt/stacks`; die Zuordnung Server → Kanal-ID steht in
`/opt/panel/daten/kanaele-zuordnung.json`. Gibt es nichts zu tun, verbindet sich
der Dienst gar nicht erst.

**Gelöscht wird nur, was unberührt ist** (Jens' Entscheidung): von Platzwart
angelegt — erkannt an der gespeicherten ID, nicht am Namen —, weder umbenannt
noch verschoben, ohne Unterkanäle, niemand drin. Sonst bleibt der Kanal stehen,
steht im Protokoll und wird nach `#platzwart-stoerung` gemeldet. Einen Kanal
gleichen Namens, den jemand von Hand angelegt hat, übernimmt das Werkzeug als
„von Hand angelegt" und löscht ihn nie. Die Bestätigungsseite „Server entfernen"
sagt **vor** dem Klick, was mit dem Kanal geschieht.

**Namen.** Ein Kanal heißt wie sein Server: bei Katalogspielen der Name aus
`panel.json`, sonst der Katalogname, sonst der Stackname mit großem
Anfangsbuchstaben (Enshrouded, Palworld … — die von Hand gebauten Server haben
keinen anderen Namen). Weicht der Soll-Name später ab, etwa nach einer Änderung
des Namensmusters, benennt der Abgleich Kanäle um, die Platzwart angelegt hat —
aber nur, wenn sie noch so heißen, wie Platzwart sie genannt hat. Hat ein Mensch
einen Kanal umbenannt, gewinnt der Mensch.

**Flutschutz.** ServerQuery erreicht TeamSpeak über das Docker-Gateway, nicht
von `127.0.0.1` — die Anfragen stehen also nicht auf seiner Allowlist. Gemessen:
drei Anmeldungen kurz hintereinander, und TeamSpeak antwortete `client is
flooding` und nahm danach länger als zwei Minuten keine Verbindung an. Das
Werkzeug schickt deshalb höchstens einen Befehl je 0,6 s, eine Verbindung je
Lauf, und benennt eine Drosselung als solche.

**Discord** läuft genauso, mit einem Bot (ein Webhook kann keine Kanäle
anlegen): eine eigene Kategorie (Vorgabe „Spieleserver", öffentlich), je
Spielserver ein **Textkanal** (Discord schreibt ihn klein: `#valheim`) und ein
**Sprachkanal** (`🔊 Valheim`, #244). Unberührt heißt dort
zusätzlich: **Kanalrechte unverändert und noch nie eine Nachricht darin** —
Discord bewahrt den Verlauf, und der geht nie mit verloren. Beim Sprachkanal
kommt „niemand drin" dazu — und das kennt Discords REST-Schnittstelle nicht, nur
das Gateway. `kanal-verwalten` meldet sich deshalb, wenn ein Sprachkanal zum
Löschen ansteht, kurz am Gateway an (Intents `GUILDS` und `GUILD_VOICE_STATES`,
beide nicht privilegiert), liest die Belegung und trennt (gemessen: 1,4 s).
Klappt das nicht, bleibt der Sprachkanal bis zum nächsten Abgleich stehen, statt
blind gelöscht zu werden. Server aus der Zeit vor #244 bekommen ihren
Sprachkanal beim nächsten Abgleich nachgereicht. Der Bot wird mit
Token und Server-ID hinterlegt und beim Speichern geprüft (Mitglied des Servers,
darf Kanäle verwalten). Nachgewiesen am echten Discord-Server mit einer privaten
Testkategorie: angelegt (die Kanäle erben die Rechte der Kategorie), Vorschau,
ein Kanal mit einer Nachricht blieb stehen, ein von Hand angelegter ebenfalls,
der unberührte wurde gelöscht. Der Bot hat auf dem Discord-Server
Administratorrechte — Jens' Entscheidung, E33.

> *One TeamSpeak channel per game server, off until switched on here: write-only
> ServerQuery credentials (checked at TeamSpeak via stdin), a parent channel and
> a name pattern. Channels are created and deleted by the kanal-abgleich service,
> never in a page request — triggered after installs and removals and every five
> minutes; `/opt/stacks` is the only list of servers. Deleted only if untouched:
> created by Platzwart (stored id, not name), not renamed or moved, no
> subchannels, nobody inside — otherwise kept, audited and reported. Names come
> from panel.json, the catalogue or the capitalised stack name; a changed target
> name renames Platzwart's channels unless a person renamed them. The removal
> confirmation page says which before the click. ServerQuery is flood-limited
> (measured), so commands are paced. Discord works the same with a bot (a
> webhook cannot create channels): its own public category, one text channel per
> server plus a voice channel (#244); untouched there also means unchanged
> permissions and never a single message — history is never deleted — and, for
> voice, nobody inside, which only the Gateway knows: a short Gateway session
> (non-privileged intents) reads occupancy; if it fails, the channel waits for the
> next run. The bot is checked when saved; it has
> administrator rights on the Discord server by Jens' decision (E33).*

## Mods hochladen `/mods/{stack}`

Wo kein Katalog hinreicht, bringt der Betreiber die Datei selbst mit. Nach der
Messung in #130 (2026-09-10) war das der Normalfall: Von den sieben damals
laufenden Servern nahm **keiner** Steam-Workshop-Mods auf eine Weise, die uns
nützt. Den Workshop gibt es seither für vier Katalogspiele (oben); für alles
andere bleibt der Upload.

**Nur für Administratoren**, nicht für `verwalten`. Ein Mod ist Code, der *im*
Spielserver läuft — mit dessen Bind-Mount und dessen Netzzugang. Einen von Hand
gebauten Server zu entfernen ist bereits admin-only, weil er sich nicht aus dem
Katalog wiederherstellen lässt; fremden Code hineinzulegen ist mindestens
dasselbe.

Die Seite zeigt, wohin ein Mod gehört, ob das Verzeichnis gesichert wird, die
schon vorhandenen Mods mit Größe (jeden mit einem Knopf „entfernen") und ein
Feld zum Hochladen einer Datei. Nach dem Hochladen oder Entfernen muss der
Server neu starten, damit er den Mod lädt.

> *Where no catalogue reaches, the operator brings the file. Per the measurement
> in #130 (2026-09-10) that was the normal case — none of the seven servers
> running then took Workshop mods usefully; the Workshop has since been added for
> four catalogue games, and everything else keeps the upload. Admin only, not
> verwalten: a mod is code running inside the game server with its bind mount
> and network access, and putting third-party code in is at least as serious as
> removing a hand-built server, which is admin-only already. The page shows where
> a mod goes, whether that directory is backed up, the existing mods with size
> and a remove button, and an upload field; the server needs a restart to load a
> change.*

### Wohin ein Mod gehört, steht in einer Datei — und wird nicht geraten

`/etc/spiele-mods.json`, eine Angabe je Spiel. Steht ein Spiel dort nicht drin,
**weist das Panel den Upload ab und sagt warum**:

> Für palworld ist nicht hinterlegt, wohin ein Mod gehört. Ein Mod im falschen
> Verzeichnis tut nichts, und es fällt niemandem auf — deshalb wird hier nicht
> geraten.

Das ist der Grund für die Strenge: Ein Mod am falschen Ort erzeugt **keinen
Fehler**. Der Server startet, das Spiel läuft, der Mod fehlt — und niemand
sucht danach.

Gemessen am 2026-09-10: Von den sieben Servern hatte **nur FOUNDRY** überhaupt
ein Mod-Verzeichnis (`server/Mods`). Heute stehen zwei Spiele in der Datei:
FOUNDRY und Valheim.

> *Where a mod belongs is configured per game in `/etc/spiele-mods.json`; a game
> not listed there has its upload refused with the reason, because a mod in the
> wrong directory produces no error at all — the server starts, the game runs,
> the mod is absent and nobody looks for it. Measured on 2026-09-10, only
> FOUNDRY had a mod directory at all; today the file lists FOUNDRY and Valheim.*

**Valheim (#153)** nimmt Mods über **BepInEx** an, einen Lader, den das
ich777-Image selbst mitbringt: `ENABLE_BEPINEX` unter *Konfiguration* auf `true`
setzen und neu starten. Das Image lädt dann bei **jedem** Start die neueste
Fassung von `denikson/BepInExPack_Valheim` von Thunderstore — ohne feste Version
und ohne Prüfsumme (E32). Die Mods gehören nach `serverfiles/BepInEx/plugins`;
fehlt `BepInEx/core`, weist der Upload ab und nennt den Schalter, statt eine
Datei abzulegen, die nie geladen wird (`voraussetzung` in `spiele-mods.json`).
Gemessen an einem Wegwerf-Container desselben Images: BepInEx 5.4.2350
installiert, `Chainloader startup complete`, ein Plugin in `plugins` wird geladen
(`Loading [Jotunn 2.30.0]`). Viele Valheim-Mods verlangen dieselbe Version bei
jedem Mitspieler — vor dem Hochladen absprechen.

Den Schalter hat der laufende Valheim-Server über `spiel-verwalten
katalog-abgleich` bekommen: Er trägt Katalogvariablen, die einem schon
installierten Server fehlen, mit ihrem wörtlichen Vorgabewert nach (nie
Platzhalter, nie einen gesetzten Wert) — über `compose-feld anlegen`, mit
demselben Gerüstvergleich wie jede Änderung. Das Panel selbst kann nichts
anlegen, nur setzen, was dasteht. Stufe 30 und `ausrollen.sh` rufen den Abgleich
auf, sobald der Katalog neu eingesetzt wird; er startet nichts neu.

> *Valheim takes mods through BepInEx, which the ich777 image installs itself when
> `ENABLE_BEPINEX` is true — fetching the latest pack from Thunderstore on every
> start, unpinned (E32). Mods go to `BepInEx/plugins`; without `BepInEx/core` the
> upload is refused with the way to fix it. Measured on a throwaway container.
> `spiel-verwalten katalog-abgleich` adds catalogue variables an installed server
> lacks (literal defaults only) through `compose-feld anlegen` and its structural
> check; the panel itself can only set what exists.*

### Zip Slip, und warum jeder Eintrag einzeln geprüft wird

Ein Archiv bringt seine eigene Fassung der Falle mit, die schon `konfig-datei`
geformt hat — dort war es ein Symlink `z: -> /` unter StarRupture. Hier:

* ein Eintrag namens `../../../../etc/cron.d/uebernahme`
* oder einer, der **selbst ein Symlink** auf `/` ist

Beide werden vom Entpacker geschrieben, **bevor** irgendeine nachträgliche
Pfadprüfung greifen kann. Deshalb wird jeder Eintrag **einzeln und vor dem
Entpacken** am aufgelösten Ziel geprüft, und Archive mit Symlinks werden gar
nicht erst angefasst.

Entpackt wird in ein Zwischenverzeichnis, nicht ins Ziel — was dort landet, ist
ungeprüft; erst nach allen Prüfungen wird verschoben.

> *An archive brings its own version of the trap that shaped `konfig-datei` —
> there a `z: -> /` symlink under StarRupture: an entry named
> `../../../../etc/cron.d/uebernahme`, or one that is itself a symlink to `/`.
> Both are written by the extractor before any later path check can apply. So
> every entry is checked individually and before extraction, against the
> resolved target, and archives containing symlinks are refused outright.
> Extraction goes to a staging directory; only after all checks is anything
> moved into place.*

### Weitere Schranken

| Schranke | Warum |
|---|---|
| Endungen `.zip .dll .jar .pak .json .cfg .txt .lua` | alles andere hat in einem Mod-Verzeichnis nichts zu suchen |
| höchstens 512 MB | ARKs Workshop-Elemente sind 319 MB — die Größenordnung ist real |
| mindestens 10 GB frei | auf einer vollen Platte scheitert als Erstes die **Sicherung**, und dann ist der Rückweg weg, bevor etwas passiert |
| Dateiname ohne Pfadanteile | **abgewiesen, nicht zurechtgebogen** |
| Eigentümer vom Zielverzeichnis übernommen | FOUNDRYs Fremdabbild besteht auf uid 1000, die anderen laufen als 4711 — eine Datei mit falschem Eigentümer ist ein Mod, der stillschweigend nicht lädt |

Der erste Entwurf nahm beim Dateinamen erst den Basisnamen und prüfte **danach**
auf `/` — eine Prüfung, die nach `basename()` nie anschlagen kann.
`../../boese.dll` wäre als `boese.dll` klaglos gelandet. Sicher war das, aber
still; wer so einen Namen schickt, soll eine Antwort bekommen.

> *Further limits: eight extensions (anything else has no business in a mod
> directory), at most 512 MB (ARK's Workshop items are 319 MB, so the order of
> magnitude is real), at least 10 GB free (on a full disk the backup fails
> first, and then the way back is gone before anything happens), file names
> without path parts — refused, not bent into shape — and ownership taken from
> the target directory (FOUNDRY's image insists on uid 1000, the others run as
> 4711, and a file with the wrong owner is a mod that silently does not load).
> The first draft took the basename and only then checked for "/" — a check that
> can never fire after `basename()`; safe, but silent.*

### Fällt das Verzeichnis unter einen Sicherungsausschluss?

Dann sagt das Panel es **vor** dem Hochladen. Für FOUNDRY ist das der Fall:
`server/Mods` liegt in `server/`, und das ist ausgeschlossen — ein Mod dort
überlebt keine Neuinstallation. Gelesen wird die echte `/etc/borg-ausschluss.txt`,
nicht geraten, mit Borgs Musterregel (`*` innerhalb eines Pfadteils, #231).

> *If the target directory falls under a backup exclusion, the panel says so
> before the upload. For FOUNDRY it does: `server/Mods` sits inside `server/`,
> which is excluded, so a mod there does not survive a reinstall. The real
> exclusion file is read, using borg's pattern rule.*

### Die Bytes gehen über stdin, nicht als Argument

Argumente stehen für jeden Benutzer der Maschine in der Prozessliste. Das Panel
selbst **prüft die Datei nicht** — es läuft unprivilegiert und soll gar nicht
erst in die Lage kommen, etwas auszupacken.

> *The bytes travel on stdin, not as an argument — arguments are visible to
> every user of the machine in the process list. The panel does not check the
> file itself: it runs unprivileged and should never be in a position to unpack
> anything.*

---

## Leerlauf: schlafen legen und beim Beitritt wecken

Sieben Server belegen im Leerlauf 12,1 GiB, und die Summe ihrer Grenzen ist
doppelt so groß wie der Arbeitsspeicher der Maschine. Ein Server, auf dem
niemand ist, muss nicht laufen.

Der Schalter steht auf der **Einstellungsseite** jedes Servers (`leerlauf an` /
`leerlauf aus`), aus per
Voreinstellung, je Server — dieselbe Regel wie beim Auto-Update, und aus
demselben Grund: Eine Automatik, die alles auf einmal betrifft, ist die, die man
später nicht mehr zuordnen kann. Der Schalter schaltet die **Automatik**, nicht
den Server: „leerlauf aus" hält ihn nicht an.

> *Seven servers idle at 12.1 GiB, and the sum of their limits is twice the
> machine's memory; a server nobody is on does not need to run. The switch sits
> on every server's settings page, off by default and per server — the same
> rule as auto-update, for the same reason. It switches the automation, not the
> server: "leerlauf aus" does not stop it.*

### Das Aufwecken hält systemd, nicht ein eigenes Programm

Solange ein Server schläft, hört **systemd** auf seinen Spielports. Beim ersten
Paket hält es den Weckposten an, gibt die Ports frei und startet den Container.
Es gibt hier kein selbst geschriebenes Stück Code, das auf einem öffentlichen
Port Pakete liest.

Das erste Paket geht dabei verloren. Spielclients versuchen es erneut, und ein
Server, der ohnehin eine Minute zum Starten braucht, wird nicht dadurch besser,
dass man das eine Paket aufhebt.

> *While a server sleeps, systemd listens on its game ports. On the first
> packet it stops the wake socket, frees the ports and starts the container.
> There is no hand-written code reading packets on a public port. The first
> packet is lost; game clients retry, and a server needing a minute to start
> gains nothing from keeping that one packet.*

### ufw muss die Ports durchlassen — aber nur, solange geschlafen wird

Das ist die Falle, die dieses System ohnehin prägt, hier von der anderen Seite:

* Ein **laufender** Container bekommt seinen Verkehr über Dockers DNAT und die
  `FORWARD`-Kette, und die liegt **vor** den ufw-Ketten. ufw sieht ihn nie.
* Ein **schlafender** Server hat systemd auf dem Wirt lauschen — und derselbe
  Verkehr läuft plötzlich durch `INPUT`. Dort ist die Voreinstellung `DROP`.

Gemessen am 2026-09-10: Der Weckposten lauschte, `NAccepted=0`, und ein Paket
von außen kam nie an. Dasselbe Paket von der Maschine selbst weckte sofort —
Loopback lässt ufw durch.

`platzwart-schlaf` legt die Regeln deshalb beim Schlafenlegen an und **nimmt sie
beim Aufwecken wieder weg**. Eine Regel, die nichts tut, aber dasteht, macht aus
`ufw status` eine Liste, der man nicht mehr glaubt.

> *This is the trap that shapes the whole system, from the other side: a
> running container gets its traffic via Docker's DNAT in the FORWARD chain,
> ahead of ufw, so ufw never sees it; a sleeping server has systemd listening on
> the host, and the same traffic suddenly goes through INPUT, where the default
> is DROP. Measured on 2026-09-10: the wake socket listened with
> `NAccepted=0`, and a packet from outside never arrived, while the same packet
> from the machine itself woke it at once — loopback passes ufw. So the rules
> are added when a server goes to sleep and removed again on wake-up; a rule
> that does nothing but stays makes `ufw status` a list nobody believes.*

### Zwei Fehler, die es fast lautlos gegeben hätte

**Der Weckdienst darf sich nicht selbst anhalten.** Der erste Entwurf rief
`systemctl stop` auf den Socket aus dem Dienst heraus, den systemd gerade
startete — das verklemmt sich, der Dienst endete mit Status 1 und der Container
kam nie hoch. Von Hand lief derselbe Befehl anstandslos, was die Suche
verlängerte. Richtig ist `Conflicts=` in der Unit: systemd hält den Posten als
Teil derselben Transaktion an.

**Startet der Container, während die Ports noch gehalten werden, kommt er ohne
veröffentlichte Ports hoch** — er steht auf „Up" und ist für niemanden
erreichbar, und Docker meldet dabei **keinen Fehler**. Deshalb wartet
`platzwart-schlaf` erst, bis die Ports frei sind, und prüft danach das
**Ergebnis** statt des Rückgabewerts. Fehlen Ports, wird einmal neu erzeugt;
bleibt es dabei, meldet sich der Platzwart.

> *Two faults that almost went silent. The wake unit must not stop its own
> socket: the first draft called `systemctl stop` on the socket from inside the
> service systemd was starting, which deadlocked — the service ended with status
> 1 and the container never came up, while the same command by hand worked
> fine. `Conflicts=` in the unit is the right mechanism: systemd stops the
> socket as part of the same transaction. And a container started while the
> ports are still held comes up without published ports — "Up", reachable by
> nobody, and Docker reports no error. So the tool waits until the ports are
> free and checks the result rather than the return code; missing ports trigger
> one recreate, and if they stay missing, Platzwart reports it.*

### Wann ein Server als leer gilt

| Grundlage | Frist | Warum |
|---|---|---|
| **Echte Spielerzahl** | 30 min leer | eine Zahl ist eine Aussage |
| **Nur Netzverkehr** | 180 min unter 1,5 kB/s | ein Stellvertreter, deshalb die deutlich längere Frist |

**Eine fehlende Spielerzahl gilt nie als null.** Sonst legte sich ein Server
schlafen, über den man gar nichts weiß — mitten im Spiel.

> *When a server counts as empty: 30 minutes at a real player count of zero —
> a number is a statement — or, where there is only traffic, 180 minutes under
> 1.5 kB/s, a stand-in and hence the much longer period. A missing player count
> never counts as zero, or a server nobody knows anything about would go to
> sleep mid-game.*

### Fehlwecken sind eingeplant

Ein Portscan weckt den Server. Das ist gewollt harmlos: Wenn niemand beitritt,
ist er beim nächsten Durchlauf wieder leer und legt sich wieder hin. Teuer wäre
nur ein Flattern — deshalb werden die Weckvorgänge gezählt, und häufen sie sich
(mehr als zwölf an einem Tag), meldet sich der Platzwart mit dem Befehl zum
Abschalten.

**Abschalten weckt sofort.** Ein schlafender Server, dessen Automatik gerade
abgeschaltet wurde, bliebe sonst liegen — und niemand könnte sich das erklären.

**Ein Verwaltungsport weckt nie.** `ports_filtern` nimmt nur, was nicht auf
`127.0.0.1` gebunden ist. Stünde TeamSpeaks ServerQuery in der Weckliste, hielte
systemd ihn nach dem Schlafenlegen auf `0.0.0.0` offen und machte aus einem
localhost-Port einen öffentlichen.

> *Wake-ups are planned for: a port scan wakes the server, which is harmless by
> design — with nobody joining, the next run finds it empty and puts it back.
> Only flapping would be expensive, so wake-ups are counted, and more than twelve
> in a day are reported with the command to switch the feature off. Switching it
> off wakes a sleeping server at once, or it would stay down with nothing left to
> wake it. Management ports never wake anything: only ports not bound to
> localhost are taken, or systemd would hold TeamSpeak's ServerQuery on
> `0.0.0.0` while asleep and turn a localhost port into a public one.*

### Spiele ohne Beitrittspasswort: Freigabe von Hand

Minecraft und TeamSpeak **kennen** kein Beitrittspasswort (`passwort.art: keins`).
Bis #183 gingen sie deshalb kurz nach der Installation ans Netz. Seit Jens'
Entscheidung zu E26 — *„Ein Server ohne Passwort darf nicht automatisch ans Netz
gehen"* — bleibt ihr Port zu, bis jemand mit `verwalten` oder `admin` ihn auf der
Einstellungsseite freigibt. Die Rückfrageseite sagt **vor** dem Klick, was den
Server stattdessen schützt: bei Minecraft die Whitelist (`ENFORCE_WHITELIST`,
`WHITELIST`), bei TeamSpeak das Serverpasswort im Client. Die Freigabe steht im
Protokoll.

Die Prüfung „nur bei `keins`" sitzt in `spiel-einrichtung --freigeben`, nicht im
Panel — ein anderer Aufrufweg soll sie nicht umgehen können; für jede andere
Passwortart wäre die Freigabe ein Weg an E26 vorbei. Und nur `spiel-einrichtung`
schreibt die Freigabe, unter derselben Sperre wie der Timer: Schriebe
`panel-aktion` sie selbst, könnte ein gleichzeitiger Lauf sie mit seiner älteren
Fassung überschreiben. Veröffentlicht wird danach über den einen Weg,
`port-ermitteln`.

**Whitelist pflegen (#185).** Die Minecraft-Einträge erzwingen die Whitelist —
ohne einen Weg, Namen einzutragen, kam nach der Freigabe niemand hinein (von Jens
bemerkt). Die Einstellungsseite hat deshalb bei Minecraft (Java) einen Abschnitt
**Whitelist**: eintragen, entfernen, Liste. `panel-aktion whitelist` spricht
dazu `rcon-cli` **im** Container an; der Server schreibt `whitelist.json` selbst,
sofort und ohne Neustart, und prüft den Namen bei Mojang („That player does not
exist"). Der Name wird vorher streng geprüft (3–16 Zeichen aus Buchstaben,
Ziffern, `_`) und geht als eigenes Argument weiter, nie durch eine Shell;
eingeschleuste Befehle wie `Notch; op Notch` weist zusätzlich schon der Server
ab (gemessen). Nur bei laufendem Server, nur Java — Bedrock hat eine andere
Liste.

> *Minecraft and TeamSpeak have no join password. Since #183 their port stays
> closed until someone with verwalten or admin releases it on the settings page;
> the confirmation page says what protects the server instead (whitelist, client
> server password). The "keins only" check and the write live in
> `spiel-einrichtung --freigeben`, under the timer's lock; publishing goes through
> `port-ermitteln` The settings page manages the Minecraft whitelist
> (#185) through `rcon-cli` inside the container: live, persisted by the server,
> names checked strictly and passed as their own argument; Java edition only.*

### Beim Entfernen verschwindet auch der Leerlauf

Keiner der beiden Entfernwege räumte den Leerlauf ab (#169), und die Prüfschleife
überspringt einen Server ohne Verzeichnis stumm. Wer **im Schlaf** entfernt
wurde, hinterließ seinen Weckposten (der die Ports weiter hält), dessen
ufw-Freigaben und den Listeneintrag — ein späterer Server gleichen Namens hätte
sich ab dem ersten leeren Abend schlafen gelegt. Jetzt ruft das Entfernen
`platzwart-schlaf --vergessen <stack>` — **nach** der letzten Sicherung (scheitert
die, hat sich nichts geändert) und **ohne** den Server zu starten, anders als
„leerlauf aus".

Die ufw-Regeln werden dabei auch über ihren **Kommentar** gefunden
(`platzwart-schlaf:<stack>`), nicht nur über den Zustand: Beim ersten Test
blieben zwei Regeln stehen, weil der Zustand die Ports nicht mehr kannte.

> *Neither removal path cleared idle sleep (#169), and the check loop skips a
> server without a directory silently. A server removed while asleep left its
> wake socket (still holding the ports), its ufw rules and its list entry — a
> later server of the same name would have gone to sleep from its first empty
> evening. Removal now calls `platzwart-schlaf --vergessen <stack>` — after the
> final backup (if that fails, nothing has changed) and without starting the
> server, unlike "leerlauf aus". The ufw rules are also found by their comment,
> not only through the state: in the first test two rules stayed behind because
> the state no longer knew the ports.*

### Ein Lauf zur Zeit

Der Grund dafür: Timer, Wecken, `--schlafen` und `--vergessen` lesen alle den
Zustand, ändern ihn und schreiben ihn zurück. Der Timer startete eine Sekunde vor
einem `--schlafen` und schrieb danach seine ältere Fassung zurück — die Ports des
schlafenden Servers waren weg. Zwischen Timer und Wecken hätte derselbe Fehler
einen wachen Server als schlafend geführt. Jeder Lauf nimmt deshalb eine Sperre
(`/run/platzwart-schlaf.lock`); das Wecken wartet höchstens einen Timerlauf ab.
Nachgestellt mit Timer und `--schlafen` gleichzeitig: Die Ports blieben im
Zustand, und das Entfernen im Schlaf ließ nichts zurück — kein Weckposten, keine
ufw-Regel, kein Listeneintrag, keine Zugangsdaten, kein DNS-Name.

> *One run at a time: the timer, waking, `--schlafen` and `--vergessen` all read
> the state, change it and write it back. The timer started a second before a
> manual `--schlafen` and then wrote its older copy back — the sleeping server's
> ports were gone; between timer and waking the same fault would have listed an
> awake server as asleep. Every run therefore takes a lock
> (`/run/platzwart-schlaf.lock`); waking waits at most one timer run.
> Reproduced with timer and `--schlafen` at once: the ports stayed in the state,
> and removal while asleep left nothing behind — no wake socket, no ufw rule, no
> list entry, no credentials, no DNS name.*

---

## Der Verlauf auf der Karte

Bis zum 2026-09-10 war alles im Panel eine **Momentaufnahme**. Es konnte zeigen,
dass `foundry` 4,3 von 6 GiB belegt — aber nicht, ob das seit Wochen so ist oder
seit drei Tagen steigt. Und genau das ist die Frage, die man stellt.

Auf der Karte eines laufenden Servers steht deshalb jetzt eine kleine Linie: der
Speicherverlauf der letzten 24 Stunden. Der Tooltip nennt Bereich und Zeitraum.

> *Until 2026-09-10 everything in the panel was a snapshot: it could show that
> `foundry` uses 4.3 of 6 GiB, but not whether that has been true for weeks or
> has been climbing for three days — which is the question one asks. The card of
> a running server now carries a small line: the memory history of the last 24
> hours, with range and period in the tooltip.*

### Ein Ringpuffer, keine Zeitreihendatenbank

`platzwart-verlauf` schreibt alle fünf Minuten einen Wert nach
`/var/lib/platzwart-verlauf.json`:

```
{"foundry": [[zeit, mem_mb, cpu_prozent, spieler|null], ...]}
```

2016 Werte je Server sind bei diesem Abstand **eine Woche** und kosten rund
60 kB. Dafür braucht es keinen Dienst, keinen Port und keine
Aufbewahrungsregel, über die man streiten kann.

> *`platzwart-verlauf` writes one sample every five minutes — time, memory in
> MB, CPU percent, players or null. 2016 samples per server are a week at that
> spacing and cost about 60 kB: no service, no port, no retention policy to
> argue about.*

### Nichts zu messen ist kein Fehler

Läuft kein Container — frische Maschine, letztes Spiel entfernt, alles
angehalten —, endet `platzwart-verlauf` ohne Fehler und schreibt keine Zeile
(#191). Bis dahin endete es mit Exit 1, und seit die Wache fehlgeschlagene
Dienste meldet (#171), schlug jede neue Maschine vor ihrem ersten Spiel Alarm.
Antwortet Docker **nicht**, bleibt es ein Fehler: Ein Verlauf, der still
aufhört, ist schlimmer als einer, der sich beschwert. Und entfernt wird nur,
was es als Container nicht mehr gibt — bis #191 verlor ein **angehaltener**
Server bei jedem Lauf seine ganze Woche, weil `docker stats` nur laufende
Container kennt.

> *Nothing running is not an error (#191): no row, exit 0 — it used to exit 1,
> which the wache turned into a false alarm on every fresh machine. Docker not
> answering still fails. Only containers that no longer exist are dropped; a
> stopped server used to lose its week on every run.*

### Die Lücken sind der springende Punkt

**Jeder Wert trägt seine eigene Zeit**, sie wird nicht aus einem festen Abstand
gerechnet. Fällt ein Lauf aus, entsteht dadurch eine Lücke, die man sehen kann.

Die Linie wird an jedem Abstand über dem Doppelten des Messtakts **unterbrochen**.
Eine durchgezogene Linie behauptete sonst Messwerte, die es nie gab — und
ausgerechnet ein Ausfall sähe aus wie ein besonders ruhiger Verlauf. Der Tooltip
zählt die Lücken mit.

Aus demselben Grund steht im Timer `Persistent=false`: Ein nachgeholter Lauf
schriebe einen Messwert mit falschem Zeitstempel und schüttete genau die Lücke
zu, die man sehen soll.

> *Every sample carries its own time rather than one derived from a fixed
> spacing, so a missed run leaves a visible gap. The line breaks wherever the
> spacing exceeds twice the sampling interval — drawn straight through, it would
> claim readings that never existed, and an outage would look like a
> particularly calm stretch; the tooltip counts the gaps. For the same reason the
> timer is `Persistent=false`: a caught-up run would write a sample with the
> wrong timestamp and fill in the very gap one is meant to see.*

### Was bewusst nicht passiert

* **Nicht aus dem Seitenaufbau messen.** Die Übersicht **liest** nur. Ein
  zusätzlicher `docker stats`-Aufruf je Seitenaufruf wäre spürbar.
* **Keine alte Spielerzahl in den Verlauf schreiben.** Nur frische Werte gehen
  hinein — eine alte Zahl läse sich später als Messwert dieses Zeitpunkts.
* **Entfernte Server verschwinden.** Sonst wüchse die Datei mit jedem
  gelöschten Spiel weiter und der Verlauf zeigte Geister.

Nachgewiesen: Eine Reihe mit 40 Minuten Pause ergibt **zwei** Liniensegmente und
`1 Messlücke(n)` im Tooltip, eine durchgehende Reihe **eines**.

> *What deliberately does not happen: no measuring during page rendering — the
> overview only reads, and an extra `docker stats` per page view would be
> noticeable; no stale player counts in the history, since an old number would
> later read as a measurement of that moment; and removed servers drop out, or
> the file would grow with every deleted game and the history would show
> ghosts. Proven: a series with a 40-minute pause yields two line segments and
> "1 gap" in the tooltip, a continuous one a single segment.*

---

## Auf dem Telefon: `manifest.webmanifest`

Die Oberfläche lässt sich als App installieren — Android über „Zum Startbildschirm
hinzufügen", iOS über Teilen → Zum Home-Bildschirm. `display: standalone` nimmt
die Browserleiste weg.

**Der Gewinn liegt nicht im Aussehen, sondern bei den Passkeys.** Auf dem Telefon
wird aus „Authenticator öffnen, sechs Ziffern ablesen, tippen bevor sie ablaufen"
ein Fingerabdruck. Und das Panel ist genau das, wonach man unterwegs greift:
*Läuft der Server noch? Starte ihn neu.*

Drei Entscheidungen:

* **Erzeugt, nicht als Datei ausgeliefert.** Zwei Werte kommen aus der
  Konfiguration (der Name der Welt); eine Datei müsste beim Ausrollen ersetzt
  werden, und dann gäbe es sie zweimal.
* **Die Symbole zeichnet `werkzeuge/logo.py`**, jetzt auch in 192 und 512 —
  nicht von Hand daneben gelegt. Genau dafür gibt es das Werkzeug.
* **Kein Service Worker.** Ein Offline-Zwischenspeicher für eine Seite, deren
  ganzer Zweck der aktuelle Zustand ist, zeigte einen alten Zustand — und das
  ist schlimmer als eine Fehlermeldung.

**`manifest-src 'self'` gehört in die CSP**, in *beiden* Blöcken. `default-src
'none'` deckt es **nicht** ab, es ist eine eigene Direktive — ohne sie lädt der
Browser das Manifest nicht, die Installation bleibt einfach aus, und es gibt
keinen sichtbaren Fehler.

> *The panel installs as an app; `display: standalone` removes the browser
> chrome. The gain is not cosmetic but the passkeys: on a phone, "open the
> authenticator, read six digits, type them before they expire" becomes a
> fingerprint — and the panel is exactly what one reaches for away from the
> desk. Generated rather than served as a file, because two values come from the
> configuration. Icons are drawn by `logo.py`, now at 192 and 512 as well. No
> service worker: an offline cache for a page whose entire purpose is current
> state would show stale state. `manifest-src 'self'` belongs in both CSP blocks
> — `default-src 'none'` does not cover it, and without it installation silently
> does not happen.*

---

## Die öffentliche Statusseite `/status`

Wer wissen wollte, ob ein Server läuft und wie man beitritt, brauchte einen
Panel-Zugang oder musste fragen. Das Panel ist dafür das falsche Werkzeug: Es
ist eine Verwaltungsoberfläche hinter Passwort, TOTP und Passkeys, und jemandem
ein Konto zu geben, damit er eine Beitrittsadresse ablesen kann, ist verkehrt
herum.

Das Tab-Symbol steckt als **`data:`-URI** im Kopf, nicht als Verweis auf
`/favicon.svg`. Zwei Gründe, und der zweite wiegt schwerer: Die Seite bleibt in
sich geschlossen — ein Verweis ließe den Browser das Panel anfragen, genau das,
was diese Seite vermeidet —, und die CSP braucht dafür nur `img-src data:` und
**keinen Wirt**. Mit `img-src 'self'` dürfte die Seite jedes Bild dieser Herkunft
laden; mit `data:` nur, was sie selbst mitbringt.

Ohne beides fehlt das Symbol **stillschweigend**: Der Browser fällt auf
`/favicon.ico` zurück, das Panel liefert es mit HTTP 200 aus — und die eigene
CSP der Seite verwirft es. Im Tab blieb das leere Blatt, ohne dass irgendwo ein
Fehler auftauchte.

Die Seite trägt **Platzwart** als Namen und das Zeichen aus `werkzeuge/logo.py`
— als **Inline-SVG**, gelesen aus der Datei, die dieses Werkzeug erzeugt hat.
Nicht als `<img>`: Die Seite lädt kein einziges Bild, deshalb bleibt
`default-src 'none'` stehen. Ein eingebettetes SVG ist Auszeichnung, keine
Ressource, und braucht keine Lockerung. Und nicht noch einmal abgetippt:
`logo.py` gibt es genau deshalb, damit die Formen einmal als Zahlen stehen.

`https://<panel-domain>/status` zeigt ohne Anmeldung: welcher Server läuft,
unter welcher Adresse man beitritt, und — wo abrufbar — wie viele gerade drauf
sind.

> *Finding out whether a server is up and how to join used to need a panel
> account or a question — backwards for a management surface behind password,
> TOTP and passkeys. `/status` shows, without a login, which server runs, the
> join address, and where available how many are on. The tab icon is a `data:`
> URI in the page head rather than a link to `/favicon.svg`: the page stays
> self-contained (a link would make the browser ask the panel, exactly what the
> page avoids), and the CSP needs only `img-src data:` and no host. Without both
> the icon went missing silently — the browser fell back to `/favicon.ico`, the
> panel served it with 200, and the page's own CSP discarded it. The page is
> titled Platzwart and carries the mark from `logo.py` as inline SVG read from
> the generated file: not an `<img>`, so `default-src 'none'` stays, and not
> retyped, since `logo.py` exists so the shapes are defined once.*

### Eine Datei, keine Route im Panel

Das war die offene Frage, und sie ist bewusst gegen die naheliegende Lösung
entschieden. Eine öffentliche Route **im Panelprozess** teilt sich mit der
Verwaltung den Speicher, die Darstellungsfunktionen und die
Sicherheitskopfzeilen. Ein vergessener Schalter in einer gemeinsam benutzten
Funktion gibt dann alles preis — das Panel hat diese Lehre schon einmal gezogen,
deshalb gibt es `ohne_geheimnis()`.

Stattdessen schreibt `platzwart-status` jede Minute eine fertige Datei nach
`/var/lib/platzwart-status/index.html`, und Caddy liefert sie unmittelbar aus:
**kein `reverse_proxy`, kein `forward_auth`, keine Sitzung.** Die Seite erreicht
das Panel nie und kann nichts verraten, was sie nicht selbst geladen hat.

Geschrieben wird daneben und dann umbenannt — Caddy liefert die Datei laufend
aus, und ein halb geschriebener Stand wäre eine halbe Seite.

> *A file, not a route in the panel — decided against the obvious option. A
> public route inside the panel process shares memory, renderers and security
> headers with the management surface, and one forgotten flag in a shared
> function gives everything away; the panel learned that once already, hence
> `ohne_geheimnis()`. Instead `platzwart-status` writes a finished file every
> minute to `/var/lib/platzwart-status/index.html`, and Caddy serves it directly
> — no `reverse_proxy`, no `forward_auth`, no session. The page never reaches the
> panel and cannot reveal what it never loaded. It is written beside the target
> and renamed, since Caddy serves it continuously and a half-written file would
> be half a page.*

### Die Kopfzeilen sind strenger als beim Panel, nicht lockerer

```
Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline';
                         base-uri 'none'; form-action 'none'; frame-ancestors 'none'
Cache-Control: public, max-age=60
```

Die Seite enthält **kein JavaScript und kein einziges Bild**, deshalb bleibt
`default-src 'none'` und nur `style-src` wird geöffnet. `no-store` wäre hier
falsch: Es gibt nichts zu schützen, und 60 Sekunden Zwischenspeicher halten
Neugierige von der Platte fern — länger nicht, weil die Seite jede Minute neu
entsteht.

> *The headers are stricter than the panel's, not looser: the page contains no
> JavaScript and not a single image, so `default-src 'none'` stays and only
> `style-src` is opened. `no-store` would be wrong here — there is nothing to
> protect, and 60 seconds of caching keeps the curious off the disk; no longer,
> since the page is rebuilt every minute.*

### Was bewusst nicht daraufsteht

* **Server, deren Einrichtung nicht abgeschlossen ist.** `einrichtung_offen`
  markiert genau den Zustand, in dem ein Port veröffentlicht sein kann, bevor
  das Beitrittspasswort steht (E23). So einen Server auch noch anzukündigen wäre
  derselbe Fehler mit einem Megafon.
* **Server ohne Adresse.** Für einen Mitspieler haben sie keinen Wert.
* Keine Verwaltungsdaten: keine Pfade, keine Fassungen, keine Protokollauszüge,
  keine Benutzernamen, keine Ports außer dem Beitrittsport.

Nach dem Ausrollen von außen gegengeprüft — der Name des Panels, `/opt/`,
`127.0.0.1`, `sudo`, `docker`, `einrichtung` kommen nicht vor; die zwei Treffer
auf „Passwort" sind Hinweise *für Mitspieler* („Passwort je Rolle", „Passwort im
Spiel"), und `root` steht im CSS (`:root{…}`).

> *Deliberately not on the page: servers whose setup is unfinished —
> `einrichtung_offen` marks exactly the state in which a port could be published
> before the join password is in place (E23), and announcing such a server would
> be the same mistake with a megaphone; servers without an address, worthless to
> a player; and any management data — no paths, versions, log excerpts, user
> names, or ports other than the join port. Checked from outside after rollout:
> none of those strings appear; the two hits on "Passwort" are hints for
> players, and `root` is in the CSS.*

### Eine Falle beim Einbau

`handle /status*` mit `root * /var/lib/platzwart-status` allein ergibt **404**:
Caddy sucht dann `<root>/status`. Dabei sieht die Route richtig aus und die
Datei liegt richtig da. `uri strip_prefix /status` gehört dazu.

> *An install trap: `handle /status*` with `root * /var/lib/platzwart-status`
> alone yields 404, because Caddy then looks for `<root>/status` — while the route
> looks right and the file sits in the right place. `uri strip_prefix /status`
> belongs with it.*

### Die Beitrittsadressen stehen jetzt in einer Datei

`/etc/spiele-adressen.json` — vorher waren sie eine Tabelle im Quelltext des
Panels. Zwei Programme lesen sie jetzt: die Oberfläche und der Seitenschreiber.
Zwei Stellen, die dieselbe Tabelle führen, laufen auseinander, und dann nennt
die öffentliche Seite einen anderen Port als das Panel.

> *The join addresses of the hand-built servers moved from a table in the
> panel's source into `/etc/spiele-adressen.json`, because two programs read
> them now — the panel and the page writer — and two places keeping the same
> table drift apart, until the public page names a different port than the
> panel.*
## Spieler, wo es geht — Verkehr, wo nicht

Auf der Karte eines laufenden Servers steht entweder eine **echte Spielerzahl**
(`0/10 Spieler`) oder der **Netzverkehr** (`ruhig`, `Verkehr 45 kB/s`). Welches
von beidem, entscheidet sich daran, ob der Server auf eine Abfrage antwortet.

> *A running server's card shows either a real player count (`0/10 Spieler`) or
> the network traffic (`ruhig`, `Verkehr 45 kB/s`), depending on whether the
> server answers a query.*

### Eine Fehlmessung, die eine Funktion gekostet hat

Hier stand bis zum 2026-09-10, es gebe keine Spielerzahlen — Palworld antworte
auf keine Steam-Abfrage, TeamSpeak spreche ein eigenes Protokoll, Enshrouded „ein
drittes Format". Das war **falsch**, und zwar in einem Punkt, der zählt:

```
=== Steam-Abfrage (A2S_INFO), 2026-09-10 ===
  valheim      0/10 Spieler   "Valheim Docker"
  enshrouded   0/4 Spieler    "<WELT_NAME>"
  palworld     keine Antwort
  foundry      keine Antwort
  satisfactory keine Antwort
```

Enshrouded antwortet auf **ganz normales A2S**. Die vermutliche Ursache des
Irrtums steckt im Protokoll: Seit 2020 beantworten Server die erste
`A2S_INFO`-Anfrage nicht mit Daten, sondern mit einem **Challenge** (`0x41`);
erst die Wiederholung mit angehängtem Challenge liefert die Antwort. Wer das
nicht tut, sieht einen antwortenden Server als stumm — und schreibt „nicht
abrufbar" in die Dokumentation.

Das ist die Lehre, nicht die Zahl: Eine Messung, die „geht nicht" ergibt, ist
erst dann ein Befund, wenn auch der Weg geprüft wurde, auf dem sie misst.

> *Until 2026-09-10 this section claimed there were no player counts — Palworld
> answering no Steam query, TeamSpeak speaking its own protocol, Enshrouded "a
> third format". That was wrong in the point that matters: Valheim and
> Enshrouded answer plain A2S. The likely cause of the error is in the protocol:
> since 2020 servers answer the first `A2S_INFO` not with data but with a
> challenge (`0x41`), and only the repeat carrying it returns the answer; whoever
> skips that sees a responding server as silent and writes "not obtainable" into
> the docs. The lesson, not the number: a measurement yielding "does not work" is
> a finding only once the path it measures along has been checked too.*

### Wie es jetzt läuft

`spieler-zaehlen` fragt jede Minute über einen Timer und schreibt
`/var/lib/platzwart-spieler.json`. Die Übersicht **liest** nur — eine Abfrage im
Seitenaufbau würde jeden Seitenaufruf um die langsamste Antwort verlängern.

Der **Abfrageport wird gefunden, nicht konfiguriert.** Eine Angabe im Katalog
hätte drei der sieben Server nicht erreicht: `satisfactory`, `windrose` und
`foundry` sind von Hand gebaut und haben keinen Katalogeintrag. Stattdessen
werden die veröffentlichten UDP-Ports durchprobiert und der, der antwortet,
gemerkt — Valheim veröffentlicht drei, genau einer antwortet.

**Wer schweigt, wird nicht jede Minute erneut gefragt.** Fünf der sieben
antworten nicht; sie im Minutentakt anzufragen sind Pakete an Spielports, die
niemandem nützen. Wiedervorlage nach 30 Minuten — ein Spiel kann seine Abfrage
nach einem Update anschalten. Gemessen: erster Lauf 2,8 s (alle, parallel),
danach 0,33 s.

Die Abfragearten stehen als Klassen nebeneinander, dieselbe Naht wie bei den
DNS-Anbietern (E24). Wer TeamSpeaks ServerQuery oder Satisfactorys HTTPS-API
ergänzt, schreibt eine Klasse und trägt sie ein, sonst nichts.

> *How it runs: `spieler-zaehlen` queries every minute by timer and writes
> `/var/lib/platzwart-spieler.json`; the overview only reads, since a query in
> the request path would lengthen every page view by the slowest answer. The
> query port is discovered, not configured — a catalogue field would have missed
> the three hand-built servers — by probing the published UDP ports and
> remembering the one that answers (Valheim publishes three, exactly one
> answers). A silent server is not asked every minute: it is retried after 30
> minutes, since a game can switch its query on after an update. Measured: first
> run 2.8 s (all in parallel), afterwards 0.33 s. Query kinds are classes side by
> side, the same seam as the DNS providers (E24); adding TeamSpeak's ServerQuery
> or Satisfactory's HTTPS API is one class and one entry.*

### Was bewusst *nicht* angezeigt wird

* **Wer nicht antwortet, bekommt keine Null.** Er steht gar nicht erst im Stand;
  die Karte zeigt dann Verkehr. Eine Null wäre eine Aussage, keine Antwort ist
  keine.
* **Zahlen über drei Minuten alt.** Steht der Timer, ist die letzte Zahl keine
  Auskunft über „gerade" mehr. Eine veraltete Zahl als aktuelle auszugeben ist
  schlimmer als keine.

> *Deliberately not shown: a server that does not answer gets no zero — it is
> absent from the file, and the card shows traffic; a zero would be a statement,
> no answer is none. And counts older than three minutes: if the timer stopped,
> the last number says nothing about "now", and a stale number presented as
> current is worse than none.*

### Der Verkehr bleibt — für die anderen fünf

Er kommt aus demselben `docker stats`, das die Übersicht ohnehin abruft, und
beantwortet die Frage, um die es wirklich geht: *Kann ich neu starten, oder ist
gerade jemand drauf?* Drei Fälle, in denen auch er bewusst leer bleibt:

* **Erster Abruf.** Der Wert ist kumulativ seit dem Containerstart; ohne
  Vergleichswert gibt es keine Rate.
* **Der Zähler fällt.** Das heißt Container-Neustart, nicht negativer Verkehr.
* **Der letzte Abruf ist über 15 Minuten her.** Dann sagt die Differenz nichts
  mehr über „gerade".

Der letzte Zählerstand je Server liegt in `/opt/panel/daten/netzstand.json`;
die Rate entsteht aus der Differenz zweier Abrufe der Übersicht.

> *Traffic remains for the servers that do not answer. It comes from the same
> `docker stats` the overview fetches anyway and answers the question that
> really matters — can I restart, or is somebody on? It stays blank on the first
> poll (the value is cumulative since container start, so there is no rate
> without a previous one), when the counter falls (a container restart, not
> negative traffic), and when the last poll is more than 15 minutes old. The
> last counter per server is kept in `/opt/panel/daten/netzstand.json`, and the
> rate is the difference between two overview polls.*

---

## Sicherung herunterladen `/holen-fragen/{stack}/{archiv}`

Auf der Seite `Sicherungen` steht neben *zurückspielen* jetzt *herunterladen*.
Der Klick führt erst auf eine Zwischenseite mit der **Größe** — ein Verweis, der
sich als 2,1 GB herausstellt, ist auf einer getakteten Verbindung eine böse
Überraschung.

**Durchgereicht als Strom, nicht als Datei.** `borg export-tar … -` schreibt das
Archiv direkt auf die Standardausgabe, und die Oberfläche reicht es in 256-kB-
Blöcken weiter. Erst nach `/tmp` zu entpacken und dann zu packen bräuchte den
Platz doppelt und scheiterte an den großen Ständen — Valheim allein ist 2,16 GB
über 1033 Dateien.

**Kein Zeitlimit auf der Übertragung.** Ein 2-GB-Download dauert über eine
Hausleitung Minuten; die übliche 60-Sekunden-Grenze schnitte mitten in einer
Datei ab, und heraus käme ein tar, das aussieht wie eine Sicherung und keine ist.
Begrenzt wird über die angezeigte Größe, nicht über die Zeit.

**Bricht der Browser ab, endet auch `borg`.** Sonst liefe der Prozess weiter und
hielte eine Sperre auf dem Repository — nachgemessen: nach einem Abbruch bei
1 MB von 2,1 GB blieb kein Prozess zurück und die Archivliste war sofort wieder
abrufbar.

**Für `verwalten` und `admin`, nicht für `bedienen`.** Ein Spielstandarchiv
enthält die Konfigurationsdateien des Servers und damit das Beitrittspasswort —
dieselbe Grenze wie bei den Zugangsdaten. Die Zwischenseite sagt das auch.

> *Downloads stream straight from Borg rather than being staged: extracting to
> `/tmp` and packing would need the space twice and fail on the larger saves.
> There is no timeout on the transfer, because cutting a 2 GB download mid-file
> yields a tar that looks like a backup and is not; the size is shown beforehand
> instead. If the browser aborts, borg is terminated with it, or it would keep a
> lock on the repository — verified. The archive holds the server's config and
> therefore the join password, so it follows the credentials boundary.*

---

## Von Hand gebaute Server entfernen `/entfernen-fragen/{stack}`

Die Katalogdeinstallation verlangt eine `panel.json` und weist alles andere ab —
das schützt die von Hand gebauten Stacks davor, von einer Routine gelöscht zu
werden, die nichts über sie weiß. Nur ließen sie sich damit **gar nicht** mehr
entfernen, außer über SSH. StarRupture allein waren **21,1 GB** — es war der
erste Server, der auf diesem Weg ging (2026-09-09).

Deshalb ein **eigener Weg**, keine gelockerte Prüfung: Die Katalogroutine liest
`panel.json` für die Ausschlussliste und räumt Katalogzustand ab — Dinge, die es
hier nicht gibt. Eine Prüfung wegzunehmen, damit ein zweiter Fall durchpasst,
macht aus zwei klaren Abläufen einen unklaren. Gemeinsam haben beide Wege die
Endsicherung, das Abräumen von Leerlauf, Zugangsdaten und Auto-Update, den
Kanal-Abgleich und — seit #253 — das Entfernen des DNS-Namens: Stufe 70 legt
auch für von Hand gebaute Stacks einen an, und `starrupture.<zone>` zeigte Tage
nach dem Entfernen noch auf die Maschine.

**Der Knopf steht nicht neben harmlosen.** Er liegt auf der Einstellungsseite des
Servers in einem eigenen, rot überschriebenen Abschnitt **Entfernen**, abgesetzt
und als letzter — und dahinter folgt weiterhin die Rückfrageseite.

Zuerst stand `entfernen` auf der Karte in derselben Reihe wie `Protokoll`,
`Einstellungen` und `Konfigdateien`: drei harmlose Knöpfe und einer, der 21 GB
löscht. Danach lag er hinter einem eigenen Schritt **bearbeiten**, der die Karte
gelb umrahmte. Seit die Karte nur noch drei Knöpfe trägt (#161), gibt es diesen
Modus nicht mehr — er war eine Behelfslösung dafür, dass der Knopf auf der Karte
stand, und die ist entfallen. Von der Karte bis zum Löschen sind es jetzt drei
Seiten statt zwei.

**Nur für `admin`**, anders als die Katalogdeinstallation, die `verwalten`
benutzen darf: Diese Stacks hat niemand über den Katalog angelegt, es gibt keinen
Eintrag, aus dem sie sich neu installieren ließen — nur die Sicherung.

**Die Größe steht vor dem Klick**, nicht danach. 21,1 GB zu löschen und 56 KB zu
löschen sind verschiedene Entscheidungen, und die Seite sagt, welche ansteht.

Vor dem Löschen läuft eine **Endsicherung**; schlägt sie fehl, wird nichts
gelöscht. Ist die Sicherung ganz abgeschaltet, steht das als Warnung auf der
Seite — **vor** dem Klick, nicht als Meldung hinterher.

> *Catalogue removal requires a `panel.json` and refuses everything else, which
> protects hand-built stacks from a routine that knows nothing about them — but
> also made them unremovable except over SSH (StarRupture alone was 21.1 GB and
> was the first to go this way). Hence a separate path rather than a loosened
> check: the catalogue routine reads `panel.json` and clears catalogue state, none
> of which exists here. Both paths share the final backup, clearing idle sleep,
> credentials and auto-update, the channel sync and — since #253 — removing the
> DNS name, which stage 70 creates for hand-built stacks too. The button no
> longer sits beside harmless ones: it lives in a red "Entfernen" section at the
> end of the settings page, followed by the confirmation page. Admin only, since
> there is no catalogue entry to reinstall from. The size is shown before the
> click, and a final backup runs first; if it fails, nothing is deleted; with
> backups switched off, the page warns before the click.*

---

## Aktualisieren und Sammelsteuerung

**Aktualisieren** holt eine neue Fassung des Images und startet den Server damit
neu. Der Knopf steht auf der Einstellungsseite jedes Servers, für `verwalten`
und `admin`.

**Die Sicherung davor ist Bedingung, nicht Schritt.** Ein Update kann einen
Spielstand unbrauchbar machen — ein neuer Serverstand, der einen alten Spielstand
liest, ist genau der Fall, in dem „dann spiele ich eben zurück" auch wirklich
funktionieren muss. Scheitert die Sicherung, unterbleibt das Update. Ist die
Sicherung ganz abgeschaltet (`BORG_REPO=aus`), wird gar nicht erst aktualisiert.

Erzwungen wird das in `panel-aktion`, nicht in der Oberfläche: Eine Schutzmaßnahme,
die ein anderer Aufrufweg umgeht, ist keine.

**Zwei verschiedene Antworten:** „schon aktuell" und „aktualisiert". Verglichen
wird die **Image-ID**, nicht die JSON-Ausgabe von `docker compose images` — die
enthält `LastTagTime`, und der Zeitstempel ändert sich bei jedem `pull`, auch
wenn dasselbe Image erneut geholt wurde. Der erste Anlauf meldete deshalb immer
„aktualisiert", und ein Knopf, der immer dasselbe sagt, wird nicht mehr gelesen.

**Ein gestoppter Server bleibt gestoppt.** Er wird nicht kurz gestartet, um die
neue Fassung zu übernehmen — das Image ist geholt und greift beim nächsten Start.
Der erste Anlauf startete ihn und hielt ihn wieder an; er kam mit **Exit 137**
zurück, also hart abgeschossen, weil er auf SIGTERM noch nicht ansprechbar war.

**Sammelsteuerung** oben auf der Übersicht: *alle laufenden anhalten* und
*zuletzt laufende starten*. Beide nutzen dieselbe Liste unter
`/var/lib/spiele-wiederanlauf`, die auch der Neustart schreibt — kein zweiter
Zustand, der auseinanderlaufen kann. Ohne Liste sagt „starten" das auch, statt zu
raten.

> *Updating pulls a new image and restarts the server with it. The backup
> beforehand is a precondition, not a step: if it fails, or if backups are off
> entirely, the update does not happen — enforced in `panel-aktion`, because a
> safeguard another entry point bypasses is not one. "Already current" and
> "updated" are distinguished by image ID, not by the JSON output, which carries
> a timestamp that changes on every pull. A stopped server stays stopped rather
> than being briefly started, which returned exit 137 on the first attempt.*

---

## Serverprotokoll `/logs/{stack}`

Die letzten Zeilen aus `docker logs`, mit Zeitstempeln, pro Server. Erreichbar
über **Einstellungen** → **Protokoll** — **auch bei gestoppten Servern**, denn
gerade dann will man wissen, warum.

**Warum es das gibt:** Die Rolle `verwalten` darf Spiele installieren und
entfernen, aber das Webterminal bleibt `admin` vorbehalten. Ohne diese Seite wäre
sie halb blind — installieren ja, nachsehen warum es nicht startet nein. Die
einzige Antwort wäre „frag einen Administrator" gewesen, und das hebt die
Delegation wieder auf.

**Drei Grenzen:**

| | |
|---|---|
| Zeilenzahl | wird in `panel-aktion` begrenzt (1–2000), nicht in der Oberfläche — ein unbegrenztes `--tail` auf einen tagelang laufenden Container wäre ein Selbstangriff auf das Panel |
| Ausgabe | wird **escaped**; im Log steht beliebiger Text aus dem Spielserver, einschließlich allem, was Spieler in den Chat geschrieben haben |
| Rolle | `verwalten` und `admin`, **nicht** `bedienen`: manche Server schreiben ihre Konfiguration beim Start ins Log, Beitrittspasswort eingeschlossen — die Seite folgt damit derselben Grenze wie die Zugangsdaten |

Leer und nicht abrufbar sind zwei verschiedene Meldungen. Ohne diesen Unterschied
sucht man den Fehler an der falschen Stelle.

> *The last lines of `docker logs` per server, also for stopped ones — that is
> when it matters most. It exists because the `verwalten` role may install
> servers but has no terminal, so without it that role could install a server and
> not see why it fails. The line count is bounded server-side, the output is
> escaped (arbitrary text from the game, player chat included), and the page
> follows the credentials permission rather than the start/stop one, because some
> servers echo their join password on start.*

---

## Protokoll `/protokoll`

Wer hat wann was getan. Nur für `admin` — die Seite nennt Benutzernamen und
gescheiterte Anmeldungen.

Aufgezeichnet wird jede schreibende Aktion: installieren, entfernen, starten,
anhalten, neu starten, Konfigurationsfelder und -dateien, Wiederherstellungen,
Zugangsdaten, Benutzerverwaltung, Maschinenneustart — dazu Anmeldungen,
**auch die gescheiterten**, denn nach einem Vorfall sucht man genau danach.

**Was bewusst nicht darin steht:** Passwörter und Dateiinhalte. Bei einem Feld,
dessen Name auf ein Geheimnis hindeutet, steht nur die Länge; bei einer
geschriebenen Datei nur Name, Zeilen- und Zeichenzahl; bei einer Installation
nur Spiel und Ergebnis — bis #239 stand dort die ganze Ausgabe von
`spiel-verwalten` samt der zwei frisch gewürfelten Passwörter (die zwei
betroffenen Zeilen wurden nachträglich geschwärzt); bei einem Schlüssel fremder
Dienste nur die letzten vier Zeichen. Ein Protokoll soll nachvollziehbar machen,
*wer was* angefasst hat, und nicht Geheimnisse an einer zweiten Stelle sammeln.

Auch Änderungen, die kein Mensch im Panel auslöst, stehen darin: Kanäle, die
`kanal-verwalten` anlegt, umbenennt oder löscht, erscheinen unter dem Benutzer
`platzwart`.

Vorher ließ sich das nur zufällig aus `journalctl` rekonstruieren, weil jede
Aktion über `sudo panel-aktion` läuft. Diese Zeile nennt aber den **Dienstnutzer**
`panel`, nie den angemeldeten Menschen, entsteht nur für den Weg über die
sudo-Brücke und fällt mit der Journalrotation weg.

Die Datei liegt unter `/opt/panel/daten/audit.jsonl`, eine JSON-Zeile je
Ereignis; ab 4 MB wird einmal nach `.jsonl.1` rotiert.

**Ein Protokoll, das heimlich nichts mehr schreibt, ist schlimmer als keines** —
seine Leere liest sich als „es ist nichts passiert". Ein Schreibfehler wird
deshalb gemerkt und **auf der Seite angezeigt**, und eine unlesbare Zeile
erscheint als solche, statt übersprungen zu werden.

> *Who did what, when — admin only, since it names users and failed logins.
> Every writing action is recorded, plus logins including failed ones. Passwords
> and file contents deliberately stay out: a secret-looking field logs only its
> length, a written file only its name and size, an installation only game and
> result (until #239 it held the installer's full output including both fresh
> passwords; the two affected lines were redacted), an outside-service key only
> its last four characters. Channel changes made by `kanal-verwalten` appear
> under the user `platzwart`. A log that quietly stops
> writing is worse than none, so a write error is surfaced on the page, and an
> unreadable line is shown as such rather than skipped.*

---

## Seiten

### Übersicht `/`

Oben vier Kennzahlen der Maschine mit Balken: Arbeitsspeicher, CPU-Last (im
Verhältnis zu den Kernen), Platte und Auslagerung. Für `verwalten` und `admin`
darunter die **Sammelsteuerung**: *alle laufenden anhalten* und *zuletzt
laufende starten*. Dann je Server eine Karte mit:

* Titelbild (oder zwei Buchstaben), Name, Zustand `läuft`/`gestoppt`;
* Beitrittsadresse und Hinweis — aus `panel.json` oder
  `/etc/spiele-adressen.json`;
* bei einem laufenden Server Balken für Speicher (gegen die Grenze) und CPU,
  darunter die Spielerzahl oder der Netzverkehr und die Linie des
  Speicherverlaufs;
* Warnungen, wo etwas nicht stimmt: *Noch keine Beitrittsadresse* (der Port
  kommt erst aus der Konfiguration des ersten Starts), *Einrichtung läuft*,
  *Server startet nicht*, *Ohne Beitrittspasswort!*, *Spielerzahl nicht
  gesetzt*; nach einer Portermittlung, aus welcher Datei der Port stammt;
* **drei Knöpfe**: `anhalten`, `neu starten` und `Einstellungen` — bei einem
  gestoppten Server `starten` und `Einstellungen`. `Einstellungen` erscheint
  nur, wenn die Seite für die Rolle etwas zeigt.

Unten ein Satz zur Sicherung — die Aufbewahrung, oder ein deutlicher Warnkasten,
wenn sie abgeschaltet ist. Die Übersicht ist so breit wie die Katalogseite; die
Karten behalten ihre Größe und stehen nur zu mehreren nebeneinander.

Ohne die Warnungen liefe ein Server im schlimmsten Fall **ohne
Beitrittspasswort** und niemand würde es merken; ohne den Unterschied zwischen
„kein Passwortfeld" und „startet nicht" suchte man einen offenen Port, den es
gar nicht gibt (#158).

> *Overview: four machine metrics with bars — memory, CPU load relative to the
> cores, disk and swap; for verwalten and admin the bulk controls "stop all
> running" and "start the last running"; then one card per server with artwork,
> name and state, join address and note, memory and CPU bars plus player count or
> traffic and the memory history for a running server, warnings where something
> is wrong (no join address yet, setup in progress, server does not start,
> without a join password, player limit not set, and where a discovered port
> came from), and three controls — stop, restart, settings (start and settings
> when stopped; settings only if that page shows the role anything). At the
> bottom a line on backup retention, or a clear warning when backups are off.
> Without the warnings a server could run without a join password unnoticed;
> without telling "no password field" from "does not start" one would hunt for
> an open port that does not exist (#158).*

### Einstellungen eines Servers `/server/<stack>`

Alles, was nicht Anhalten oder Neustarten ist (#161). Vorher trug eine Karte bis
zu **elf** Knöpfe (bei `admin` auf einem von Hand gebauten Server) — die zwei,
die man täglich braucht, gingen darin unter.

| Abschnitt | Inhalt | Rolle |
|---|---|---|
| Freigabe | `Port freigeben …` — nur bei Spielen ohne Beitrittspasswort, solange die Freigabe fehlt; steht ganz oben | verwalten, admin |
| Whitelist | Minecraft (Java): eingetragene Namen mit `entfernen`, Feld zum Eintragen | verwalten, admin |
| Workshop | nur bei Spielen mit Anbindung: eingetragene Mods (Titel, Größe, Link) mit `entfernen`, Suche (mit Steam-Schlüssel), Feld für Link/ID/Sammlung | verwalten, admin |
| Betrieb | `autoupdate an/aus`, `leerlauf an/aus`, `jetzt aktualisieren` | verwalten, admin |
| Einstellen | `Konfiguration` (`/konfig`), `Konfigdateien (n)` (`/dateien`) | verwalten, admin |
| | `Mods` | admin |
| Daten | `Sicherungen` | alle, sofern die Sicherung an ist |
| | `Protokoll` | verwalten, admin |
| Entfernen | `Server entfernen …` — nur für von Hand gebaute Server, rot abgesetzt | admin |

**Jede Bedingung ist wörtlich die, die vorher auf der Karte stand.** Einen
Knopf auf eine andere Seite zu verschieben ist genau der Moment, in dem eine
Prüfung verloren geht; deshalb ist das für alle drei Rollen nachgeprüft worden,
und `bedienen` sieht dort genau das, was es vorher auf der Karte sah. Der Knopf
`Einstellungen` erscheint nur, wenn die Seite für die Rolle etwas zeigt — ein
Knopf, hinter dem nichts liegt, ist schlimmer als keiner.

**Nach einem Klick bleibt man auf der Seite.** `autoupdate`, `leerlauf` und
`aktualisieren` schicken ein verstecktes Feld `zurueck=server` mit; die Antwort
leitet dann auf `/server/<stack>` statt auf die Übersicht. Das Ziel ist fest:
entweder die Einstellungsseite **genau dieses** Servers oder die Übersicht,
und der Name muss dieselbe Regel erfüllen wie in `panel-aktion`. Ein frei
wählbares Rückziel wäre eine offene Weiterleitung. Aus demselben Grund führt
„zurück" auf den Unterseiten (Konfiguration, Konfigdateien, Mods, Sicherungen,
Protokoll, Entfernen-Rückfrage) jetzt zur Einstellungsseite, nicht zwei Ebenen
hoch.

> *Everything other than stop and restart lives here, in sections: release (for
> games without a join password, at the top), whitelist (Minecraft Java),
> Workshop (games with a binding), operation (auto-update, idle sleep, update
> now), settings (configuration, config files with their count, mods for
> admins), data (backups, server log) and removal (hand-built servers, admin,
> set apart in red). Each control appears
> under exactly the condition it had on the card — moving a control to another
> page is precisely when a check gets lost — and the card only links here if
> the page has something for the role. After a toggle you stay on the page via
> a fixed return target (this server's settings page or the overview, never a
> free URL, which would be an open redirect).*

### Spiele `/spiele`

Der Katalog: alle Einträge mit Titelbild, Kurzbeschreibung, Speicher- und
Plattenbedarf und dem Hinweis, ob ein Spiel schon installiert ist.
Installieren mit einem Klick, Entfernen mit Rückfrage. Nach dem Installieren
meldet die Seite, ob der Server gestartet wurde, und verweist auf die
**Zugangsdaten**, wo die zwei frisch gewürfelten Passwörter stehen.

Übergeben wird **nur der Schlüssel**. Alles andere — Image, Ports, Volumes,
Umgebung — kommt aus `/etc/spiele-katalog.json`, das die Oberfläche nur lesen
kann. Siehe [04-spielekatalog.md](04-spielekatalog.md).

> *The catalogue: every entry with artwork, blurb, memory and disk needs and
> whether it is installed. Install with one click, remove with a confirmation;
> after installing, the page says whether the server was started and points to
> the credentials page, where the two freshly generated passwords are listed. Only the key is passed; everything else
> comes from the catalogue file, which the panel can only read.*

### Suche, Kategorien und Sortierung auf der Katalogseite

Bei 179 Einträgen ist Blättern keine Bedienung mehr. Die Seite hat deshalb:

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
Fließtext richtig und für 179 Kacheln viel zu wenig — auf einem breiten
Bildschirm standen drei Spalten neben zwei Dritteln leerem Grau. Der Katalog
bekommt deshalb eine eigene Spalte bis 2400 px und ein engeres Raster (240 statt
300 px Mindestbreite, flachere Bilder). Gemessen: aus 3 Spalten werden 7 auf Full
HD und 9 bis 11 auf breiteren Schirmen. Die Kopfleiste bleibt bei 1000 px — sie
soll nicht über den ganzen Schirm wandern.

Über 2400 px wird nicht weiter aufgezogen: Eine Kachelreihe, die breiter ist als
das Blickfeld, liest niemand mehr als Reihe.

> *The catalogue page is wider than the rest: 1000px is right for prose and far
> too little for 179 tiles, which left three columns beside two thirds of empty
> background. It gets its own column up to 2400px and a tighter grid — measured,
> 3 columns become 7 on Full HD and 9–11 on wider screens. Beyond 2400px nothing
> is gained: a row wider than the field of view stops reading as a row.*

Die Sortierung ist **fest alphabetisch**. Vorher gab es A → Z, Z → A und „größte
zuerst"; an ihre Stelle ist die Buchstabenleiste getreten. Eine umgekehrte
Reihenfolge neben einer Buchstabenauswahl hilft niemandem: Wer unter „M"
nachsieht, will die M-Spiele, nicht ihre Richtung.

| Kategorie | Einträge |
|---|---|
| Aufbau & Simulation | 9 |
| Survival & Koop | 49 |
| Sandbox & Rollenspiel | 13 |
| Shooter | 78 |
| Arena & Klassiker | 24 |
| Rennen & Fahren | 5 |
| Dienste | 1 |
| Sonstiges | 0 |

Bis #251 fehlten hier 17 Spiele ganz: Die Generatoren hatten sie ohne
Kategorie angelegt, und so passten sie in keinen Filter, nicht einmal in
„Sonstiges". Seither prüft `vollstaendigkeit.sh`, dass jeder Eintrag eine hat.

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

> *At 179 entries, scrolling is not an interface. The page offers a text search
> across name, key and blurb (multiple words must all match, or a longer query
> would return more results than a shorter one), eight categories with counts
> that respect the search but not the category filter, and a letter bar.
> Everything is server-side via GET parameters — not a preference but a
> consequence of `default-src 'none'`, where client-side filtering would be dead.
> Categories are assigned by hand rather than taken from Steam, whose genres say
> nothing about whether a game suits an evening for two. The table lists the
> entries per category; until #251 17 games had no category at all and matched
> no filter, not even "Sonstiges" — the completeness check now requires one for
> every entry.*

### Zugangsdaten `/passwoerter`

Beitritts- und Adminpasswörter aller Server, an einer Stelle. Zwei Quellen,
sichtbar getrennt:

* **Automatisch gelesen** — aus den compose-Dateien und den `panel.json`.
  Immer aktuell, weil direkt aus der Quelle.
* **Selbst gepflegt** — für Server, deren Passwort sich nicht auslesen lässt:
  Satisfactory (Hash und Salt in einer binären `.sav`) und TeamSpeak (Hash in
  SQLite, dazu der ServerQuery-Zugang `serveradmin`). Anlegen mit Server,
  Bezeichnung und Wert, einzeln löschen. Diese Einträge **können veralten** und
  sind deshalb gekennzeichnet.

Nur für `verwalten` und `admin`. Ein entfernter Server verschwindet aus beiden
Quellen (#169).

> *All join and admin passwords in one place, from two visibly separated
> sources: read automatically from the compose files and `panel.json`, always
> current; and kept by hand for servers whose password cannot be read back —
> Satisfactory (hash and salt in a binary save) and TeamSpeak (hash in SQLite,
> plus the ServerQuery login) — added with server, label and value, deleted one
> by one, and marked because they can go stale. verwalten and admin only; a
> removed server disappears from both sources (#169).*

### Benutzer `/nutzer`

Eine Tabelle aller Konten mit Rolle, Zustand des zweiten Faktors und Vorrat an
Wiederherstellungscodes, je Konto `2FA zurücksetzen` und `löschen`; darunter das
Formular zum **Anlegen**: Name (nur Buchstaben und Ziffern, höchstens 20
Zeichen, klein gespeichert), Startpasswort (mindestens 10 Zeichen, weitergeben
muss es der Administrator selbst) und Rolle. Jede Ablehnung nennt ihren Grund
und steht im Protokoll.

**Was die Oberfläche nicht kann:** eine Rolle nachträglich ändern und ein
Passwort ändern — weder das eigene noch ein fremdes. Beides geht heute nur über
Löschen und neu Anlegen (der Benutzer richtet dann auch den zweiten Faktor neu
ein) oder von Hand in `nutzer.json`.

`2FA zurücksetzen` erneuert das TOTP-Geheimnis und entwertet die
Wiederherstellungscodes **und die Passkeys** des Kontos; beim nächsten Anmelden
richtet der Benutzer den zweiten Faktor neu ein. Die Passkeys blieben bis #254
gültig — ein Passkey auf dem verlorenen Gerät war nach dem Zurücksetzen weiter
ein zweiter Faktor, genau der Fall, für den es den Knopf gibt.

Beim Anlegen entsteht ein TOTP-Geheimnis, das **niemandem angezeigt wird** —
auch nicht dem Administrator. Der neue Benutzer bekommt es bei seiner ersten
Anmeldung selbst als QR-Code. So muss es nie über einen Kanal weitergegeben
werden.

Das eigene Konto lässt sich nicht löschen: sonst sperrt man sich mit einem Klick
aus, und ohne Administrator käme niemand mehr an die Benutzerverwaltung.

**Groß- und Kleinschreibung spielt beim Benutzernamen keine Rolle** (#248).
Konten werden klein gespeichert, die Anmeldung — per TOTP wie per Passkey —
findet `Karla7` auch als `karla7`, und ein zweites Konto, das sich nur in der
Schreibweise unterscheidet, wird abgewiesen. Vorher war der Vergleich exakt: Der
erste Anmeldeversuch am einzigen `verwalten`-Konto scheiterte am großen
Anfangsbuchstaben, und die Seite sagte nur „Anmeldung fehlgeschlagen" — der
Schreibfehler sah aus wie ein falsches Passwort. Im Protokoll steht bei einem
Fehlversuch weiterhin genau das, was eingetippt wurde.

> *Users: a table of all accounts with role, second-factor state and remaining
> recovery codes, each with "reset 2FA" and "delete", and a form to create one —
> name (letters and digits only, at most 20 characters, stored in lower case),
> initial password (at least 10 characters, handed over by the administrator)
> and role; every refusal names its reason and is audited. What the panel cannot
> do: change a role afterwards or change a password, one's own or anyone else's
> — today that means deleting and re-creating the account or editing
> `nutzer.json` by hand. Resetting 2FA renews the TOTP secret and revokes the
> account's recovery codes and passkeys; the user enrols again at the next
> login. Passkeys stayed valid until #254 — one on the lost device remained a
> second factor after the reset, exactly the case the button exists for. A new TOTP secret is
> shown to nobody, not even the administrator — the new user receives it as a QR
> code on their first login, so it never travels over a channel. Deleting your
> own account is blocked: it would lock the last administrator out of user
> management. User names are case-insensitive (#248): stored in lower case,
> found regardless of case at login (TOTP and passkey), duplicates differing only
> in case are refused; a failed attempt still logs exactly what was typed.*

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
weiter. Zugelassen sind Textendungen (`.ini`, `.cfg`, `.json`, `.txt` …) und
einzelne volle Dateinamen mit fremder Endung, die Text-Konfiguration sind:
bisher nur Unturneds `Commands.dat` mit dem Beitrittspasswort (#223) — `.dat`
ist sonst oft binär. Zwei Ansichten derselben Datei:

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
| Bearbeitbar | jede Umgebungsvariable außer den gesperrten, jede Änderung mit Gerüstvergleich | frei, im Rahmen der Pfadprüfung |

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

Geändert wird immer **ein Feld** — nie die compose-Datei als Ganzes. Wer dort
ein Volume `/:/host` eintragen könnte, wäre root auf der Maschine. Die
Umgebungsvariablen laufen über `compose-feld`: Sperrliste, kein Zeilenumbruch im
Wert und als eigentlicher Schutz ein Vergleich der von Docker erzeugten
Endfassung vor und nach der Änderung — weicht mehr ab als die Umgebung, wird
zurückgerollt. Darunter stehen Sonderfälle, die nicht in der Umgebung stehen:
die **Speichergrenze** (`mem_limit` und `memswap_limit` gemeinsam, Form `8g`)
und bei Palworld die **wirksamen** Werte aus `PalWorldSettings.ini`
(Servername, Passwörter, Spielerzahl), weil der Container sie dort führt. Vor
jeder Änderung entsteht eine Kopie `.vor-panel-<zeit>`; wirksam wird sie beim
nächsten Neustart des Servers.

> *Always one field — never the compose file as a whole, since a volume of
> `/:/host` would mean root on the machine. Environment variables go through
> `compose-feld`: a deny-list, no newline in the value, and as the real
> safeguard a before/after comparison of Docker's rendered config that rolls
> back if anything beyond the environment differs. Below them are the special
> cases outside the environment: the memory limit (memory and swap together,
> written like `8g`) and for Palworld the effective values in
> `PalWorldSettings.ini`, because the container keeps them there. Every change
> leaves a `.vor-panel-<time>` copy and takes effect at the next restart.*

### Archive und Wiederherstellung `/archive/<stack>`, `/restore`

Die Seite **Sicherungen** listet die Borg-Archive dieses Servers mit Zeitpunkt,
jüngste zuerst; je Archiv `zurückspielen` (verwalten, admin) und
`herunterladen` (verwalten, admin). Für `bedienen` ist sie eine reine Liste.
Läuft gerade eine Sicherung, wartet die Seite bis 150 s auf die Sperre und sagt
es, wenn sie trotzdem nicht durchkommt.

`zurückspielen` führt auf eine Rückfrage, die nennt, was geschieht. Danach packt
`panel-aktion restore` das Archiv **zuerst** aus, bei laufendem Server; erst
wenn das gelang, hält es den Server an, kopiert den Ist-Stand nach
`/srv/games/<stack>.vor-restore-<zeit>`, legt die von der Sicherung
ausgeschlossenen Pfade (die Spielinstallation) beiseite, spielt den Stand ein,
legt sie an denselben Ort zurück, übernimmt den Eigentümer vom Ist-Stand und
startet den Server wieder — nur, wenn er vorher lief. Die Meldung nennt den Ort
der Kopie; sie gehört nach der Prüfung gelöscht, sonst sichert sie der nächste
Volllauf mit. Einzelheiten in [05-sicherung.md](05-sicherung.md#über-die-oberfläche).

> *The backups page lists this server's Borg archives with their time, newest
> first, each with restore and download for verwalten and admin; for bedienen it
> is a plain list. During a running backup it waits up to 150 s for the lock and
> says so if it still cannot get through. Restoring leads to a confirmation
> page; `panel-aktion restore` then extracts the archive first, while the server
> keeps running, and only after that succeeded stops the server, copies the
> current state to `<dir>.vor-restore-<time>`, moves the excluded paths (the game
> installation) aside, restores, puts them back at the same place, takes
> ownership from the previous state and restarts the server only if it was
> running. The message names the copy's location; delete it after checking, or
> the next full backup archives it too.*

---

## Module `/module` (nur admin)

Optionale Dienste, die **nachinstalliert** werden können — heute genau einer,
das **Statistik**-Modul (Prometheus, Grafana, node_exporter). Ausführlich in
[12-module-und-statistik.md](12-module-und-statistik.md); hier, was die Seite
tut.

Die Seite zeigt je Modul entweder den Bedarf und einen Knopf **installieren**
oder — wenn es installiert ist — was gerade läuft, einen Link auf seine Seite,
eine Tabelle aller **Schalter**, die **Einstellungen** als Auswahl und
**entfernen**. Jeder Knopf ruft `panel-aktion modul …`; die Oberfläche schickt
dabei nie einen Pfad, ein Abbild oder eine Portangabe, sondern ausschließlich
Namen und Werte aus dem Modulkatalog.

Zwei Rückfragen sind eingebaut:

* **Entfernen** sagt vorher, was verschwindet, und lässt die gesammelten
  Messwerte auf Wunsch liegen — eine wieder installierte Statistik zeigt dann
  die alte Geschichte weiter.
* **Ein Schalter mit Warnung** (cAdvisor, Erreichbarkeitsprobe) führt auf eine
  eigene Seite, die den Preis nennt, bevor er umgelegt wird. Der Text steht im
  Katalog, nicht in der Seite: Wer einen Schalter hinzufügt, schreibt ihn einmal
  und kann ihn nicht vergessen.

Wer die Modulseite selbst sehen darf, entscheidet der Katalog (`rolle`). Beim
Statistik-Modul ist das `verwalten` — dieselbe Rolle, die auch die Spiele
verwaltet; die Modulverwaltung hier bleibt bei `admin`.

> *Optional services that can be added later — today exactly one, the statistics
> module. Per module the page shows either what it needs and an install button,
> or what is running, a link to its page, a table of switches, the settings as
> selects and a remove button. Every button calls `panel-aktion modul …`, and the
> panel never sends a path, image or port — only names and values from the module
> catalogue. Two confirmations are built in: removal says what disappears and can
> keep the collected metrics, and a switch carrying a warning (cAdvisor, the
> reachability probe) leads to its own page stating the price first, with the text
> taken from the catalogue so it cannot be forgotten. Who may see a module's own
> page is decided by the catalogue (`rolle`) — `verwalten` for statistics, while
> managing modules stays with `admin`.*

---

## Modpaket für Mitspieler (#280)

Auf der Mod-Seite eines Servers, unter dem Hochladen: **für Mitspieler
freigeben**. Der Platzwart packt dann den Inhalt des Modverzeichnisses als ZIP
und legt es unter `/modpaket/<stack>.zip` ab — **öffentlich, ohne Anmeldung**,
und die Statusseite verlinkt es neben der Beitrittsadresse.

Warum überhaupt: `etc/spiele-mods.json` sagt es für Valheim selbst — *„Viele Mods
brauchen dieselbe Version bei jedem Mitspieler, sonst kommt niemand mehr auf den
Server."* Bis hierher musste der Betreiber jedem einzeln sagen, welche Dateien in
welcher Fassung; jetzt holt sich jeder genau die, die der Server fährt.

Warum als **Freigabe** und nicht als Nebeneffekt des Hochladens: Das Paket
verlässt die Maschine und ist für jeden abrufbar, der den Link kennt. Das ist
dieselbe Art Entscheidung wie die Freigabe eines Servers ohne Beitrittspasswort
(E26) — sie gehört dem Menschen, nicht dem Ablauf. Zurückgenommen wird sie mit
demselben Knopf; Datei **und** Stand verschwinden, denn eine liegengebliebene
Datei wäre weiter abrufbar, während die Oberfläche „nicht freigegeben" sagt.

Was **nicht** mitgepackt wird: Verknüpfungen. Ein Link im Archiv zeigt beim
Auspacken irgendwohin, und was hier hineingerät, liegt öffentlich — die Seite
nennt hinterher, was ausgelassen wurde. Gepackt wird ausschließlich das
Modverzeichnis aus dem Katalog, nie ein geratener Pfad.

Wird danach ein Mod hochgeladen oder entfernt, **packt der Platzwart das Paket
selbst neu**: Sonst installierten Mitspieler weiter eine Datei, die der Server
nicht mehr hat — und kämen genau deswegen nicht mehr herein. Ohne Freigabe
geschieht nichts.

Caddy liefert das Verzeichnis ohne Listing: Wer den Namen des Servers kennt,
bekommt sein Paket; sonst antwortet die Route 404.

> *On a server's mod page: release the modpack for players. Platzwart zips the
> mod directory and serves it publicly at `/modpaket/<stack>.zip`, linked from the
> status page next to the join address — because mods usually have to match
> version for version, and until now every player had to be told by hand. It is a
> release, not a side effect of uploading: the package leaves the machine, which
> is the same kind of decision as releasing a server without a join password
> (E26). Withdrawing removes file and state together, since a left-over file would
> still be fetchable while the panel says "not released". Symlinks are never
> packed and are named afterwards; only the catalogue's mod directory is packed.
> Uploading or removing a mod repacks automatically — otherwise players keep
> installing a file the server no longer has. No listing: knowing the server's
> name is enough, everything else answers 404.*

---

## Alle Routen

Rollen: **—** ohne Anmeldung · **alle** jede angemeldete Rolle · **verwalten**
`verwalten` und `admin` · **admin** nur `admin`. Die Spalte nennt die **erste**
Prüfung im Handler; was eine Seite danach je Rolle zeigt, steht beim jeweiligen
Abschnitt. `werkzeuge/vollstaendigkeit.sh` prüft, dass jede Route aus
`panel/app.py` hier steht (#179) — die vorige Tabelle kannte 22 von 61 Routen
und führte `/konfig` und `/archive` noch als admin-only.

| Methode | Pfad | Rolle | Zweck |
|---|---|---|---|
| GET | `/login` · POST `/login` | — | Anmeldung |
| GET | `/einrichten` · POST `/einrichten` | — | zweiten Faktor einrichten (nur mit Einrichtungs-Token) |
| GET | `/qr` | — | QR-Code (nur mit Einrichtungs-Token) |
| POST | `/passkey/anmelden-start` · `/passkey/anmelden-fertig` | — | Anmeldung mit Passkey |
| GET | `/abmelden` | — | Sitzung beenden |
| GET | `/favicon.ico` · `/favicon.svg` · `/apple-touch-icon.png` · `/icon-192.png` · `/icon-512.png` · `/manifest.webmanifest` | — | Symbole, Handy-App |
| GET | `/passkey.js` | — | Skript für Passkeys (nur `/login` und `/konto` dürfen es laden) |
| GET | `/` | alle | Übersicht |
| GET | `/bild/{stack}` · `/katalogbild/{schluessel}` | alle | Titelbilder |
| POST | `/aktion` | alle | starten / anhalten / neu starten |
| GET | `/server/{stack}` | alle | Einstellungen eines Servers — Inhalt je Rolle |
| GET | `/archive/{stack}` | alle | Archivliste (Knöpfe darin je Rolle) |
| GET | `/konto` · `/codes` · POST `/codes-neu` | alle | eigenes Konto, Wiederherstellungscodes |
| POST | `/passkey/anlegen-start` · `/passkey/anlegen-fertig` · `/passkey-loeschen` | alle | eigene Passkeys |
| GET | `/spiele` · POST `/installieren` | verwalten | Katalog, Spiel installieren |
| GET | `/deinstallieren-fragen/{stack}` · POST `/deinstallieren` | verwalten | Katalogspiel entfernen |
| POST | `/whitelist` | verwalten | Minecraft-Whitelist: eintragen, entfernen |
| GET | `/workshop/{stack}` · POST `/workshop` | verwalten | Steam-Workshop: suchen, Link/ID/Sammlung prüfen, Mods ein- und austragen |
| GET | `/freigabe-fragen/{stack}` · POST `/port-freigeben` | verwalten | Spiel ohne Beitrittspasswort von Hand ans Netz geben (nur `keins`) |
| POST | `/alle` | verwalten | alle anhalten / zuletzt laufende starten |
| POST | `/aktualisieren` · `/auto-update` · `/leerlauf` | verwalten | Betrieb eines Servers |
| GET | `/konfig/{stack}` · POST `/konfig-setzen` | verwalten | Umgebungsvariablen (Einzelfelder) |
| GET | `/dateien/{stack}` · `/datei/{stack}` · POST `/datei-speichern` | verwalten | Konfigurationsdateien |
| GET | `/logs/{stack}` | verwalten | Serverprotokoll |
| GET | `/holen-fragen/{stack}/{archiv}` · `/archiv-holen/{stack}/{archiv}` | verwalten | Sicherung herunterladen |
| GET | `/restore-fragen/{stack}/{archiv}` · POST `/restore` | verwalten | Wiederherstellung |
| GET | `/passwoerter` · POST `/zugang-anlegen` · `/zugang-loeschen` | verwalten | Zugangsdaten |
| GET | `/entfernen-fragen/{stack}` · POST `/fremd-entfernen` | admin | von Hand gebauten Server entfernen |
| GET | `/mods/{stack}` · POST `/mod-hochladen` · `/mod-entfernen` | admin | Mods |
| POST | `/modpaket` | admin | Modpaket für Mitspieler freigeben oder zurückziehen (#280) |
| GET | `/nutzer` · POST `/nutzer-anlegen` · `/mfa-zuruecksetzen` · `/nutzer-loeschen` | admin | Benutzerverwaltung |
| GET | `/protokoll` | admin | Protokoll aller Aktionen |
| GET | `/integrationen` · POST `/integrationen/steam` | admin | Schlüssel fremder Dienste (Steam-Web-API) |
| POST | `/integrationen/teamspeak` | admin | Kanäle je Server (#137): TeamSpeak-Zugang und Discord-Bot (je geprüft), Schalter, Oberkanal/Kategorie, Namensmuster |
| GET | `/neustart-fragen` · POST `/neustart` | admin | Maschine neu starten |
| GET | `/module` · POST `/modul-installieren` · `/modul-entfernen` · `/modul-schalter` · `/modul-einstellung` | admin | Zusatzmodule: installieren, schalten, entfernen (#261) |
| GET | `/modul-entfernen-fragen/{modul}` · `/modul-schalter-fragen/{modul}/{name}` | admin | Rückfragen dazu — vor dem Entfernen und vor einem Schalter mit Warnung |
| GET | `/auth-check` | admin | interne Prüfung für Caddy (Terminal) |
| GET | `/auth-modul` | laut Katalog | interne Prüfung für Caddy (Modulseiten); gibt Benutzer und Rolle als Kopfzeile zurück |

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
| `/opt/panel/daten/nutzer.json` | `{"secret": …, "nutzer": {"<name>": {"passwort_hash", "totp", "rolle", "totp_bestaetigt", "codes": [Argon2id-Hashes], "passkeys": [{"id", "pubkey", "zaehler", "angelegt"}]}}}` |
| `/opt/panel/daten/zugangsdaten.json` | Liste selbst gepflegter Zugänge |
| `/opt/panel/daten/audit.jsonl` | Protokoll, eine JSON-Zeile je Ereignis, ab 4 MB einmal nach `.jsonl.1` |
| `/opt/panel/daten/steam-api.conf` | Steam-Web-API-Schlüssel |
| `/opt/panel/daten/teamspeak.conf` · `discord.conf` | Zugänge für die Kanäle |
| `/opt/panel/daten/kanaele.json` · `kanaele-zuordnung.json` | Einstellungen der Kanäle · welcher Server welche Kanäle hat |
| `/opt/panel/daten/netzstand.json` | letzter Netzzählerstand je Server |
| `/opt/panel/daten/konfigzahlen.json` | Zahl der Konfigurationsdateien je Server (schreibt der Einrichtungs-Timer) |

Alles unter `/opt/panel/daten` gehört `panel` (Geheimnisse `0600`) und wandert
im täglichen Volllauf in das Archiv `panel-*` (#218). Geschrieben wird immer über
eine `.tmp`-Datei mit anschließendem `replace()`. Ein Absturz mitten im Schreiben
hinterließe sonst eine halbe JSON-Datei, und dann käme niemand mehr an die
Oberfläche.

> *Panel data: the table lists every file under `/opt/panel/daten` — users with
> hashes, TOTP secrets, recovery-code hashes and passkeys, hand-kept
> credentials, the audit log, the outside-service keys, the channel settings and
> mapping, the last traffic counters and the config-file counts. Everything
> there belongs to `panel` (secrets 0600) and goes into the `panel-*` archive in
> the daily full run (#218). Writes always go through a `.tmp` file followed by
> an atomic `replace()`: a crash mid-write would otherwise leave half a JSON file
> behind and lock everyone out of the panel.*

Die frühere Einzelnutzer-Datei `/opt/panel/konfig.json` und ihre einmalige
Übernahme gibt es seit #216 nicht mehr. Die Datei stand noch auf der Maschine
und trug das **aktuelle** Sitzungs-Secret, den Passwort-Hash und das
TOTP-Geheimnis — eine zweite Kopie gültiger Zugangsdaten. Vor dem Löschen wurde
verglichen, dass jeder Wert in `nutzer.json` steht.

> *The legacy single-user `konfig.json` and its migration are gone since #216;
> the file still held the current session secret, password hash and TOTP
> secret. Every value was verified to be in `nutzer.json` before deletion.*
