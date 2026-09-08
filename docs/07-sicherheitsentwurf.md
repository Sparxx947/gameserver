# 07 — Sicherheitsentwurf

Nicht „was ist eingeschaltet", sondern **wo die Grenzen verlaufen und warum**.

> *Not a list of enabled features but a description of where the boundaries run
> and why.*

---

## Die eine Grenze, auf die es ankommt

Die Weboberfläche ist über das Internet erreichbar und kann Container starten,
Passwörter ändern und Sicherungen zurückspielen. Sie ist damit das lohnendste
Ziel auf der Maschine. Der ganze Entwurf dreht sich um eine Frage: **Was passiert,
wenn jemand die Kontrolle über den Prozess `panel` bekommt?**

Antwort: Er kann genau das, was `panel-aktion` erlaubt — und nichts sonst.

```
Benutzer panel   ── kein Docker-Socket
                 ── keine Shell
                 ── kein Schreibrecht auf den eigenen Code
                 ── keine Leserechte auf /root
                 │
                 └── sudo -n /usr/local/bin/panel-aktion   ← einzige Erweiterung
                       │
                       └── 14 fest verdrahtete Zweige,
                           jeder Parameter gegen Positivlisten
```

> *The one boundary that matters: the panel is internet-facing and can start
> containers, change passwords and restore backups, making it the most valuable
> target on the machine. The whole design answers one question — what can someone
> do who takes over the `panel` process? Exactly what `panel-aktion` permits, and
> nothing else.*

### Warum kein Docker-Socket

Die naheliegende Umsetzung wäre, `panel` in die Gruppe `docker` zu stecken. Das
ist **gleichbedeutend mit root**:

```bash
docker run -v /:/host -it alpine chroot /host sh
```

Ein Einzeiler, und der Angreifer ist root auf der Maschine. Deshalb: kein
Socket, keine Gruppe, sondern eine Brücke, die genau die gewünschten Operationen
kennt.

> *The obvious approach — putting `panel` in the `docker` group — is equivalent
> to granting root: one line with `-v /:/host` and a chroot gets you there. Hence
> a bridge that knows only the intended operations.*

### Was `panel-aktion` prüft

| Eingabe | Prüfung |
|---|---|
| Stack-Name | `^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$` **und** muss in `/opt/stacks/` existieren |
| Archivname | `^[a-z0-9-]{1,40}-[0-9]{8}-[0-9]{6}$` **und** muss mit dem Stack beginnen |
| Konfigurationsfeld | Positivliste von 11 Feldnamen plus `mem_limit` |
| Katalogschlüssel | muss im Katalog stehen |
| DNS-Aktion | nur `setzen`, `entfernen`, `liste`, `pruefen` |

Kein `eval`, keine Shell-Expansion von Eingaben, kein Pfad, über den eigene
Befehle einzuschleusen wären.

**Die Feldliste ist der Kern.** Die compose-Datei als Ganzes freizugeben wäre
eine Rechteausweitung: Wer dort ein Volume `/:/host` eintragen kann, ist root.
Deshalb dürfen nur einzelne, benannte Felder geändert werden.

> *What `panel-aktion` validates is listed above. No eval, no shell expansion of
> inputs, no path to inject commands. The field allow-list is the crux: exposing
> the compose file as a whole would be a privilege escalation, since a `/:/host`
> volume means root.*

Eine Feinheit aus dem Betrieb: Die Prüfung nutzt einen Here-String, **keine
Pipe**. `grep -q` beendet sich beim ersten Treffer, die schreibende Seite bekommt
`SIGPIPE` (141), und mit `set -o pipefail` gilt die Pipeline als gescheitert —
jeder **gültige** Stack wäre abgewiesen worden.

> *A detail from operations: the check uses a here-string, not a pipe. `grep -q`
> exits on first match, the writer gets SIGPIPE, and with `pipefail` the pipeline
> counts as failed — every valid stack would have been rejected.*

---

## Anmeldung

| | |
|---|---|
| Faktor 1 | Passwort, Argon2id |
| Faktor 2 | TOTP, verpflichtend, nicht abschaltbar |
| Sitzung | 8 h, signiertes Cookie, `HttpOnly` `Secure` `SameSite=strict` |
| CSRF | eigenes Token je Sitzung, bei jedem Schreibzugriff mit `hmac.compare_digest` |
| Sperre | 5 Fehlversuche je IP → 15 min |

**Drei Entscheidungen, die leicht anders ausgefallen wären:**

1. **Die Rolle kommt aus der Datei, nicht aus dem Cookie.** Sonst behielte ein
   herabgestufter Benutzer seine Rechte bis zu acht Stunden.
