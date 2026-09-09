# 06 — Netz, DNS und Firewall

## Die wichtigste Eigenheit: Docker geht an ufw vorbei

`ufw status` zeigt vier Regeln — 22, 80, 443 und das Tailnet. Trotzdem sind
Spielports von außen erreichbar. Das ist **kein Fehler in der Konfiguration**,
sondern die Bauweise von Docker.

Docker trägt seine Portveröffentlichungen als DNAT-Regeln in die
`nat`-Tabelle ein, und zwar in einer Kette, die **vor** den ufw-Ketten greift.
Ein Paket auf einen veröffentlichten Port wird umgeschrieben und in den
Container geleitet, bevor ufw es überhaupt sieht.

Praktische Folgen:

* **Spielports müssen nicht in ufw stehen.** Sie stehen deshalb bewusst nicht
  drin — eine Regel, die nichts bewirkt, ist schlimmer als keine: sie täuscht.
* **Ports gehen mit dem Container auf und zu.** `docker compose down` entfernt
  die DNAT-Regeln; der Port ist danach dicht. Nachgemessen am 2026-09-06 an
  Satisfactory: nach dem Stoppen waren die `iptables`-Regeln verschwunden.
* **Wer einen Port wirklich schließen will, ändert die compose-Datei**, nicht
  ufw.
* **Ein Port soll nur lokal erreichbar sein?** Dreiteilige Angabe:
  `127.0.0.1:8080:8080/tcp`.

> *The key quirk: Docker publishes ports as DNAT rules in a chain that runs
> before ufw's, so published ports are reachable regardless of what ufw says.
> Game ports are therefore deliberately absent from ufw — a rule that does
> nothing is worse than no rule, because it misleads. Ports open and close with
> the container (measured on Satisfactory: stopping it removed the iptables
> rules). To close a port, change the compose file, not ufw; to bind locally
> only, use the three-part form `127.0.0.1:8080:8080/tcp`.*

**Verwaltungsports gehören immer auf `127.0.0.1`.** RCON, Webkonsolen,
ServerQuery, Telnet — das sind Administrationszugänge mit Passwort und beliebte
Ziele. Necesse veröffentlichte seine Webkonsole auf `0.0.0.0:8080`; der Katalog
bindet sie deshalb lokal, ebenso bei sieben weiteren Spielen. Zugriff bei Bedarf
über einen SSH-Tunnel:

```bash
ssh -L 10011:127.0.0.1:10011 gameserver
```

> *Management ports always bind to 127.0.0.1: RCON, web consoles, ServerQuery
> and telnet are password-protected admin interfaces and popular targets. Necesse
> published its web console on 0.0.0.0:8080; the catalogue binds it locally, as
> for seven other games. Reach them through an SSH tunnel.*

---

## ufw

```
Default: deny (incoming), allow (outgoing), deny (routed)

Anywhere on tailscale0   ALLOW IN  Anywhere          # Notzugang und Sicherungen
22/tcp                   ALLOW IN  <ADMIN_IP>        # SSH nur von zuhause
80/tcp                   ALLOW IN  Anywhere          # Caddy: Zertifikat
443/tcp                  ALLOW IN  Anywhere          # Panel
```

**Port 80 muss offen bleiben**, auch wenn dort nichts Nützliches steht: Caddy
erneuert das Zertifikat über HTTP-01, und Let's Encrypt ruft dafür
`http://<name>/.well-known/…` auf. Zu ist Port 80 nur so lange unauffällig, bis
das Zertifikat in 60 Tagen abläuft.

**SSH nur aus einem Netz** setzt eine feste Adresse zuhause voraus. Wer keine
hat, öffnet 22 für alle — der Schutz liegt dann allein bei der
Schlüsselanmeldung (Passwörter sind ohnehin aus) und bei fail2ban. Als
Rückfallebene bleibt in beiden Fällen das Tailnet.

> *Port 80 must stay open even though nothing useful is served there: Caddy
> renews via HTTP-01. A closed port 80 stays unnoticed exactly until the
> certificate expires 60 days later. Restricting SSH to one network assumes a
> static address at home; without one, open 22 and rely on key-only auth plus
> fail2ban. Either way Tailscale remains the fallback.*

---

## fail2ban

