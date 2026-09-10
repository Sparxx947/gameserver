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

Gesichert werden **Spielstände, Serverkonfiguration und die compose-Dateien**.

Nicht gesichert wird die **Spielinstallation**. SteamCMD lädt sie jederzeit neu;
Enshrouded allein sind 8,9 GB, die sich nie ändern. Sie mitzunehmen kostet Platz
und Zeit, ohne einen einzigen Wiederherstellungsfall zu verbessern.

Die Trennlinie steht in `/etc/borg-ausschluss.txt` und ist **pro Spiel
handgearbeitet**, weil die Bilder ihre Verzeichnisse unterschiedlich anordnen:

| Spiel | Warum es nicht pauschal geht |
|---|---|
| Windrose | Unter `server/` liegt die Installation **und** `R5/Saved` — ein pauschales `server` nähme den Spielstand mit heraus |
| StarRupture | Installation und `StarRupture/Saved` teilen sich denselben Zweig |
| Palworld | Installation raus, aber `Pal/Saved` und `backups/` bleiben |
| Satisfactory | `gamefiles` und `logs` raus, `saved` und `backups` bleiben |

> *Saves, server config and compose files are backed up; the game installation is
> not — SteamCMD refetches it, and Enshrouded alone is 8.9 GB of never-changing
> data. The exclusion list is hand-written per game because the images lay out
> their directories differently: for several of them the installation and the
> save data share a branch, so a blanket exclusion would drop the saves.*

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

`Übersicht` → Karte des Servers → `Archive` → Stand wählen → Rückfrage
bestätigen. Der Server wird angehalten, das Archiv ausgepackt, der Server wieder
gestartet — sofern er vorher lief.

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

1. Neue Maschine nach [02-installation.md](02-installation.md) aufsetzen,
   Stufen 10 bis 50.
2. **Borg-Passphrase** von ihrem zweiten Ablageort holen und nach
   `/root/.borg-passphrase` legen (`0600`).
3. Die compose-Dateien zurückholen — sie liegen im Archiv `config-*`:
   ```bash
   cd / && borg extract "$REPO::config-20260906-040000"
   ```
4. Je Spiel den letzten Stand auspacken (siehe oben).
5. Container starten, DNS mit `dns-pflegen setzen <name>` neu eintragen.

> *Total loss: rebuild stages 10–50, restore the passphrase from its off-host
> copy, extract the `config-*` archive for the compose files, extract each game's
> latest state, start the containers and re-create the DNS records.*

---

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

### Einmal am Tag, nicht alle drei Stunden

Diese beiden Meldungen gehen mit einer Ruhezeit von **einem Tag** hinaus. Der
Lauf kommt alle 15 Minuten; mit der üblichen Sperre von drei Stunden wären das
acht Nachrichten täglich über ein längst bekanntes Problem, und nach dem zweiten
Tag liest sie niemand mehr. Ein Fund, der sich selbst in die Bedeutungslosigkeit
nagt, ist so gut wie keiner.

Die Meldung über eine **fehlgeschlagene** Sicherung bleibt bei drei Stunden —
die ist dringend.

> *FOUNDRY had been backed up since 06.09. with two files in every archive: four
> empty directories, reported as success every time. Not "the save is missing"
> but the worse thing — the safety net reporting itself intact while holding
> nothing; a restore would have restored an empty world and no monitoring would
> have seen the difference, because everything it checks was fine. Two checks
> now follow every archive, and the absolute floor matters more than the drop:
> comparing against the previous archive never fires when that one was equally
> empty. Size rather than file count: the first draft counted files and promptly
> flagged satisfactory, where four .sav files ARE the complete save — and a
> false alarm is expensive here, since an alert that fires on a healthy game
> stops being taken seriously. The size comes from `borg create --stats` rather
> than a second borg call, and is recorded after the check, or later runs would
> compare against the collapsed value and stay quiet. Both messages carry a one-day
> quiet period: this runs every 15 minutes, and eight messages a day about a
> known problem stop being read. The failed-backup message keeps the short
> window — that one is urgent.*

## Prüfen

```bash
systemctl list-timers --no-pager | grep sicherung      # laufen die Zeitpläne?
journalctl -u spiele-sicherung -n 30 --no-pager        # letzter Lauf
borg list --short "$REPO" | tail -20                   # jüngste Archive
borg info "$REPO"                                      # Größe, Verdichtung
borg check --repository-only "$REPO"                   # Unversehrtheit
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
