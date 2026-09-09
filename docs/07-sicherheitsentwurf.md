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
| Faktor 2 | TOTP, ein **Passkey** oder ein Wiederherstellungscode — abschaltbar ist keiner |
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

## Wiederherstellungscodes

Zehn Einmalcodes, erzeugt in dem Moment, in dem der Benutzer seinen zweiten
Faktor bestätigt, **einmal** angezeigt, danach nur noch gehasht vorhanden. Sie
treten an die Stelle der sechs Ziffern — **nicht** an die des Passworts.

**Warum es sie braucht:** TOTP ist Pflicht. Wer sein Gerät verlor, kam bisher nur
über „ein Administrator setzt den zweiten Faktor zurück" wieder herein. Bei genau
einem Administrator ist das keine Wiederherstellung, sondern eine Aussperrung.

**Die Zahlen sind nicht geraten:**

| Vorgabe | Quelle | hier |
|---|---|---|
| ≥ 64 Bit Zufall | NIST SP 800-63B-4 §4.2.1.1 | **93,3 Bit** |
| gehasht speichern, unter 112 Bit gesalzenes Passwort-Hash-Verfahren | OWASP ASVS 5.0.0 V6.5.2 | Argon2id |
| Einmalgebrauch | NIST §3.1.2 | Code wird **entfernt**, nicht markiert |
| Rate-Limiting Pflicht | NIST §3.2.2 | 5 Fehlversuche je IP → 15 min (bestand schon) |

16 Zeichen aus dem Alphabet von E19 (57 Zeichen ohne `0/O` und `1/l/I`) ergeben
5,83 × 16 = 93,3 Bit. Angezeigt werden sie in Vierergruppen, weil sie ausgedruckt
und abgetippt werden.

**Vier Entscheidungen im Detail:**

1. **Erzeugt bei der Bestätigung, nicht beim Anlegen des Kontos.** So sieht der
   Benutzer sie selbst und der Administrator nie — dieselbe Überlegung wie beim
   TOTP-Geheimnis.
2. **Der verbrauchte Code wird gelöscht, nicht als benutzt markiert.** Ein
   Einmalcode, der noch in der Datei steht, wird früher oder später doch
   akzeptiert.
3. **Die Form entscheidet, welcher Weg geprüft wird.** Sechs Ziffern sind ein
   TOTP, 16 Zeichen ein Wiederherstellungscode. Sonst liefen bei jedem vertippten
   TOTP zehn Argon2-Prüfungen mit — rund eine Sekunde.
4. **Ein Zurücksetzen des zweiten Faktors entwertet die Codes.** Sie gehören zum
   alten Faktor; blieben sie liegen, wäre das Zurücksetzen keines.

Die Einlösung steht **im Protokoll**, mitsamt der Zahl der verbleibenden Codes:
Es ist der eine Weg hinein, der ohne den zweiten Faktor im üblichen Sinne
auskommt. Unter „Mein Konto" sieht jeder seinen Vorrat und kann neue erzeugen;
die Benutzerliste zeigt ihn für alle, damit ein leerer Vorrat auffällt, bevor
jemand davorsteht.

> *Ten single-use codes, generated when the user confirms their second factor,
> shown once, stored hashed. 16 characters from the 57-character look-alike-free
> alphabet is 93.3 bits — above NIST's 64-bit minimum, below the ASVS 112-bit
> threshold, hence Argon2id. The redeemed code is deleted rather than flagged; a
> reset of the second factor invalidates the codes; and the input shape decides
> which path is checked, so Argon2 does not run on every mistyped TOTP.*

---

## Warum nicht E-Mail-Codes

Naheliegend wäre, den zweiten Faktor per Mail zu schicken. **NIST SP 800-63B-4
§3.1.3.1 verbietet das ausdrücklich:** „Email **SHALL NOT** be used for
out-of-band authentication" — abfangbar unterwegs und auf Zwischenservern,
umleitbar per DNS-Spoofing, und oft schon mit dem Passwort allein erreichbar.

Das PCI SSC nennt den Kern: Wer sein Mailkonto mit demselben Passwort öffnet, für
den sind die beiden Faktoren nicht unabhängig — es ist „a usage of *something you
know* twice". Die EBA lässt Mail-Codes nur gelten, wenn das Postfach ausschließlich
über ein registriertes Gerät erreichbar ist; ENISA und CISA führen sie als
„letzten Ausweg".

Praktisch kommt hinzu: Die Maschine hat keinen Mailversand.

> *Email as a second factor is explicitly forbidden by NIST SP 800-63B-4 §3.1.3.1.
> PCI SSC names the core problem: if the mailbox opens with the same password, the
> factors are not independent — "'something you know' twice". The machine has no
> mail transport either.*

---

## Passkeys — und die eine Lockerung, die sie kosten

Ein Passkey ist der zweite Faktor **ohne geteiltes Geheimnis**. Der private
Schlüssel verlässt das Gerät nie, der Server kennt nur den öffentlichen. Und er
ist an die Domain gebunden: Eine nachgebaute Anmeldeseite unter einer anderen
Adresse bekommt schlicht keine Signatur — deshalb bewertet das BSI Passkeys bei
Echtzeit-Phishing mit „Gut", TOTP mit „Schlecht".