```
ignoreip = 127.0.0.1/8 ::1 <ADMIN_NETZ> 100.64.0.0/10
findtime = 3600      maxretry = 3      bantime = 48h
banaction = ufw
[sshd] backend = systemd
```

`100.64.0.0/10` ist der Adressbereich von Tailscale — der Notzugang darf sich
nicht selbst aussperren.

Bewusst **ohne** die Mail- und FTP-Jails (die Dienste gibt es hier nicht) und
ohne Meldeaktion an AbuseIPDB (bräuchte einen weiteren API-Schlüssel).

> *`100.64.0.0/10` is Tailscale's range — the emergency access must not lock
> itself out. Mail/FTP jails are omitted (no such services here) as is the
> AbuseIPDB reporting action (needs another API key).*

---

## Caddy

Einziger nach außen offener Webdienst. Holt und erneuert das Zertifikat selbst.

**Nur HTTP/1.1.** Das Webterminal braucht einen echten WebSocket-Upgrade; über
HTTP/2 antwortete Caddy darauf mit `404`, und der Browser meldete
`websocket connection closed with code: 1006`. Über HTTP/1.1 kommt sauber
`101 Switching Protocols`. Für ein Panel mit zwei Benutzern ist der Verzicht auf
h2/h3 belanglos.

Zwei Kopfzeilensätze, weil die Anforderungen auseinandergehen:

| | Panel | Terminal |
|---|---|---|
| `default-src` | `'none'` | `'self'` |
| Skripte | keine | `'self' 'unsafe-inline' 'unsafe-eval'` |
| WebSocket | — | `connect-src wss://<panel>` |
| Zwischenspeicher | `no-store, no-cache` | `no-store` |

Die strenge Richtlinie des Panels (`default-src 'none'`) würde `ttyd` vollständig
blockieren — ein Terminal braucht JavaScript und WebSockets. Umgekehrt darf das
Panel diese Lockerung nicht bekommen: Es zeigt Zugangsdaten an.

**CSP-Schlüsselwörter müssen einfach gequotet sein.** Ohne die Anführungszeichen
liest der Browser `'self'` und `'none'` als **Hostnamen**. Am 2026-09-06
blockierte `form-action` dadurch das Anmeldeformular, und im Protokoll kam nicht
einmal ein `POST` an.

> *Caddy is the only externally reachable web service. HTTP/1.1 only: the
> terminal needs a real WebSocket upgrade, and over HTTP/2 Caddy answered 404
> ("code: 1006" in the browser) while HTTP/1.1 yields a clean 101. Two header
> sets, because the panel's strict `default-src 'none'` would block ttyd
> entirely, and the panel must not get the terminal's relaxations since it
> displays credentials. CSP keywords must be single-quoted — unquoted, the
> browser reads `'self'` as a hostname, which once blocked the login form with no
> POST reaching the log at all.*

### Das Terminal hängt an der Panel-Sitzung

`ttyd` hat **keine eigene Anmeldung**. Caddy fragt vor jedem Aufruf beim Panel
nach (`forward_auth` auf `/auth-check`): nur eine gültige Admin-Sitzung bekommt
`204`, alles andere `401`.

Dabei müssen die Upgrade-Kopfzeilen **aus der Auth-Anfrage entfernt** werden.
Sonst sieht uvicorn einen WebSocket-Versuch auf einer normalen HTTP-Route und
antwortet `403` — der Handshake scheiterte, obwohl die Sitzung gültig war.

```
header_up -Upgrade
header_up -Connection
header_up -Sec-Websocket-Key
header_up -Sec-Websocket-Version
header_up -Sec-Websocket-Protocol
header_up -Sec-Websocket-Extensions
```

> *ttyd has no authentication of its own; Caddy asks the panel before every
> request. The upgrade headers must be stripped from that auth request, or
> uvicorn sees a WebSocket attempt on a plain HTTP route and answers 403 — the
> handshake failed even with a valid session.*

---

## DNS bei Cloudflare

Ein CNAME je Spiel auf **einen einzigen A-Eintrag**:

```
enshrouded.<zone>  CNAME  gs.<zone>     (dns-only)
palworld.<zone>    CNAME  gs.<zone>     (dns-only)
gs.<zone>          A      <SERVER_IPV4>
```

