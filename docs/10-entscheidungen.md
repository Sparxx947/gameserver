# 10 — Entscheidungen

Warum es so ist und nicht anders. Jeder Eintrag nennt die Alternative, die
naheliegend gewesen wäre, und den Grund, der dagegen sprach — meist ein
konkreter Fehlschlag.

> *Why things are the way they are. Each entry names the obvious alternative and
> the reason against it — usually a concrete failure.*

---

## E1 — Die Oberfläche bekommt keinen Docker-Socket

**Naheliegend:** `panel` in die Gruppe `docker`, fertig.
**Dagegen:** Socket-Zugriff ist gleichbedeutend mit root
(`docker run -v /:/host`). Ein internet-erreichbarer Webdienst mit root wäre der
gesamte Sicherheitsentwurf zunichte.
**Stattdessen:** eine sudo-Brücke mit 14 fest verdrahteten Zweigen, jeder
Parameter gegen Positivlisten.
**Kosten:** Jede neue Fähigkeit der Oberfläche braucht eine Erweiterung in
`panel-aktion`. Das ist der Punkt.

> *Obvious: put `panel` in the `docker` group. Against: socket access equals
> root, which would void the entire design. Instead: a sudo bridge with 14
> hard-wired branches. Cost: every new panel capability needs a change in the
> bridge — which is the point.*

---

## E2 — Die Oberfläche übergibt einen Schlüssel, keine Definition

**Naheliegend:** ein Formular für Image, Ports, Volumes.
**Dagegen:** Wer diese Felder setzt, kann `/:/host` mounten. Das ist E1 durch die
Hintertür.
**Stattdessen:** ein Katalog in `/etc`, den die Oberfläche nur lesen kann; sie
übergibt einen Schlüssel.
**Kosten:** Ein neues Spiel erfordert einen Katalogeintrag statt eines
Formulars. Dafür gibt es `katalog-vorpruefung`.

---

## E3 — Bind-Mounts statt Docker-Volumes

**Naheliegend:** benannte Volumes, wie in den meisten Compose-Beispielen.
**Dagegen:** Ein Volume liegt unter `/var/lib/docker/volumes/<hash>/_data`. Borg
müsste diesen Pfad kennen — er ändert sich beim Neuanlegen — oder ein
Hilfscontainer müsste kopieren.
**Stattdessen:** `/srv/games/<name>` als Bind-Mount. Benennbar, ohne Docker
lesbar, überlebt `docker system prune`.
**Kosten:** Rechte muss man selbst setzen. Daher die feste UID/GID 4711.

---

## E4 — Feste UID 4711 für alle Spieldaten

**Naheliegend:** jedem Container seine eigene UID geben.
**Dagegen:** Nach einem Neuaufbau stimmen die Nummern nicht mehr überein, und die
Spielstände gehören niemandem. Ein Server, der seine Welt nicht schreiben kann,
verliert den Fortschritt der Sitzung — ohne Fehlermeldung.
**Stattdessen:** ein Systembenutzer `spiele` mit fest vergebener UID/GID.

---

## E5 — Ein Borg-Archiv je Spiel, nicht eines für alles

**Naheliegend:** ein Archiv `gameserver-<zeit>` mit allem darin.
**Dagegen:** Um ein einzelnes Spiel zurückzuholen, müsste man das Gesamtarchiv
durchsuchen. Und `prune` würde für den gemeinsamen Topf rechnen: das häufig
gesicherte Spiel verdrängt das seltene.
**Stattdessen:** Präfix je Spiel, `prune --glob-archives "<spiel>-*"`.
**Kosten:** mehr Archive in der Liste. Dafür holt man ein Spiel gezielt zurück.

---

## E6 — Der Viertelstundenlauf lässt gestoppte Spiele aus

**Naheliegend:** immer alles sichern, ist am einfachsten.
**Dagegen:** Ein gestopptes Spiel ändert sich nicht. Die „Sohn"-Stufe
(`--keep-within 2d`) wäre binnen zwei Tagen mit Kopien desselben Standes
gefüllt — die Aufbewahrung verwässert, ohne einen Stand mehr zu bewahren.
**Stattdessen:** nur laufende Container; die tägliche Vollsicherung nimmt den
Rest mit.

