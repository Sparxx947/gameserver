# 04 — Der Spielekatalog

`/etc/spiele-katalog.json` — 179 Spiele, die sich über die Oberfläche mit einem
Klick installieren und wieder entfernen lassen.

> *179 games installable and removable from the panel with a single click.*

---

## Warum ein Katalog und nicht ein Formular

Die naheliegende Lösung wäre ein Formular, in das man Image, Ports und Volumes
einträgt. Sie ist unbrauchbar: Wer diese Werte setzen kann, kann
`-v /:/host` mounten und ist damit root auf der Maschine. Die Weboberfläche darf
nur eines übergeben — **einen Schlüssel**. Alles andere schlägt `spiel-verwalten`
im Katalog nach, und den Katalog kann die Oberfläche nur lesen.

> *The obvious design — a form for image, ports and volumes — is unusable:
> anyone who can set those can mount `-v /:/host` and is root. The panel passes
> only a key; everything else is looked up in the catalogue, which it can only
> read.*

---

## Aufbau eines Eintrags

```json
{
  "schluessel": "necesse",
  "name": "Necesse",
  "kurz": "Pixel-Sandbox mit Bossen und Automatisierung",
  "appid": 1169040,
  "image": "ghcr.io/ich777/steamcmd:necesse",
  "mem_gb": 3,
  "platte_gb": 3,
  "ports": ["14159:14159/udp", "127.0.0.1:8080:8080/tcp"],
  "volumes": ["/srv/games/necesse:/serverdata"],
  "env": {
    "GAME_ID": "1169370",
    "GAME_PARAMS": "",
    "UID": "4711", "GID": "4711",
    "UMASK": "000", "DATA_PERM": "770",
    "WORLD_NAME": "@@WELT_NAME@@"
  },
  "passwort": { "art": "datei", "pfad": "", "feld": "" },
  "adresse_port": 14159,
  "spieler": 4,
  "hinweis": "…",
  "ausschluss": ["steamcmd", "serverfiles/steamapps"]
}
```