Zieht der Server um, ist genau **ein** Eintrag zu ändern.

### Feste oder wechselnde Adresse

`SERVER_IPV4` in `konfiguration.env` entscheidet, wer den A-Eintrag pflegt:

| Wert | Wer pflegt `DNS_ZIEL` | `dns-ziel.timer` |
|---|---|---|
| `203.0.113.10` (eine IPv4) | ein Mensch, von Hand | aus |
| `dynamic` | der Server selbst, alle 5 Minuten | an |

Bei `dynamic` misst `dns-pflegen ziel-setzen` die öffentliche IPv4 und schreibt sie
in den A-Eintrag. Die Spiel-CNAMEs zeigen weiterhin auf diesen einen Namen und
folgen deshalb von allein — **kein CNAME wird angefasst**. Der A-Eintrag wird
mit TTL 60 ausgeliefert, damit die Welt nach einem Adresswechsel schnell folgt;
die CNAMEs behalten ihre 300 Sekunden, weil sie sich nie ändern.

**Das Zertifikat des Panels hängt mit daran.** Caddy erneuert es über ACME, und
dazu muss `PANEL_DOMAIN` öffentlich auf den Server zeigen. Am einfachsten ist
ein CNAME auf `DNS_ZIEL` — dann folgt er ohne weiteres Zutun. Steht
`PANEL_DOMAIN` als eigener A-Eintrag **innerhalb** von `DNS_ZONE`, zieht
`ziel-setzen` ihn mit nach und lässt dabei ein gesetztes `proxied` in Ruhe: das
Panel spricht HTTPS und darf hinter dem Cloudflare-Proxy stehen. Liegt der Name
außerhalb der Zone, bleibt er Handarbeit; `ziel-setzen` sagt das dann auch.

### Anlegen und Nachführen sind zweierlei

`dns-pflegen` trennt beides bewusst:

| Befehl | Legt an | Ändert | Wer ruft ihn |
|---|---|---|---|
| `grundgeruest` | ja, nur was fehlt | **nie** | Stufe 25, einmal bei der Einrichtung |
| `ziel-setzen` | nur `DNS_ZIEL` bei `dynamic` | ja | `dns-ziel.timer`, alle 5 Minuten |

Der Zeitgeber läuft unbeaufsichtigt und darf deshalb keine Namen erfinden —
`grundgeruest` läuft genau einmal, auf ausdrücklichen Anstoß, und schreibt
niemals einen bestehenden Eintrag um. Damit ist von Hand nur noch die Zone
selbst anzulegen und der Token zu hinterlegen.

> *Creating and updating are deliberately separate: `grundgeruest` creates only
> what is missing and never rewrites an existing record; `ziel-setzen` updates
> and belongs to the unattended timer, which must not invent names.*

### Einen weiteren Anbieter schreiben

Umgesetzt sind `cloudflare` (im Betrieb) und `hetzner` (nach Dokumentation,
gegen eine nachgebildete API geprüft, **noch nicht gegen eine echte Zone**).
Beide sitzen in `bin/dns-pflegen`, und sie sind absichtlich gegensätzlich —
Cloudflare mit vollständigen Namen und einem Proxy, Hetzner mit relativen Namen
und ohne. Wer einen dritten schreibt, findet in einem der beiden schon den
passenden Fall.

**Ein Anbieter kann fünf Dinge und entscheidet nichts.** Ob ein Eintrag angelegt,
geändert oder in Ruhe gelassen wird, steht einmal darüber und für alle — siehe
[E24](10-entscheidungen.md). Wer das in der Klasse noch einmal entscheidet, baut
die zweite Auslegung derselben Sicherheitsregel, und beide „funktionieren".

#### 1. Die Klasse

```python
class MeinAnbieter(Anbieter):
    name = "meinanbieter"        # so heißt er in ANBIETER= der Konfigdatei
    kennt_proxy = False          # True nur, wenn es einen HTTP-Proxy davor gibt
    API = "https://api.example.net/v1"

    def zone_id(self)                 -> str
    def saetze(self, zid, name=None)  -> list[satz]
    def anlegen(self, zid, satz)
    def aendern(self, zid, kennung, satz)
    def loeschen(self, zid, kennung)
```