---

## E7 — Die Passwort-Einrichtung rät keine Feldnamen

**Naheliegend:** je Spiel Pfad und Feldname in den Katalog schreiben.
**Dagegen:** 36 von 41 Spielen legen ihre Konfiguration erst beim ersten Start
an, oft nach minutenlangem Download. Die Feldnamen sind nirgends zuverlässig
dokumentiert; sie aus Foren abzuschreiben hätte in den meisten Fällen still
danebengelegen.
**Stattdessen:** Mustersuche über `.ini`, `.json`, `.xml` und `.cfg`, mit
negativen Ausschlüssen (nicht `rcon`, nicht `steam`, nicht `db`).
**Und entscheidend:** Nach sechs Stunden **gibt der Schritt auf und meldet es**.
Ein Server ohne Beitrittspasswort darf nicht unauffällig sein.

> *Obvious: record path and field name per game. Against: 36 of 41 games write
> their config only on first start, and the field names are not reliably
> documented — copying them from forums would have silently missed most of the
> time. Instead: pattern matching with negative exclusions. Crucially, after six
> hours the step gives up and says so: a server without a join password must not
> be quiet about it.*

---

## E8 — Spielports stehen nicht in ufw

**Naheliegend:** für jeden Spielport eine ufw-Regel, der Ordnung halber.
**Dagegen:** Sie hätte keine Wirkung. Docker trägt seine Veröffentlichungen als
DNAT-Regeln ein, die **vor** den ufw-Ketten greifen. Eine Regel, die nichts tut,
ist schlimmer als keine — sie täuscht Sicherheit vor und wird beim nächsten
Nachdenken für die wirksame Stelle gehalten.
**Stattdessen:** ufw regelt, was nicht über Docker läuft (22, 80, 443, Tailnet).
Wer einen Spielport schließen will, ändert die compose-Datei.

---

## E9 — Verwaltungsports auf `127.0.0.1`

**Anlass:** Necesse veröffentlichte seine Webkonsole auf `0.0.0.0:8080`. Das fiel
nur auf, weil jemand hinsah.
**Regel seither:** RCON, Webkonsolen, ServerQuery, Telnet und API-Ports bekommen
im Katalog die dreiteilige Form `127.0.0.1:port:port`. Betrifft acht Spiele.
**Offen:** Eine Prüfung, die meldet, wenn ein Container einen unerwarteten Port
auf `0.0.0.0` legt, gibt es noch nicht.

---

## E10 — Portkollisionen werden gegen die Realität geprüft, nicht gegen den Katalog

**Naheliegend:** beim Anlegen des Katalogs alle Ports global eindeutig machen.
**Dagegen:** Das erzwang Ersatzports ab 30000 für fast jedes Spiel, obwohl nie
zwei gleichzeitig laufen.
**Schlimmer noch:** Ein Lauf, der Kollisionen automatisch auflöste, wollte
**TeamSpeak von 9987 auf 30115 verschieben** — ein laufender Server findet seine
eigenen Ports als belegt vor. Jeder Client hätte den Server verloren.
**Stattdessen:** Der Katalog darf Ports doppelt vergeben; `spiel-verwalten` prüft
gegen die **tatsächlich gebundenen** Ports und lehnt bei echter Kollision ab.
**Wer das je automatisiert: installierte Spiele ausnehmen.**

> *Obvious: make every port globally unique in the catalogue. Against: that
> forced replacement ports on nearly every game for no benefit — and worse, an
> automated resolution run tried to move TeamSpeak from 9987 to 30115, because a
> running server sees its own ports as taken. Instead the catalogue may reuse
> ports and the installer checks reality. Anyone automating this must exclude
> installed games.*

---

## E11 — Caddy fährt nur HTTP/1.1

**Anlass:** Über HTTP/2 antwortete Caddy auf den WebSocket-Upgrade des Terminals
mit `404`; im Browser stand `websocket connection closed with code: 1006`. Über
HTTP/1.1 kommt sauber `101 Switching Protocols`.
**Kosten:** kein h2, kein h3. Bei einem Panel mit zwei Benutzern belanglos.

---

## E12 — Zwei getrennte Kopfzeilensätze

