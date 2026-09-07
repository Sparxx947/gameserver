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

### Zwei Fallen

**1. Nie per `dig` prüfen, ob ein Eintrag existiert.** Steht in der Zone ein
Wildcard `*.<zone>`, beantwortet er **jeden** erfundenen Namen — und zeigt dabei
auf den falschen Server. Eine Prüfung per Namensauflösung meldet deshalb immer
„vorhanden". `cf-dns` fragt ausschließlich die API.

**2. Spielserver dürfen nicht `proxied` sein.** Cloudflares Proxy kann nur HTTP
und HTTPS; ein Spielport dahinter ist von außen tot. Deshalb überall
`proxied: false`, mit Gegenprobe nach dem Schreiben und einem eigenen Befehl
`cf-dns pruefen`, der falsch gesetzte Einträge meldet.

> *Two traps: never use `dig` to test whether a record exists — a wildcard in the
> zone answers every made-up name, pointing at the wrong server, so a lookup
> always reports "present". `cf-dns` asks the API only. And game records must
> never be proxied: Cloudflare's proxy speaks HTTP(S) only, so a game port behind
> it is dead from outside. Hence `proxied: false` everywhere, verified after
> writing, with `cf-dns pruefen` to report stragglers.*

### Der Token

`/etc/cloudflare-gameserver.conf`, `0600 root`:

```
CF_TOKEN=<token>
```

Berechtigung: **Zone / DNS / Bearbeiten**, Zonenressource **nur die eigene
Zone**. Nie der globale API-Schlüssel — der darf alles im Konto, auch Zonen
löschen und Abrechnungsdaten lesen.

`cf-dns` erzwingt außerdem IPv4 (überschreibt `socket.getaddrinfo`): Der Zugriff
über IPv6 schlug in dieser Umgebung fehl, und der Fehler sah aus wie ein
Token-Problem.

> *The token needs Zone / DNS / Edit on your own zone only — never the global API
> key, which can do anything in the account. `cf-dns` also forces IPv4 by
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
