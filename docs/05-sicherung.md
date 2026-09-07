# 05 — Sicherung und Wiederherstellung

Borg über Tailscale auf einen Sicherungsserver. Ein Archiv **je Spiel**, alle 15
Minuten für laufende Server, täglich vollständig.

> *Borg over Tailscale to a backup host. One archive per game, every 15 minutes
> for running servers, plus a full daily run.*

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
5. Container starten, DNS mit `cf-dns setzen <name>` neu eintragen.

> *Total loss: rebuild stages 10–50, restore the passphrase from its off-host
> copy, extract the `config-*` archive for the compose files, extract each game's
> latest state, start the containers and re-create the DNS records.*

---

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