**Naheliegend:** eine Richtlinie für die ganze Domain.
**Dagegen:** Das Panel fährt `default-src 'none'` — das blockiert `ttyd`
vollständig, denn ein Terminal braucht JavaScript und WebSockets. Umgekehrt darf
das Panel die Lockerungen des Terminals nicht bekommen: Es zeigt Zugangsdaten.
**Stattdessen:** zwei `handle`-Blöcke mit eigenen Kopfzeilen.

---

## E13 — Der Panel-Dienst ist absichtlich schwach gehärtet

**Naheliegend:** die volle systemd-Härtung, wie sie überall empfohlen wird.
**Dagegen — vier gemessene Fehlschläge:**

| Option | Wirkung |
|---|---|
| `NoNewPrivileges=yes` | `sudo` kann nicht mehr nach root — die Übersicht blieb leer |
| `LockPersonality`, `ProtectKernelTunables`, `ProtectControlGroups` | setzen `NoNewPrivileges` **implizit** |
| `ProtectSystem=strict` | Borg kann seinen Cache nicht anlegen — Archivliste leer |
| `ProtectHome` | `panel-aktion` käme nicht an die Borg-Passphrase |

**Die eigentliche Lehre:** Alle vier äußerten sich als *funktionierende
Oberfläche mit leeren Listen*, nie als Fehlermeldung. Härtung, die man nicht
prüft, härtet nicht — sie bricht leise.
**Stattdessen:** `NoNewPrivileges=no`, `PrivateTmp=yes`, `ProtectSystem=full`.
Der Schutz kommt aus Dateirechten und der engen Brücke.

> *Obvious: full systemd hardening as universally recommended. Against: four
> measured failures, each presenting as a working UI with empty lists rather than
> an error. Unverified hardening does not harden — it breaks quietly.*

---

## E14 — Das TOTP-Geheimnis sieht niemand

**Naheliegend:** beim Anlegen eines Kontos den QR-Code zeigen, damit der
Administrator ihn weitergeben kann.
**Dagegen:** Dann wandert der zweite Faktor durch einen Chat, eine Mail oder ein
Terminalprotokoll — und ist keiner mehr.
**Stattdessen:** Das Geheimnis entsteht beim Anlegen, wird aber nirgends
angezeigt. Der neue Benutzer bekommt es bei seiner ersten Anmeldung selbst.
**Gleiches gilt bei der Einrichtung:** Stufe 30 gibt das Startpasswort aus, das
TOTP-Geheimnis nicht.

---

## E15 — Die Rolle kommt aus der Datei, nicht aus dem Cookie

**Naheliegend:** die Rolle mit in die signierte Sitzung packen, spart einen
Dateizugriff.
**Dagegen:** Ein herabgestufter oder gelöschter Benutzer behielte seine Rechte
bis zum Ablauf des Cookies — acht Stunden.
**Kosten:** ein Lesevorgang je Anfrage. Bei zwei Benutzern nicht messbar.

---

## E16 — `/srv/dienste` getrennt von `/srv/games`

**Anlass:** Die Prüfung der Sicherungen verlangt für jedes Verzeichnis unter
`/srv/games` Spielstand-Dateien. TeamSpeak hat keine und hätte dauerhaft Alarm
ausgelöst — ein Daueralarm, den man nach zwei Wochen nicht mehr liest.

---

## E17 — Ein CNAME je Spiel auf einen A-Eintrag

**Naheliegend:** je Spiel ein A-Eintrag auf die IP.
**Dagegen:** Beim Umzug wären alle zu ändern, und man vergisst einen.
**Stattdessen:** `gs.<zone>` trägt die IP, alle Spiele sind CNAMEs darauf. Ein
Eintrag beim Umzug.
**Und:** `dns-pflegen` fragt nie die Namensauflösung, sondern immer die API — ein
Wildcard in der Zone beantwortet jeden erfundenen Namen und machte jede Prüfung
per `dig` wertlos.

---

## E18 — Sicherung über Tailscale, nicht über einen offenen Port

**Naheliegend:** SSH des Sicherungsservers ins Internet stellen.
**Dagegen:** Ein weiterer öffentlich erreichbarer Dienst, den man pflegen und
überwachen muss — für einen Zweck, der ihn nicht braucht.
**Nebeneffekt:** Das Tailnet ist zugleich der Notzugang, wenn eine ufw-Regel oder
ein fail2ban-Bann den SSH-Zugang aussperrt.
**Kosten:** Ist das Tailnet unten, scheitert die Sicherung. Das meldet der Timer.

