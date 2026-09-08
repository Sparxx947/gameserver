# 04 — Der Spielekatalog

`/etc/spiele-katalog.json` — 41 Spiele, die sich über die Oberfläche mit einem
Klick installieren und wieder entfernen lassen.

> *41 games installable and removable from the panel with a single click.*

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
| `env` | Umgebung. `{PASSWORT}` und `{ADMIN}` werden beim Installieren durch die frisch gewürfelten Passwörter ersetzt |
| `passwort.art` | `env` (Passwort steht in der Umgebung), `datei` (der Server legt eine Konfigurationsdatei an), `keins` |
| `adresse_port` | der Port, der in der Beitrittsadresse steht |
| `spieler` | Sollwert für die Spielerzahl |
| `hinweis` | wird in der Oberfläche angezeigt; hier stehen Fallstricke |
| `ausschluss` | Pfade unterhalb des Datenverzeichnisses, die **nicht** gesichert werden |

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

## Installation Schritt für Schritt

1. **Nachschlagen.** Schlüssel im Katalog suchen; unbekannt → Abbruch.
2. **Platz prüfen.** `platte_gb` + 10 GB Reserve müssen frei sein.
3. **Ports prüfen.** Kollision wird gegen die **tatsächlich belegten** Ports
   geprüft, nicht gegen alle im Katalog vergebenen. Sonst bekäme fast jedes
   Spiel einen Ersatzport, obwohl nie zwei gleichzeitig laufen.
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
> would be relocated), generate two passwords, write the files, create the
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

Findet er nach sechs Stunden nichts, gibt er auf und meldet sichtbar:
**„KEIN Passwortfeld gefunden – der Server läuft ohne Beitrittspasswort."**
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