2. **Das Einrichtungs-Token hat einen eigenen Salt**, nicht bloß eine kürzere
   Laufzeit. Ein Token für die MFA-Einrichtung darf niemals als Sitzungscookie
   durchgehen.
3. **Das TOTP-Geheimnis sieht niemand** — auch der Administrator nicht, der ein
   Konto anlegt. Der Benutzer bekommt es bei der ersten Anmeldung selbst als
   QR-Code. So wandert es nie durch einen Chat, eine Mail oder ein Protokoll.

> *Three decisions that could easily have gone the other way: the role is read
> from disk rather than the cookie (a demoted user would otherwise keep rights
> for eight hours); the enrolment token has its own salt rather than merely a
> shorter lifetime (it must never pass as a session cookie); and nobody sees the
> TOTP secret, not even the administrator creating the account — the user gets it
> as a QR code on first login, so it never travels through a chat, a mail or a
> log.*

---

## Das Webterminal

Ein Terminal im Browser ist die größte Angriffsfläche im ganzen Aufbau. Drei
Schranken davor:

1. **Nur über Caddy erreichbar** — `ttyd` bindet auf `127.0.0.1:7681`.
2. **Caddy fragt beim Panel nach.** `forward_auth` auf `/auth-check`: nur eine
   gültige **Admin**-Sitzung bekommt `204`.
3. **Es läuft als der Mensch, nicht als root.** Für privilegierte Befehle
   verlangt `sudo` erneut das Passwort — eine zweite Hürde, falls jemand eine
   offene Browsersitzung übernimmt.

> *A browser terminal is the largest attack surface here, so three barriers: it
> binds to localhost only; Caddy checks the panel session before every request
> and requires the admin role; and it runs as the human rather than root, so sudo
> asks for the password again if an open browser session is hijacked.*

---

## Härtung des Panel-Dienstes — und ihre Grenze

```ini
NoNewPrivileges=no
PrivateTmp=yes
ProtectSystem=full
```

Das sieht dünn aus und ist eine bewusste Entscheidung mit Messhintergrund:

* **`NoNewPrivileges` muss aus bleiben.** Mit gesetztem Flag kann `sudo` nicht
  mehr nach root wechseln („The 'no new privileges' flag is set"). Die App zeigte
  davon **nichts** — die Übersicht blieb einfach leer.
* **Achtung, implizite Setzung:** `LockPersonality`, `ProtectKernelTunables` und
  `ProtectControlGroups` setzen `NoNewPrivileges` laut systemd-Dokumentation
  mit. Sie dürfen hier deshalb nicht stehen.
* **`ProtectSystem=full`, nicht `strict`.** `strict` macht das *gesamte*
  Dateisystem schreibgeschützt; dann kann Borg seinen Cache nicht anlegen, und
  die Archivliste blieb leer.
* **Kein `ProtectHome`.** `panel-aktion` liest `/root/.borg-passphrase`. Der
  Schutz kommt hier aus den Dateirechten (`0600 root`), nicht aus dem
  Namensraum — der Benutzer `panel` käme ohnehin nicht heran.

Die Lehre daraus ist allgemeiner: **Härtungsoptionen, die man nicht prüft,
härten nicht, sondern brechen leise.** Alle vier Fälle äußerten sich als
funktionierende Oberfläche mit leeren Listen, nicht als Fehlermeldung.

> *The service hardening looks thin, and that is measured rather than lazy:
> `NoNewPrivileges` must stay off or sudo cannot reach root — and three other
> options set it implicitly; `ProtectSystem=strict` stops Borg from writing its
> cache; `ProtectHome` would block reading the backup passphrase, which is
> protected by file mode instead. The general lesson: unverified hardening does
> not harden, it breaks quietly — all four cases presented as a working UI with
> empty lists, never as an error.*

---

## Die Sicherheitsrichtlinie im Browser

```
default-src 'none'; style-src 'unsafe-inline'; img-src 'self';
form-action 'self'; base-uri 'none'; frame-ancestors 'none'
```

`default-src 'none'` heißt: **keine** externen Ressourcen, **kein** JavaScript,
keine Schriften, keine `data:`-URIs. Deshalb ist die Oberfläche serverseitig
gerendert und die Symbole liegen als echte Dateien vor — ein Favicon als
`data:`-URI würde blockiert.

`Cache-Control: no-store, no-cache` auf allen Panel-Antworten: Die Seite zeigt
Zugangsdaten, und ein zwischengespeicherter Stand hält auch alte
Sicherheitskopfzeilen am Leben.

> *`default-src 'none'` means no external resources, no JavaScript, no fonts and
> no `data:` URIs — hence server-side rendering and icons as real files. All
> panel responses are `no-store`: the page shows credentials, and a cached copy
> keeps stale security headers alive too.*

---

## Passwörter im Klartext

Die Beitritts- und Adminpasswörter stehen im Klartext in den compose-Dateien.
Das ist unschön und **unvermeidlich**: Die Spielserver verlangen sie so.

Der Schutz liegt deshalb bei den Dateirechten — `0600 root:root` — und bei der
Brücke: Die Oberfläche zeigt sie an, indem `panel-aktion` sie als root liest,
nicht indem der Benutzer `panel` Lesezugriff bekäme.

Passwörter werden **je Server** gewürfelt, nie geteilt, und ohne verwechselbare
Zeichen (`0/O`, `1/l/I`) und ohne Sonderzeichen: Sie werden vorgelesen und
abgetippt, und manche Spiele filtern Sonderzeichen still weg.

> *Join and admin passwords sit in cleartext in the compose files because the
> game servers require it. Protection comes from file mode (0600 root) and from
> the bridge — the panel displays them by having `panel-aktion` read them as
> root, not by granting the `panel` user access. Passwords are per server, never
> shared, and avoid look-alike characters and punctuation: they get read aloud
> and typed by hand, and some games silently strip special characters.*

---

## Wann ein Server nach außen offen ist

Ein Spielserver ist genau in dem Moment erreichbar, in dem sein Port in der
`compose.yaml` steht und der Container damit läuft. Dieser Schritt — nicht die
Installation, nicht der erste Start — ist die Grenze nach außen.

Deshalb steht er am **Ende** der Einrichtung. 17 Katalogspiele nennen ihren Port
erst in der Konfiguration, die ihr erster Start schreibt; `port-ermitteln` trägt
ihn nach, aber nur, wenn `einrichtung_offen` nicht mehr gesetzt ist — also das
Beitrittspasswort steht oder die Suche danach endgültig aufgegeben und laut
gemeldet wurde.

Das Gate hängt bewusst am **Ergebnis der Einrichtung**, nicht am
Konfigurationsformat. Ein Format, das niemand kennt, führt dann zu einem Server
ohne Port und mit sichtbarer Meldung — nicht zu einem offenen Server ohne
Passwort. Am 08.09. war beides gleichzeitig zu sehen: ET: Legacy stand auf
`27960/udp` offen im Netz, während die Einrichtung sein `set g_password ""`
mangels Unterstützung für den id-Tech-Stil gar nicht gefunden hatte.

Es gibt genau **einen** Weg, der einen Port veröffentlicht. `port-ermitteln`
einzeln aufgerufen übergibt per `execv` an `spiel-einrichtung`, statt selbst zu
handeln — sonst hätte der Knopf im Panel eine zweite Reihenfolge, und zwei
Reihenfolgen werden früher oder später verschieden.

> *A game server becomes reachable the moment its port lands in the compose file,
> so that step sits at the very end of setup and only runs once setup has settled.
> The gate keys off the setup result rather than the config format, so an unknown
> format yields a server with no port and a visible warning instead of an open
> server with no password. Exactly one code path publishes ports; the standalone
> tool hands over via `execv`.*

---

## Was dieser Aufbau **nicht** leistet

Ehrlichkeitshalber:

* **Keine Ausbruchssicherheit der Container.** Die Spielserver laufen als
  normale Docker-Container ohne zusätzliche Profile. Eine Lücke im Spielserver,
  die aus dem Container ausbricht, trifft die Maschine.
* **Keine Prüfung der Images.** `ghcr.io/ich777/steamcmd` und die anderen Bilder
  werden als vertrauenswürdig angenommen. Sie sind es vermutlich; geprüft ist es
  nicht.
* **Kein Schutz gegen den Administrator.** Wer das Panel-Konto hat, hat über das
  Terminal die Maschine.
* **Keine Überwachung der veröffentlichten Ports.** Ein Container, der einen Port
  auf `0.0.0.0` legt, den niemand erwartet hat, fällt derzeit nur bei einer
  Handprüfung auf. Eine Prüfung gegen eine Freigabeliste wäre der nächste
  sinnvolle Schritt.
* **Keine Zwei-Personen-Regel.** Löschen, Wiederherstellen und Neustart hängen an
  einer Rückfrage, nicht an einer zweiten Zustimmung.

> *What this design does not provide, stated plainly: no container escape
> hardening (a game-server vulnerability that escapes hits the host); no image
> verification (the images are assumed trustworthy, not verified); no protection
> against the administrator (panel account plus terminal equals the machine); no
> monitoring of published ports (a container binding an unexpected 0.0.0.0 port
> is currently caught only by hand — a check against an allow-list would be the
> next sensible step); and no four-eyes rule (destructive actions are gated by a
> confirmation, not a second approval).*