---

## E19 — Passwörter ohne Sonderzeichen und ohne `0/O`, `1/l/I`

**Naheliegend:** maximale Entropie.
**Dagegen:** Diese Passwörter werden vorgelesen und abgetippt. Und manche Spiele
filtern Sonderzeichen still weg — dann steht in der Datei etwas anderes als in
der Anzeige, und niemand kommt auf den Server.
**Stattdessen:** 14 Zeichen aus einem Alphabet von 57 Zeichen ohne
Verwechslungsgefahr — nachgerechnet **81,7 Bit**. Für ein Beitrittspasswort, das
zudem hinter einem Spielserver ohne Anmeldeversuchsgrenze steht, mehr als genug;
die Borg-Passphrase bekommt mit 32 Zeichen 186,7 Bit.

> *Obvious: maximum entropy. Against: these passwords are read aloud and typed by
> hand, and some games silently strip punctuation — leaving the file holding
> something other than what is displayed, and nobody gets in. Instead: 14
> characters from a 57-character look-alike-free alphabet, a measured 81.7 bits.
> The Borg passphrase gets 32 characters, or 186.7 bits.*

---

## E20 — Der Bausatz parametrisiert, statt umzubauen

**Naheliegend:** Die Skripte auf eine zentrale `/etc/gameserver.conf` umstellen,
damit das Repositorium sauber wird.
**Dagegen:** Dann wiche das Repositorium vom laufenden System ab — und es
beschriebe eine Maschine, die es so nicht gibt. Eine Dokumentation, die eine
Fiktion beschreibt, ist schlimmer als keine.
**Stattdessen:** Die Dateien stehen **1:1 wie auf dem Server** im Repositorium;
ersetzt sind nur die standortbezogenen Werte, durch `@@PLATZHALTER@@`, die beim
Einbau aus `konfiguration.env` gefüllt werden. Bleibt einer stehen, bricht die
Einrichtung ab.

> *Obvious: refactor the scripts onto a central config file so the repository
> looks tidy. Against: the repository would then differ from the running system
> and describe a machine that does not exist — documentation of a fiction is
> worse than none. Instead the files are byte-for-byte as deployed, with only
> site-specific values replaced by placeholders filled from
> `konfiguration.env`; a left-over placeholder aborts the install.*

---

## E21 — Bei wechselnder Adresse pflegt der Server den A-Eintrag selbst

**Naheliegend:** einen DDNS-Namen in `SERVER_IPV4` eintragen, oder `DNS_ZIEL` auf
einen fremden DDNS-Namen zeigen lassen.

**Dagegen, erstens:** `SERVER_IPV4` ist gar kein Eintragspunkt. Aus dem Wert
entstand nie ein DNS-Eintrag — er landete ausschließlich in Kommentaren von
`dns-pflegen`. Ein Name dort wurde klaglos angenommen und tat nichts. Genau das ist
die schlimmste Sorte Einstellung: eine, die man für erledigt hält.

**Dagegen, zweitens:** Ein fremder DDNS-Name als `DNS_ZIEL` würde zwar
funktionieren — die Spiel-CNAMEs zeigen dann eben dorthin —, holt sich aber einen
zweiten Anbieter in den Pfad jedes Spielservers, und `PANEL_DOMAIN` bliebe
trotzdem außen vor. Damit hinge das Zertifikat an einem Namen, den niemand
nachzieht. Nach E17 trägt genau **ein** Eintrag die Adresse; ein zweiter Anbieter
daneben verdoppelt die Stellen, an denen es schiefgehen kann.

**Stattdessen:** `SERVER_IPV4=dynamic` schaltet `dns-ziel.timer` ein. Der misst
alle fünf Minuten die öffentliche IPv4 und schreibt sie in den A-Eintrag
`DNS_ZIEL` — den Eintrag, den es ohnehin schon gibt. Cloudflare bleibt die
einzige Quelle der Wahrheit, die Spiel-CNAMEs werden nicht angefasst, und
`PANEL_DOMAIN` folgt als CNAME von allein oder wird als A-Eintrag innerhalb der
Zone mitgezogen.