Ein `satz` ist **immer** dieselbe Form, in beide Richtungen:

```python
{"kennung": "abc123",              # was der Anbieter zum Ändern/Löschen braucht
 "typ":     "A" | "CNAME",
 "name":    "spiel.beispiel.de",   # VOLLSTÄNDIG, ohne Punkt am Ende
 "wert":    "203.0.113.10",        # ohne Punkt am Ende
 "ttl":     300,
 "proxy":   False}
```

Alles, was die API anders macht, wird in der Klasse übersetzt — `_satz()` beim
Lesen, `_nutzlast()` beim Schreiben. `Hetzner` zeigt beides.

#### 2. Eintragen

```python
ANBIETER = {"cloudflare": Cloudflare, "hetzner": Hetzner, "meinanbieter": MeinAnbieter}
```

Mehr nicht. Kein Aufrufer ändert sich, keine Stufe, keine systemd-Einheit.

#### 3. Worauf zu achten ist

| Fallstrick | Was passiert, wenn man ihn übersieht |
|---|---|
| **Relative Namen** | Viele APIs führen `spiel` statt `spiel.zone.de`, den Zonenkopf als `@`. Nach außen müssen es volle Namen sein, sonst vergleichen die Regeln Äpfel mit Birnen. |
| **Punkt am Ende** | `ziel.zone.de.` und `ziel.zone.de` sind für die Regeln zwei verschiedene Werte — der Abgleich schlägt dann bei jedem Lauf an, und `setzen` schreibt jedes Mal neu. |
| **CNAME ohne Punkt** | Manche APIs hängen die Zone dann ein zweites Mal an: `ziel.zone.de.zone.de`. |
| **Fehler als leere Liste** | Der schlimmste. Wer bei einem API-Fehler `[]` zurückgibt, sagt „gibt es nicht" — und `grundgeruest` legt daraufhin alles **noch einmal** an. Ein Fehler muss abbrechen. |
| **Antwort, die kein JSON ist** | Ein Proxy davor schickt HTML, ein Fehlerleib zerfällt zu `null`. Dafür gibt es `lies_json()`; ohne sie steigt die Fehlerbehandlung selbst mit einem Traceback aus. |
| **Blättern** | Eine Zone mit mehr Einträgen als einer Seite wird sonst still unvollständig gelesen — und „nicht gefunden" heißt hier „wird noch einmal angelegt". |
| **`kennt_proxy`** | Bei `False` entfällt die Proxy-Prüfung; `pruefen` meldet dann „kennt keinen Proxy" und endet mit 0. |

#### 4. Prüfen, bevor sich jemand darauf verlässt

Gegen eine **echte** Zone, in dieser Reihenfolge:

```bash
dns-pflegen anbieter          # richtiger Anbieter, richtige Datei?
dns-pflegen grundgeruest      # legt an, was fehlt
dns-pflegen grundgeruest      # zweiter Lauf darf NICHTS ändern
dns-pflegen setzen testspiel
dns-pflegen setzen testspiel  # "steht bereits richtig"
dns-pflegen liste
dns-pflegen entfernen testspiel
```

Dazu zwei Fälle, die schiefgehen **müssen**: ein Eintrag, der woandershin zeigt,
darf sich weder von `grundgeruest` überschreiben noch von `entfernen` löschen
lassen. Und ein falsches Token muss eine Meldung ergeben, keine leere Liste.

> *Writing another provider: a provider does five things and decides nothing —
> whether a record is created, changed or left alone is written once, above, for
> all of them (E24). Records travel in one normalised shape in both directions;
> everything the API does differently is translated inside the class. The
> pitfalls are relative names, trailing dots, errors passed off as empty lists,
> non-JSON bodies and pagination. Verify against a real zone with the sequence
> above, including the two cases that must fail.*

#### Die Abnahme als ein Befehl

Die Reihenfolge oben von Hand durchzugehen sind neun Schritte, von denen
**zwei fehlschlagen müssen** — und ein Schritt, der nicht fehlschlägt obwohl er
soll, fällt beim Ablesen nicht auf. Deshalb steht sie als Programm da:

```bash
werkzeuge/dns-abnahme.sh --selbsttest          # ohne Zone, ohne Netz
werkzeuge/dns-abnahme.sh --anbieter hetzner --zone beispiel.de \
                         --ip 203.0.113.10 --token-datei ~/.hetzner-token
```

Es installiert nichts. Aus `bin/dns-pflegen` entsteht in einem temporären
Verzeichnis eine Wegwerf-Fassung mit den Werten des Laufs; `/etc/dns-gameserver.conf`
wird **nicht** angefasst. Jeder Eintrag, den der Lauf anlegt, trägt einen
zufälligen Präfix `abnahme-<8 hex>-…`, kann also keinen vorhandenen treffen, und
wird am Ende wieder entfernt — auch wenn ein Schritt scheitert.

Zwei Dinge, die es bewusst **nicht** tut:

* **Den Token in `argv` nehmen.** Argumente stehen für jeden Benutzer der
  Maschine in der Prozessliste. Der Token kommt aus einer Datei oder aus
  `DNS_ABNAHME_TOKEN` und wird nirgends ausgegeben.
* **Die beiden A-Einträge löschen**, die `grundgeruest` anlegt. `dns-pflegen`
  kennt dafür keinen Befehl, weil es A-Einträge grundsätzlich nicht löscht
  (E21). Das Skript nennt sie am Ende beim Namen, damit sie nicht liegen
  bleiben.

Den „fremden Eintrag", der sich nicht löschen lassen darf, erzeugt es ohne eine
einzige anbieterspezifische Zeile: Es rendert eine **zweite** Fassung mit einem
anderen `DNS_ZIEL`. Aus deren Sicht zeigt derselbe CNAME woandershin — und genau
das ist der Fall, den `entfernen` verweigern muss.

> *Running the sequence by hand is nine steps, two of which must fail — and a
> step that fails to fail is not noticed when read off a screen, so it is a
> program instead. It installs nothing: a throwaway rendering of `dns-pflegen`
> in a temp directory, never touching `/etc/dns-gameserver.conf`. Every record
> it creates carries a random `abnahme-<8 hex>` prefix, so it cannot collide
> with a real one, and is removed afterwards even when a step fails. It
> deliberately does not take the token in `argv` (arguments are world-readable
> in the process list) and does not delete the two A records `grundgeruest`
> creates — `dns-pflegen` never deletes A records (E21) — but names them at the
> end. The "foreign record" that must refuse deletion is produced without a
> single provider-specific line: a second rendering with a different `DNS_ZIEL`,
> from whose point of view the same CNAME points elsewhere.*

---

**Ein DNS-Name in `SERVER_IPV4` ergibt nichts** — auch kein DDNS-Name. Aus
diesem Wert entsteht kein Eintrag; die Adresse trägt allein `DNS_ZIEL`. Bis
dahin wurde ein Name dort klaglos angenommen und wirkte nirgends. Heute bricht
`install/lib.sh` mit einer Meldung ab, die auf `dynamic` verweist.

> *`SERVER_IPV4` decides who maintains the A record: a fixed address means a
> human does it and the timer stays off; `dynamic` means the server measures its
> own public IPv4 every five minutes and writes the record itself. The game
> CNAMEs point at that one name and follow along — none of them is touched. The
> A record is served with TTL 60 so the world follows quickly after a change,
> while the CNAMEs keep 300 s because they never move. The panel certificate
> depends on this too: ACME needs `PANEL_DOMAIN` to resolve publicly. A CNAME to
> `DNS_ZIEL` is simplest; an A record inside the zone is carried along (an
> existing `proxied` flag is left alone, since the panel speaks HTTPS and may sit
> behind the proxy); outside the zone it stays manual. A hostname in
> `SERVER_IPV4` achieves nothing — no record is derived from it — and setup now
> aborts instead of accepting it silently.*

### Drei Fallen

**1. Nie per `dig` prüfen, ob ein Eintrag existiert.** Steht in der Zone ein
Wildcard `*.<zone>`, beantwortet er **jeden** erfundenen Namen — und zeigt dabei
auf den falschen Server. Eine Prüfung per Namensauflösung meldet deshalb immer
„vorhanden". `dns-pflegen` fragt ausschließlich die API.

