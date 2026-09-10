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

Ein Schalter je Server auf der Karte: **auto an** / **auto aus**. Aus per
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
> it has rotated out.*

---


---

## Die öffentliche Statusseite `/status`

Wer wissen wollte, ob ein Server läuft und wie man beitritt, brauchte einen
Panel-Zugang oder musste fragen. Das Panel ist dafür das falsche Werkzeug: Es
ist eine Verwaltungsoberfläche hinter Passwort, TOTP und Passkeys, und jemandem
ein Konto zu geben, damit er eine Beitrittsadresse ablesen kann, ist verkehrt
herum.

Die Seite trägt **Platzwart** als Namen und das Zeichen aus `werkzeuge/logo.py`
— als **Inline-SVG**, gelesen aus der Datei, die dieses Werkzeug erzeugt hat.
Nicht als `<img>`: Die Seite lädt kein einziges Bild, deshalb bleibt
`default-src 'none'` stehen. Ein eingebettetes SVG ist Auszeichnung, keine
Ressource, und braucht keine Lockerung. Und nicht noch einmal abgetippt:
`logo.py` gibt es genau deshalb, damit die Formen einmal als Zahlen stehen.

`https://<panel-domain>/status` zeigt ohne Anmeldung: welcher Server läuft,
unter welcher Adresse man beitritt, und — wo abrufbar — wie viele gerade drauf
sind.

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

### Was bewusst nicht daraufsteht

* **Server, deren Einrichtung nicht abgeschlossen ist.** `einrichtung_offen`
  markiert genau den Zustand, in dem ein Port veröffentlicht sein kann, bevor
  das Beitrittspasswort steht (E23). So einen Server auch noch anzukündigen wäre
  derselbe Fehler mit einem Megafon.
* **Server ohne Adresse.** Für einen Mitspieler haben sie keinen Wert.
* Keine Verwaltungsdaten: keine Pfade, keine Fassungen, keine Protokollauszüge,
  keine Benutzernamen, keine Ports außer dem Beitrittsport.

Nach dem Ausrollen von außen gegengeprüft — `panel.sparxx…`, `/opt/`,
`127.0.0.1`, `sudo`, `docker`, `einrichtung` kommen nicht vor; die zwei Treffer
auf „Passwort" sind Hinweise *für Mitspieler* („Passwort je Rolle", „Passwort im
Spiel"), und `root` steht im CSS (`:root{…}`).

### Eine Falle beim Einbau

`handle /status*` mit `root * /var/lib/platzwart-status` allein ergibt **404**:
Caddy sucht dann `<root>/status`. Dabei sieht die Route richtig aus und die
Datei liegt richtig da. `uri strip_prefix /status` gehört dazu.

### Die Beitrittsadressen stehen jetzt in einer Datei

`/etc/spiele-adressen.json` — vorher waren sie eine Tabelle im Quelltext des
Panels. Zwei Programme lesen sie jetzt: die Oberfläche und der Seitenschreiber.
Zwei Stellen, die dieselbe Tabelle führen, laufen auseinander, und dann nennt
die öffentliche Seite einen anderen Port als das Panel.

> *Finding out whether a server is up meant having a panel account or asking —
> backwards for a management surface behind password, TOTP and passkeys. The
> open question was route-versus-file, decided against the obvious option: a
> public route inside the panel process shares memory, renderers and headers
> with the management surface, and one forgotten flag in a shared renderer gives
> everything away. Instead a timer writes a finished file every minute and Caddy
> serves it directly — no reverse_proxy, no forward_auth, no session — so the
> page never reaches the panel and cannot leak what it never loaded. Written
> beside and renamed, since a half-written file would be half a page. Its headers
> are stricter than the panel's, not looser: no JavaScript and no images, so
> `default-src 'none'` stays. Servers whose setup is unfinished are omitted —
> announcing one that may be open without a join password would be the same
> mistake with a megaphone. The install trap: without `uri strip_prefix /status`
> Caddy looks for `<root>/status` and returns 404 while everything looks right.
> Join addresses moved into `/etc/spiele-adressen.json` because two programs read
> them now, and two copies of one table drift apart.*
## Spieler, wo es geht — Verkehr, wo nicht

Auf der Karte eines laufenden Servers steht entweder eine **echte Spielerzahl**
(`0/10 Spieler`) oder der **Netzverkehr** (`ruhig`, `Verkehr 45 kB/s`). Welches
von beidem, entscheidet sich daran, ob der Server auf eine Abfrage antwortet.

### Eine Fehlmessung, die eine Funktion gekostet hat

Hier stand bis zum 2026-09-10, es gebe keine Spielerzahlen — Palworld antworte
auf keine Steam-Abfrage, TeamSpeak spreche ein eigenes Protokoll, Enshrouded „ein
drittes Format". Das war **falsch**, und zwar in einem Punkt, der zählt:

```
=== Steam-Abfrage (A2S_INFO), 2026-09-10 ===
  valheim      0/10 Spieler   "Valheim Docker"
  enshrouded   0/4 Spieler    "mjfabrix"
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

### Was bewusst *nicht* angezeigt wird

* **Wer nicht antwortet, bekommt keine Null.** Er steht gar nicht erst im Stand;
  die Karte zeigt dann Verkehr. Eine Null wäre eine Aussage, keine Antwort ist
  keine.
* **Zahlen über drei Minuten alt.** Steht der Timer, ist die letzte Zahl keine
  Auskunft über „gerade" mehr. Eine veraltete Zahl als aktuelle auszugeben ist
  schlimmer als keine.

### Der Verkehr bleibt — für die anderen fünf

Er kommt aus demselben `docker stats`, das die Übersicht ohnehin abruft, und
beantwortet die Frage, um die es wirklich geht: *Kann ich neu starten, oder ist
gerade jemand drauf?* Drei Fälle, in denen auch er bewusst leer bleibt:

* **Erster Abruf.** Der Wert ist kumulativ seit dem Containerstart; ohne
  Vergleichswert gibt es keine Rate.
* **Der Zähler fällt.** Das heißt Container-Neustart, nicht negativer Verkehr.
* **Der letzte Abruf ist über 15 Minuten her.** Dann sagt die Differenz nichts
  mehr über „gerade".

> *A card shows a real player count where the server answers a query, and network
> traffic where it does not. Until 2026-09-10 this section claimed no counts were
> obtainable — wrongly: Enshrouded answers plain A2S. The likely cause of the
> error is in the protocol: since 2020 the first A2S_INFO is answered with a
> challenge, and only the repeat carrying it returns data, so a responding server
> looks silent. The lesson is not the number but this: a measurement yielding
> "not possible" is only a finding once the method itself has been checked.
> A timer queries every minute and the overview only reads, since querying inside
> the request path would lengthen every page load. The query port is discovered
> rather than configured — three of the seven servers are hand-built and have no
> catalogue entry. Silent servers are retried every 30 minutes, not every minute.
> A server that does not answer gets no zero: it is absent from the file, and a
> zero would be a statement where there is no answer. Counts older than three
> minutes are dropped — stale presented as current is worse than nothing.*

Der letzte Stand liegt in `/opt/panel/daten/netzstand.json`.

> *The card shows current network traffic, not a player count — because there is
> no player count: Palworld answers no Steam query, TeamSpeak speaks its own
> protocol, Enshrouded a third, and most of the 179 catalogue games would have no
> way at all. Traffic exists for every container and comes from the same
> `docker stats` call. It answers the question that matters — can I restart, or
> is somebody on — without claiming to know something it does not. Nothing is
> shown on the first poll, when the counter falls (a restart), or when the last
> poll is more than 15 minutes old.*

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
entfernen, außer über SSH. StarRupture allein sind **21,1 GB**.

Deshalb ein **eigener Weg**, keine gelockerte Prüfung: Die Katalogroutine liest
`panel.json` für die Ausschlussliste, entfernt DNS-Namen und räumt Katalogzustand
ab — alles Dinge, die es hier nicht gibt. Eine Prüfung wegzunehmen, damit ein
zweiter Fall durchpasst, macht aus zwei klaren Abläufen einen unklaren.

**Der Knopf liegt hinter einem eigenen Schritt.** Auf der Karte steht zunächst
nur **bearbeiten**; erst danach erscheint **entfernen** — und zwar nur auf
*dieser* Karte, alle anderen bleiben gesperrt. Die entsperrte Karte bekommt einen
gelben Rahmen, denn ein Modus, den man nicht sieht, ist selbst eine Falle.
**fertig** führt zurück.

Vorher stand `entfernen` in derselben Reihe wie `Protokoll`, `Einstellungen` und
`Konfigdateien`: drei harmlose Knöpfe und einer, der 21 GB löscht. Die
Rückfrageseite fängt einen Fehlgriff ab, aber der Knopf sollte gar nicht erst
danebenliegen.

Umgesetzt **serverseitig** über einen Parameter, nicht mit JavaScript: Die
Übersicht läuft unter `default-src 'none'`, und die Lockerung für Passkeys gilt
nur für `/login`, `/konto` und `/passkey.js` — sie soll sich nicht ausbreiten.

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
> also made them unremovable except over SSH. Hence a separate path rather than a
> loosened check: the catalogue routine reads `panel.json`, removes DNS names and
> clears catalogue state, none of which exists here. Admin only, since there is no
> catalogue entry to reinstall from. The size is shown before the click, and a
> final backup runs first; if it fails, nothing is deleted.*

---

## Aktualisieren und Sammelsteuerung

**Aktualisieren** holt eine neue Fassung des Images und startet den Server damit
neu. Der Knopf steht auf jeder Karte, für `verwalten` und `admin`.

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
über den Knopf **Protokoll** auf der Serverkarte — **auch bei gestoppten
Servern**, denn gerade dann will man wissen, warum.

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
geschriebenen Datei nur Name, Zeilen- und Zeichenzahl. Ein Protokoll soll
nachvollziehbar machen, *wer was* angefasst hat, und nicht Geheimnisse an einer
zweiten Stelle sammeln.

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
> length, a written file only its name and size. A log that quietly stops
> writing is worse than none, so a write error is surfaced on the page, and an
> unreadable line is shown as such rather than skipped.*

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