**Und:** In diesem Betrieb legt `dns-pflegen` den A-Eintrag auch an, wenn er fehlt —
anders als im festen Betrieb, wo er bewusst Handarbeit bleibt. Der Unterschied
ist nicht Bequemlichkeit, sondern Eigentum: bei `dynamic` gehört der Eintrag dem
Programm, sonst einem Menschen. Wer beides gleich behandelt, bekommt entweder
einen Automatismus, der fremde Einträge überschreibt, oder einen dynamischen
Betrieb, der beim ersten Lauf an einem fehlenden Eintrag scheitert.

**Nachtrag (Stufe 25):** Die Grenze „das Programm besitzt `DNS_ZIEL` nur bei
`dynamic`" hat einen Fall offengelassen: `PANEL_DOMAIN` wurde **nie** angelegt,
und die DNS-Stufe lief als Nummer 70 ohnehin erst nach dem Zertifikat aus Stufe
40. Auf einer frischen Zone war dieser eine Name damit die letzte Handarbeit,
die eine sonst durchlaufende Einrichtung noch brauchte — und wenn er fehlte,
stand im Journal ein gescheiterter ACME-Versuch, nicht der Grund dafür.

`dns-pflegen grundgeruest` schließt das, ohne die Entscheidung umzudrehen: es legt
an, was fehlt, und ändert **nie** einen vorhandenen Eintrag. Der Besitz wechselt
damit nicht — wer einen Eintrag von Hand pflegt, behält ihn unangetastet, auch
wenn er woandershin zeigt. Nachgeführt wird weiterhin nur bei `dynamic` und nur
von `ziel-setzen`. Der Unterschied ist die Aufsicht: `grundgeruest` läuft einmal
und auf ausdrücklichen Anstoß, der Zeitgeber unbeaufsichtigt alle fünf Minuten.
Ein Automatismus dieser zweiten Sorte darf keine Namen erfinden.

> *Addendum: the ownership line left one case open — `PANEL_DOMAIN` was never
> created, and the DNS stage ran after the certificate stage, so on a fresh zone
> that single name was the last piece of handwork an otherwise unattended
> install still needed. `dns-pflegen grundgeruest` closes it without reversing the
> decision: it creates what is missing and never changes an existing record, so
> ownership does not move. What differs is supervision — it runs once, on
> purpose; the timer runs unattended every five minutes and must not invent
> names.*

**Kosten:** Der Server hängt für die Messung an drei fremden Auskunftsstellen.
Deshalb entscheidet die Mehrheit und nicht die erste Antwort, und Adressen aus
`100.64.0.0/10` werden verworfen — dort liegt sowohl Provider-NAT als auch
Tailscale, und in beiden Fällen wäre die Messung wertlos. Sind sich zwei Stellen
nicht einig, wird **nichts** geschrieben und der alte Eintrag bleibt stehen.

> *Obvious: put a DDNS hostname in `SERVER_IPV4`, or point `DNS_ZIEL` at a
> foreign DDNS name. Against, first: `SERVER_IPV4` was never an entry point at
> all — no record was ever derived from it, the value only ever landed in
> comments, so a hostname there was accepted silently and did nothing. That is
> the worst kind of setting: one people believe is handled. Against, second: a
> foreign DDNS name as `DNS_ZIEL` would work for the games but puts a second
> provider in the path of every game server, and leaves `PANEL_DOMAIN` — and with
> it the certificate — behind, pointing at a name nobody updates. Per E17 exactly
> one record carries the address; a second provider doubles the places where that
> can break. Instead, `SERVER_IPV4=dynamic` enables `dns-ziel.timer`, which
> measures the public IPv4 every five minutes and writes it into the A record
> that already exists. Cloudflare stays the single source of truth, no game CNAME
> is touched, and the panel name follows as a CNAME or is carried along as an A
> record inside the zone. In that mode `dns-pflegen` also creates the record when it
> is missing, unlike fixed mode where it stays hand-made — the difference is
> ownership, not convenience: treating both alike yields either an automation
> that overwrites foreign records or a dynamic mode that fails on its first run.
> The cost is a dependency on three third-party echo services, which is why a
> majority decides rather than the first answer, why `100.64.0.0/10` is discarded
> (carrier NAT and Tailscale both live there, and the measurement would be
> worthless either way), and why nothing at all is written when two sources fail
> to agree.*
## E22 — Die Sicherung lässt sich abschalten, aber nicht heimlich