| Feld | Bedeutung |
|---|---|
| `schluessel` | interner Name, zugleich Stack- und Verzeichnisname; `[a-z0-9-]` |
| `appid` | Steam-App-ID, nur um das Titelbild zu holen (`0` = kein Steam-Titel) |
| `image` | Container-Image, mit Version |
| `mem_gb` | wird zu `mem_limit` **und** `memswap_limit` |
| `platte_gb` | erwarteter Platzbedarf; die Installation lehnt ab, wenn weniger als dieser Wert plus 10 GB Reserve frei ist |
| `ports` | Docker-Portangaben. Dreiteilige Form (`127.0.0.1:8080:8080/tcp`) bindet **nur lokal** |
| `volumes` | Bind-Mounts, immer unter `/srv/games/<schluessel>` |
| `ordner` | Ordner unter `/serverdata`, die das Image voraussetzt, aber nicht selbst anlegt — die Installation legt sie als Eigentümer der Daten an. Don't Starve Together: `.klei/DoNotStarveTogether` (sein Startskript ruft `mkdir` ohne `-p` auf und legt sich sonst für immer schlafen) |
| `env` | Umgebung. `{PASSWORT}` und `{ADMIN}` werden beim Installieren durch die frisch gewürfelten Passwörter ersetzt, `{SPIELER}` durch den Wert aus `spieler` — bei Spielen, deren Spielerzahl als Startparameter steht (#177) |
| `passwort.art` | `env` (Passwort steht in der Umgebung), `datei` (der Server legt eine Konfigurationsdatei an), `params` (Passwort als Startparameter in `GAME_PARAMS`; der Port folgt erst, wenn der laufende Server per A2S „Passwort nötig“ meldet — E27), `keins` (das Spiel kennt kein Beitrittspasswort; der Port geht erst nach einer Freigabe von Hand auf — #183) |
| `passwort.befehle` | nur mit `passwort.pfad`: Befehle, die in eine Datei mit **einem Befehl je Zeile** gehören, z. B. `{"Password": "{PASSWORT}", "MaxPlayers": "{SPIELER}"}` bei Unturneds `Commands.dat`. Die Installation schreibt sie **vor dem ersten Start**; der Port folgt erst, wenn der laufende Server per A2S „Passwort nötig" meldet (E31) |
| `adresse_port` | der Port, der in der Beitrittsadresse steht |
| `spieler` | Sollwert für die Spielerzahl |
| `hinweis` | wird in der Oberfläche angezeigt; hier stehen Fallstricke |
| `ausschluss` | Pfade unterhalb des Datenverzeichnisses, die **nicht** gesichert werden (Borgs `sh:`-Stil, `*` innerhalb eines Pfadteils). Nur gemessene Installationspfade eintragen — ohne Messung bleibt alles drin (#221). `spiel-verwalten ausschluesse` bringt Änderungen auf schon installierte Server |

> *Field reference above. Note `mem_gb` sets both memory and swap limits, a
> three-part port entry binds locally only, `{PASSWORT}`/`{ADMIN}` are replaced
> with freshly generated passwords at install time, and `ausschluss` lists paths
> kept out of the backup.*

---

## Zwei Bauarten

| | ich777 | LinuxGSM |
|---|---|---|
| Image | `ghcr.io/ich777/steamcmd:<spiel>` und eigene | `gameservermanagers/gameserver:<kürzel>` |
| Datenverzeichnis | `/serverdata` | `/data` |
| Umgebung | `GAME_ID`, `GAME_PARAMS`, `UID`/`GID` | `GAMESERVER`, `UID`/`GID` |
| Konfiguration | je Spiel verschieden | `config-lgsm/<gs>/` **und** `serverfiles/` |
| Einträge | 86 | 68 |

Erzeugt werden beide aus den Vorlagen der jeweiligen Quelle —
`werkzeuge/katalog-ergaenzen.py` und `werkzeuge/katalog-lgsm.py`. Das Feld
`bauart` im Katalog nennt die Herkunft.

**Doppelte Spiele werden über den Namen abgeglichen, nicht über die App-ID.**
Bei GoldSrc teilen sich **13 Spiele** die Sammel-ID 90 (Half-Life Dedicated
Server) — ein Abgleich darüber hätte Counter-Strike 1.6, Day of Defeat, Natural
Selection und zehn weitere fälschlich als Duplikate verworfen. Verglichen wird
gegen den Katalog **und** gegen die handgebauten Stacks: Palworld und
Satisfactory laufen, stehen aber in keinem Katalog.

> *Two build styles, both derived from their source's templates. Duplicates are
> matched by name, never by app id: 13 GoldSrc games share the collective id 90,
> and matching on it would have discarded Counter-Strike 1.6, Day of Defeat and
> eleven others. The comparison covers the catalogue and the hand-built stacks —
> Palworld and Satisfactory run but appear in no catalogue.*

### Vier Eigenheiten von LinuxGSM

An einem echten Fall durchgetestet (Ricochet), bevor 68 Einträge entstanden.
Jede der vier machte eine Anpassung an den Werkzeugen nötig:

1. **`_default.cfg` trägt „DO NOT EDIT, ANY CHANGES WILL BE OVERWRITTEN!"** und
   wird bei jedem Start neu geschrieben. Der Einrichtungsschritt setzte dort
   Werte und meldete Erfolg — wirkungslos. Jetzt ausgefiltert.
2. **Jede LinuxGSM-Konfiguration enthält `betapassword` und `ntfypassword`** —
   Steams Beta-Zweig und ein Benachrichtigungsdienst. Beide sahen aus wie
   Beitrittspasswörter und wurden gesetzt.
3. **Die eigentliche Serverkonfiguration steht im GoldSrc-Stil** ohne
   Gleichheitszeichen und ohne Semikolon: `sv_password ""`. Das erkannte die
   Ersetzung nicht — der Server wäre ohne Beitrittspasswort gelaufen.
4. **`serverfiles/` darf nicht pauschal von der Sicherung ausgeschlossen
   werden.** Dort liegen bei Ricochet 138 MB Installation **und** die 1 KB große
   Serverkonfiguration. Ausgeschlossen wird deshalb nur
   `serverfiles/steamapps`, `log` und `.steam`.

> *Four LinuxGSM quirks, each found by testing one real case before adopting 68
> entries: a regenerated `_default.cfg` that made the setup step report success
> for nothing; two password-shaped fields that are not join passwords; the
> GoldSrc config style the replacement did not recognise, which would have left
> the server without a join password; and a `serverfiles/` directory holding both
> the installation and the real configuration.*

## Die Bilder

| Image | Anzahl | Bemerkung |
|---|---|---|
| `ghcr.io/ich777/steamcmd:<spiel>` | 37 | Ein Bauplan, 79 Spielserver — unterschieden durch `GAME_ID` und `GAME_PARAMS` |
| `itzg/minecraft-server` | 1 | Minecraft (Java) |
| `factoriotools/factorio` | 1 | Factorio |
| `devidian/vintagestory` | 1 | Vintage Story |
| `teamspeak` | 1 | kein Spiel |

**Die ich777-Images verlangen `UID`/`GID`, nicht `PUID`/`PGID`.** Und sie
brauchen die Unterverzeichnisse `steamcmd` und `serverfiles` **vor** dem ersten
Start — fehlen sie, dreht der Container in einer Neustartschleife mit
„SteamCMD not found!" und lädt nie etwas herunter. `spiel-verwalten` legt sie
deshalb selbst an.

> *The ich777 images expect `UID`/`GID`, not `PUID`/`PGID`, and need the
> `steamcmd` and `serverfiles` subdirectories to exist before first start —
> otherwise the container loops with "SteamCMD not found!" and downloads
> nothing. The installer creates them.*

---

## Portregeln im Katalog

`werkzeuge/katalog-ports.py` prüft vier Regeln, und `vollstaendigkeit.sh` ruft
es bei jedem Lauf. Jede Regel stammt aus einem Fehler, der im Katalog wirklich
stand (#163, gefunden am 2026-09-10):

| Regel | Was vorher im Katalog stand |
|---|---|
| **Verwaltungsports nur auf `127.0.0.1`** (Grenze 4) | FiveM und RedM veröffentlichten ihre *WebConsole* — ein gotty-Terminal direkt an der Serverkonsole, **ohne Anmeldung**. Dazu RCON bei 52 Source-/GoldSrc-Spielen (TCP 27015), bei Squad und Quake Live, die Webadministration von Killing Floor 1 und 2, das Web Panel von 7 Days to Die, der Server-Manager von Assetto Corsa. |
| **TCP und UDP eines Containerports auf einem Hostport** | Die Kollisionsauflösung verschob beide getrennt. FiveM braucht beide auf **einem** Port und war so nicht erreichbar. |
| **Die Beitrittsadresse zeigt auf einen Port, auf dem das Spiel ankommt** | Bei TF2 zeigte sie auf `30118/tcp`, das Spiel lauschte auf `30130/udp`. Dasselbe bei acht weiteren, darunter Conan Exiles. |
| **Kein Hostport doppelt, lokale eingeschlossen** | Creativerse und 7 Days to Die teilten sich `26900/udp`, Assetto Corsa lag auf dem lokalen Port von 7 Days to Die. Die Installation lehnte das zweite Spiel ab — oder, bei lokalen Ports, startete es gar nicht. |

**Warum die Regel für Verwaltungsports nie griff:** Sie stand im Generator als
Namensmuster (`rcon|webconsole|admin|…`) — und wurde mit der **Portnummer**
verglichen. Der Name kam gar nicht an: Der Parser las nur `<HostPort>` und
`<ContainerPort>`, die Namen stehen in den `<Config Type="Port">`-Einträgen der
Vorlage. Die Regel steht jetzt **einmal**, in `katalog-ports.py`, und beide
Generatoren benutzen sie. Eine Kopie war genau das, was sie verrotten ließ.

**Wo die Prüfung nichts weiß:** Der Katalog speichert keine Portnamen. Die
Prüfung kennt die Verwaltungsports deshalb als Liste von Containerports
(`VERWALTUNG` im Werkzeug) — sie fängt die bekannten, ein neues Spiel mit einem
neuen Verwaltungsport fällt erst auf, wenn jemand die Vorlage liest. Die
Generatoren entscheiden dagegen nach dem **Namen** aus der Vorlage.

**Zwei bewusste Ausnahmen** — der Webport von **Eco** (`3001/tcp`) und die
Statistik von **Assetto Corsas stracker** (`50041/tcp`) bleiben öffentlich: Beide
sind für Spieler da, auch wenn dahinter ein Anmeldebereich liegt. Unturned
nennt `27015/tcp` in seiner Vorlage „Game Port" und ist deshalb von der
RCON-Regel ausgenommen.

Keines der geänderten 94 Spiele war installiert. Ein installiertes Spiel hätte
seinen Port behalten müssen — sonst verliert jeder Client den Server.

> *`werkzeuge/katalog-ports.py`, run by the completeness check, enforces four
> rules, each from a real defect found on 2026-09-10 (#163): management ports
> bind to localhost (FiveM/RedM published an unauthenticated server console,
> 52 Source games their RCON); TCP and UDP of one container port share a host
> port (FiveM needs both on one); the join port is one the game listens on (TF2
> pointed at its TCP port); and no host port is used twice, local ones included.
> The management rule never fired because the generator matched its name pattern
> against the port number — the parser never read the names at all. It now
> lives once, in `katalog-ports.py`. The catalogue stores no port names, so the
> check relies on a list of known container ports, while the generators decide
> by template name. Eco's web port and Assetto Corsa's stracker stay public on
> purpose; Unturned's 27015/tcp is a game port. None of the 94 changed games was
> installed — an installed one would have had to keep its port.*

---

## Installation Schritt für Schritt

1. **Nachschlagen.** Schlüssel im Katalog suchen; unbekannt → Abbruch.
2. **Platz prüfen.** `platte_gb` + 10 GB Reserve müssen frei sein.
3. **Ports prüfen.** Kollision wird gegen die **tatsächlich belegten** Ports
   geprüft, nicht gegen alle im Katalog vergebenen. Sonst bekäme fast jedes
   Spiel einen Ersatzport, obwohl nie zwei gleichzeitig laufen. **Auch die
   lokalen** (`127.0.0.1:…`): Bis #163 stand hier, eine lokale Bindung könne
   mit nichts kollidieren. Gemessen weist das System `127.0.0.1:N` ab, wenn ein
   anderer Container `0.0.0.0:N` hält, und umgekehrt, für TCP wie UDP.
4. **Passwörter würfeln.** Beitritt und Admin, je 14 Zeichen ohne verwechselbare
   Zeichen.
5. **Dateien schreiben.** `compose.yaml` (`0600 root`), `panel.json`
   (`0640 root:panel`), Ausschlussblock in `/etc/borg-ausschluss.txt`,
   Zugangsdaten, Titelbild.
6. **Verzeichnis anlegen.** `mkdir`, **dann** `chmod` — der `mode`-Parameter von
   `mkdir` wird von der `umask` beschnitten. Mit `umask 077` entstand aus
   `mkdir(mode=0o750)` ein `0700`, die Oberfläche konnte `panel.json` nicht
   lesen, und in der Übersicht fehlte wortlos die Beitrittsadresse.
7. **Starten**, aber nur wenn der freie Arbeitsspeicher zum `mem_limit` reicht.

> *Install steps: look up the key, check disk space, check ports against
> actually bound ports (not every port in the catalogue, or nearly every game
> would be relocated) — local ones included, since `127.0.0.1:N` and `0.0.0.0:N`
> exclude each other (measured) — generate two passwords, write the files, create the
> directory with `mkdir` followed by an explicit `chmod` — the `mode` argument is
> masked by `umask`, which once silently cost the join address in the overview —
> and start only if free RAM covers the memory limit.*

---

## Die Passwort-Einrichtung

Die meisten Server legen ihre Konfigurationsdatei **erst beim ersten Start** an,
oft nach einem mehrere Minuten langen Download. Das Passwort lässt sich also
nicht vorab setzen.

Deshalb der Timer `spiel-einrichtung.timer`: alle zwei Minuten prüft er, ob eine
Konfigurationsdatei aufgetaucht ist, und trägt Beitrittspasswort, Adminpasswort
und Spielerzahl ein.

Er rät die Feldnamen **nicht**, sondern sucht sie über Muster — in `.ini`,
`.json`, `.xml` und `.cfg`:

```
Passwort : enthält password/passwort/passwd/psw, aber NICHT
           admin, rcon, steam, api, web, db, sql, mysql, token
Admin    : admin oder owner zusammen mit einem Passwortwort, aber NICHT rcon
Spieler  : maxplayer, maxclients, slots, playerlimit …, aber NICHT reserved, min
```

**Ein Muster allein reicht aber nicht.** In JSON-Dateien wird zusätzlich
geprüft, **was dort vorher stand** — ersetzt wird nur Gleiches durch Gleiches:
eine Zahl durch eine Zahl, ein Text durch einen Text. Felder, deren Name auf
`comment` deutet, bleiben grundsätzlich unangetastet.

Der Grund ist gemessen, nicht vorsorglich. Factorios `server-settings.json`
enthält neben `max_players` auch:

| Feld | Inhalt |
|---|---|
| `_comment_max_players` | ein Erklärtext — enthält den Feldnamen vollständig |
| `ignore_player_limit_for_returning_players` | ein **Boolean** — enthält `player_limit` |

Beide treffen das Spielerzahl-Muster. Ohne die Typprüfung bekamen sie die
Spielerzahl `4` eingetragen, und Factorio verweigerte den Start mit
*„Value must be a bool in property tree at
ROOT.ignore_player_limit_for_returning_players"* — in einer Neustartschleife,
während das Panel die Einrichtung als **abgeschlossen** führte. Zwei weitere
Felder (`_comment_max_upload_slots`, `_comment_autosave_slots`) wären über
`slots` genauso getroffen worden.

Diese Regel braucht kein Wissen über ein einzelnes Spiel — das ist ihr Wert. Sie
trägt aber **nur, wo es Typen gibt**: `.ini`, `.cfg` und `.xml` kennen nur Text.
Dort gilt seit #227 eine schwächere Fassung: Steht als Wert `true` oder `false`
(auch in Anführungszeichen, mit Kommentar dahinter), ist das Feld ein Schalter
und bleibt. Anlass war Killing Floor 2: `bNoPassword=False` im Serverbrowser-
Filter traf das Passwortmuster über den Namen und bekam das Passwort. Schalter
mit Zahlenwert (`sv_nopassword 1`) erkennt der Wert nicht — deshalb nimmt das
Passwortmuster zusätzlich Namen wie `NoPassword`, `UsePassword`,
`RequirePassword`, `HasPassword` aus. Gegengeprüft über alle 2834
Konfigurationsdateien der laufenden Server: Genau dieser eine Treffer fällt weg,
kein echtes Passwortfeld.

Ein übersprungenes Feld wird **genannt**, nicht stillschweigend ausgelassen:

```
uebersprungen: server-settings.json:ignore_player_limit_for_returning_players
               (Kommentarfeld, Schalter oder andere Art)
```

Stilles Überspringen war schon einmal die Ursache — beim Minecraft-Fall passte
das Feld nicht, und niemand erfuhr davon.

> *A pattern alone is not enough. In JSON files the existing value is checked
> too: like replaces like — a number a number, a text a text — and fields whose
> name reads as a comment are never touched. The reason is measured, not
> precautionary: Factorio's `server-settings.json` holds
> `_comment_max_players` (an explanatory text carrying the full field name) and
> `ignore_player_limit_for_returning_players` (a **boolean** containing
> `player_limit`). Both match the player-limit pattern, both received the number
> 4, and Factorio refused to start with "Value must be a bool" in a restart loop
> while the panel showed the setup as complete. The rule needs no per-game
> knowledge, which is its value, but it only carries where types exist — ini,
> cfg and xml know only text. A skipped field is named rather than passed over
> in silence: silent skipping was the cause once before. Since #227 the text
> formats keep fields whose value is `true`/`false`, and the password pattern
> excludes switch names like `NoPassword`/`UsePassword` (KF2's `bNoPassword`
> got the password); across 2834 live config files only that one hit drops.*

Findet er nach sechs Stunden nichts, meldet er es sichtbar — veröffentlicht
wird dann aber **nicht** (E26, entschieden am 2026-09-11: „Ein Server ohne
Passwort darf nicht automatisch ans Netz gehen."). Der Port geht erst auf, wenn
ein späterer Lauf ein Feld findet oder der Server per A2S „Passwort nötig"
meldet. Bis dahin lautete die Meldung „KEIN Passwortfeld gefunden – der Server
läuft ohne Beitrittspasswort", und der Port wurde trotzdem veröffentlicht.

**Dieser Satz gilt aber nur, wenn der Server auch wirklich lief.** Vorher wurde
er unbesehen ausgegeben, und beim ersten Aufbau auf einer frischen Maschine war
er dreimal falsch — in die *alarmierende* Richtung: Wer ihn liest, sucht einen
offenen Port ohne Passwort. Es gab keinen, weil es keinen Server gab.

Der Schritt sieht deshalb vor jeder Meldung nach, ob hinter dem Container
überhaupt etwas läuft, und benennt sonst den wahren Grund:

| Lage des Containers | Meldung |
|---|---|
| läuft | „KEIN Passwortfeld gefunden …" (unverändert) |
| startet immer wieder neu | „SERVER STARTET NICHT – der Container startet immer wieder neu (N Neustarts)" |
| läuft nicht | „SERVER STARTET NICHT – der Container läuft nicht" |
| meldet sich ungesund | „SERVER STARTET NICHT – der Container meldet seinen eigenen Gesundheitstest als fehlgeschlagen" |

Auch die Wartemeldung sagt es: „wartet auf die Konfigurationsdatei des Servers
— **aber der Container läuft nicht**". Ein Server, der nie startet, wartet nicht,
er ist kaputt.

> *That sentence only holds if the server was actually running. It used to be
> printed unseen, and on a first install on a fresh machine it was wrong three
> times out of three — wrong in the alarming direction, because whoever reads it
> goes looking for an open port without a password, and there was none, because
> there was no server. The step now checks whether anything is running behind
> the container and names the real reason otherwise; the waiting message says it
> too. A server that never starts is not waiting, it is broken.*
Diese Meldung ist der Kern der Sache: ein Server ohne Passwort darf nicht
unauffällig sein.

> *Most servers write their config only on first start, often after a long
> download, so the password cannot be set in advance. A timer checks every two
> minutes and fills in the join password, admin password and player count. Field
> names are matched by pattern, not guessed, across ini/json/xml/cfg. After six
> hours it gives up and says so visibly — a server without a password must not
> be quiet about it.*

**Fünf Fallen, die das Ersetzen gekostet hat:**

* `\s` in der Zeilenregel frisst den Zeilenumbruch. Bei leerem Wert wurde die
  Folgezeile als Wert verschluckt; das Passwort landete eine Zeile tiefer und
  das Adminfeld wurde nie gefunden. → `[ \t]*` und `[^\r\n]*`.
* XML kommt in **zwei** Formen vor: als Attribut und als
  `<property name="…" value="…">` (7 Days to Die).
* Ohne `^(?!.*rcon)` überschrieb die Adminregel das RCON-Passwort.
* Der Zeilenschwanz muss erhalten bleiben: Necesses `server.cfg` verlor die
  Kommas hinter `slots` und `password` und war damit ungültig.
* Der **id-Tech-Stil** stellt ein `set` voran — `set g_password ""` statt
  `g_password ""`. Die Regel verlangte, dass die Zeile ausschließlich aus
  Schlüssel und Wert besteht, und ging deshalb an allen zehn Quake-, Wolfenstein-
  und Jedi-Knight-Ablegern im Katalog vorbei: ET: Legacy lief im Test **ohne
  Beitrittspasswort**, während sein Port schon veröffentlicht war. Das Präfix ist
  jetzt optional und wird erhalten — ohne es liest das Spiel die Zeile nicht mehr.

> *Five traps this cost: `\s` eats the newline (an empty value swallowed the next
> line); XML appears both as attributes and as `<property name= value=>`; without
> a negative look-ahead the admin rule overwrote the RCON password; the line
> tail — trailing comma or comment — must be preserved or the file becomes
> invalid; and the id-Tech style prefixes `set`, which the rule rejected, leaving
> all ten Quake/Wolfenstein/Jedi Knight entries without a join password.*

---

## Der Port nach dem ersten Start

17 Spiele im Katalog nennen ihren Port **nicht** im Katalogeintrag, sondern erst
in ihrer eigenen Konfiguration — derselben Datei, die der erste Start schreibt.
Vorher ist er schlicht nicht bekannt. Sie starten deshalb **ohne
veröffentlichten Port**, und `port-ermitteln` trägt ihn nach.

Die Regel steht als `port_regel` im Katalogeintrag und stammt aus LinuxGSMs
`lgsm/modules/info_game.sh` — sie ist abgeschrieben, nicht geraten:

```json
"port_regel": {"art": "quakec", "feld": "net_port",
               "datei": "${selfname}.cfg", "protokolle": ["udp"]}
```

Neun Formate kommen vor: `json`, `xml`, `ini`, `java_properties`, `lua`,
`pc_config`, `quakec` sowie `keyvalue_pairs_equals` und `_space`.

**Nicht der Pfad entscheidet, welche Datei gilt, sondern der Inhalt.** LinuxGSM
ersetzt `${selfname}` durch den Servernamen, den wir vorab nicht kennen; gesucht
wird deshalb notfalls auf die Endung allein. Das trifft gleichnamige Dateien:
ET: Legacy hat `etlserver.cfg` **zweimal** — als LinuxGSM-Einstellungen unter
`config-lgsm/` (189 Byte, ohne `net_port`) und als echte Spielkonfiguration
unter `serverfiles/etmain/` (7301 Byte, mit `net_port`). Es gewinnt die erste
Datei, in der das Feld tatsächlich auf einem gültigen Port steht. Auskommentierte
Vorgaben (`//set net_port "27960"`) zählen nicht.

**Der Port kommt zuletzt** — siehe E23. Das Eintragen ist der Schritt, der den
Server nach außen öffnet, und es geschieht erst, wenn die Einrichtung entschieden
ist.

Kollidiert der Port mit einem belegten, weicht der **Host**-Port auf 30500–30999
aus; der Container-Port bleibt, denn den kennt nur das Spiel. Der eigene Stack
zählt dabei nicht als belegt — sonst hielte ein zweiter Lauf seinen eigenen
Eintrag für fremd.

> *17 games name their port only in their own config — the file the first start
> writes — so they start with no published port and `port-ermitteln` fills it in
> afterwards. The rules are copied from LinuxGSM's `info_game.sh`, not guessed.
> Content decides which file counts, not the path: ET: Legacy has two files named
> `etlserver.cfg`, and the one that matters is whichever actually carries the
> field. The port is written last, after setup has settled — that write is what
> exposes the server.*

---

## Alle Spiele im Katalog

Erzeugt aus `etc/spiele-katalog.json` — nicht von Hand ändern, sondern
`python3 werkzeuge/katalog-doku.py` laufen lassen. `vollstaendigkeit.sh` meldet,
wenn Liste und Katalog auseinandergehen.

> *Generated from the catalogue; regenerate rather than edit. The completeness
> check reports drift.*

<!-- katalog:anfang -->

<!-- Erzeugt von werkzeuge/katalog-doku.py — nicht von Hand aendern. -->

| Schlüssel | Name | Kategorie | Bauart | Steam |
|---|---|---|---|---|
| `7daystodie` | 7DaysToDie | survival | ich777 | `251570` |
| `abioticfactor` | AbioticFactor | survival | ich777 | `427410` |
| `ahl` | Action Half-Life | arena | linuxgsm | — |
| `ahl2` | Action: Source | arena | linuxgsm | `977050` |
| `alienswarm` | AlienSwarm | shooter | ich777 | `630` |
| `alienswarmreactivedrop` | AlienSwarm ReactiveDrop | shooter | ich777 | `563560` |
| `altitude` | Altitude | arena | ich777 | `41300` |
| `americantrucksimulator` | AmericanTruckSimulator | rennen | ich777 | `270880` |
| `americasarmyprovinggrounds` | AmericasArmy ProvingGrounds | shooter | ich777 | `203300` |
| `ark` | ARK: Survival Evolved | survival | linuxgsm | `346110` |
| `arma3` | ARMA 3 | shooter | linuxgsm | `107410` |
| `armar` | Arma Reforger |  | linuxgsm | `1874880` |
| `assettocorsa` | AssettoCorsa | rennen | ich777 | `244210` |
| `astroneer` | Astroneer | survival | ich777 | `361420` |
| `avorion` | Avorion | sandbox | ich777 | `445220` |
| `barotrauma` | Barotrauma | survival | ich777 | `602960` |
| `bb` | BrainBread | shooter | linuxgsm | — |
| `bb2` | BrainBread 2 | shooter | linuxgsm | `346330` |
| `bd` | Base Defense | shooter | linuxgsm | `632730` |
| `bf1942` | Battlefield 1942 |  | linuxgsm | — |
| `bfv` | Battlefield: Vietnam |  | linuxgsm | — |
| `bmdm` | Black Mesa: Deathmatch | shooter | linuxgsm | — |
| `bo` | Ballistic Overkill |  | linuxgsm | — |
| `bs` | Blade Symphony | shooter | linuxgsm | `225600` |
| `btl` | BATTALION: Legacy | shooter | linuxgsm | `489940` |
| `cc` | Codename CURE | shooter | linuxgsm | `355180` |
| `chivalrymedievalwarfare` | Chivalry MedievalWarfare | shooter | ich777 | `220070` |
| `citadelforgedwithfire` | Citadel ForgedWithFire | survival | ich777 | `487120` |
| `cod` | Call of Duty | shooter | linuxgsm | `2620` |
| `cod2` | Call of Duty 2 | shooter | linuxgsm | `2630` |
| `cod4` | Call of Duty 4 | shooter | linuxgsm | — |
| `coduo` | Call of Duty: United Offensive | shooter | linuxgsm | `2640` |
| `codwaw` | Call of Duty: World at War | shooter | linuxgsm | `10090` |
| `colonysurvival` | ColonySurvival | aufbau | ich777 | `366090` |
| `conanexiles` | ConanExiles | survival | ich777 | `440900` |
| `corekeeper` | CoreKeeper | survival | ich777 | `1621690` |
| `counterstrike2d` | CounterStrike2D | arena | ich777 | — |
| `craftopia` | Craftopia | survival | ich777 | `1307550` |
| `creativerse` | Creativerse | survival | ich777 | `280790` |
| `cs` | Counter-Strike 1.6 | shooter | linuxgsm | — |
| `cs2` | Counter-Strike 2 | shooter | linuxgsm | `730` |
| `cscz` | Counter-Strike: Condition Zero | shooter | linuxgsm | `80` |
| `csgo` | Counter-Strike: Global Offensive | shooter | linuxgsm | — |
| `css` | Counter-Strike: Source | shooter | linuxgsm | `240` |
| `cstrike16` | CStrike1.6 | shooter | ich777 | `90` |
| `dab` | Double Action: Boogaloo | shooter | linuxgsm | `317360` |
| `dayofdefeatsource` | DayOfDefeatSource | shooter | ich777 | `232290` |
| `dayofinfamy` | DayOfInfamy | shooter | ich777 | `447820` |
| `daysofwar` | DaysOfWar | shooter | ich777 | `541790` |
| `dayz` | DayZ | survival | linuxgsm | `221100` |
| `ddnet` | DDNet | arena | ich777 | `412220` |
| `dmc` | Deathmatch Classic | arena | linuxgsm | `40` |
| `dod` | Day of Defeat | shooter | linuxgsm | `30` |
| `dodr` | Day of Dragons | survival | linuxgsm | `1088090` |
| `dontstarvetogether` | DontStarveTogether | survival | ich777 | `322330` |
| `dys` | Dystopia | shooter | linuxgsm | — |
| `eco` | ECO | aufbau | ich777 | `382310` |
| `em` | Empires Mod | shooter | linuxgsm | `17740` |
| `etl` | ET: Legacy |  | linuxgsm | — |
| `eurotrucksimulator2` | EuroTruckSimulator2 | rennen | ich777 | `227300` |
| `factorio` | Factorio | aufbau | eigenes-image | `427520` |
| `fistfuloffrags` | FistfulOfFrags | shooter | ich777 | `265630` |
| `fivem` | FiveM | sandbox | ich777 | — |
| `frozenflame` | FrozenFlame | survival | ich777 | `715400` |
| `garrysmod` | GarrysMod | sandbox | ich777 | `4000` |
| `halflife2deathmatch` | HalfLife2DeathMatch | shooter | ich777 | `232370` |
| `halflifedeathmatch` | HalfLife Deathmatch | shooter | ich777 | `90` |
| `hcu` | HYPERCHARGE: Unboxed | shooter | linuxgsm | `523660` |
| `hldms` | Half-Life Deathmatch: Source | shooter | linuxgsm | `360` |
| `hurtworld` | Hurtworld | survival | ich777 | `393420` |
| `hz` | Humanitz | survival | linuxgsm | `1766060` |
| `icarus` | Icarus | survival | ich777 | `1149460` |
| `insurgency` | Insurgency | shooter | ich777 | `222880` |
| `insurgencysandstorm` | InsurgencySandstorm | shooter | ich777 | `581330` |
| `ios` | IOSoccer | arena | linuxgsm | `673560` |
| `jbep3` | Jabroni Brawl: Episode 3 | shooter | linuxgsm | `869480` |
| `jc2` | Just Cause 2 |  | linuxgsm | `8190` |
| `jc3` | Just Cause 3 |  | linuxgsm | `225540` |
| `jk2` | Jedi Knight II: Jedi Outcast | sandbox | linuxgsm | — |
| `killingfloor` | KillingFloor | shooter | ich777 | `1250` |
| `killingfloor2` | KillingFloor2 | shooter | ich777 | `232090` |
| `l4d2` | Left 4 Dead 2 | shooter | linuxgsm | `550` |
| `lastoasis` | LastOasis | survival | ich777 | `903950` |
| `left4dead` | Left4Dead | shooter | ich777 | `500` |
| `lifeisfeudalyourown` | LifeIsFeudal YourOwn | survival | ich777 | `290080` |
| `lotrreturntomoria` | LOTR ReturnToMoria | survival | ich777 | `2933080` |
| `mcv` | Military Conflict: Vietnam | shooter | linuxgsm | `1012110` |
| `memoriesofmars` | Memories of Mars | aufbau | ich777 | `715380` |
| `mindustry` | Mindustry | aufbau | ich777 | `1127400` |
| `minecraft` | Minecraft (Java) | survival | eigenes-image | — |
| `minecraftbedrock` | Minecraft (Bedrock) | survival | eigenes-image | — |
| `minecraftfabric` | Minecraft (Fabric) | survival | eigenes-image | — |
| `minecraftforge` | Minecraft (Forge) | survival | eigenes-image | — |
| `minecraftneoforge` | Minecraft (NeoForge) | survival | eigenes-image | — |
| `minecraftpaper` | Minecraft (Paper) | survival | eigenes-image | — |
| `minecraftpurpur` | Minecraft (Purpur) | survival | eigenes-image | — |
| `minecraftquilt` | Minecraft (Quilt) | survival | eigenes-image | — |
| `minecraftspigot` | Minecraft (Spigot) | survival | eigenes-image | — |
| `mohaa` | Medal of Honor: Allied Assault | shooter | linuxgsm | — |
| `mordhau` | Mordhau | shooter | ich777 | `629760` |
| `multitheftauto` | MultiTheftAuto | sandbox | ich777 | — |
| `nd` | Nuclear Dawn | shooter | linuxgsm | `17710` |
| `necesse` | Necesse | survival | ich777 | `1169040` |
| `neotokyo` | NEOTOKYO | shooter | ich777 | `244630` |
| `nmrih` | No More Room in Hell | shooter | linuxgsm | `224260` |
| `ns` | Natural Selection | shooter | linuxgsm | — |
| `ns2` | Natural Selection 2 | shooter | linuxgsm | `4920` |
| `ns2c` | NS2: Combat | shooter | linuxgsm | `310110` |
| `ohd` | Operation: Harsh Doorstop | shooter | linuxgsm | `736590` |
| `onset` | Onset |  | linuxgsm | `1105810` |
| `openmwtes3mp` | OpenMW TES3MP | sandbox | ich777 | — |
| `openrct2` | OpenRCT2 | aufbau | ich777 | — |
| `openttd` | OpenTTD | aufbau | ich777 | `1536610` |
| `opfor` | Opposing Force | shooter | linuxgsm | — |
| `pc` | Project Cars |  | linuxgsm | `234630` |
| `pc2` | Project Cars 2 |  | linuxgsm | `378860` |
| `postscriptum` | PostScriptum | shooter | ich777 | `746200` |
| `projectzomboid` | ProjectZomboid | survival | ich777 | `108600` |
| `pvkii` | PVK II | shooter | ich777 | `17575` |
| `pvr` | Pavlov VR | shooter | linuxgsm | — |
| `q2` | Quake 2 | arena | linuxgsm | — |
| `q3` | Quake 3: Arena | arena | linuxgsm | — |
| `q4` | Quake 4 | arena | linuxgsm | `2210` |
| `quakelive` | QuakeLive | arena | ich777 | `282440` |
| `qw` | Quake World | arena | linuxgsm | — |
| `redm` | RedM | sandbox | ich777 | — |
| `ricochet` | Ricochet | arena | linuxgsm | — |
| `ro` | Red Orchestra: Ostfront 41-45 |  | linuxgsm | `1200` |
| `rtcw` | Return to Castle Wolfenstein | shooter | linuxgsm | `9010` |
| `rust` | RUST | survival | ich777 | `252490` |
| `rw` | Rising World |  | linuxgsm | `324080` |
| `samp` | San Andreas Multiplayer | sandbox | linuxgsm | — |
| `sbots` | StickyBots | shooter | linuxgsm | `889400` |
| `scpsecretlaboratory` | SCP SecretLaboratory | shooter | ich777 | `996560` |
| `scpslsm` | SCP: Secret Laboratory ServerMod | shooter | linuxgsm | — |
| `sfc` | SourceForts Classic | shooter | linuxgsm | — |
| `sof2` | Soldier Of Fortune 2: Gold Edition | shooter | linuxgsm | — |
| `sol` | Soldat |  | linuxgsm | `638490` |
| `sonsoftheforest` | SonsOfTheForest | survival | ich777 | `1326470` |
| `soulmask` | Soulmask | survival | ich777 | `2646460` |
| `squad` | Squad | shooter | ich777 | `393380` |
| `squad44` | Squad 44 | shooter | linuxgsm | `736220` |
| `st` | Stationeers |  | linuxgsm | `544550` |
| `starbound` | Starbound | survival | ich777 | `211820` |
| `starmade` | Starmade | sandbox | ich777 | `244770` |
| `subsistence` | Subsistence | survival | ich777 | `418030` |
| `survivethenights` | SurviveTheNights | survival | ich777 | `541300` |
| `svencoop` | SvenCOOP | shooter | ich777 | `225840` |
| `teamfortress2` | TeamFortress2 | shooter | ich777 | `440` |
| `teamspeak` | TeamSpeak 3 | dienst | eigenes-image | — |
| `teeworlds` | Teeworlds | arena | ich777 | `380840` |
| `terraria` | Terraria | survival | ich777 | `105600` |
| `terrariatshock` | Terraria TShock | survival | ich777 | — |
| `terratechworlds` | TerraTech Worlds | aufbau | ich777 | `2313330` |
| `tf2c` | Team Fortress 2 Classified | shooter | linuxgsm | `3545060` |
| `tfc` | Team Fortress Classic | shooter | linuxgsm | `20` |
| `theforest` | TheForest | survival | ich777 | `1326470` |
| `thefront` | TheFront | survival | ich777 | `2285150` |
| `ti` | The Isle | survival | linuxgsm | `376210` |
| `ts` | The Specialists | shooter | linuxgsm | — |
| `tu` | Tower Unite | sandbox | linuxgsm | `394690` |
| `unturned` | Unturned | survival | ich777 | `304930` |
| `urbanterror` | Urban Terror | arena | ich777 | — |
| `ut` | Unreal Tournament | arena | linuxgsm | — |
| `ut2k4` | Unreal Tournament 2004 |  | linuxgsm | — |
| `ut3` | Unreal Tournament 3 | arena | linuxgsm | — |
| `ut99` | Unreal Tournament 99 |  | linuxgsm | — |
| `valheim` | Valheim | survival | ich777 | `892970` |
| `vintagestory` | Vintage Story | survival | eigenes-image | — |
| `vrising` | V Rising | survival | ich777 | `1604030` |
| `vs` | Vampire Slayer | shooter | linuxgsm | `3043210` |
| `wet` | Wolfenstein: Enemy Territory |  | linuxgsm | `1873030` |
| `wf` | Warfork | arena | linuxgsm | `671610` |
| `windward` | Windward | survival | ich777 | `326410` |
| `wurmunlimited` | WurmUnlimited | survival | ich777 | `366220` |
| `xonotic` | Xonotic | arena | ich777 | — |
| `zandronum` | Zandronum | arena | ich777 | — |
| `zmr` | Zombie Master: Reborn | shooter | linuxgsm | — |
| `zps` | Zombie Panic! Source | shooter | linuxgsm | `17500` |

<!-- katalog:ende -->

---

## Deinstallation

1. **Endsicherung** (`spiele-sicherung --nur <stack>`). Schlägt sie fehl,
   **bricht die Deinstallation ab** — ohne gesicherten Stand wird nichts
   gelöscht.
2. `docker compose down`
3. Datenverzeichnis, Stack-Verzeichnis, Ausschlussblock, Titelbild,
   Zugangsdaten.

Verlangt zwingend eine `panel.json`. Die sieben handgepflegten Server haben
keine und sind damit vor einem Fehlklick geschützt.

> *Uninstall: a final backup first — if it fails, the uninstall aborts and
> nothing is deleted — then compose down and removal of data, stack, exclusion
> block, artwork and credentials. A `panel.json` is mandatory, which protects the
> seven hand-maintained stacks from a misclick.*

---

## Katalog erweitern

Eintrag in `spiele` ergänzen, dann **ohne Download** prüfen:

```bash
katalog-vorpruefung
```

Prüft Pflichtfelder, Schlüsselform, Portkollisionen (installierte Spiele
ausgenommen), erzeugt die echte `compose.yaml` und lässt `docker compose config`
darauf laufen, und fragt das Image-Manifest ab (`docker manifest inspect`) — das
holt nur die Metadaten, keine Schichten.

**Wer Portkollisionen automatisch auflösen will: installierte Spiele ausnehmen.**
Ein laufender Server findet seine eigenen Ports als belegt vor. Ein Lauf ohne
diese Ausnahme wollte TeamSpeak von 9987 auf 30115 verschieben — jeder Client
hätte den Server nicht mehr gefunden.

> *To extend the catalogue, add the entry and run `katalog-vorpruefung`, which
> validates without downloading anything: required fields, key shape, port
> collisions (excluding installed games), a real `docker compose config` run, and
> a manifest lookup. Anyone automating collision resolution must exclude
> installed games — a running server sees its own ports as taken, and one such
> run tried to move TeamSpeak from 9987 to 30115.*

---

## Bekannt offen

* **Fünf Host-Ports sind mehrfach vergeben** (nachgezählt am 2026-09-07):

  | Port | Spiele |
  |---|---|
  | `8766/udp` | dontstarvetogether, sonsoftheforest, theforest, wurmunlimited |
  | `26900/udp`, `26901/udp` | 7daystodie, creativerse |
  | `8777/udp` | astroneer, soulmask |
  | `27020/udp` | avorion, wurmunlimited |

  Das ist unschädlich, solange die betroffenen Spiele nicht gleichzeitig laufen
  sollen. Bei echter Kollision lehnt die Installation mit „Port bereits belegt"
  ab — sie prüft gegen die tatsächlich gebundenen Ports, nicht gegen den Katalog.

* **Minecraft hat kein Beitrittspasswort** — das Spiel kennt keins. Der
  Eintrag setzt stattdessen `ENABLE_WHITELIST` und `ENFORCE_WHITELIST`. Das ist
  strenger als ein Passwort, aber es heißt: **nach der Installation kommt
  niemand rein**, bis der erste Name auf der Liste steht:

  ```bash
  docker exec minecraft rcon-cli whitelist add <Spielername>
  ```

  Ebenfalls zu wissen: Die Installation setzt `EULA=TRUE` — das ist die
  Zustimmung zu Mojangs Nutzungsbedingungen.

* **`corekeeper` hat gar keine Portangabe.** Laut der Vorlage des Images ist
  keine Portweiterleitung nötig; der Beitritt läuft über eine GameID, die nach
  dem Start im Protokoll steht.

> *Known open: five host ports are assigned more than once (table above,
> counted 2026-09-07). Harmless unless two of the affected games should run at
> the same time; on a real collision the install refuses with "port already in
> use", checking actually bound ports rather than the catalogue. And
> `corekeeper` declares no ports at all — per the image's own template no
> forwarding is needed, and players join via a GameID printed to the log after
> startup.*