**2. Spielserver dürfen nicht `proxied` sein.** Cloudflares Proxy kann nur HTTP
und HTTPS; ein Spielport dahinter ist von außen tot. Deshalb überall
`proxied: false`, mit Gegenprobe nach dem Schreiben und einem eigenen Befehl
`dns-pflegen pruefen`, der falsch gesetzte Einträge meldet.

**3. Die eigene Adresse nie aus einer einzelnen Quelle nehmen.** Sie wird
ungeprüft in einen Eintrag geschrieben, an dem jeder Spielserver und das
Zertifikat des Panels hängen. Eine Auskunftsstelle, die ausfällt, umgeleitet
wird oder Unsinn liefert, nimmt dann alles auf einmal mit. `dns-pflegen` befragt drei
unabhängige Stellen und schreibt erst, wenn **zwei dieselbe Antwort geben** —
derselbe Gedanke wie der Kontrollwert beim Messen. Zwei Antworten werden
außerdem grundsätzlich verworfen: alles aus `100.64.0.0/10` (Provider-NAT oder
Tailscale) und jede nicht öffentliche Adresse. Und die Messung läuft
**erzwungen über IPv4**: über IPv6 antworten diese Stellen mit der IPv6-Adresse,
die in einem A-Eintrag nichts zu suchen hat.

> *Three traps: never use `dig` to test whether a record exists — a wildcard in
> the zone answers every made-up name, pointing at the wrong server, so a lookup
> always reports "present". `dns-pflegen` asks the API only. Game records must never
> be proxied: Cloudflare's proxy speaks HTTP(S) only, so a game port behind it is
> dead from outside. Hence `proxied: false` everywhere, verified after writing,
> with `dns-pflegen pruefen` to report stragglers. And one's own address never comes
> from a single source: it is written unchecked into the record every game server
> and the panel certificate hang on, so three independent services are asked and
> two must agree. Anything from `100.64.0.0/10` (carrier NAT or Tailscale) and
> any non-public address is discarded, and the measurement is forced over IPv4 —
> over IPv6 these services answer with the IPv6 address, which has no place in an
> A record.*

### Anbieter und Token

`/etc/dns-gameserver.conf`, `0600 root`:

```
ANBIETER=cloudflare
TOKEN=<token>
```

Beides steht in **einer** Datei, weil es zusammengehört: ein Token hat immer
genau die Form, die ein bestimmter Anbieter versteht. Fehlt `ANBIETER`, ist es
`cloudflare` — der einzige Anbieter, den es gab, als die Angabe noch nicht
existierte. Die ältere `/etc/cloudflare-gameserver.conf` mit `CF_TOKEN=` wird
weiter gelesen, damit vorhandene Installationen nicht stehenbleiben.

> *Both live in one file because they belong together: a token always has the
> shape exactly one provider understands. A missing `ANBIETER` means cloudflare,
> the only provider that existed before the setting did. The older file is still
> read so existing installs keep working.*

Berechtigung: **Zone / DNS / Bearbeiten**, Zonenressource **nur die eigene
Zone**. Nie der globale API-Schlüssel — der darf alles im Konto, auch Zonen
löschen und Abrechnungsdaten lesen.

`dns-pflegen` erzwingt außerdem IPv4 (überschreibt `socket.getaddrinfo`): Der Zugriff
über IPv6 schlug in dieser Umgebung fehl, und der Fehler sah aus wie ein
Token-Problem.

> *The token needs Zone / DNS / Edit on your own zone only — never the global API
> key, which can do anything in the account. `dns-pflegen` also forces IPv4 by
> overriding `socket.getaddrinfo`: IPv6 access failed here in a way that looked
> like a token problem.*

---

## Tailscale

Zweiter Weg auf die Maschine und der Transportweg der Sicherungen. `ufw` erlaubt
auf `tailscale0` alles.

Zwei Gründe:

* **Notzugang.** Sperrt eine ufw-Regel oder ein fail2ban-Bann den SSH-Zugang aus,
  bleibt das Tailnet.
* **Sicherung ohne offenen Port.** Der Sicherungsserver braucht keinen Port im
  Internet; Borg spricht über das private Netz.

> *Tailscale provides a second route to the machine and carries the backups: it
> is the way back in if a ufw rule or a fail2ban ban locks SSH out, and it lets
> the backup host stay off the public internet entirely.*