**Naheliegend:** Die Sicherung als Pflicht behandeln. Wer den Server aufbaut,
soll eben ein Sicherungsziel haben.

**Dagegen:** Das trifft die Wirklichkeit nicht. Beim ersten Aufbau gibt es das
Ziel oft noch nicht, und Stufe 50 bricht dann ab — mitten in einer Einrichtung,
die sonst durchliefe. Wer weiterkommen will, kommentiert die Stufe aus oder
trägt ein Repository ein, das es nicht gibt. Beides ist schlechter als ein
Schalter, weil danach niemand mehr sagen kann, was der Zustand der Maschine ist.

**Stattdessen:** `BORG_REPO=aus`. Kein `borg`, keine Passphrase, keine Timer,
keine Archivwege in der Oberfläche, keine letzte Sicherung beim Löschen.

**Der Schalter ist der Wert selbst, keine zweite Variable.** Ein zusätzliches
`SICHERUNG=ja/nein` neben `BORG_REPO` könnte sich widersprechen — „Sicherung an,
aber wohin?" — und man müsste entscheiden, welche der beiden recht hat. Ein Wert
kann das nicht.

**Und das Wichtigste:** Der gefährliche Zustand ist nicht „abgeschaltet", sondern
„abgeschaltet, und keiner weiß es". Ein Backup, auf das man sich verlässt, ohne
dass es existiert, ist schlimmer als eines, von dem man weiß, dass es fehlt —
derselbe Gedanke wie bei einer Dokumentation, die vom System abweicht. Deshalb:
Warnkasten auf der Übersicht, ausdrücklicher Hinweis auf der Löschbestätigung
*vor* dem Klick, und `abgleich.sh` prüft, ob die Timer **laufen** — eingesetzte,
aber abgeschaltete Einheiten sähen im reinen Dateivergleich tadellos aus.

**Was bewusst bleibt:** Die Ausschlussliste. `spiel-verwalten` liest und schreibt
sie bei jeder Installation und Deinstallation; fehlte sie, bräche die
Deinstallation mitten im Ablauf ab und ließe Reste stehen — genau der Abbruch,
der schon einmal aus einem anderen Grund passiert ist (siehe `panel.service`,
`ProtectSystem`).

> *Obvious: treat backups as mandatory. Against: that does not match reality —
> on a first build the target often does not exist yet, stage 50 aborts, and
> people either comment the stage out or enter a repository that is not there.
> Both are worse than a switch, because afterwards nobody can say what state the
> machine is in. Instead: `BORG_REPO=aus`. The switch is the value itself rather
> than a second variable, because two variables can contradict each other and one
> cannot. Most importantly, the dangerous state is not "off" but "off and nobody
> knows": a backup people rely on without it existing is worse than one they know
> is missing — the same reasoning as documentation that drifts from the system.
> Hence a warning box on the overview, an explicit note on the delete
> confirmation before the click, and `abgleich.sh` checking that the timers
> actually run, since installed-but-disabled units would look perfect in a pure
> file comparison. The exclusion list deliberately stays: `spiel-verwalten` reads
> and writes it on every install and uninstall, and its absence would abort an
> uninstall mid-way, leaving remnants behind — exactly the abort that has already
> happened once for a different reason.*

---

## E24 — Der DNS-Anbieter ist eine Klasse, nicht ein Schalter im Ablauf

**Naheliegend:** an den Stellen, die schreiben, nach dem Anbieter verzweigen —
`if anbieter == "cloudflare": … else: …`.

**Dagegen:** Dann steht die Frage „lege ich diesen Eintrag an, ändere ich ihn
oder lasse ich ihn in Ruhe" einmal je Anbieter da. Genau diese Regeln tragen
hier aber die Sicherheit: kein Spielport hinter einem Proxy, ein fremder Eintrag
wird nie gelöscht, ein vorhandener nie überschrieben, und geprüft wird immer an
der API statt an der Namensauflösung. Ein zweiter Anbieter wäre die zweite
Gelegenheit, eine davon anders auszulegen — und niemand merkt es, weil beide
Zweige „funktionieren".

