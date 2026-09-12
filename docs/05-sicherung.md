# 05 — Sicherung und Wiederherstellung

Borg über Tailscale auf einen Sicherungsserver. Ein Archiv **je Spiel**, alle 15
Minuten für laufende Server, täglich vollständig.

> *Borg over Tailscale to a backup host. One archive per game, every 15 minutes
> for running servers, plus a full daily run.*

---

## Sicherung abschalten

`BORG_REPO=aus` in `konfiguration.env` schaltet die Sicherung **vollständig** ab:
kein `borg`, keine Passphrase, keine Timer, keine Archivliste in der
Oberfläche — und beim Löschen eines Spielservers auch **keine letzte
Sicherung**. Gedacht für den Zustand, in dem es noch kein Sicherungsziel gibt.

Der Schalter ist der **Wert** von `BORG_REPO` und keine zweite Variable. Zwei
Variablen können sich widersprechen („Sicherung an, aber wohin?"), eine nicht.

Was dabei bewusst **nicht** verschwindet:

* `/etc/borg-ausschluss.txt` wird weiterhin eingesetzt und gepflegt.
  `spiel-verwalten` liest und schreibt sie bei jeder Installation und
  Deinstallation; fehlte sie, bräche die Deinstallation mitten im Ablauf ab.
* Die systemd-Einheiten liegen weiterhin auf der Maschine, nur abgeschaltet.
  Einschalten ist dann eine Zeile in `konfiguration.env` plus
  `install/50-sicherung.sh`.

Und was dabei **sichtbar** wird: Die Übersicht trägt einen Warnkasten, und die
Löschbestätigung eines Spielservers sagt ausdrücklich, dass der Stand danach weg
ist. Der gefährliche Zustand ist nicht „abgeschaltet", sondern „abgeschaltet, und
keiner weiß es" — dann verlässt man sich auf ein Netz, das nicht da ist.

`werkzeuge/abgleich.sh` prüft nicht nur die Dateien, sondern ob die Timer
**laufen**: eingesetzte, aber abgeschaltete Einheiten sehen im Dateivergleich
tadellos aus, während nichts gesichert wird.

> *`BORG_REPO=aus` disables backups entirely: no borg, no passphrase, no timers,
> no archive list in the panel, and no final backup when a game server is
> deleted. The switch is the value of `BORG_REPO` rather than a second variable,
> because two variables can contradict each other and one cannot. Two things
> deliberately stay: the exclusion list, which `spiel-verwalten` reads and writes
> on every install and uninstall and whose absence would abort an uninstall
> mid-way; and the systemd units, merely disabled, so switching on later is one
> line plus a re-run of stage 50. Two things become visible: a warning box on the
> overview and an explicit note on the delete confirmation. The dangerous state
> is not "off" but "off and nobody knows", because then people rely on a safety
> net that is not there. `abgleich.sh` checks that the timers actually run, not
> just that the files match — installed but disabled units look perfect in a file
> comparison while nothing is backed up.*

---

## Was gesichert wird — und was nicht

Gesichert werden **Spielstände, Serverkonfiguration und die compose-Dateien**,
im täglichen Vollauf dazu `/etc` (Archiv `etc-*`) und die **Panel-Daten**
(`panel-*`): `/opt/panel/daten` mit den Benutzern samt Passwort-Hashes,
TOTP-Geheimnissen und Passkeys, den Zugangsdaten und dem Protokoll.

**Die Panel-Daten standen bis #218 in keinem Archiv.** Beim Verlust der Maschine
wären alle Anmeldungen, zweiten Faktoren und Passkeys weg gewesen, dazu das
Protokoll — aufgefallen beim Entfernen der Altdatei `konfig.json` (#216). Das
Repository ist verschlüsselt; die DNS-Zugangsdaten aus `/etc` liegen dort schon.
Beide kleinen Archive laufen ohne die Plausibilitätsprüfung der Spielstände (die
Panel-Daten sind rund 36 KB und würden als „praktisch leer" gemeldet), aber
**mit Fehlerstatus**: Die `/etc`-Sicherung scheiterte bis dahin still.

> *The daily full run also archives `/etc` (`etc-*`) and the panel data
> (`panel-*`: users with hashes, TOTP secrets and passkeys, credentials, audit
> log). The panel data was in no archive until #218 — losing the machine would
> have lost every login and second factor. Both small archives skip the
> save-size check but now report failure; the `/etc` one used to fail silently.*

Nicht gesichert wird die **Spielinstallation**. SteamCMD lädt sie jederzeit neu;
Enshrouded allein sind 8,9 GB, die sich nie ändern. Sie mitzunehmen kostet Platz
und Zeit, ohne einen einzigen Wiederherstellungsfall zu verbessern.

Die Trennlinie steht in `/etc/borg-ausschluss.txt` und ist **pro Spiel
handgearbeitet**, weil die Bilder ihre Verzeichnisse unterschiedlich anordnen:

| Spiel | Warum es nicht pauschal geht |
|---|---|
| Windrose | Unter `server/` liegt die Installation **und** `R5/Saved` — ein pauschales `server` nähme den Spielstand mit heraus |
| Palworld | Installation raus, aber `Pal/Saved` und `backups/` bleiben |
| Satisfactory | `gamefiles` und `logs` raus, `saved` und `backups` bleiben |
| Valheim (ich777) | Die Bilder von ich777 installieren das Spiel **direkt** nach `serverfiles/`, der Spielstand liegt darunter in `serverfiles/.config/unity3d/IronGate/Valheim/` — raus sind deshalb die gemessenen Brocken `valheim_server_Data` (1,9 GB), `linux64`, `docker`, `*.so` |

**Katalogspiele** bekommen ihren Block aus dem Feld `ausschluss` des Katalogs.
Bis #221 stand dort für alle ich777-Spiele nur `steamcmd` und
`serverfiles/steamapps` — dort liegen bei diesen Bildern aber nur Manifeste
(Valheim: 16 KB); die Installation selbst war in jedem Archiv. Wo die
Spielstände liegen, ist je Spiel verschieden und muss gemessen werden. Deshalb
gilt: **Ohne Messung bleibt alles drin** — lieber zu viel sichern als einen
Spielstand verfehlen.

Seit #221 füllt `werkzeuge/katalog-ausschluesse.py` alle 167 Einträge der
Bauarten `ich777` und `linuxgsm` mit den Mustern, von denen sich **belegen**
lässt, dass sie kein Spielstand sein können — geteilte Bibliotheken, Steams
Laufzeit, Unitys `*_Data` und Unreals `Engine`, `Binaries`, `Content`,
`Plugins`. Maßstab ist die gemessene Valheim-Installation: von 2,65 GB sind
1,93 GB `valheim_server_Data` und 0,31 GB `*.so` — 85 %, und keins davon kann
ein Spielstand sein, weil Unity unter `.config` speichert. Ein Probelauf von
`borg create --dry-run` auf der Maschine hat das bestätigt: Welten enthalten,
Bibliotheken draußen, Archivgröße unverändert 312,8 MB (Valheims Block deckte
den Brocken schon ab — der Gewinn liegt bei den übrigen 166 Einträgen). Die
zwölf Einträge mit eigenem Abbild rührt das Werkzeug **nicht** an: Wo ein
fremdes Bild seine Ordner anlegt, weiß nur die Messung.

Ein Muster, das ein Modverzeichnis aus `etc/spiele-mods.json` verdecken würde,
lässt das Werkzeug von selbst fallen — ein selbst hochgeladener Mod kommt aus
keiner Neuinstallation zurück. Geprüft wird dabei ohne Rücksicht auf Groß- und
Kleinschreibung: Valheims `serverfiles/BepInEx/plugins` entginge dem Muster
`serverfiles/*/Plugins` sonst nur durch das kleine p. `vollstaendigkeit.sh`
prüft beides bei jedem Lauf (vorbei: `PLATZWART_KEIN_AUSSCHLUSS_GATE=1`).

Der Block entsteht bei der Installation. Damit eine spätere Katalogänderung
auch bestehende Server erreicht, gleicht `spiel-verwalten ausschluesse` alle
installierten Katalogspiele an — Stufe 30 und `ausrollen.sh` rufen es auf,
sobald der Katalog neu eingesetzt wird. Ändert sich ein Block, wird die
gemerkte Archivgröße dieses Stacks verworfen: Die Einbruchprüfung vergleicht nur
Gleiches mit Gleichem, und ein Archiv, das jetzt absichtlich 2 GB weniger hält,
ist kein Einbruch. Dass verschachtelte und Platzhalter-Ausschlüsse eine
Wiederherstellung überleben, sichert seit #231 `panel-aktion` zu.

> *Saves, server config and compose files are backed up; the game installation is
> not — SteamCMD refetches it, and Enshrouded alone is 8.9 GB of never-changing
> data. The exclusion list is hand-written per game because the images lay out
> their directories differently: for several of them the installation and the
> save data share a branch, so a blanket exclusion would drop the saves.
> ich777 images install straight into `serverfiles/`, so their catalogue
> exclusions (`steamcmd`, `serverfiles/steamapps`) left the install in every
> archive (#221). Save paths must be measured per game; without a measurement
> everything stays in. Since #221 `werkzeuge/katalog-ausschluesse.py` fills all
> 167 `ich777`/`linuxgsm` entries with patterns that can be *shown* not to be a
> save — shared libraries, the Steam runtime, Unity's `*_Data`, Unreal's
> `Engine`, `Binaries`, `Content`, `Plugins`. The yardstick is the measured
> Valheim install: 1.93 GB of its 2.65 GB is `valheim_server_Data` and 0.31 GB
> is `*.so` — 85 %, none of which can be a save because Unity stores under
> `.config`; a `borg create --dry-run` on the machine confirmed worlds in,
> libraries out, archive size unchanged at 312.8 MB. The twelve own-image
> entries are left alone. Any pattern that would cover a mod directory from
> `etc/spiele-mods.json` is dropped automatically, compared case-insensitively
> so that Valheim's `serverfiles/BepInEx/plugins` does not survive by its lower
> case p alone; `vollstaendigkeit.sh` checks both on every run.
> `spiel-verwalten ausschluesse`
> brings catalogue changes to installed servers (stage 30 and `ausrollen.sh`
> call it) and forgets the remembered archive size of a changed stack, so an
> intended shrink is not reported as a collapse.*

Katalog-Installationen ergänzen ihren eigenen Block automatisch:

```
# >>> panel:necesse (automatisch, nicht von Hand aendern)
sh:/srv/games/necesse/steamcmd
sh:/srv/games/necesse/serverfiles/steamapps
# <<< panel:necesse
```

---

## Zeitplan

| Timer | Wann | Was |
|---|---|---|
| `spiele-sicherung.timer` | alle 15 Minuten (`*:0/15`, ±60 s) | nur Spiele, deren **Container läuft** |
| `spiele-sicherung-voll.timer` | täglich 04:00 (±300 s) | alle Spiele, dazu `/opt/stacks` und `/etc` |

**Warum der Viertelstundenlauf gestoppte Spiele auslässt:** Ein gestopptes Spiel
ändert sich nicht. Es alle 15 Minuten erneut zu sichern erzeugt nur Archive ohne
neuen Inhalt und verwässert die Aufbewahrung — die „Sohn"-Stufe wäre binnen zwei
Tagen mit Kopien desselben Standes gefüllt.

Beide Timer sind `Persistent=true`: War die Maschine zur geplanten Zeit aus,
läuft der Lauf beim nächsten Start nach.

> *Why the quarter-hourly run skips stopped games: a stopped game does not
> change, and re-archiving it would fill the "son" tier with copies of one state
> within two days. Both timers are `Persistent=true`, so a missed run catches up
> after boot.*

**Die Läufe warten aufeinander.** Borg gibt nach **einer Sekunde** auf, wenn ein
anderer Lauf das Repositorium gesperrt hält. Am 2026-09-11 scheiterte so die
Vollsicherung: Sie startete um 04:02, während der Viertelstundenlauf von 04:00
noch sicherte. Dieselbe Kollision traf die letzte Sicherung vor dem Entfernen
eines Servers — und die bricht das Entfernen dann ab. `spiele-sicherung` ruft
Borg deshalb über eine Funktion mit `--lock-wait 900` auf
(`SICHERUNG_SPERRE_WARTEN`). 900 Sekunden liegen unter den 1800 Sekunden, die
`spiel-verwalten` auf die Endsicherung wartet. Nachgewiesen mit
`borg with-lock … sleep 30`: Die Sicherung wartete und lief durch; vorher brach
sie in derselben Lage sofort ab.

> *Runs wait for each other. Borg gives up after one second if another run
> holds the repository lock — that is how the full backup failed on 2026-09-11,
> starting at 04:02 while the 04:00 run was still going, and how the final
> backup before a removal aborted that removal. `spiele-sicherung` now calls
> Borg through a function with `--lock-wait 900`, below the 1800 s
> `spiel-verwalten` waits. Verified by holding the lock for 30 s.*

---

## Aufbewahrung (Großvater-Vater-Sohn)

| Stufe | Regel | Reichweite |
|---|---|---|
| Sohn | `--keep-within 2d` | jeder Viertelstundenstand, 2 Tage |
| Vater | `--keep-daily 14` | ein Stand je Tag, 14 Tage |
| Großvater | `--keep-weekly 8` | ein Stand je Woche, 8 Wochen |
| | `--keep-monthly 12` | ein Stand je Monat, 12 Monate |

`prune` läuft **nur innerhalb des jeweiligen Präfixes**
(`--glob-archives "<spiel>-*"`). Ohne diese Einschränkung räumte ein Spiel die
Stände eines anderen weg — die Regeln gelten dann für den gemeinsamen Topf, und
das häufig gesicherte Spiel verdrängt das seltene.

> *Retention above. `prune` is scoped per game with `--glob-archives`: without
> that, one game would evict another's archives, because the rules would apply to
> the shared pool and the frequently saved game would crowd out the rare one.*

Archivnamen: `<spiel>-JJJJMMTT-HHMMSS`, zum Beispiel `necesse-20260906-155744`.
Dieses Format ist Teil der Prüfung in `panel-aktion` — die Oberfläche akzeptiert
nur Namen dieser Form, und nur solche, die mit dem angefragten Stack beginnen.

---

## Wiederherstellung

### Über die Oberfläche

`Übersicht` → Karte des Servers → `Einstellungen` → `Sicherungen` → Stand wählen →
Rückfrage bestätigen (`verwalten` und `admin`). `panel-aktion restore` geht dann
in dieser Reihenfolge vor:

1. **Auspacken** des Archivs in ein Wegwerfverzeichnis, von `/` aus gerechnet —
   bei **laufendem** Server; das Archiv ändert sich nicht. Scheitert das, hat sich
   am Server nichts geändert.
2. Enthält das Archiv das Datenverzeichnis nicht, Abbruch — ebenfalls ohne
   Änderung.
3. Server **anhalten** (sonst schriebe er beim Beenden über das Zurückgespielte).
4. **Ist-Stand kopieren** nach `/srv/games/<stack>.vor-restore-<zeit>`; geht das
   nicht, läuft der Server wie vorher weiter.
5. **Ausgeschlossene Pfade beiseitelegen** (siehe unten); scheitert das, wird
   nichts gelöscht.
6. Datenverzeichnis leeren, Stand hineinkopieren, ausgeschlossene Pfade an
   denselben Ort zurücklegen.
7. **Eigentümer** vom Ist-Stand übernehmen, nicht hart 4711 — FOUNDRYs Image
   läuft fest als uid 1000.
8. Wieder starten — nur, wenn er vorher lief.

Die Meldung nennt den Ort der Kopie aus Schritt 4. Sie gehört nach der Prüfung
gelöscht (`werkzeuge/aufraeumen.sh --mit-restore-kopien`), sonst sichert der
nächste Volllauf sie mit.

> *Through the panel: overview → the server's card → settings → backups → pick a
> state → confirm (verwalten and admin). `panel-aktion restore` then proceeds in
> this order: extract the archive into a scratch directory while the server keeps
> running (a failure changes nothing); abort if the archive lacks the data
> directory; stop the server so it cannot write over the restored state on
> shutdown; copy the current state to `<dir>.vor-restore-<time>` (if that fails,
> the server keeps running); move the excluded paths aside (if that fails,
> nothing is deleted); empty the directory, copy the state in, put the excluded
> paths back at the same place; take ownership from the previous state rather
> than forcing 4711; restart only if it was running. The message names the
> copy's location — delete it after checking, or the next full run archives it
> too.*

**Während einer Sicherung wird gewartet.** Der 15-Minuten-Lauf hält das
Repository rund vier Minuten gesperrt. Bis #234 scheiterten Liste, Größe,
Download und Wiederherstellung in dieser Zeit sofort mit „Repository nicht
erreichbar" — beim ersten echten Versuch dreimal hintereinander. Jetzt warten sie
auf die Sperre (Liste und Größe bis 150 s, Auspacken bis 10 min), und
scheitern sie doch daran, sagt die Meldung „Gerade läuft eine Sicherung".
Die Wiederherstellung packt das Archiv **zuerst** aus, bei laufendem Server:
Früher hielt sie ihn vorher an und ließ ihn aus, wenn das Auspacken scheiterte.

> *Waiting during a backup: the 15-minute run holds the repository lock for
> about four minutes. Until #234, list, size, download and restore failed at
> once during that time with "repository unreachable" — three times in a row on
> the first real attempt. They now wait for the lock (list and size up to 150 s,
> extraction up to 10 minutes, download up to 15), and if they still fail on it,
> the message says "a backup is running". The restore extracts first, while the
> server runs; it used to stop the server first and leave it stopped when
> extraction failed.*

**Ausgeschlossene Pfade überleben das Zurückspielen.** Die Spielinstallation
steht bewusst nicht im Archiv; das Datenverzeichnis wird vor dem Kopieren aber
geleert. `panel-aktion` legt deshalb vorher jeden Pfad aus
`/etc/borg-ausschluss.txt` weg, der unter dem Datenverzeichnis liegt, und
danach **an denselben relativen Ort** zurück. Die erste Fassung verschob jede
Zeile wörtlich und legte sie mit `basename` zurück (#231): Zeilen mit
Platzhalter (`sh:/srv/games/*/server/*.dat`) fanden nichts — Enshrouded hätte
32 Spieldateien zu je rund 250 MB verloren, Palworld `steamclient.so` —, und
verschachtelte Pfade kamen ganz oben an (Windroses `server/R5/Content` als
`windrose/Content`). Jetzt werden Platzhalter wie in Borgs `sh:`-Stil
aufgelöst (`*` innerhalb eines Pfadteils), nichts unterhalb eines schon
gewählten Pfades doppelt, und scheitert das Weglegen, wird nichts gelöscht.
Geprüft an einem Nachbau der Lagen von Windrose, Enshrouded und Valheim: jede
Datei am alten Ort, der Spielstand aus dem Archiv. Dieselbe Musterregel gilt
jetzt in der Sicherungsprobe und in `mod-verwalten` (beide verglichen vorher
mit `startswith`, ein `*` passte nie).

> *Excluded paths survive the restore: moved away before the data dir is
> emptied and put back at the same relative place. The first version moved
> each line literally and restored by basename (#231) — glob lines matched
> nothing (Enshrouded would have lost 32 data files), nested paths came back
> at the top. Globs are now expanded like borg's sh: style; the same rule is
> used by the backup probe and mod-verwalten.*

### Von Hand

```bash
export BORG_PASSPHRASE=$(cat /root/.borg-passphrase)
export BORG_RSH="ssh -o BatchMode=yes"
REPO="ssh://borg@<ziel>/backup/gameserver/gameserver.borg"

borg list --short "$REPO" | grep '^necesse-' | tail -20     # Stände ansehen
docker compose -f /opt/stacks/necesse/compose.yaml down     # Server anhalten

cd / && borg extract "$REPO::necesse-20260906-155744"       # zurückspielen
chown -R 4711:4711 /srv/games/necesse                       # Rechte richten

docker compose -f /opt/stacks/necesse/compose.yaml up -d
```

**`borg extract` läuft von `/` aus**, weil die Archive absolute Pfade enthalten.
Aus einem anderen Verzeichnis heraus entsteht ein Unterbaum `srv/games/…` an der
falschen Stelle, und der Server startet mit leerer Welt — ohne Fehlermeldung.

**`chown` danach ist keine Kür.** Borg stellt die Eigentümer wieder her, aber ein
Auspacken in ein neu angelegtes Verzeichnis oder auf einer frisch aufgesetzten
Maschine kann daneben liegen. Ein Spielserver, der seine Welt nicht schreiben
kann, verliert den Fortschritt der Sitzung.

> *Restore via the panel, or by hand as shown. `borg extract` must run from `/`
> because archives hold absolute paths — from anywhere else it creates a stray
> `srv/games/…` subtree and the server starts with an empty world, silently.
> The `chown` afterwards is not optional: a game server that cannot write its
> world loses the session's progress.*

### Ganzer Server verloren

**Geführt:** `install/assistent.sh`, Weg 2 „Wiederaufbau" — er erledigt die
Schritte unten in einer durchdachten Reihenfolge (Stufe 50 erst **nach** dem
Zurückspielen, sonst sichert ihr Probelauf eine leere Maschine), wählt je Präfix
das neueste Archiv vor seinem Start und übernimmt DNS-Token und Webhooks auf
Rückfrage aus `etc-*`; die Katalogblöcke der Ausschlussliste baut
`spiel-verwalten katalog-abgleich` neu. Beschrieben in
[11-neueinrichtung.md](11-neueinrichtung.md#9-wiederaufbau-aus-der-sicherung).
Von Hand:

> *Guided: `install/assistent.sh`, path 2 "rebuild", does the steps below in a
> considered order (stage 50 only after the restore, or its test run backs up an
> empty machine), picks per prefix the newest archive before its start and takes
> DNS token and webhooks from `etc-*` on request; `katalog-abgleich` rebuilds the
> exclusion list's catalogue blocks. Described in 11-neueinrichtung.md. By hand:*

1. Neue Maschine nach [02-installation.md](02-installation.md) aufsetzen,
   Stufen 10 bis 50.
2. **Borg-Passphrase** von ihrem zweiten Ablageort holen und nach
   `/root/.borg-passphrase` legen (`0600`).
3. Die compose-Dateien zurückholen — sie liegen im Archiv `config-*`:
   ```bash
   cd / && borg extract "$REPO::config-20260906-040000"
   ```
4. Je Spiel den letzten Stand auspacken (siehe oben) — auf einer **neuen**
   Maschine mit `--numeric-ids`: Ohne den Schalter stellt Borg Eigentümer nach
   **Namen** her, und trägt die neue Maschine denselben Benutzernamen unter
   einer anderen UID, gehört die Welt danach der falschen Nummer. Container
   kennen nur Nummern (FOUNDRY läuft fest als 1000). Im Container nachgestellt:
   ohne den Schalter kam UID 1000 als 1001 zurück.
   ```bash
   cd / && borg extract --numeric-ids "$REPO::<spiel>-<zeitstempel>"
   ```
5. **Panel-Daten** zurückholen — Benutzer, zweite Faktoren, Passkeys,
   Zugangsdaten, Protokoll:
   ```bash
   cd / && borg extract "$REPO::panel-<zeitstempel>"
   systemctl restart panel
   ```
   Eigentümer und Rechte kommen mit (`panel:panel`, `nutzer.json` `0600`).
   Hat Stufe 30 schon einen neuen ersten Benutzer angelegt, ersetzt das
   Auspacken ihn — gewollt, denn danach gelten die alten Anmeldungen wieder.
   Probeweise ausgepackt am 2026-09-11: `nutzer.json` und `zugangsdaten.json`
   bytegleich mit den laufenden. Mit dem Archiv kommen auch der Steam-Schlüssel,
   die Zugänge für TeamSpeak und Discord und die Kanalzuordnung zurück.
6. `/etc` aus dem Archiv `etc-*` nur **gezielt** zurückholen, was fehlt —
   `/etc/dns-gameserver.conf`, `/etc/platzwart-melden.conf`,
   `/etc/borg-ausschluss.txt` mit den Katalogblöcken —, nicht das ganze
   Verzeichnis über eine frische Maschine legen.
7. Container starten, DNS mit `dns-pflegen setzen <name>` neu eintragen.
8. Die Schalter je Server von Hand wieder setzen: Auto-Update und Leerlauf
   stehen in `/var/lib/…liste` und sind **in keinem Archiv**.

> *Total loss: rebuild stages 10–50, restore the passphrase from its off-host
> copy, extract the `config-*` archive for the compose files, extract each game's
> latest state (on a new machine with `--numeric-ids` — by name, a same-named
> user with another uid would own the world and a fixed-uid container could no
> longer write; reproduced: uid 1000 came back as 1001), extract the `panel-*` archive (users, second factors, passkeys,
> credentials, audit log, the Steam key, the TeamSpeak and Discord logins and the
> channel mapping — owner and modes come along) and restart the panel, take only
> the missing files from the `etc-*` archive (DNS token, webhook file, exclusion
> list) rather than laying the whole directory over a fresh machine, start the
> containers and re-create the DNS records, and set the per-server switches for
> auto-update and idle sleep again by hand — their lists under `/var/lib` are in
> no archive.*

---

## Wenn ein Archiv nichts enthält

Am 2026-09-10 stellte sich heraus, dass FOUNDRY seit dem 06.09. gesichert wurde
und **jedes Archiv zwei Dateien enthielt** — vier leere Verzeichnisse. Der Lauf
meldete jedes Mal Erfolg, der Rückgabewert war 0, das Archiv entstand.

```
borg info … foundry-20260910-164531
Number of files: 2
```

Das ist nicht „der Spielstand fehlt", sondern das Schlimmere: **Das Netz meldet
sich heil und fängt nichts.** Eine Wiederherstellung hätte eine leere Welt
wiederhergestellt, und keine Überwachung hätte den Unterschied gesehen — weil
alles, was sie prüft, in Ordnung war.

`spiele-sicherung` prüft deshalb nach jedem Archiv zwei Dinge, und **die erste
Prüfung ist die wichtigere**:

| Prüfung | Schlägt an bei | Findet |
|---|---|---|
| **Untergrenze** | unter 50 kB | ein Archiv, das von Anfang an leer ist |
| **Einbruch** | unter 25 % des letzten Laufs | etwas, das Inhalt hatte und ihn verliert |

Ohne die Untergrenze hätte es FOUNDRY **nie** gefunden: Ein Vergleich mit dem
Vorgänger schlägt nicht an, wenn der genauso leer war.

**Gemessen wird die Größe, nicht die Dateizahl.** Der erste Entwurf zählte
Dateien und meldete prompt `satisfactory` als praktisch leer — dort liegen genau
vier `.sav`-Dateien, und das *ist* der vollständige Spielstand. Vier Dateien mit
258 kB und zwei mit 13 kB sehen als Zahl ähnlich aus und sind es nicht. Ein
Fehlalarm ist hier besonders teuer: Diese Meldung soll man ernst nehmen, und
eine, die bei einem gesunden Spiel losgeht, nimmt man nach dem zweiten Mal nicht
mehr ernst.

Die Größe kommt aus `borg create --stats` — ein zweiter borg-Aufruf nur zum
Messen wäre bei einem Lauf alle 15 Minuten unnötig teuer. Gemerkt wird sie in
`/var/lib/spiele-sicherung.groessen`, und zwar **nach** der Prüfung; sonst
verglichen die folgenden Läufe gegen den eingebrochenen Wert und schwiegen.

Die Umrechnung der Einheit steht in einer **eigenen Funktion**. Im ersten
Entwurf stand das `awk`-Programm mitten in der Aufrufzeile, und die
verschachtelten Anführungszeichen zerbrachen dabei (`awk: runaway string
constant`). Der Lauf meldete daraufhin für fünf Spiele `Exit 2`, **obwohl die
Sicherung selbst durchgelaufen war** — ein Werkzeug, dessen Auswertung den
ganzen Lauf scheitern lässt, ist schlimmer als eines ohne Auswertung.

> *On 2026-09-10 it turned out that FOUNDRY had been backed up since 06.09. with
> two files in every archive — four empty directories — while each run reported
> success, returned 0 and created its archive. Not "the save is missing" but the
> worse thing: the net reports itself intact and catches nothing; a restore would
> have restored an empty world, and no monitoring would have seen the
> difference, because everything it checked was fine. `spiele-sicherung` now
> checks every archive twice, the first check being the more important: a floor
> (under 50 kB, finds an archive empty from the start) and a collapse (under 25 %
> of the previous run, finds content being lost). Without the floor FOUNDRY
> would never have been found — comparing with the predecessor does not fire
> when that one was equally empty. Size is measured, not file count: the first
> draft counted files and promptly flagged satisfactory, whose four `.sav` files
> are the complete save; a false alarm is especially costly here. The size comes
> from `borg create --stats` rather than a second borg call, and is stored in
> `/var/lib/spiele-sicherung.groessen` after the check, or later runs would
> compare against the collapsed value and stay quiet. The unit conversion lives
> in a function of its own: in the first draft the awk program sat inline, its
> nested quotes broke ("runaway string constant"), and the run reported exit 2
> for five games although the backup itself had completed — an evaluation that
> fails the whole run is worse than none.*

### Die dritte Prüfung: hat sich überhaupt noch etwas geändert?

Die beiden Prüfungen oben messen die **Größe**. Ein Spielstand, der einmal
geschrieben und nie wieder angefasst wurde, behält seine Größe: Er kommt durch
die Untergrenze (genug Inhalt) *und* durch den Einbruchsvergleich (nichts
gefallen) — alle 15 Minuten, für immer. Das Archiv ist dann eine treue Kopie
einer Welt, die vor Tagen aufhörte, geschrieben zu werden.

Erkannt wurde also ein Netz, das **nie** etwas gefangen hat — aber nicht eines,
das **aufgehört** hat.

**Das Signal dafür kostet nichts.** `borg create --stats` nennt die
deduplizierte Größe, also was gegenüber dem letzten Lauf wirklich neu ist.
Gemessen am 2026-09-10:

| Spiel | insgesamt | davon neu |
|---|---|---|
| `windrose` (schreibt gerade) | 76,05 MB | **181,31 kB** |
| `satisfactory` (schreibt nicht) | 259,05 kB | **639 B** |
| `teamspeak` (nur Konfiguration) | 252,26 kB | **643 B** |

Die rund 640 Byte sind Borgs eigene Verwaltungsdaten — das ist der Boden. Alles
darüber heißt: es hat sich etwas geändert. Und das braucht **kein Wissen
darüber, wie ein einzelnes Spiel seine Stände ablegt**; genau daran wäre eine
Lösung über Dateimuster gescheitert, die bei Valheim und FOUNDRY das Falsche traf.

**Zwei Bedingungen müssen zusammenkommen**, sonst meldet die Prüfung Unsinn:

* seit **24 Stunden** kam nichts Neues dazu, **und**
* der Container läuft auch schon so lange.

„Läuft seit gestern und hat nichts geschrieben" ist eine Aussage. „Wurde vor
zehn Minuten gestartet" ist keine, egal wie alt der Spielstand ist.

Gespeichert wird der **Zeitpunkt der letzten echten Änderung**, nicht die Zahl
stiller Läufe: Ein Neustart des Zeitgebers würde einen Zähler zurücksetzen und
die Stille von vorn beginnen lassen.

**Ausgenommen ist, was von Natur aus tagelang nichts schreibt** — voreingestellt
`teamspeak`, dessen Daten Konfiguration und eine Datenbank sind, die sich nur
ändert, wenn jemand Kanäle umbaut. Eine Regel, die das meldet, wird
stummgeschaltet und nimmt die echten Funde mit. Änderbar über
`SICHERUNG_OHNE_ALTERSPRUEFUNG`.

**Was die Prüfung sichtbar machen wird:** Zwei der sieben Stacks tragen einen
Schalter, der das Spiel anhält, wenn niemand drauf ist — FOUNDRYs
`PAUSE_SERVER_WHEN_EMPTY` und Satisfactorys `AUTOPAUSE`. Am 2026-09-10 hatte
Satisfactory seit **17,6 Stunden** nichts geschrieben, während der Server lief.
Ob das für dieses Abbild normal ist, hat bis dahin **niemand gemessen** — und
die Prüfungen, die es gab, hätten es nicht gesagt.

> *The two checks above measure size. A save written once and never touched keeps
> its size and passes both forever, while the archive is a faithful copy of a
> world that stopped being written days ago — so a net that never caught anything
> was detected, but not one that stopped catching. The signal costs nothing:
> `--stats` reports the deduplicated size, i.e. what is genuinely new since the
> last run, and roughly 640 bytes is borg's own bookkeeping floor. It needs no
> per-game knowledge of where saves live, which is exactly what a file-pattern
> approach got wrong for Valheim and FOUNDRY. Two conditions must coincide:
> nothing new for 24 hours AND the container up that long — "running since
> yesterday and wrote nothing" is a statement, "started ten minutes ago" is not.
> The moment of the last real change is stored rather than a count of quiet runs,
> so restarting the timer does not restart the silence. Exempt by default is
> `teamspeak`, whose data legitimately sits unchanged for days; a rule that flags
> it gets muted and takes the real findings with it.*

### Was der Selbsttest beweist

```bash
spiele-sicherung --selbsttest
```

Die drei Prüfungen oben wurden bei ihrer Entstehung sorgfältig belegt — die
Nachweise standen aber in Pull-Request-Beschreibungen, also an einem Ort, an dem
sie sich nicht noch einmal ausführen lassen. Jetzt stehen die Fälle im Skript
selbst und laufen wieder.

Geprüft werden **zwei verschiedene Dinge**, und das zweite ist das, was schon
zweimal gefehlt hat:

**1. Entscheiden die Prüfungen richtig?** Die Entscheidungen sind dafür vom
Melden getrennt — `befund_leer`, `befund_einbruch`, `befund_neu`,
`ist_ausgenommen` und `befund_still` fassen weder eine Datei noch Docker an.
Neben jedem stillen Fall steht einer, der melden *muss*, und wo eine Schwelle
liegt, stehen beide Werte daneben: 2047 Byte gelten als „nichts Neues", 2048
nicht. Die Ausnahmeliste wird in beide Richtungen geprüft — `teamspeak` still,
`windrose` meldet, und `team` ist kein Treffer, weil `grep -w` auf ganze Wörter
sieht.

**2. Sind die Helfer an dieser Stelle überhaupt definiert?** Bash definiert eine
Funktion erst, wenn die Zeile ausgeführt wird. Der Selbsttest steht dort, wo auch
die Schleife läuft — was hier fehlt, findet sie ebenso wenig. Am 2026-09-10 ist
genau das an *einem Tag zweimal* passiert: erst `in_bytes`, dann `melden`, beide
hinter der Schleife, beide zur Laufzeit `command not found`, und beide Male
meldete der Lauf Erfolg und schrieb „Sicherung abgeschlossen".

Das ist der Grund, warum die zweite Prüfung nicht überflüssig ist: **Die
Rechnungen waren richtig und lieferten nichts.** Ein Test, der nur rechnet, hätte
das nie gesehen.

Der Selbsttest braucht weder Borg noch die Passphrase noch Docker — er wird
deshalb erkannt, *bevor* die Passphrase gelesen wird, und läuft auf jeder
Maschine.

> *The three checks above were carefully proven when written, but the proofs sat
> in pull request descriptions, where they cannot be run again. The cases now
> live in the script. Two different things are checked. First, whether the checks
> decide correctly: the decisions are separated from the reporting into pure
> functions touching neither files nor Docker, each silent case paired with one
> that must report, and both values quoted wherever a threshold sits — 2047 bytes
> count as "nothing new", 2048 does not; the exemption list is tested in both
> directions, including that `team` does not match `teamspeak`, because `grep -w`
> looks at whole words. Second, whether the helpers are defined at that point at
> all: bash defines a function when the line runs, the self-test sits where the
> loop sits, and what is missing here is missing there. On 2026-09-10 that
> happened twice in one day — first `in_bytes`, then `melden`, both behind the
> loop, both `command not found` at runtime while the run reported success. That
> is why the second check is not redundant: the arithmetic was right and
> delivered nothing, and a test that only does arithmetic would never have seen
> it. It needs neither borg nor the passphrase nor Docker, so it is recognised
> before the passphrase is read and runs anywhere.*

### Und dieselbe Prüfung bei jedem Lauf

Der Selbsttest steht an genau der Stelle, an der die Schleife läuft — er **fängt**
den Reihenfolgefehler also. Gemessen, mit `in_bytes()` versuchsweise dahinter:

```
spiele-sicherung --selbsttest    ->  FEHLER  in_bytes() ist hier NICHT definiert
spiele-sicherung --nur teamspeak ->  Sicherung abgeschlossen
```

Der Selbsttest sieht es. **Der echte Lauf im selben Zustand meldet weiter
Erfolg.** Und das Fehlerbild, gegen das hier gebaut wird, ist genau „hastige
Änderung, danach kein Selbsttest" — beide Vorfälle des 2026-09-10 waren das.

Deshalb steht dieselbe Prüfung noch einmal unmittelbar vor der Schleife, bei
jedem Lauf. Fünf `declare`-Aufrufe kosten nichts und machen aus dem stillen
Erfolg ein Abbrechen mit Rückgabewert **3**:

```
ABBRUCH: in_bytes() ist an dieser Stelle noch nicht definiert.
  Die Funktion steht hinter der Schleife, die sie ruft. Bash definiert
  erst beim Ausfuehren - der Lauf wuerde sonst Erfolg melden und nichts tun.
```

> *The self-test sits exactly where the loop runs, so it does catch the ordering
> trap. But a real run in the same state still reports success — and the failure
> guarded against is precisely "hasty edit, no self-test", which is what both
> incidents of that day were. So the same check runs immediately before the loop
> on every run, turning a silent success into exit 3.*


### Einmal am Tag, nicht alle drei Stunden

Diese beiden Meldungen gehen mit einer Ruhezeit von **einem Tag** hinaus. Der
Lauf kommt alle 15 Minuten; mit der üblichen Sperre von drei Stunden wären das
acht Nachrichten täglich über ein längst bekanntes Problem, und nach dem zweiten
Tag liest sie niemand mehr. Ein Fund, der sich selbst in die Bedeutungslosigkeit
nagt, ist so gut wie keiner.

Die Meldung über eine **fehlgeschlagene** Sicherung bleibt bei drei Stunden —
die ist dringend.

> *Once a day, not every three hours: the floor, collapse and silence findings go
> out with a one-day quiet period. The run comes every 15 minutes; with the usual
> three-hour lock that would be eight messages a day about a long-known problem,
> and after the second day nobody reads them — a finding that grinds itself into
> irrelevance is as good as none. The message about a failed backup keeps three
> hours: that one is urgent.*

## Probeweise zurückspielen, ohne den Server anzufassen

Die echte Wiederherstellung hält einen Server an, löscht seine Daten und
schreibt das Archiv darüber — sie braucht deshalb ein ausdrückliches Okay. Aber
die Hälfte, die die wichtige Frage beantwortet, braucht **keinen Stillstand**:

```bash
sicherung-probe <spiel>              # neuestes Archiv
sicherung-probe <spiel> --archiv X   # ein bestimmtes
sicherung-probe --selbsttest
```

Auspacken in ein Wegwerfverzeichnis, hineinsehen, wegwerfen. Gemeldet wird, ob
es sich überhaupt auspacken lässt, was herauskommt (Dateien, Größe, jüngste
Datei) und wie das zu dem steht, was jetzt auf der Platte liegt.

**Eine Sicherung, die nie zurückgespielt wurde, ist eine Behauptung.** Am
2026-09-10 kamen drei Funde mit derselben Form zusammen — FOUNDRYs hohle
Archive, die Lücke bei stehengebliebenen Ständen, der blinde Abgleich. Jedes Mal
meldete sich etwas heil, ohne dass jemand hineingesehen hatte.

> *The real restore stops a server, deletes its data and writes the archive over
> it, so it needs an explicit go-ahead. The half that answers the important
> question needs no outage: extract into a scratch directory, look inside, throw
> it away. The report says whether it extracts at all, what comes out (files,
> size, newest file) and how that compares with what is on disk now. A backup
> that was never restored is a claim: on 2026-09-10 three findings of the same
> shape came together — FOUNDRY's hollow archives, the gap for saves that stopped
> changing, the blind comparison tool — each time something reported itself
> intact without anybody having looked inside.*

### Was es nicht tut

* **Es schreibt nie nach `/srv/games`.** `borg extract` schreibt relativ zum
  aktuellen Verzeichnis, und die Archive tragen absolute Pfade. Aus `/`
  gestartet, schriebe es direkt über den laufenden Server — das ist genau der
  Unterschied zwischen dieser Probe und der echten Wiederherstellung. Die Probe
  startet deshalb **zwingend** aus dem Wegwerfverzeichnis.
* **Es lässt nichts liegen**, auch nicht bei Fehlern. Mehrere GB unter `/tmp`,
  die niemand wegräumt, füllen die Platte — und dann scheitert als Erstes die
  Sicherung.
* **Es läuft nicht auf einem Zeitgeber.** Jede Nacht einige GB auszupacken, um
  etwas zu beweisen, kostet mehr, als es belegt.
* **Es bricht ab, wenn der Platz nicht reicht** — mindestens 10 GB müssen
  danach frei bleiben. Eine Probe, die die Platte füllt, bräche genau die
  Sicherung, die sie prüfen soll.

> *What it does not do: it never writes to `/srv/games` — `borg extract` writes
> relative to the current directory and the archives carry absolute paths, so
> started from `/` it would write straight over the running server; the probe
> therefore always starts from its scratch directory. It leaves nothing behind,
> not even on errors — several GB under `/tmp` nobody removes fill the disk, and
> then the backup fails first. It runs on no timer: extracting several GB every
> night to prove something costs more than it shows. And it refuses when space is
> short — at least 10 GB must remain free, since a probe filling the disk would
> break the very backup it checks.*

### Der Vergleich rechnet die Ausschlüsse heraus

Sonst wäre er Äpfel gegen Obstkörbe: Valheims Archiv hält 2,4 GB, das
Verzeichnis auf der Platte ein Mehrfaches — die Spielinstallation ist
ausgeschlossen, weil sie sich neu herunterladen lässt. Jedes gesunde Archiv sähe
dann aus, als halte es nur einen Bruchteil. Gelesen wird die echte
`/etc/borg-ausschluss.txt`.

Bis #231 verglich die Probe mit `startswith` — Zeilen mit Platzhalter wirkten
nie. Für Enshrouded meldete sie deshalb „Das Archiv hält nur 0 %" (70,8 MB im
Archiv gegen 9 GB live, davon fast alles Installation) — ein Fehlalarm, der
den Befund dort wertlos machte. Mit Borgs Musterregel: 33 Dateien und 70,8 MB
auf beiden Seiten.

> *The comparison subtracts the exclusions, or it would compare apples with fruit
> baskets: Valheim's archive holds 2.4 GB, the directory on disk several times
> that, because the game installation is excluded as re-downloadable — every
> healthy archive would look like a fraction. The real exclusion file is read.
> Until #231 the probe compared with `startswith`, so glob lines never applied:
> for Enshrouded it reported "the archive holds only 0 %" (70.8 MB against 9 GB
> live, almost all installation), a false alarm that made the finding
> worthless. With borg's pattern rule: 33 files and 70.8 MB on both sides.*

### Die Probe wartet auf die Sicherung

Die Sicherung läuft alle 15 Minuten und hält dabei die Sperre des Repositoriums.
Der erste Lauf gegen Valheim brach genau daran ab, während nebenan `borg create`
lief. Die Probe ist nicht eilig und wartet jetzt bis zu 15 Minuten
(`--lock-wait`), statt zu scheitern.

> *The probe waits for the backup: that runs every 15 minutes and holds the
> repository lock meanwhile. The first run against Valheim broke off on exactly
> that while `borg create` ran next door. The probe is in no hurry and now waits
> up to 15 minutes (`--lock-wait`) instead of failing.*

### Was sie am ersten Tag gefunden hat

Beim Test gegen FOUNDRY meldete sie **12,7 MB mit einer Datei von 18:13** — wo
am Nachmittag zwei leere Verzeichnisse gelegen hatten. Damit war bewiesen, dass
das Abschalten von `PAUSE_SERVER_WHEN_EMPTY` #138 **doch** behoben hatte. Ich
hatte das eine Stunde zuvor verworfen, nach sieben Minuten Warten; der erste
Autosave kommt aber erst rund elf Minuten nach dem Start. Das Werkzeug fand, was
der zweite Blick übersehen hatte.

> *The real restore stops a server and writes the archive over it, so it needs
> explicit approval — but the half that answers the important question needs no
> outage: extract to a scratch directory, look inside, throw away. A backup that
> was never restored is a claim. It never writes into /srv/games — borg extract
> writes relative to the current directory, and from "/" it would overwrite the
> live server, which is exactly the difference from a real restore. It never
> leaves its scratch directory behind, does not run on a timer, and refuses when
> space is short. The live comparison excludes the backup's own exclusions, or
> every healthy archive would look like a fraction. It waits for the 15-minute
> backup's lock rather than failing. On its first day it proved that turning off
> PAUSE_SERVER_WHEN_EMPTY had fixed #138 after all — which I had rejected an hour
> earlier after waiting seven minutes, when the first autosave comes after
> eleven.*

## Prüfen

```bash
systemctl list-timers --no-pager | grep sicherung      # laufen die Zeitpläne?
journalctl -u spiele-sicherung -n 30 --no-pager        # letzter Lauf
borg list --short "$REPO" | tail -20                   # jüngste Archive
borg info "$REPO"                                      # Größe, Verdichtung
borg check --repository-only "$REPO"                   # Unversehrtheit
spiele-sicherung --selbsttest                          # entscheiden die Prüfungen richtig?
```

Eine gute Zahl ist erst dann beruhigend, wenn sie auch schlecht werden könnte.
Bei `borg list` heißt das: Steht dort ein Archiv von **heute**? Eine lange Liste
alter Archive sieht gesund aus und ist es nicht.

> *Checks above. A reassuring number only counts if it could have gone bad: with
> `borg list`, the question is whether there is an archive from today. A long list
> of old archives looks healthy and is not.*

---

## Die Passphrase

`/root/.borg-passphrase`, `0600 root`. Sie ist der **einzige** Schlüssel zum
Repositorium.

Eine Kopie gehört an einen zweiten Ort **außerhalb dieses Servers**. Geht die
Maschine verloren — und genau dafür ist die Sicherung da —, ist ein
verschlüsseltes Repositorium ohne Passphrase wertlos. Ein Passwortmanager oder
ein Zettel im Ordner sind beide besser als nichts.

> *The passphrase is the only key to the repository. Keep a copy off this host: a
> lost machine is exactly the case the backup exists for, and without the
> passphrase an encrypted repository is worthless.*