Hier ist er ein **zusätzlicher** zweiter Faktor, kein Ersatz. Das Passwort bleibt
Faktor 1, und wer keinen Passkey einrichtet, meldet sich unverändert mit den
sechs Ziffern an.

### Der Preis: JavaScript auf drei Seiten

WebAuthn ist ausschließlich über `navigator.credentials` erreichbar. Einen Weg
ohne JavaScript gibt es nicht und wird es nicht geben: Der W3C-Antrag dafür
(w3c/webauthn#1255) wurde im **Februar 2025 ohne Ersatz geschlossen**, mit der
Begründung, zwei Wege zum selben Ziel seien der größere Albtraum.

Das Panel lief mit `default-src 'none'` — gar kein Skript. Diese Zeile ist jetzt
für **drei Pfade** gelockert: `/login`, `/konto`, `/passkey.js`.

Vier Dinge halten die Lockerung klein:

| | |
|---|---|
| **Nur drei Pfade** | Die Übersicht, die Spieleseiten, die Zugangsdaten und das Protokoll behalten `default-src 'none'` — nachgemessen an den ausgelieferten Kopfzeilen, nicht an der Konfiguration |
| **Kein `'unsafe-inline'`, kein `'unsafe-eval'`** | `script-src 'self'` allein. Das Skript liegt als eigene Datei; inline stünde es nicht |
| **`nosniff`** | Ein ausgeliefertes Titelbild kann nicht als Skript durchgehen |
| **Die Datei gehört root** | `/opt/panel/statisch/passkey.js` ist `0644 root:root` — der Dienst kann Code, den er ausliefert, nicht überschreiben. Dieselbe Überlegung wie bei `app.py` |

### Sechs Entscheidungen im Ablauf

1. **Die öffentliche Herkunft ist maßgeblich**, nicht `127.0.0.1`. Die App läuft
   hinter Caddy; eine Signatur für die öffentliche Adresse passte sonst nie.
2. **Die Challenge liegt in einem signierten, fünf Minuten gültigen Cookie**,
   nicht im Serverzustand — dasselbe Muster wie beim Einrichtungs-Token — und ist
   an den Benutzer gebunden, damit sie nicht in einer fremden Sitzung gilt.
3. **Das Passwort wird vor der Challenge geprüft.** Sonst wäre aus zwei Faktoren
   einer geworden, ohne dass es jemand entschieden hätte.
4. **Eine Antwort für drei Fälle.** „Kein solcher Benutzer", „falsches Passwort"
   und „kein Passkey hinterlegt" ergeben denselben 401. Sonst verriete diese
   Route, welche Konten existieren und welche einen Passkey haben.
5. **Der Signaturzähler wird zurückgeschrieben.** Wächst er nicht, ist das der
   Hinweis auf einen geklonten Authenticator; `py_webauthn` wirft dann.
6. **Fehlt die Bibliothek, startet das Panel trotzdem.** TOTP läuft weiter, die
   Passkey-Wege melden sich sauber ab. Ein Panel, das wegen eines optionalen
   Zusatzes nicht mehr hochkommt, wäre der schlechtere Tausch.

`Permissions-Policy` braucht nichts: `publickey-credentials-get` steht
standardmäßig auf `self`, und das Panel wird nirgends eingebettet
(`frame-ancestors 'none'`).

> *A passkey is a second factor without a shared secret: the private key never
> leaves the device and it is bound to the domain, so a look-alike login page
> gets no signature. The price is JavaScript, which WebAuthn cannot do without —
> the W3C closed that request in February 2025. The relaxation covers three paths
> only, with `script-src 'self'` and no unsafe-inline, and was verified against
> the headers actually served rather than the configuration. The public origin is
> authoritative, the challenge travels signed rather than in server state, the
> password is checked first so two factors do not become one, and all three
> failure cases share one answer so the route reveals nothing.*

---

## Was ein Wiederherstellungscode nicht behebt

TOTP beruht auf einem **geteilten Geheimnis**: Server und Gerät kennen dieselbe
Zeichenkette. Das BSI bewertet TOTP-Apps deshalb in zwei von vier Szenarien
genauso schlecht wie E-Mail-TANs (Bewertungstabellen „IT-Sicherheit", Version 1.1,
05/2026):

| Szenario | TOTP | Passkeys/FIDO2 |
|---|---|---|
| Echtzeit-Phishing | **Schlecht** | **Gut** |
| Leak beim Dienst | **Schlecht** | **Gut** |

Ein Hardware-Token ändert daran nichts — er ist nur ein anderes Behältnis für
dasselbe Geheimnis. Wirklich besser ist allein ein Verfahren mit Domainbindung
und ohne serverseitiges Geheimnis.

> *TOTP rests on a shared secret, which is why the BSI rates TOTP apps as poorly
> as email in two of four scenarios. A hardware token changes nothing about that —
> it is merely a different container for the same secret.*

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