**Stattdessen:** Ein Anbieter kann sechs Dinge — Zone finden, Sätze holen,
anlegen, ändern, löschen — und entscheidet nichts. Er liefert und nimmt immer
dieselbe Form (`kennung`, `typ`, `name`, `wert`, `ttl`, `proxy`). Die Regeln
stehen einmal darüber und kennen keine einzige API. Ein neuer Anbieter ist
damit eine Klasse und ein Eintrag in `ANBIETER` — und er *kann* die Regeln nicht
anders auslegen, weil er sie nicht sieht.

**Kosten:** Eine Eigenheit, die nur ein Anbieter hat, muss durch die gemeinsame
Form. Cloudflares `proxied` ist so ein Fall: es steht als `proxy` in jedem Satz
und wird über `kennt_proxy` abgeschaltet, statt es zu verstecken. Das ist der
ehrliche Preis — eine Naht, die so tut, als gäbe es keine Unterschiede, wäre
dieselbe Falle eine Ebene höher.

**Und:** Das Werkzeug heißt deshalb nicht mehr `cf-dns`. Ein Name, der einen
Anbieter nennt, wäre nach dem ersten zweiten Anbieter falsch — und zwar so, dass
man ihm nicht zutraut, was er kann. Der alte Name steht in `rueckbau.sh` unter
`ALTLASTEN`: die Werkzeugliste wird aus `bin/` abgeleitet und kennt nur die
Gegenwart, ein umbenanntes Werkzeug hätte sonst jeden Rückbau überlebt.

> *Obvious: branch on the provider where records are written. Against: the rules
> about creating, changing and leaving records alone are what carries the safety
> here — no game port behind a proxy, never delete a foreign record, never
> overwrite an existing one, always verify against the API. A second provider
> would be a second chance to read one of them differently, and nobody notices
> because both branches "work". Instead a provider does six things and decides
> nothing; the rules sit above it and know no API. Cost: a provider-specific
> trait must pass through the shared shape — Cloudflare's `proxied` travels as
> `proxy` and is switched off via `kennt_proxy` rather than hidden. Hence the
> rename away from `cf-dns`; the old name lives on in `rueckbau.sh` under
> `ALTLASTEN`, because the tool list is derived from `bin/` and knows only the
> present.*

---

## E23 — Der Port kommt zuletzt, nicht zuerst

17 Spiele nennen ihren Port erst in der Konfiguration, die ihr erster Start
schreibt. Sie starten deshalb ohne veröffentlichten Port, und `port-ermitteln`
trägt ihn nach. Die Frage war, wo dieser Schritt im Ablauf steht.

**Naheliegend wäre der Port zuerst.** Ohne veröffentlichten Port ist der Server
gar nicht erreichbar; ein Beitrittspasswort nützte dort niemandem. Genau so war
es zuerst gebaut.

**Dagegen spricht, was der Schritt tatsächlich tut:** Das Eintragen des Ports ist
der Moment, in dem der Server nach außen offen ist. Steht er vor der
Passwort-Einrichtung, liegt zwischen beiden ein Fenster, in dem der Server
erreichbar ist und kein Passwort verlangt. Am 08.09. war das kein Gedankenspiel:
ET: Legacy antwortete auf `198.51.100.10:27960` mit `g_needpass 0`, während die
Einrichtung noch auf die Konfigurationsdatei wartete. Beide Schritte brauchen
ohnehin dieselbe Datei — die Reihenfolge kostet also nichts.

**Also drei Dinge, nicht eines:**

1. **Reihenfolge umgedreht.** `spiel-einrichtung` setzt erst das Passwort, dann
   den Port.
2. **Ein Gate davor.** Der Port wird nur eingetragen, wenn `einrichtung_offen`
   nicht mehr gesetzt ist — also entweder das Passwort steht oder die Suche
   endgültig aufgegeben und laut gemeldet wurde. Das Gate hängt am **Ergebnis**,
   nicht am Format: ein künftiges Konfigurationsformat, das niemand kennt, kann
   nicht daran vorbei.
