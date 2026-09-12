# Eigenes SCUM-Abbild — Stand 2026-09-12: gebaut, **nicht veröffentlicht**

## Warum überhaupt ein eigenes

Das verbreitete Fremdabbild (`ghcr.io/evilolaf/scum`) läuft **als root** und legt
seine Dateien als root in `/srv/games` an — als einziger Server dieser Maschine.
Alle anderen laufen als 4711. Übernommen ist von dort nichts: Das Projekt steht
**ohne Lizenz** im Netz, sein Dockerfile darf man nicht kopieren. Was hier steht,
sind die technischen Notwendigkeiten — SCUM ist ein Windows-Programm (Wine), es
will einen X-Server (Xvfb), Wine braucht `winbind` und `crypt32`.

> *Why our own: the common third-party image runs as root and writes root-owned
> files, alone among the servers here. Nothing was copied — that project carries
> no licence. What the Dockerfile holds are the technical necessities.*

## Was erreicht ist

Der Server **läuft als uid 4711** und schreibt seine Spielstände als 4711
(`stat` belegt: `uid=4711 gid=4711`). Der Bau läuft durch, SteamCMD lädt die
17 GB, Wine startet `SCUMServer.exe`, die Konfiguration entsteht.

## Warum es nicht veröffentlicht ist

SCUM schaltet in unserem Abbild den Mehrspielerbetrieb ab:

```
LogTemp: Warning: Dll Verification result: -2146762496   (CRYPT_E_NOT_FOUND)
LogSCUM: DLL signature verification failed, disabling multiplayer
LogSCUM: AddMultiplayerDisabledReason: DllIntegrityCompromised
```

Das Fremdabbild meldet an derselben Stelle `Dll Verification result: 0` —
**gemessen auf denselben Serverdateien, nacheinander**, das ist also kein
Umgebungseffekt. Ein Abbild zu veröffentlichen, das keinen Mehrspielerbetrieb
kann, wäre ein Versprechen, das es nicht hält.

## Was als Ursache ausgeschlossen ist (gemessen, nicht vermutet)

| ausgeschlossen | wie |
|---|---|
| Die Spieldateien | frischer Download in unserem Abbild schlägt genauso fehl |
| Die Wine-Fassung | beide `wine-11.0` aus der WineHQ-Quelle |
| `crypt32.dll` | identische Prüfsumme in beiden Prefixen |
| Zertifikatspeicher | unser Prefix hat **mehr** Einträge als das funktionierende |
| Paketstand | Unterschied sind nur X11-Extras |
| winetricks-Fassung | auf `20260125` festgenagelt wie im Fremdabbild — gleicher Fehlschlag |

**Offen und nicht abschließend geprüft:** root gegen 4711. Der Gegenversuch mit
unserem Abbild als root lieferte binnen neun Minuten kein Protokoll, blieb also
ohne Aussage. Sollte sich das bestätigen, wäre der Preis für „läuft als 4711"
genau das, was wir gewinnen wollten — dann ist die Frage neu zu stellen.

> *Not published because SCUM disables multiplayer in this image
> (`DllIntegrityCompromised`), while the third-party image reports verification
> result 0 on the very same server files. Ruled out by measurement: the game
> data, the Wine version, the crypt32 DLL, the certificate stores, the package
> set and the winetricks version. Still open: root versus uid 4711.*