3. **Nur ein Weg.** `port-ermitteln` einzeln aufgerufen — der Knopf im Panel tut
   das — übergibt per `execv` an `spiel-einrichtung`, statt selbst zu handeln.
   Zwei Wege, die Ports veröffentlichen, wären früher oder später zwei
   verschiedene Reihenfolgen.

Punkt 2 ist der eigentliche Schutz. Punkt 1 allein hätte den Fehler nur
verschoben: als die Reihenfolge stimmte, fand die Einrichtung im id-Tech-Format
trotzdem kein Passwortfeld, gab kein Passwort ein — und der Port wäre ohne das
Gate wieder veröffentlicht worden.

> *17 games only name their port in the config their first start writes, so the
> port is filled in afterwards. Obvious: do that first, since without a published
> port the server is unreachable and a password helps nobody. Against: publishing
> the port is exactly what exposes the server, so doing it first opens a window in
> which the server is reachable and asks for no password — measured on 08.09.,
> ET: Legacy answered with `g_needpass 0` while setup was still waiting. Both
> steps need the same file anyway, so the order costs nothing. Hence three things:
> the order reversed; a gate that keys off the result (setup settled) rather than
> the config format, so an unknown format cannot slip past; and a single code path,
> with the standalone tool handing over via `execv` instead of acting itself. The
> gate is the actual protection — reversing the order alone would only have moved
> the bug, since setup still found no password field in the id-Tech format.*

---

## E25 — Das Projekt heißt Platzwart

`gameserver` beschreibt die Gattung, nicht dieses Projekt — und es beschreibt
ausgerechnet das, was hier **nicht** drinsteckt.

**Warum der Name trägt:** Der Platzwart bespielt den Platz nicht, er hält ihn
instand: Linien kreiden, Netz prüfen, abends abschließen. Das ist genau der
Inhalt von `werkzeuge/` — `abgleich.sh` ändert ausdrücklich nichts,
`vollstaendigkeit.sh` prüft, `aufraeumen.sh` räumt, `rueckbau.sh` baut ab. Kein
einziges Werkzeug hier ist zum Spielen da.

Der Doppelsinn trägt zweimal: **warten** heißt instand halten *und* abwarten —
`port-ermitteln` hat dafür den Rückgabewert `2 = warte`, weil manche Spiele ihren
Port erst nach dem ersten Start verraten. Und **Platz** ist der Sportplatz wie
der Plattenplatz, den `RESERVE_GB = 10` freihält.

**Was dagegen sprach:** Deutsch, außerhalb des Sprachraums undurchsichtig, neun
Buchstaben. Die Alternative wäre **Ludus** gewesen (lateinisch *Spiel* und
*Schule*) — international lesbar, aber ohne den Bezug zur Instandhaltung, der
den Namen hier überhaupt erst richtig macht.

**Was sich ändert und was nicht:** Der Titel der Oberfläche, das Zeichen (siehe
`werkzeuge/logo.py` — die Mitte eines Spielfelds) und die Überschrift des
Repositoriums. **Nicht** geändert werden die Werkzeugnamen (`spiel-verwalten`,
`dns-pflegen`, …), das SSH-Ziel `gameserver` — das ist die Maschine, nicht das
Projekt — und **nicht die WebAuthn-`RP_ID`**: An ihr hängen die vorhandenen
Passkeys, eine Änderung machte sie allesamt ungültig. Geändert wurde nur der
Anzeigename daneben.

Bereits eingerichtete Authenticator-Einträge behalten ihren alten Namen. Das ist
kosmetisch und kein Fehler: Der Aussteller steht in der `otpauth://`-URI, die nur
bei der Einrichtung gelesen wird.

> *`gameserver` names the genre, not this project — and names precisely what is
> not in it. A groundskeeper does not play on the pitch, he keeps it usable, which
> is exactly what `werkzeuge/` does: compare, check, tidy, tear down. The German
> "warten" carries both maintaining and waiting, which `port-ermitteln`'s exit
> code 2 does too. Against it: German, opaque abroad. The alternative, Ludus, is
> internationally readable but loses the maintenance connection that makes the
> name fit. Tool names, the SSH target and above all the WebAuthn RP_ID stay —
> existing passkeys are bound to the latter.*
