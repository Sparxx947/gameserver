"""Spieleserver-Panel — Weboberflaeche fuer den gameserver.

Sicherheitsentwurf:
  * Laeuft als unprivilegierter Nutzer "panel" und spricht NIE direkt mit Docker
    oder Borg, sondern nur ueber sudo /usr/local/bin/panel-aktion. Wer Zugriff
    auf docker.sock hat, ist faktisch root — den gibt es hier nicht.
  * panel-aktion prueft jeden Parameter gegen Positivlisten. Insbesondere die
    Konfiguration: bearbeitet werden duerfen einzelne FELDER, nie die
    compose.yaml als Ganzes — wer dort ein Volume "/:/host" eintragen kann,
    ist root auf der Maschine.
  * Anmeldung mit Passwort (Argon2id) UND TOTP. Sitzungscookie signiert,
    HttpOnly/Secure/SameSite=strict, 8 h. CSRF-Token bei jedem Schreibzugriff.
  * Zwei Rollen: "admin" darf alles, "bedienen" darf nur starten, anhalten und
    neu starten — keine Passwoerter, keine Wiederherstellung, keine
    Benutzerverwaltung, keine Konfigurationsaenderung.
"""
import base64, hmac, json, os, secrets, string, subprocess, time
import re
from html import escape as esc
from urllib.parse import quote
from pathlib import Path

import pyotp
import qrcode
import qrcode.image.svg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, InvalidHashError
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse, FileResponse, Response
from itsdangerous import BadSignature, URLSafeTimedSerializer

# Eigenes Datenverzeichnis: /opt/panel selbst gehoert root, damit die App
# ihren eigenen Code NICHT ueberschreiben kann. Schreibbar ist nur "daten".
NUTZERDATEI = Path("/opt/panel/daten/nutzer.json")
# Selbst gepflegte Zugangsdaten. Noetig, weil manche Server ihre Passwoerter nur
# GEHASHT oder VERSCHLUESSELT ablegen und sie sich nicht auslesen lassen:
# Satisfactory (Hash+Salt in der binaeren .sav), TeamSpeak (Hash in SQLite),
# StarRupture (RSA-verschluesselt). Diese Eintraege koennen veralten — deshalb
# werden sie in der Anzeige deutlich von den automatisch gelesenen getrennt.
EIGENE = Path("/opt/panel/daten/zugangsdaten.json")
ALTKONFIG = Path("/opt/panel/konfig.json")
BILDER = Path("/opt/panel/bilder")
AKTION = ["/usr/bin/sudo", "-n", "/usr/local/bin/panel-aktion"]
# BORG_REPO=aus schaltet die Sicherung ab. Die Oberflaeche blendet dann alle
# Archivwege aus - nicht als Schutz (der sitzt in panel-aktion, wo die Rechte
# liegen), sondern damit niemand auf Knoepfe klickt, die es fachlich nicht gibt,
# und damit die Abwesenheit des Netzes SICHTBAR ist. Ein stillschweigend
# abgeschaltetes Backup ist gefaehrlicher als gar keines: man verlaesst sich
# darauf.
# *The panel hides every backup path when backups are off. Not as a guard - that
#  sits in panel-aktion where the privileges are - but so nobody clicks buttons
#  for something that does not exist, and so the missing safety net is visible.
#  A silently disabled backup is more dangerous than none: people rely on it.*
SICHERUNG_AN = "@@BORG_REPO@@" != "aus"
SITZUNG_MAXALTER = 8 * 3600
SPERRE_AB, SPERRE_DAUER = 5, 15 * 60

# Beitrittsadressen. Bewusst hier gepflegt und nicht aus der compose-Datei
# geraten: der DNS-Name steht dort nicht, und die veroeffentlichten Ports
# weichen teils vom Spielstandard ab (7777 hat Satisfactory, deshalb liegt
# StarRupture auf 7779 und Windrose auf 7780).
ADRESSEN = {
    "enshrouded":   ("enshrouded.@@DNS_ZONE@@", 15637, "Direktbeitritt, Passwort je Rolle"),
    "palworld":     ("palworld.@@DNS_ZONE@@", 8211, "über die Community-Liste als „@@WELT_NAME@@“"),
    "satisfactory": ("satisfactory.@@DNS_ZONE@@", 7777, "Server im Spiel hinzufügen"),
    "foundry":      ("foundry.@@DNS_ZONE@@", 3724, "Direktbeitritt"),
    "starrupture":  ("starrupture.@@DNS_ZONE@@", 7779, "Direktbeitritt"),
    "windrose":     ("windrose.@@DNS_ZONE@@", 7780, "Direktbeitritt"),
    "teamspeak":    ("ts.@@DNS_ZONE@@", 9987, "Standardport, im Client genügt der Name"),
}

KATALOG = Path("/etc/spiele-katalog.json")
KATALOGBILDER = Path("/opt/panel/bilder/katalog")


def katalog() -> list[dict]:
    """Der Katalog ist eine reine Lesequelle - geschrieben wird er nie von hier.
    Faellt er aus, bleibt der Rest der Oberflaeche benutzbar."""
    try:
        return json.loads(KATALOG.read_text())["spiele"]
    except Exception:
        return []


def kategorien_liste() -> dict:
    """Schluessel -> Beschriftung, aus dem Katalog. Faellt der Eintrag aus, gibt
    es eben keine Kategorieleiste - die Seite bleibt benutzbar."""
    try:
        return json.loads(KATALOG.read_text()).get("_kategorien", {})
    except Exception:
        return {}


def stackinfo(name: str) -> dict:
    """Angaben zu einem ueber den Katalog installierten Server. Die von Hand
    gebauten Stacks haben keine panel.json - fuer sie greift ADRESSEN."""
    try:
        return json.loads((Path("/opt/stacks") / name / "panel.json").read_text())
    except Exception:
        return {}


def adresse_von(name: str) -> tuple:
    if name in ADRESSEN:
        return ADRESSEN[name]
    p = stackinfo(name)
    if p:
        port = p.get("adresse_port", 0)
        return (f"{name}.@@DNS_ZONE@@", port, p.get("hinweis", "")[:150])
    return ("", 0, "")


hasher = PasswordHasher()
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
fehlversuche: dict[str, list[float]] = {}


def laden() -> dict:
    if NUTZERDATEI.exists():
        return json.loads(NUTZERDATEI.read_text())
    # Einmalige Uebernahme der alten Einzelnutzer-Konfiguration.
    alt = json.loads(ALTKONFIG.read_text())
    daten = {"secret": alt["secret"], "nutzer": {alt["nutzer"]: {
        "passwort_hash": alt["passwort_hash"], "totp": alt["totp"], "rolle": "admin"}}}
    speichern(daten)
    return daten


def speichern(daten: dict) -> None:
    tmp = NUTZERDATEI.with_suffix(".tmp")
    tmp.write_text(json.dumps(daten, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(NUTZERDATEI)


daten = laden()
signierer = URLSafeTimedSerializer(daten["secret"], salt="panel-sitzung")
# Eigener Salt und eigene, KURZE Lebensdauer fuer die MFA-Einrichtung: ein
# Einrichtungs-Token darf niemals als Sitzungscookie durchgehen.
einrichtung = URLSafeTimedSerializer(daten["secret"], salt="panel-mfa-einrichtung")
EINRICHTUNG_MAXALTER = 10 * 60


def eigene_laden() -> list[dict]:
    if not EIGENE.exists():
        return []
    try:
        return json.loads(EIGENE.read_text())
    except json.JSONDecodeError:
        return []


def eigene_speichern(liste: list[dict]) -> None:
    tmp = EIGENE.with_suffix(".tmp")
    tmp.write_text(json.dumps(liste, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(EIGENE)


def aktion(*args: str, timeout: int = 900) -> tuple[int, str]:
    try:
        p = subprocess.run(AKTION + list(args), capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 1, "Zeitüberschreitung"


def angemeldet(request: Request) -> dict | None:
    keks = request.cookies.get("sitzung")
    if not keks:
        return None
    try:
        s = signierer.loads(keks, max_age=SITZUNG_MAXALTER)
    except BadSignature:
        return None
    # Rolle immer frisch aus der Datei — sonst behielte ein abgemeldeter oder
    # herabgestufter Nutzer seine Rechte bis zum Ablauf des Cookies.
    n = laden()["nutzer"].get(s.get("nutzer"))
    if not n:
        return None
    s["rolle"] = n["rolle"]
    return s


def ist_admin(s: dict | None) -> bool:
    return bool(s and s.get("rolle") == "admin")


# Drei Rollen, mit einer klaren Trennlinie: "verwalten" darf alles rund um die
# SPIELESERVER, "admin" zusaetzlich alles rund um die MASCHINE und die MENSCHEN
# (Benutzerverwaltung, Webterminal, Neustart der Maschine, Protokoll).
#
# Vorher gab es dazwischen nichts: wer ein Spiel installieren koennen sollte,
# musste Administrator werden - und bekam damit Benutzerverwaltung und Terminal
# gleich mit.
#
# Wichtig: Diese Rolle lockert KEINE bestehende Pruefung. Sie entscheidet nur,
# ob eine Route ueberhaupt betreten werden darf; was dann ausgefuehrt wird,
# entscheidet weiterhin die Positivliste in panel-aktion.
# *Three roles with a clear line: "verwalten" covers the game servers, "admin"
#  additionally covers the machine and the people. This loosens no existing
#  check - the role gates the route, the allow-list still gates the action.*
ROLLEN = ("admin", "verwalten", "bedienen")


def darf_verwalten(s: dict | None) -> bool:
    """Spiele installieren, entfernen, konfigurieren, wiederherstellen."""
    return bool(s and s.get("rolle") in ("admin", "verwalten"))


# --- Wiederherstellungscodes -------------------------------------------------
#
# TOTP ist Pflicht und nicht abschaltbar. Wer sein Geraet verliert, kam bisher
# nur ueber "ein Administrator setzt den zweiten Faktor zurueck" wieder herein -
# bei genau einem Administrator ist das keine Wiederherstellung, sondern eine
# Aussperrung.
#
# Zehn Einmalcodes, erzeugt wenn der Benutzer seinen zweiten Faktor bestaetigt,
# EINMAL angezeigt, danach nur noch gehasht vorhanden. Sie treten an die Stelle
# des TOTP-Codes, nicht an die des Passworts.
#
# Die Zahlen sind nicht geraten:
#   * NIST SP 800-63B-4 §4.2.1.1 verlangt mindestens 64 Bit aus einem geeigneten
#     Zufallsgenerator, gehashte Speicherung und Einmalgebrauch.
#   * OWASP ASVS 5.0.0 V6.5.2 zieht die Grenze bei 112 Bit: darunter ist ein
#     GESALZENES Passwort-Hash-Verfahren Pflicht, darueber genuegt ein schneller
#     Hash.
#   * Das Alphabet aus E19 (57 Zeichen ohne 0/O und 1/l/I) traegt 5,83 Bit je
#     Zeichen. 16 Zeichen sind 93,3 Bit - ueber dem NIST-Minimum, unter der
#     ASVS-Schwelle, also Argon2id. Das ist ohnehin da.
#
# *TOTP is mandatory here, so losing the device meant losing the account: with a
#  single administrator, "an admin resets it" is a lockout, not a recovery path.
#  Ten single-use codes, shown once, stored hashed. 16 characters from the 57-
#  character look-alike-free alphabet is 93.3 bits - above the NIST minimum of 64,
#  below the ASVS threshold of 112, hence Argon2id.*
CODE_ANZAHL = 10
CODE_LAENGE = 16
CODE_ZEICHEN = "".join(c for c in string.ascii_letters + string.digits if c not in "0O1lI")


def code_erzeugen() -> str:
    return "".join(secrets.choice(CODE_ZEICHEN) for _ in range(CODE_LAENGE))


def code_lesbar(c: str) -> str:
    """In Vierergruppen - diese Codes werden ausgedruckt und abgetippt."""
    return "-".join(c[i:i + 4] for i in range(0, len(c), 4))


def codes_neu() -> tuple:
    """(Klartextliste zum EINMALIGEN Anzeigen, Hashliste zum Speichern)."""
    klar = [code_erzeugen() for _ in range(CODE_ANZAHL)]
    return klar, [hasher.hash(c) for c in klar]


def code_einloesen(name: str, eingabe: str) -> bool:
    """Prueft einen Wiederherstellungscode und verbraucht ihn.

    Der verbrauchte Code wird aus der Datei ENTFERNT, nicht als benutzt markiert:
    ein Einmalcode, der noch dasteht, wird frueher oder spaeter doch akzeptiert.
    *The redeemed code is removed rather than flagged: a single-use code that is
     still on file eventually gets accepted again.*
    """
    eingabe = eingabe.replace("-", "").replace(" ", "")
    if len(eingabe) != CODE_LAENGE:
        return False
    d = laden()
    n = d["nutzer"].get(name)
    if not n:
        return False
    rest = list(n.get("codes") or [])
    for h in rest:
        try:
            hasher.verify(h, eingabe)
        except (VerifyMismatchError, InvalidHashError):
            continue
        rest.remove(h)
        n["codes"] = rest
        speichern(d)
        return True
    return False


# --- Aktivität: was tut sich auf einem Server gerade? -------------------------
#
# Die naheliegende Anzeige waere eine Spielerzahl. Die gibt es aber nicht:
# gemessen am 2026-09-09 antwortet Palworld auf keine Steam-Abfrage (weder 27015
# noch 8211), TeamSpeak spricht ein eigenes Protokoll, Enshrouded ein drittes.
# Jedes Spiel braeuchte einen eigenen Weg, und fuer die meisten der 179
# Katalogspiele gaebe es gar keinen.
#
# Der Netzverkehr ist dagegen fuer JEDEN Container da und kommt aus demselben
# "docker stats", das die Oberflaeche ohnehin abruft. Er beantwortet die Frage,
# um die es wirklich geht - "kann ich neu starten oder ist jemand drauf?" - ohne
# eine Zahl zu erfinden, die es nicht gibt. Deshalb heisst die Anzeige "Verkehr"
# und nicht "Spieler".
#
# *The obvious display would be a player count, but there is none: measured,
#  Palworld answers no Steam query, TeamSpeak speaks its own protocol, Enshrouded
#  a third. Network traffic exists for every container and comes from the same
#  docker stats call, and it answers the question that actually matters - "can I
#  restart, or is somebody on?" - without inventing a number.*
NETZSTAND = Path("/opt/panel/daten/netzstand.json")


def _bytes(text: str) -> float:
    """"106kB" -> 106000. Docker schreibt kB/MB/GB dezimal, KiB/MiB/GiB binaer."""
    m = re.match(r"([\d.]+)\s*([kKMGT]?i?)B", text.strip())
    if not m:
        return 0.0
    zahl, einheit = float(m.group(1)), m.group(2)
    faktor = {"": 1, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
              "Ki": 1024, "Mi": 1024**2, "Gi": 1024**3, "Ti": 1024**4}
    return zahl * faktor.get(einheit, 1)


def verkehr_rate(gemessen: dict) -> dict:
    """Bytes je Sekunde seit dem letzten Abruf, je Server.

    Der Wert aus "docker stats" ist kumulativ seit dem Start des Containers -
    als Anzeige waere er wertlos ("171 kB" sagt nichts darueber, ob gerade jemand
    spielt). Gebraucht wird die AENDERUNG, also zwei Messungen und die Zeit
    dazwischen.

    Faellt der Zaehler (Container neu gestartet), wird der Eintrag verworfen
    statt eine negative Rate zu zeigen: ein Neustart ist kein Verkehr.
    *The counter is cumulative since container start, so the change is what
     matters. A falling counter means a restart, not negative traffic.*
    """
    jetzt = time.time()
    try:
        alt = json.loads(NETZSTAND.read_text())
    except (OSError, ValueError):
        alt = {}
    raten, neu = {}, {"zeit": jetzt, "werte": gemessen}
    spanne = jetzt - float(alt.get("zeit", 0) or 0)
    # Unter 2 s ist die Differenz Rauschen, ueber 15 min sagt sie nichts mehr
    # ueber "gerade".
    if 2 <= spanne <= 900:
        for name, summe in gemessen.items():
            vorher = (alt.get("werte") or {}).get(name)
            if vorher is None or summe < vorher:
                continue
            raten[name] = (summe - vorher) / spanne
    try:
        NETZSTAND.write_text(json.dumps(neu))
    except OSError:
        pass          # Kein Grund, die Uebersicht scheitern zu lassen
    return raten


def verkehr_text(bps: float | None) -> str:
    """Kurz und ehrlich. Ohne Vergleichswert steht da nichts - eine leere Angabe
    ist besser als eine erfundene."""
    if bps is None:
        return ""
    if bps < 1500:
        return '<span class=z>ruhig</span>'
    if bps < 1e6:
        return f'<span class=z>Verkehr {bps/1e3:.0f} kB/s</span>'
    return f'<span class=z>Verkehr {bps/1e6:.1f} MB/s</span>'


# --- Passkeys (WebAuthn) -----------------------------------------------------
#
# TOTP beruht auf einem GETEILTEN Geheimnis: Server und Geraet kennen dieselbe
# Zeichenkette. Sie laesst sich in Echtzeit abphishen und sie liegt beim Dienst.
# Das BSI bewertet TOTP-Apps deshalb in zwei von vier Szenarien genauso schlecht
# wie E-Mail-TANs (Bewertungstabellen "IT-Sicherheit", 1.1, 05/2026). Ein
# Passkey hat kein serverseitiges Geheimnis und ist an die Domain gebunden - eine
# nachgebaute Anmeldeseite bekommt schlicht keine Signatur.
#
# Hier ist er ein ZWEITER Faktor neben TOTP, kein Ersatz: Das Passwort bleibt
# Faktor 1, und wer keinen Passkey einrichtet, meldet sich unveraendert mit den
# sechs Ziffern an.
#
# *TOTP rests on a shared secret; a passkey has no server-side secret and is
#  bound to the domain, so a look-alike login page gets no signature. Here it is
#  an alternative second factor, not a replacement.*
try:
    from webauthn import (generate_registration_options, verify_registration_response,
                          generate_authentication_options, verify_authentication_response,
                          options_to_json, base64url_to_bytes)
    from webauthn.helpers.structs import (AuthenticatorSelectionCriteria,
                                          UserVerificationRequirement,
                                          PublicKeyCredentialDescriptor)
    PASSKEY_MOEGLICH = True
except ImportError:
    # Die Bibliothek fehlt: TOTP funktioniert weiter, die Passkey-Wege melden
    # sich sauber ab. Ein Panel, das wegen eines fehlenden Zusatzes gar nicht
    # mehr startet, waere der schlechtere Tausch.
    # *Missing library: TOTP keeps working and the passkey routes decline. A
    #  panel that refuses to start over an optional extra is the worse trade.*
    PASSKEY_MOEGLICH = False

# Die oeffentliche Herkunft, nicht die interne. Die App laeuft hinter Caddy auf
# 127.0.0.1:8099 - wuerde sie sich selbst als Herkunft eintragen, passte die
# Signatur des Browsers nie.
# *The public origin, not the internal one: the app runs behind Caddy, and a
#  signature made for the public origin never matches 127.0.0.1.*
RP_ID = "@@PANEL_DOMAIN@@"
RP_HERKUNFT = f"https://{RP_ID}"
RP_NAME = "Spieleserver @@WELT_NAME@@"


def bytes_zu_b64url(b: bytes) -> str:
    """base64url OHNE Auffuellzeichen - so schreibt WebAuthn seine Kennungen, und
    so kommen sie auch aus dem Browser zurueck. Mit "=" am Ende faende der
    Vergleich in anmelden-fertig den passenden Schluessel nicht."""
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def passkeys_von(name: str) -> list:
    return (laden()["nutzer"].get(name) or {}).get("passkeys") or []


def passkey_speichern(name: str, eintrag: dict) -> None:
    d = laden()
    d["nutzer"][name].setdefault("passkeys", []).append(eintrag)
    speichern(d)


# --- Protokoll: wer hat wann was getan ---------------------------------------
#
# Vorher liess sich das nur zufaellig aus dem Journal rekonstruieren, weil jede
# Aktion ueber "sudo panel-aktion" laeuft. Diese Zeile nennt aber den
# DIENSTNUTZER "panel", nie den angemeldeten Menschen, entsteht nur fuer den Weg
# ueber die sudo-Bruecke und faellt mit der Journalrotation weg. Am 08.09. liess
# sich damit gerade noch klaeren, ob ein Server durch einen Fehler verschwunden
# war oder geloescht wurde - Glueck, keine Funktion.
# *Previously reconstructible only by accident from the journal, which names the
#  service account rather than the person, covers only the sudo path, and expires
#  with rotation.*
AUDITDATEI = Path("/opt/panel/daten/audit.jsonl")
AUDIT_MAX = 4 * 1024 * 1024        # danach einmal rotieren, .1 bleibt liegen

# Ein Protokoll, das heimlich nichts mehr schreibt, ist schlimmer als keins: seine
# Leere liest sich als "es ist nichts passiert". Ein Schreibfehler wird deshalb
# gemerkt und in der Oberflaeche angezeigt, statt still verschluckt zu werden.
# *An audit log that quietly stops recording is worse than none, because its
#  emptiness reads as "nothing happened".*
AUDIT_FEHLER: str | None = None

# Feldnamen, deren WERT nie ins Protokoll darf. Das Protokoll soll nachvollziehbar
# machen, WAS geaendert wurde - nicht Passwoerter an einer zweiten Stelle sammeln.
GEHEIM_MUSTER = re.compile(r"passwo?r|passwd|\bpsw\b|secret|token|api[_-]?key|rcon", re.I)


def ohne_geheimnis(feld: str, wert: str) -> str:
    """Wert fuers Protokoll: bei Passwortfeldern nur die Laenge, sonst gekuerzt."""
    if GEHEIM_MUSTER.search(feld or ""):
        return f"<{len(wert)} Zeichen, nicht protokolliert>"
    w = (wert or "").strip().replace("\n", " ")
    return w[:120] + ("…" if len(w) > 120 else "")


def protokoll(s: dict | None, aktion: str, ziel: str = "",
              ergebnis: str = "ok", **details) -> None:
    global AUDIT_FEHLER
    eintrag = {
        "zeit": time.strftime("%Y-%m-%d %H:%M:%S%z"),
        "nutzer": (s or {}).get("nutzer") or "—",
        "rolle": (s or {}).get("rolle") or "—",
        "aktion": aktion,
        "ziel": ziel,
        "ergebnis": ergebnis,
    }
    if details:
        eintrag["details"] = details
    try:
        AUDITDATEI.parent.mkdir(parents=True, exist_ok=True)
        if AUDITDATEI.exists() and AUDITDATEI.stat().st_size > AUDIT_MAX:
            AUDITDATEI.replace(AUDITDATEI.with_name(AUDITDATEI.name + ".1"))
        with AUDITDATEI.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(eintrag, ensure_ascii=False) + "\n")
        AUDIT_FEHLER = None
    except OSError as e:
        AUDIT_FEHLER = f"{type(e).__name__}: {e}"


def protokoll_lesen(grenze: int = 300) -> list:
    """Die letzten Eintraege, neueste zuerst. Kaputte Zeilen werden als solche
    gezeigt statt uebersprungen - eine stillschweigend verschluckte Zeile waere
    genau die, die jemand loswerden wollte."""
    zeilen = []
    for p in (AUDITDATEI, AUDITDATEI.with_name(AUDITDATEI.name + ".1")):
        try:
            zeilen += p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            pass
        if len(zeilen) >= grenze:
            break
    aus = []
    for z in reversed(zeilen[-grenze * 2:]):
        if not z.strip():
            continue
        try:
            aus.append(json.loads(z))
        except ValueError:
            aus.append({"zeit": "?", "nutzer": "?", "rolle": "?",
                        "aktion": "UNLESBARE ZEILE", "ziel": z[:120], "ergebnis": "?"})
        if len(aus) >= grenze:
            break
    return aus


def pruefe(request: Request, csrf: str) -> dict | None:
    s = angemeldet(request)
    if not s or not hmac.compare_digest(csrf, s["csrf"]):
        return None
    return s


def gesperrt(ip: str) -> int:
    jetzt = time.time()
    versuche = [t for t in fehlversuche.get(ip, []) if jetzt - t < SPERRE_DAUER]
    fehlversuche[ip] = versuche
    return int(SPERRE_DAUER - (jetzt - versuche[0])) if len(versuche) >= SPERRE_AB else 0


KOPF = """<!doctype html><html lang=de><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>Spieleserver</title><link rel=icon href="/favicon.svg" type="image/svg+xml"><link rel="alternate icon" href="/favicon.ico" sizes="48x48 32x32 16x16"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>
:root{color-scheme:dark;--bg:#14161a;--k:#1d2026;--r:#2b303a;--t:#e6e8ec;--d:#9aa1ad;--a:#5b9dd9;--g:#4caf7d;--x:#d9534f;--y:#d9a441}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--t);font:15px/1.5 system-ui,sans-serif}
.w{max-width:1000px;margin:0 auto;padding:22px 16px}h1{font-size:20px;margin:0 0 16px}
/* Der Katalog bekommt eine eigene, breitere Spalte. 1000px sind fuer Fliesstext
   richtig und fuer 154 Kacheln viel zu wenig: auf einem breiten Bildschirm
   standen drei Spalten neben zwei Dritteln leerem Grau. Die Kopfleiste bleibt
   bei 1000px - sie soll nicht ueber den ganzen Schirm wandern.
   *The catalogue gets its own wider column: 1000px is right for prose and far
    too little for 154 tiles, which left three columns beside two thirds of empty
    background. The header stays at 1000px.* */
.w.breit{max-width:2400px}
/* Kopfleiste: bleibt beim Scrollen oben, zeigt durch Hervorhebung, auf welcher
   Seite man ist. backdrop-filter faellt in aelteren Browsern still weg — die
   Leiste hat deshalb eine eigene Hintergrundfarbe und ist nicht darauf angewiesen. */
.hd{position:sticky;top:0;z-index:10;background:rgba(20,22,26,.92);
  backdrop-filter:blur(8px);border-bottom:1px solid var(--r)}
/* Die Kopfleiste ist so breit wie der BREITE Inhalt (.w.breit), nicht wie der
   schmale. Bei 1000px lief die Navigation ueber, sobald "Mein Konto" und
   "Protokoll" dazukamen: acht Punkte brauchen rund 654px, Marke und Nutzerblock
   noch einmal 317px, macht mit Abstaenden etwa 1043px. "nav" hat
   "overflow:auto", also erschien statt eines Umbruchs ein Schiebebalken quer
   durch das Menue.
   *The header spans the wide content width, not the narrow one: at 1000px the
    nav overflowed once two more items were added, and overflow:auto turned that
    into a sideways scrollbar instead of a wrap.* */
.hdi{max-width:2400px;margin:0 auto;padding:0 16px;height:56px;
  display:flex;align-items:center;gap:20px}
.marke{font-weight:700;letter-spacing:.02em;display:flex;align-items:center;gap:8px;flex:none}
.marke .logo{width:24px;height:24px;flex:none;display:block}
nav{display:flex;gap:4px;flex:1;min-width:0;overflow:auto}
.nv{padding:7px 12px;border-radius:7px;color:var(--d);text-decoration:none;font-size:14px;white-space:nowrap}
.nv:hover{background:var(--k);color:var(--t)}
.nv.hier{background:var(--k);color:var(--t);box-shadow:inset 0 -2px 0 var(--a)}
/* Suchfeld und die beiden Filterleisten der Katalogseite. Bewusst ohne
   JavaScript: die Seite laeuft unter default-src 'none'. */
.suche{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0 10px}
.suche input[type=search]{flex:1;min-width:220px;padding:9px 12px;border-radius:8px;
  border:1px solid var(--r);background:var(--k);color:var(--t);font-size:15px}
.suche input[type=search]:focus{outline:2px solid var(--a);outline-offset:-1px}
.leiste{display:flex;gap:4px;flex-wrap:wrap;margin:0 0 10px}
.leiste .nv{font-size:13px;padding:6px 10px}
.leiste .nv .z{opacity:.65;margin-left:3px}
/* Buchstabenleiste: gleich breite Felder, damit sie nicht bei jeder Suche
   herumspringt. Leere Buchstaben bleiben stehen und sind erkennbar tot. */
.abc .nv{min-width:26px;text-align:center;padding:6px 7px;font-variant-numeric:tabular-nums}
.abc .leer{color:var(--r);cursor:default}
.abc .leer:hover{background:none;color:var(--r)}
.usr{display:flex;align-items:center;gap:10px;font-size:13px;color:var(--d);flex:none}
.usr b{color:var(--t)}
.rolle{font-size:11px;background:var(--r);padding:2px 7px;border-radius:99px}
@media(max-width:640px){.marke span{display:none}.usr b{display:none}}
.d{color:var(--d);font-size:13px;margin-bottom:20px}
.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
/* Kompakte Kacheln fuer den Katalog: schmaler und mit flacherem Bild, damit auf
   einen Bildschirm ein Vielfaches passt. 240px ist die Grenze, ab der ein
   zweizeiliger Spielname noch lesbar bleibt. */
.g.eng{grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:10px}
.g.eng img,.g.eng .ph{height:88px}
.g.eng .cb{padding:9px 11px;gap:5px}
.g.eng .n{font-size:14px}
.g.eng .z{font-size:12px;line-height:1.35}
.c{background:var(--k);border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.c img{width:100%;height:110px;object-fit:cover;display:block}
.ph{width:100%;height:110px;background:linear-gradient(135deg,#232833,#2f3644);display:flex;align-items:center;justify-content:center;color:var(--d);font-size:26px;font-weight:700;letter-spacing:.08em}
.cb{padding:12px 14px;display:flex;flex-direction:column;gap:8px;flex:1}
.n{font-weight:600}.z{font-size:12px;color:var(--d)}
.s{display:inline-block;padding:2px 8px;border-radius:99px;font-size:12px}
.on{background:rgba(76,175,125,.15);color:var(--g)}.off{background:rgba(154,161,173,.15);color:var(--d)}
/* Zwei bewusste Reihen: oben die Steuerung (farbig), darunter die Verweise.
   Vier Knoepfe passen bei Kartenbreite nie in eine Zeile — ein ungeplanter
   Umbruch sieht aus wie ein Fehler, zwei geordnete Reihen nicht. */
.akt{display:flex;gap:6px;margin-top:auto;flex-wrap:wrap}
.akt form.steuer{display:flex;gap:6px;width:100%}
.akt form.steuer button{flex:1}
/* Die Verweise duerfen umbrechen. Ohne flex-wrap wurden sie stattdessen
   gestaucht: mit "Protokoll" sind es bis zu vier Knoepfe in einer 300px breiten
   Karte, und "flex:1" verteilt die Breite gleichmaessig, bis die Beschriftung
   nicht mehr lesbar ist. Mit Umbruch bekommt jede Zeile ihre Breite; die
   Mindestbreite verhindert, dass zwei Knoepfe sich eine Zeile teilen, in die
   sie nicht passen.
   *The links may wrap. Without flex-wrap they were squeezed instead: with
    "Protokoll" there can be four buttons in a 300px card, and flex:1 divides the
    width evenly until the labels are unreadable.* */
.akt .verweise{display:flex;gap:6px;width:100%;flex-wrap:wrap}
.akt .verweise .b{flex:1 1 auto;min-width:104px;text-align:center}
/* Knoepfe und Links muessen GLEICH aussehen. Buttons erben die Schrift des
   Dokuments nicht von selbst (deshalb font:inherit) und bringen eigene
   Innenabstaende und Zeilenhoehen mit — daher feste Hoehe und inline-flex,
   sonst sitzen <button> und <a> unterschiedlich hoch und verschieden gross. */
button,.b{font:inherit;font-size:12.5px;line-height:1;height:30px;padding:0 10px;
  display:inline-flex;align-items:center;justify-content:center;
  background:var(--r);color:var(--t);border:0;border-radius:6px;cursor:pointer;
  text-decoration:none;white-space:nowrap;vertical-align:middle}
button:hover,.b:hover{background:#39404d}
/* Auslastungsbalken */
.bal{display:flex;align-items:center;gap:8px;font-size:12px;color:var(--d)}
.bal .lab{width:58px;flex:none}
.bal .sp{width:64px;flex:none;text-align:right;font-variant-numeric:tabular-nums}
/* BEIDE brauchen display:block. Die Balken sind <span>-Elemente, und bei
   inline-Elementen wirken width und height nicht — die Fuellung blieb dadurch
   unsichtbar, man sah nur die leere Spur. Aufgefallen 2026-09-06 im Betrieb,
   auf dem Screenshot war es mir durchgegangen. */
.tr{display:block;flex:1;height:7px;background:#12141a;border-radius:99px;overflow:hidden}
.fi{display:block;height:100%;min-width:2px;border-radius:99px;background:var(--g);
  transition:width .3s}
.fi.mid{background:var(--y)}.fi.hot{background:var(--x)}
.sys{background:var(--k);border-radius:10px;padding:16px;margin-bottom:18px;
  display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:20px}
.kz .t{font-size:11px;color:var(--d);text-transform:uppercase;letter-spacing:.06em}
.kz .v{font-size:19px;font-variant-numeric:tabular-nums;margin:2px 0 6px}
.kz .tr{width:100%}
/* Knoepfe sollen in EINE Zeile passen: etwas schmaler, und die Reihe darf
   umbrechen, ohne dass die Karten dadurch unterschiedlich hoch werden. */
.akt{min-height:32px}
.last{min-height:44px}
.p{background:var(--a);color:#08121c}.x{background:var(--x);color:#fff}.y{background:var(--y);color:#1a1200}
form{display:inline}input,select{background:var(--k);border:1px solid var(--r);color:var(--t);padding:8px 10px;border-radius:6px;font-size:14px}
input[type=text],input[type=password]{width:100%}
label{display:block;margin:12px 0 4px;font-size:13px;color:var(--d)}
table{width:100%;border-collapse:collapse;background:var(--k);border-radius:8px;overflow:hidden}
th,td{padding:9px 12px;text-align:left;border-bottom:1px solid var(--r);font-size:14px}
th{color:var(--d);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.04em}
tr:last-child td{border-bottom:0}
.card{background:var(--k);border-radius:8px;padding:20px;max-width:340px;margin:60px auto}
.f{color:var(--x);font-size:13px;margin-top:12px}
code{background:var(--bg);padding:2px 6px;border-radius:4px;font-size:13px}
.m{color:var(--d);font-size:12px;margin-top:24px}
.warn{background:rgba(217,164,65,.12);border-left:3px solid var(--y);padding:10px 14px;border-radius:6px;margin:14px 0;font-size:13px}
</style></head><body>"""
FUSS = "</div></body></html>"
RUMPF = "<div class=w>"


def nach_bytes(text: str) -> float:
    """'1.367GiB' -> Bytes. Docker liefert je nach Groesse B/KiB/MiB/GiB."""
    text = text.strip()
    for endung, faktor in (("GiB", 1073741824), ("MiB", 1048576), ("KiB", 1024), ("B", 1)):
        if text.endswith(endung):
            try:
                return float(text[:-len(endung)]) * faktor
            except ValueError:
                return 0.0
    return 0.0


def balken(beschriftung: str, anteil: float, text: str) -> str:
    """Ein Balken mit Farbschwelle. Ueber 85 % rot, ueber 60 % gelb — so faellt
    ein Server, der an seine Grenze stoesst, sofort ins Auge, statt in einer
    Zahlenkolonne unterzugehen."""
    anteil = max(0.0, min(100.0, anteil))
    klasse = "hot" if anteil >= 85 else ("mid" if anteil >= 60 else "")
    return (f'<div class=bal><span class=lab>{beschriftung}</span>'
            f'<span class=tr><span class="fi {klasse}" style="width:{anteil:.0f}%"></span></span>'
            f'<span class=sp>{text}</span></div>')


def kennzahl(titel: str, wert: str, anteil: float) -> str:
    """Grosse Zahl mit Balken darunter — lesbarer als Beschriftung, Balken und
    Wert nebeneinander in einer Zeile."""
    anteil = max(0.0, min(100.0, anteil))
    klasse = "hot" if anteil >= 85 else ("mid" if anteil >= 60 else "")
    return (f'<div class=kz><div class=t>{titel}</div><div class=v>{wert}</div>'
            f'<span class=tr><span class="fi {klasse}" style="width:{anteil:.0f}%"></span></span></div>')


# Logo als Inline-SVG: Die CSP des Panels erlaubt Bilder nur von "self"
# und keine data:-URIs. Inline gezeichnet braucht es weder eine zweite
# Anfrage noch eine Ausnahme - und bleibt in jeder Groesse scharf.
LOGO = ('<svg class=logo viewBox="0 0 32 32" aria-hidden=true><rect x=1 y=1 width=30 height=30 rx=8 fill="#5b9dd9"/><g fill="#e6e8ec"><rect x=4.5 y=10.5 width=23 height=11 rx=4.6/><path d="M6.5 19.5 4.8 25.5h4.8L11 20.4z"/><path d="M25.5 19.5l1.7 6h-4.8L21 20.4z"/></g><g fill="#5b9dd9"><rect x=8 y=15 width=6.2 height=2.2 rx=0.9/><rect x=9.8 y=13.2 width=2.6 height=5.8 rx=0.9/><circle cx=21.4 cy=14.6 r=1.7/><circle cx=24.2 cy=17.4 r=1.7/></g></svg>')


def kopfleiste(s: dict, hier: str = "") -> str:
    """Kopfleiste mit Navigation. "hier" markiert die aktuelle Seite — ohne diese
    Rueckmeldung weiss man auf Unterseiten nicht, wo man steht."""
    punkte = [("/", "Übersicht", "start"), ("/konto", "Mein Konto", "konto")]
    # Zwei Stufen: was die SPIELE betrifft, sieht auch "verwalten"; was die
    # Maschine und die Benutzer betrifft, bleibt bei "admin". Die Navigation
    # blendet nur aus — die Entscheidung sitzt in jeder Route selbst.
    # *Two tiers; the navigation only hides, each route decides for itself.*
    if darf_verwalten(s):
        punkte += [("/spiele", "Spiele", "spiele"),
                   ("/passwoerter", "Zugangsdaten", "pw")]
    if ist_admin(s):
        punkte += [("/nutzer", "Benutzer", "nutzer"),
                   ("/protokoll", "Protokoll", "prot"),
                   ("/terminal/", "Terminal", "term"), ("/neustart-fragen", "Neustart", "reboot")]
    nav = "".join(f'<a class="nv{" hier" if k == hier else ""}" href="{u}">{t}</a>'
                  for u, t, k in punkte)
    return (f'<div class=hd><div class=hdi>'
            f'<div class=marke>{LOGO}<span>Spieleserver</span></div>'
            f'<nav>{nav}</nav>'
            f'<div class=usr><b>{s["nutzer"]}</b><span class=rolle>{s["rolle"]}</span>'
            f'<a class=b href=/abmelden>abmelden</a></div>'
            f'</div></div>')


@app.get("/bild/{stack}")
def bild(request: Request, stack: str):
    if not angemeldet(request):
        return RedirectResponse("/login", 303)
    if not stack.isalnum():
        return RedirectResponse("/", 303)
    p = BILDER / f"{stack}.jpg"
    return FileResponse(p) if p.is_file() else RedirectResponse("/", 303)


@app.get("/", response_class=HTMLResponse)
def uebersicht(request: Request, meldung: str = ""):
    s = angemeldet(request)
    if not s:
        return RedirectResponse("/login", 303)
    rc, aus = aktion("status", timeout=60)
    # Erst alle Netzzaehler einsammeln, dann die Raten bilden: eine gemeinsame
    # Zeitspanne fuer alle Server, statt je Karte eine eigene.
    gemessen = {}
    for z in aus.splitlines():
        teil = z.split("\t")
        if len(teil) >= 5 and teil[1] == "laeuft" and "/" in teil[4]:
            rein, raus = teil[4].split("/", 1)
            gemessen[teil[0]] = _bytes(rein) + _bytes(raus)
    raten = verkehr_rate(gemessen)
    # Einmal fuer alle Karten holen, nicht je Karte einmal: ein Aufruf ueber die
    # sudo-Bruecke kostet spuerbar, und die Antwort ist fuer jede Karte dieselbe.
    # *Fetched once for all cards, not per card.*
    _, au_roh = aktion("auto-update-liste", timeout=30)
    auto_an = {z.strip() for z in au_roh.splitlines() if z.strip()}
    karten, systemleiste, kerne = [], "", 6
    for z in aus.splitlines():
        if z.startswith("SYSTEM\t"):
            t = z.split("\t")
            if len(t) >= 8:
                mben, mges, load, kerne = int(t[1]), int(t[2]), float(t[3]), int(t[4])
                pben, pges, swap = int(t[5]), int(t[6]), t[7]
                sben, sges = (int(x) for x in swap.split("/"))
                systemleiste = ("<div class=sys>"
                    + kennzahl("Arbeitsspeicher", f"{mben/1024:.1f} <span class=t>von {mges/1024:.0f} GB</span>",
                               100 * mben / mges)
                    + kennzahl("CPU-Last", f"{load:.2f} <span class=t>von {kerne} Kernen</span>",
                               100 * load / kerne)
                    + kennzahl("Platte", f"{pben/1024:.0f} <span class=t>von {pges/1024:.0f} GB</span>",
                               100 * pben / pges)
                    + kennzahl("Auslagerung", f"{sben} <span class=t>von {sges} MB</span>",
                               100 * sben / sges if sges else 0)
                    + "</div>")
            continue
        t = z.split("\t")
        if len(t) < 4:
            continue
        name, zustand, cpu, mem = t[0], t[1], t[2], t[3]
        an = zustand == "laeuft"
        verkehr = verkehr_text(raten.get(name)) if an else ""
        bild_html = (f'<img src="/bild/{name}" alt="">' if (BILDER / f"{name}.jpg").is_file()
                     else f'<div class=ph>{name[:2].upper()}</div>')
        knoepfe = []
        if an:
            knoepfe.append(f'<button class=y name=was value=restart>neu starten</button>')
            knoepfe.append(f'<button class=x name=was value=stop>anhalten</button>')
        else:
            knoepfe.append(f'<button class=p name=was value=start>starten</button>')
        pi = stackinfo(name)
        verweise = (f'<a class=b href="/archive/{name}">Sicherungen</a>'
                    if SICHERUNG_AN else "")
        if darf_verwalten(s):
            # Auch fuer gestoppte Server: dann sind die Logs am wichtigsten.
            # *Also for stopped servers - that is when the log matters most.*
            verweise += f'<a class=b href="/logs/{name}">Protokoll</a>'
            verweise += f'<a class=b href="/konfig/{name}">Einstellungen</a>'
            # Die Zahl kommt aus konfigzahlen.json (von spiel-einrichtung alle
            # zwei Minuten gepflegt). Ein eigener Aufruf je Server waere hier zu
            # teuer, und panel.json scheidet aus: die von Hand gebauten Stacks
            # haben gar keine.
            # *From konfigzahlen.json, refreshed every two minutes; a per-server
            #  call would be too expensive and panel.json does not exist for the
            #  hand-built stacks.*
            anz = konfigzahlen().get(name)
            zusatz = f" ({anz})" if isinstance(anz, int) and anz else ""
            verweise += f'<a class=b href="/dateien/{name}">Konfigdateien{zusatz}</a>'
        # Aktualisieren ist ein eigenes Formular, kein Verweis: es aendert etwas
        # und braucht deshalb das CSRF-Merkmal. Die Sicherung davor erzwingt
        # panel-aktion, nicht die Oberflaeche - eine Schutzmassnahme, die man
        # durch einen anderen Aufrufweg umgehen kann, ist keine.
        # *Updating is a form, not a link: it changes something and needs the CSRF
        #  token. The backup is enforced in panel-aktion, not here - a safeguard
        #  that another entry point bypasses is not one.*
        aktualisieren_knopf = ""
        # Fuer JEDEN Server, auch die von Hand gebauten. Der Schalter lag zuerst
        # in der panel.json und erreichte damit einen von acht - ausgerechnet
        # Palworld und Enshrouded, die laufend Patches bekommen, waren aussen vor.
        # *For every server, hand-built ones included: keyed on its own list
        #  rather than panel.json, which reached one server out of eight.*
        if darf_verwalten(s):
            auto = name in auto_an
            aktualisieren_knopf += (
                f'<form method=post action=/auto-update style=display:contents>'
                f'<input type=hidden name=csrf value="{s["csrf"]}">'
                f'<input type=hidden name=stack value="{name}">'
                f'<input type=hidden name=wert value="{"aus" if auto else "an"}">'
                f'<button class="b{" y" if auto else ""}" '
                f'title="Nächtlich neue Fassungen holen — nur wenn gesichert werden '
                f'kann und niemand spielt">'
                f'auto {"an" if auto else "aus"}</button></form>')
        if darf_verwalten(s):
            # "+=", NICHT "=": Hier stand eine Zuweisung, und die warf den
            # Auto-Schalter von oben weg - er wurde gebaut und im selben Atemzug
            # ueberschrieben. Auf der Karte war davon nichts zu sehen, und jeder
            # Block sieht fuer sich betrachtet richtig aus.
            # *"+=", not "=": an assignment here discarded the auto switch built
            #  a few lines above - created and overwritten in the same breath.*
            aktualisieren_knopf += (
                f'<form method=post action=/aktualisieren style=display:contents>'
                f'<input type=hidden name=csrf value="{s["csrf"]}">'
                f'<input type=hidden name=stack value="{name}">'
                f'<button class=b title="Neue Fassung holen — sichert vorher">'
                f'aktualisieren</button></form>')
        aktionen = (f'<form method=post action=/aktion class=steuer>'
                    f'<input type=hidden name=csrf value="{s["csrf"]}">'
                    f'<input type=hidden name=stack value="{name}">{"".join(knoepfe)}</form>'
                    f'<div class=verweise>{verweise}{aktualisieren_knopf}</div>')
        host, port, hinweis = adresse_von(name)
        adresse = (f'<div class=z><code>{host}{":" + str(port) if port else ""}</code><br>{hinweis}</div>'
                   if host else "")
        # Wenn ein frisch installierter Server sein Passwort noch nicht gesetzt
        # bekommen hat, muss das sichtbar sein - sonst steht er ungeschuetzt im
        # Netz, ohne dass es jemand merkt.
        # Kein veroeffentlichter Port heisst: der Server laeuft, aber niemand
        # kommt hin. Das muss oben stehen, noch vor der Passwortwarnung - ohne
        # Port ist das Passwort belanglos.
        # *No published port means the server runs but nobody can reach it; this
        #  outranks the password warning, which would be moot.*
        if pi.get("port_regel"):
            adresse += ('<div class=warn>Noch keine Beitrittsadresse: Dieses Spiel nennt seinen '
                        'Port erst in <code>' + esc(pi["port_regel"].get("datei", "?")) + '</code>, '
                        'die der Server beim ersten Start schreibt. Danach trägt der '
                        'Einrichtungsschritt ihn selbst nach und startet den Server neu.</div>')
        elif pi.get("port_ermittelt"):
            pe = pi["port_ermittelt"]
            adresse += (f'<div class=z>Port {pe["host"]} wurde am {esc(str(pe["am"])[:10])} aus '
                        f'<code>{esc(pe["quelle"])}</code> übernommen.</div>')
        if pi.get("einrichtung_offen"):
            adresse += ('<div class=warn>Einrichtung läuft: '
                        + pi.get("einrichtung_stand", "") + '</div>')
        elif pi and "KEIN Passwortfeld" in pi.get("einrichtung_stand", ""):
            adresse += ('<div class=warn>Ohne Beitrittspasswort! '
                        + pi.get("einrichtung_stand", "") + '</div>')
        # Eigene Bedingung fuer die Spielerzahl: sie kann fehlschlagen, waehrend
        # das Passwort steht. Frueher fiel das unter den Tisch, weil nur der
        # Passwort-Fall geprueft wurde - Minecraft lief mit 20 Plaetzen statt 4.
        # *Own branch: the player limit can fail while the password succeeded.
        #  This used to go unnoticed, and Minecraft ran with 20 slots instead
        #  of 4.*
        elif pi and "Spielerzahl NICHT" in pi.get("einrichtung_stand", ""):
            adresse += ('<div class=warn>Spielerzahl nicht gesetzt: '
                        + pi.get("einrichtung_stand", "") + '</div>')
        if an:
            benutzt, grenze = (nach_bytes(x) for x in (mem.split("/") + ["0"])[:2])
            cpu_wert = float(cpu.rstrip("%") or 0)
            last = ('<div class=last>'
                    + balken("Speicher", 100 * benutzt / grenze if grenze else 0,
                             f"{benutzt/1073741824:.1f}/{grenze/1073741824:.0f} GB")
                    + balken("CPU", cpu_wert / kerne, f"{cpu_wert:.0f}%")
                    + (f'<div style=margin-top:4px>{verkehr}</div>' if verkehr else "")
                    + '</div>')
        else:
            # Platzhalter gleicher Hoehe, damit gestoppte Server das Raster
            # nicht zerreissen.
            last = '<div class="last z" style="display:flex;align-items:center">nicht aktiv</div>'
        karten.append(f"""<div class=c>{bild_html}<div class=cb>
<div class=n>{name} <span class="s {'on' if an else 'off'}">{'läuft' if an else 'gestoppt'}</span></div>
{adresse}
{last}
<div class=akt>{aktionen}</div></div></div>""")
    # Breit wie die Katalogseite: die Uebersicht stand als einzige Seite mit
    # Kacheln in einer 1000px-Spalte, waehrend der Katalog danebenlag und die
    # ganze Breite nutzte. Das Raster selbst bleibt unveraendert
    # (minmax(300px,1fr)) - die Karten behalten ihre Groesse und stehen nur zu
    # mehreren nebeneinander.
    # *Wide like the catalogue page. The grid itself is unchanged, so the cards
    #  keep their size and simply sit more per row.*
    hinweis = f'<div class=m>{esc(meldung)}</div>' if meldung else ""
    # Sammelknoepfe nur fuer die Rolle, die Server ohnehin starten und anhalten
    # darf, und nur wenn es ueberhaupt Server gibt.
    sammel = ""
    if darf_verwalten(s) and karten:
        sammel = (f'<div style="display:flex;gap:6px;margin:0 0 14px;flex-wrap:wrap">'
                  f'<form method=post action=/alle><input type=hidden name=csrf value="{s["csrf"]}">'
                  f'<input type=hidden name=was value=anhalten>'
                  f'<button class=y>alle laufenden anhalten</button></form>'
                  f'<form method=post action=/alle><input type=hidden name=csrf value="{s["csrf"]}">'
                  f'<input type=hidden name=was value=starten>'
                  f'<button class=b>zuletzt laufende starten</button></form></div>')
    return HTMLResponse(KOPF + kopfleiste(s, "start") + '<div class="w breit">'
        + hinweis + f"{systemleiste}{sammel}<div class=g>{''.join(karten)}</div>"
        + ("<div class=m>Sicherungen laufen alle 15 Minuten für jeden laufenden Server "
           "(Großvater-Vater-Sohn: 2 Tage alle 15 min, 14 Tage täglich, 8 Wochen, 12 Monate).</div>"
           if SICHERUNG_AN else
           "<div class=warn><b>Es werden keine Sicherungen angelegt.</b> Die Sicherung ist "
           "abgeschaltet (<code>BORG_REPO=aus</code>). Jeder Spielstand liegt nur auf dieser "
           "einen Platte — geht sie kaputt oder löscht jemand einen Server, ist der Stand weg."
           "</div>") + FUSS)


@app.get("/favicon.ico")
def favicon_ico():
    return FileResponse(BILDER / "favicon.ico", media_type="image/x-icon",
                        headers={"Cache-Control": "public, max-age=86400"})


@app.get("/favicon.svg")
def favicon_svg():
    return FileResponse(BILDER / "favicon.svg", media_type="image/svg+xml",
                        headers={"Cache-Control": "public, max-age=86400"})


@app.get("/passkey.js")
def passkey_js():
    """Das einzige JavaScript des Panels. Als eigene Datei, damit die
    Sicherheitsrichtlinie mit "script-src 'self'" auskommt und kein
    'unsafe-inline' braucht."""
    return FileResponse(Path("/opt/panel/statisch/passkey.js"),
                        media_type="text/javascript",
                        headers={"Cache-Control": "no-store"})


@app.get("/apple-touch-icon.png")
def apple_icon():
    return FileResponse(BILDER / "apple-touch-icon.png", media_type="image/png",
                        headers={"Cache-Control": "public, max-age=86400"})


@app.get("/katalogbild/{schluessel}")
def katalogbild(request: Request, schluessel: str):
    if not angemeldet(request):
        return RedirectResponse("/login", 303)
    if not schluessel.isalnum():
        return RedirectResponse("/spiele", 303)
    p = KATALOGBILDER / f"{schluessel}.jpg"
    return FileResponse(p) if p.is_file() else RedirectResponse("/spiele", 303)


# ==========================================================================
#  Katalogseite: suchen, filtern, sortieren
# ==========================================================================
# Alles ueber GET-Parameter und ein normales Formular - KEIN JavaScript. Die
# Sicherheitsrichtlinie des Panels ist "default-src 'none'", ein Filter im
# Browser waere schlicht tot. Serverseitig kostet das bei 154 Eintraegen nichts
# messbares und funktioniert ausserdem mit der Zurueck-Taste, in einem
# Lesezeichen und ohne JavaScript im Browser.
# *Everything via GET parameters and a plain form - no JavaScript, because the
#  panel runs under "default-src 'none'" where client-side filtering would simply
#  be dead. Server-side costs nothing measurable at 154 entries and works with
#  the back button and in a bookmark.*

def anfangsbuchstabe(name: str) -> str:
    """Erste Gruppe eines Namens: ein Grossbuchstabe oder "0-9".

    Genau ein Spiel faengt mit einer Ziffer an (7DaysToDie). Ohne eigene Gruppe
    waere es unter keinem Buchstaben zu finden - und wer es sucht, sucht dann
    lange.
    *Exactly one game starts with a digit; without its own group it would sit
     under no letter at all.*
    """
    z = name[:1].upper()
    return z if z.isalpha() else "0-9"


def katalog_filtern(spiele: list, q: str, kat: str, buchstabe: str = "") -> list:
    """Sucht und filtert, immer alphabetisch sortiert.

    Gesucht wird in Name, Schluessel UND Kurzbeschreibung: wer "koop" eintippt,
    meint eine Eigenschaft, keinen Titel. Gross- und Kleinschreibung spielt keine
    Rolle, und mehrere Woerter muessen ALLE vorkommen (nicht irgendeines) - sonst
    liefert "koop survival" mehr Treffer als "koop" allein, was niemand erwartet.

    Die Sortierung ist FEST alphabetisch. Vorher gab es A-Z, Z-A und "groesste
    zuerst"; an ihre Stelle ist die Buchstabenleiste getreten. Eine umgekehrte
    Reihenfolge neben einer Buchstabenauswahl hilft niemandem: wer unter "M"
    nachsieht, will die M-Spiele, nicht ihre Richtung.
    *Sorting is fixed alphabetical. The three sort orders were replaced by the
     letter bar: reverse order alongside a letter selector helps nobody.*
    """
    raus = spiele
    if kat:
        raus = [g for g in raus if g.get("kategorie") == kat]
    if buchstabe:
        raus = [g for g in raus if anfangsbuchstabe(g["name"]) == buchstabe]
    for wort in q.lower().split():
        raus = [g for g in raus
                if wort in g["name"].lower()
                or wort in g["schluessel"].lower()
                or wort in g.get("kurz", "").lower()]
    return sorted(raus, key=lambda g: g["name"].lower())


@app.get("/spiele", response_class=HTMLResponse)
def spiele(request: Request, meldung: str = "", q: str = "", kat: str = "", b: str = ""):
    s = angemeldet(request)
    if not s:
        return RedirectResponse("/login", 303)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)

    rc, aus = aktion("status", timeout=60)
    da = {z.split("\t")[0] for z in aus.splitlines() if z and not z.startswith("SYSTEM\t")}
    frei_gb = 0
    for z in aus.splitlines():
        if z.startswith("SYSTEM\t"):
            t = z.split("\t")
            if len(t) >= 8:
                frei_gb = (int(t[6]) - int(t[5])) // 1024

    alle = katalog()
    # Ein unbekannter Kategorieschluessel wuerde stumm alles wegfiltern. Lieber
    # ignorieren als eine leere Seite ohne Erklaerung zeigen.
    kategorien = kategorien_liste()
    if kat and kat not in kategorien:
        kat = ""
    b = b.upper() if b != "0-9" else b
    if b and b != "0-9" and not (len(b) == 1 and b.isalpha()):
        b = ""
    gezeigt = katalog_filtern(alle, q, kat, b)

    karten = []
    for g in gezeigt:
        k = g["schluessel"]
        installiert = k in da
        bild = (f'<img src="/katalogbild/{k}" alt="">' if (KATALOGBILDER / f"{k}.jpg").is_file()
                else f'<div class=ph>{g["name"][:2].upper()}</div>')
        passt = frei_gb - g["platte_gb"] >= 10
        if installiert:
            knopf = (f'<form method=get action="/deinstallieren-fragen/{k}">'
                     f'<button class=x>entfernen</button></form>')
            stand = '<span class="s on">installiert</span>'
        elif not passt:
            knopf = '<button class=b disabled>zu wenig Platz</button>'
            stand = '<span class="s off">' + f'braucht {g["platte_gb"]} GB, frei {frei_gb} GB</span>'
        else:
            knopf = (f'<form method=post action=/installieren>'
                     f'<input type=hidden name=csrf value="{s["csrf"]}">'
                     f'<input type=hidden name=schluessel value="{k}">'
                     f'<button class=p>installieren</button></form>')
            stand = '<span class="s off">nicht installiert</span>'
        pw = ("Beitrittspasswort wird beim Anlegen gesetzt" if g["passwort"]["art"] == "env"
              else "kein Passwort möglich" if g["passwort"]["art"] == "keins"
              else "Passwort wird nach dem ersten Start gesetzt")
        karten.append(f"""<div class=c>{bild}<div class=cb>
<div class=n>{g["name"]} {stand}</div>
<div class=z>{g["kurz"]}</div>
<div class=z><b>{g["mem_gb"]} GB</b> Arbeitsspeicher · <b>{g["platte_gb"]} GB</b> Platte · max. {g.get("spieler",4)} Spieler<br>{pw}</div>
<div class=akt>{knopf}</div></div></div>""")

    hinweis = f'<div class=m>{meldung}</div>' if meldung else ""

    # --- Suchfeld, Kategorien, Sortierung ---------------------------------
    # Die aktuelle Auswahl wandert als verstecktes Feld mit, damit eine Suche
    # den Kategoriefilter nicht wegwirft und umgekehrt. Ohne das verliert man
    # bei jedem Klick die halbe Auswahl und tippt sie neu.
    # *The current selection travels along in hidden fields so a search does not
    #  discard the category filter and vice versa.*
    suchfeld = (f'<form method=get action=/spiele class=suche>'
                f'<input type=hidden name=kat value="{esc(kat)}">'
                f'<input type=hidden name=b value="{esc(b)}">'
                f'<input type=search name=q value="{esc(q)}" placeholder="Name oder Stichwort…" '
                f'autofocus>'
                f'<button class=p>suchen</button>'
                + (f'<a class=b href="/spiele?kat={quote(kat)}&b={quote(b)}">zurücksetzen</a>'
                   if q else "")
                + '</form>')

    def verweis(neu_kat: str, beschriftung: str, anzahl: int) -> str:
        aktiv = " hier" if neu_kat == kat else ""
        return (f'<a class="nv{aktiv}" href="/spiele?q={quote(q)}&kat={quote(neu_kat)}'
                f'&b={quote(b)}">{esc(beschriftung)} <span class=z>{anzahl}</span></a>')

    # Die Zahl neben jeder Kategorie zaehlt MIT der Suche, aber ohne den
    # Kategoriefilter: sie beantwortet "wie viele davon passen zu dem, was ich
    # gerade suche". Eine Zahl, die den eigenen Filter mitzaehlt, waere in jeder
    # Kategorie ausser der gewaehlten null.
    # *Counts respect the search but not the category filter, answering "how many
    #  of these match what I am looking for".*
    kat_leiste = (verweis("", "alle", len(katalog_filtern(alle, q, "", b)))
                  + "".join(verweis(k, n, len(katalog_filtern(alle, q, k, b)))
                            for k, n in kategorien.items()
                            if katalog_filtern(alle, "", k)))

    # --- Buchstabenleiste ---------------------------------------------------
    # Buchstaben OHNE Treffer bleiben stehen, nur nicht anklickbar. Sie
    # wegzulassen liesse die Leiste bei jeder Suche die Breite wechseln, und man
    # muesste jedes Mal neu suchen, wo das M nun steht. Ein ausgegrautes M sagt
    # ausserdem etwas: dass es dort nichts gibt.
    # *Letters without matches stay in place but are not clickable. Dropping them
    #  would make the bar change width on every search, and a greyed-out letter
    #  says something in itself: there is nothing there.*
    vorhanden = {}
    for g in katalog_filtern(alle, q, kat):
        vorhanden[anfangsbuchstabe(g["name"])] = vorhanden.get(anfangsbuchstabe(g["name"]), 0) + 1
    gruppen = ["0-9"] + list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    buchstaben = (f'<a class="nv{" hier" if not b else ""}" '
                  f'href="/spiele?q={quote(q)}&kat={quote(kat)}">alle</a>')
    for gr in gruppen:
        n = vorhanden.get(gr, 0)
        if not n:
            buchstaben += f'<span class="nv leer">{gr}</span>'
        else:
            buchstaben += (f'<a class="nv{" hier" if b == gr else ""}" title="{n} Spiele" '
                           f'href="/spiele?q={quote(q)}&kat={quote(kat)}&b={quote(gr)}">{gr}</a>')

    if gezeigt:
        inhalt = f'<div class="g eng">{"".join(karten)}</div>'
    else:
        inhalt = ('<div class=m>Kein Treffer. '
                  + (f'Gesucht wurde nach <b>{esc(q)}</b>' if q else "")
                  + (f' in <b>{esc(kategorien.get(kat, kat))}</b>' if kat else "")
                  + (f' unter <b>{esc(b)}</b>' if b else "")
                  + '. <a class=b href=/spiele>alles zeigen</a></div>')

    # Eigene, breitere Inhaltsspalte statt RUMPF: siehe .w.breit im Stylesheet.
    return HTMLResponse(KOPF + kopfleiste(s, "spiele") + '<div class="w breit">' + hinweis
        + suchfeld
        + f'<div class=leiste>{kat_leiste}</div>'
        + f'<div class="leiste abc">{buchstaben}</div>'
        + f'<div class=m><b>{len(gezeigt)}</b> von {len(alle)} Spielen'
          + (f' — gesucht nach „{esc(q)}“' if q else "")
          + (f' in {esc(kategorien.get(kat, ""))}' if kat else "")
          + (f', Anfangsbuchstabe <b>{esc(b)}</b>' if b else "")
          + f'. {len(da)} Server angelegt, {frei_gb} GB frei. '
          f'Die Installation legt Beitritts- und Adminpasswort an (unter '
          f'„Zugangsdaten“ zu sehen) und begrenzt auf 4 Spieler. Der erste Start '
          f'lädt das Spiel herunter — je nach Titel 5 bis 30 Minuten.</div>'
        + inhalt + FUSS)


@app.post("/installieren")
def installieren(request: Request, csrf: str = Form(""), schluessel: str = Form("")):
    s = pruefe(request, csrf)
    if not s or not darf_verwalten(s):
        return RedirectResponse("/login", 303)
    rc, aus = aktion("installieren", schluessel, timeout=900)
    protokoll(s, "Spiel installiert", schluessel,
              "ok" if rc == 0 else "fehlgeschlagen", meldung=aus.strip()[:200])
    if rc != 0:
        return RedirectResponse(f"/spiele?meldung={quote(aus.strip()[:300])}", 303)
    t = aus.strip().split("\t")
    name = t[1] if len(t) > 1 else schluessel
    stand = t[2] if len(t) > 2 else ""
    return RedirectResponse(
        f"/spiele?meldung={quote(f'{name} angelegt und {stand}. Passwörter stehen unter Zugangsdaten.')}", 303)


@app.get("/deinstallieren-fragen/{stack}", response_class=HTMLResponse)
def deinstallieren_fragen(request: Request, stack: str):
    s = angemeldet(request)
    if not s or not darf_verwalten(s):
        return RedirectResponse("/login", 303)
    p = stackinfo(stack)
    if not p:
        return HTMLResponse(KOPF + kopfleiste(s) + RUMPF
            + '<div class=m>Dieser Server wurde nicht über den Katalog installiert und '
              'lässt sich hier nicht entfernen. Das schützt die von Hand gebauten Server '
              '(Enshrouded, Palworld und die anderen) vor einem Fehlklick.</div>'
            + '<div class=m><a class=b href=/spiele>zurück</a></div>' + FUSS)
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"""
<div class=m><b>{p.get("name", stack)} wirklich entfernen?</b><br><br>
{"Es wird zuerst eine letzte Sicherung angelegt. Schlägt die fehl, bricht der Vorgang ab und es wird nichts gelöscht. Danach verschwinden" if SICHERUNG_AN else "Es verschwinden"}
Container, Spielstände auf der Platte,
Konfiguration, DNS-Name und die Zugangsdaten dieses Servers.<br><br>
{"<b>Die Sicherungen im Borg-Repository bleiben erhalten</b> — der Stand lässt sich also später zurückholen, aber nicht über diese Oberfläche."
 if SICHERUNG_AN else
 "<b>Es gibt keine Sicherung.</b> Die Sicherung ist abgeschaltet (<code>BORG_REPO=aus</code>), es wird auch keine letzte angelegt: dieser Spielstand ist danach endgültig weg."}</div>
<div class=m><form method=post action=/deinstallieren>
<input type=hidden name=csrf value="{s["csrf"]}">
<input type=hidden name=stack value="{stack}">
<button class=x>ja, entfernen</button></form>
<a class=b href=/spiele>abbrechen</a></div>""" + FUSS)


@app.post("/deinstallieren")
def deinstallieren(request: Request, csrf: str = Form(""), stack: str = Form("")):
    s = pruefe(request, csrf)
    if not s or not darf_verwalten(s):
        return RedirectResponse("/login", 303)
    rc, aus = aktion("deinstallieren", stack, timeout=1800)
    protokoll(s, "Spiel entfernt", stack,
              "ok" if rc == 0 else "fehlgeschlagen", meldung=aus.strip()[:200])
    return RedirectResponse(f"/spiele?meldung={quote(aus.strip()[:300])}", 303)


@app.get("/login", response_class=HTMLResponse)
def login_form(request: Request, fehler: str = ""):
    # Das Logo auch hier: Die Anmeldung ist die erste Seite, die man sieht -
    # ohne Kopfleiste stuende sonst nur ein nacktes Formular da.
    return HTMLResponse(KOPF + RUMPF + f"""<div class=card>
<div style="text-align:center;margin-bottom:6px">{LOGO.replace('class=logo', 'class=logo style="width:56px;height:56px;display:inline-block"')}</div>
<h1 style="text-align:center">Spieleserver</h1>
<form method=post action=/login>
<label>Benutzer</label><input type=text name=nutzer autocomplete=username autofocus>
<label>Passwort</label><input type=password name=passwort autocomplete=current-password>
<label>Einmalcode (6 Ziffern) oder Wiederherstellungscode</label><input type=text name=code inputmode=text autocomplete=one-time-code>
<div style=margin-top:16px><button class=p style=width:100%>Anmelden</button></div>
<button type=button class=b style="width:100%;margin-top:10px" data-passkey=anmelden hidden>mit Passkey anmelden</button>
<div id=pk-meldung></div>
{f'<div class=f>{fehler}</div>' if fehler else ''}
</form><script src="/passkey.js" defer></script></div>""" + FUSS)


@app.post("/login")
def login(request: Request, nutzer: str = Form(""), passwort: str = Form(""), code: str = Form("")):
    ip = request.client.host if request.client else "?"
    if (rest := gesperrt(ip)):
        return login_form(request, f"Zu viele Fehlversuche. Erneut in {rest // 60 + 1} Minuten.")
    n = laden()["nutzer"].get(nutzer)
    passwort_ok = False
    if n:
        try:
            hasher.verify(n["passwort_hash"], passwort)
            passwort_ok = True
        except (VerifyMismatchError, InvalidHashError):
            passwort_ok = False
    # Erste Anmeldung: Passwort stimmt, aber der zweite Faktor ist noch nicht
    # eingerichtet. Dann NICHT anmelden, sondern zur Einrichtung schicken — mit
    # einem kurzlebigen, eigens signierten Token, das keine Sitzung ist.
    if passwort_ok and not n.get("totp_bestaetigt"):
        fehlversuche.pop(ip, None)
        marke = einrichtung.dumps({"nutzer": nutzer})
        a = RedirectResponse("/einrichten", 303)
        a.set_cookie("einrichtung", marke, httponly=True, secure=True,
                     samesite="strict", max_age=EINRICHTUNG_MAXALTER)
        return a
    # TOTP oder Wiederherstellungscode. Die FORM entscheidet, welcher Weg geprueft
    # wird: sechs Ziffern sind ein TOTP, 16 Zeichen aus dem Alphabet ein
    # Wiederherstellungscode. Damit laeuft Argon2 nicht bei jedem falsch
    # getippten TOTP-Code mit - zehn Argon2-Pruefungen kosten rund eine Sekunde.
    # *The shape decides which path is checked, so Argon2 does not run on every
    #  mistyped TOTP code.*
    ok = per_code = False
    if passwort_ok:
        blank = code.replace("-", "").replace(" ", "")
        if len(blank) == CODE_LAENGE and not blank.isdigit():
            ok = per_code = code_einloesen(nutzer, blank)
        else:
            ok = pyotp.TOTP(n["totp"]).verify(code, valid_window=1)
    if not ok:
        fehlversuche.setdefault(ip, []).append(time.time())
        # Auch der GESCHEITERTE Versuch gehoert ins Protokoll - nach einem
        # Vorfall sucht man genau danach. Der Nutzername wird mitgeschrieben,
        # das Passwort selbstverstaendlich nicht; ob es am Passwort oder am
        # zweiten Faktor lag, bleibt bewusst offen, damit das Protokoll keine
        # Auskunft daruber gibt, welche Haelfte schon stimmte.
        # *Failed attempts belong in the log; which half was already correct
        #  deliberately is not recorded.*
        protokoll({"nutzer": nutzer or "—", "rolle": "—"},
                  "Anmeldung fehlgeschlagen", "", "abgelehnt", ip=ip)
        return login_form(request, "Anmeldung fehlgeschlagen.")
    fehlversuche.pop(ip, None)
    if per_code:
        # Der Verbrauch eines Codes gehoert ins Protokoll: es ist der eine Weg
        # hinein, der ohne den zweiten Faktor im ueblichen Sinne auskommt.
        # *Redeeming a code belongs in the log: it is the one way in that does
        #  not use the second factor as normally understood.*
        rest = len(laden()["nutzer"][nutzer].get("codes") or [])
        protokoll({"nutzer": nutzer, "rolle": n.get("rolle", "?")},
                  "Mit Wiederherstellungscode angemeldet", "", "ok", ip=ip, verbleibend=rest)
    else:
        protokoll({"nutzer": nutzer, "rolle": n.get("rolle", "?")}, "Angemeldet", "", "ok", ip=ip)
    antwort = RedirectResponse("/", 303)
    antwort.set_cookie("sitzung", signierer.dumps({"nutzer": nutzer, "csrf": secrets.token_urlsafe(24)}),
                       httponly=True, secure=True, samesite="strict", max_age=SITZUNG_MAXALTER)
    return antwort


def einrichtungs_nutzer(request: Request) -> str | None:
    keks = request.cookies.get("einrichtung")
    if not keks:
        return None
    try:
        name = einrichtung.loads(keks, max_age=EINRICHTUNG_MAXALTER)["nutzer"]
    except BadSignature:
        return None
    n = laden()["nutzer"].get(name)
    # Nach der Bestaetigung ist dieser Weg zu — sonst koennte jemand mit einem
    # alten Token jederzeit den QR-Code eines fremden Kontos nachladen.
    return name if n and not n.get("totp_bestaetigt") else None


@app.get("/qr")
def qr(request: Request):
    """Liefert den QR-Code als SVG. Nur waehrend der Einrichtung erreichbar."""
    name = einrichtungs_nutzer(request)
    if not name:
        return RedirectResponse("/login", 303)
    n = laden()["nutzer"][name]
    uri = pyotp.TOTP(n["totp"]).provisioning_uri(name=name, issuer_name="Spieleserver @@WELT_NAME@@")
    bild = qrcode.make(uri, image_factory=qrcode.image.svg.SvgPathImage, box_size=11, border=2)
    from io import BytesIO
    puffer = BytesIO()
    bild.save(puffer)
    return Response(puffer.getvalue(), media_type="image/svg+xml",
                    headers={"Cache-Control": "no-store"})


@app.get("/einrichten", response_class=HTMLResponse)
def einrichten_form(request: Request, fehler: str = ""):
    name = einrichtungs_nutzer(request)
    if not name:
        return RedirectResponse("/login", 303)
    geheim = laden()["nutzer"][name]["totp"]
    return HTMLResponse(KOPF + RUMPF + f"""<div class=card style=max-width:420px>
<h1>Zwei-Faktor einrichten</h1>
<p style=font-size:14px;color:var(--d)>Hallo <b>{name}</b>. Für die Anmeldung brauchst
du etwas, das alle 30 Sekunden einen sechsstelligen Code erzeugt. Scanne dazu den
Code unten und gib danach die sechs Ziffern ein.</p>
<div style="background:#fff;padding:10px;border-radius:10px;display:flex;justify-content:center;margin:14px 0">
<img src="/qr" alt="QR-Code" style="width:210px;height:210px"></div>
<p style=font-size:12px;color:var(--d)>Geht das Scannen nicht, trage dieses Geheimnis
von Hand ein:<br><code style=word-break:break-all>{geheim}</code></p>
<details style="margin:10px 0;font-size:13px">
<summary style="cursor:pointer;color:var(--a)">Ich möchte keine App auf dem Handy</summary>
<div style="color:var(--d);margin-top:8px;line-height:1.55">
Musst du auch nicht. Das Geheimnis oben passt in <b>alles</b>, was TOTP beherrscht:
<ul style=margin:8px 0;padding-left:18px>
<li><b>Passwortmanager auf dem PC</b> — <b>KeePassXC</b> kann es kostenlos und
    rein lokal. Auch ein selbst betriebenes <b>Vaultwarden</b> beherrscht es.
    Beim gehosteten Bitwarden ist es dagegen kostenpflichtig.</li>
<li><b>Ein eigenes kleines Gerät</b> statt des Handys — der
    <b>Reiner SCT Authenticator</b> (rund 45 €) hat eine Kamera, scannt den Code
    oben genau wie eine App und speichert bis zu 60 Konten. Es braucht keine
    Verbindung nach außen.</li>
<li><b>Ein Schlüsselanhänger-Token</b> (etwa Token2, ab rund 20 €) geht auch —
    bei den günstigen Modellen ist das Geheimnis aber ab Werk fest vergeben, sie
    können <i>dieses</i> hier nicht übernehmen. Dafür braucht es die
    programmierbaren Modelle.</li>
</ul>
Nach dem Bestätigen bekommst du außerdem <b>Wiederherstellungscodes</b> zum
Ausdrucken — damit kommst du auch dann herein, wenn das Gerät gerade nicht
greifbar ist.
</div></details>
<form method=post action=/einrichten>
<label>Code aus der App</label>
<input type=text name=code inputmode=numeric autocomplete=one-time-code autofocus>
<div style=margin-top:14px><button class=p style=width:100%>Bestätigen und anmelden</button></div>
{f'<div class=f>{fehler}</div>' if fehler else ''}
</form>
<p style=font-size:12px;color:var(--d);margin-top:14px>Das Geheimnis wird nur dieses eine
Mal angezeigt. Gleich danach bekommst du deine Wiederherstellungscodes — drucke sie aus,
dann bist du auch ohne das Gerät nicht ausgesperrt.</p>
</div>""" + FUSS)


@app.post("/einrichten")
def einrichten(request: Request, code: str = Form("")):
    name = einrichtungs_nutzer(request)
    if not name:
        return RedirectResponse("/login", 303)
    ip = request.client.host if request.client else "?"
    if (rest := gesperrt(ip)):
        return einrichten_form(request, f"Zu viele Fehlversuche. Erneut in {rest // 60 + 1} Minuten.")
    d = laden()
    if not pyotp.TOTP(d["nutzer"][name]["totp"]).verify(code, valid_window=1):
        fehlversuche.setdefault(ip, []).append(time.time())
        return einrichten_form(request, "Code stimmt nicht. Uhrzeit des Geräts prüfen.")
    fehlversuche.pop(ip, None)
    d["nutzer"][name]["totp_bestaetigt"] = True
    # Wiederherstellungscodes JETZT erzeugen, nicht beim Anlegen des Kontos: so
    # sieht sie der Benutzer selbst und nie der Administrator - dieselbe
    # Ueberlegung wie beim TOTP-Geheimnis (siehe docs/07, "Das TOTP-Geheimnis
    # sieht niemand").
    # *Generated here rather than at account creation, so the user sees them and
    #  the administrator never does - the same reasoning as for the TOTP secret.*
    klar, hashes = codes_neu()
    d["nutzer"][name]["codes"] = hashes
    speichern(d)
    protokoll({"nutzer": name, "rolle": d["nutzer"][name].get("rolle", "?")},
              "Zweiten Faktor eingerichtet", "", "ok", ip=ip, codes=len(hashes))
    a = RedirectResponse("/codes", 303)
    a.set_cookie("sitzung", signierer.dumps({"nutzer": name, "csrf": secrets.token_urlsafe(24)}),
                 httponly=True, secure=True, samesite="strict", max_age=SITZUNG_MAXALTER)
    # Die Codes reisen EINMAL in einem kurzlebigen, eigens signierten Keks zur
    # Anzeigeseite. Nicht im Sitzungscookie: das lebt acht Stunden und geht bei
    # jeder Anfrage mit. Nicht in der URL: das landete im Verlauf und im Log.
    # *They travel once in a short-lived, separately signed cookie: not in the
    #  session cookie, which lives eight hours and rides along on every request,
    #  and not in the URL, which would land in history and logs.*
    a.set_cookie("codes", einrichtung.dumps({"nutzer": name, "codes": klar}),
                 httponly=True, secure=True, samesite="strict", max_age=900)
    a.delete_cookie("einrichtung")
    return a


@app.get("/codes", response_class=HTMLResponse)
def codes_zeigen(request: Request):
    """Zeigt die Wiederherstellungscodes GENAU EINMAL, direkt nach der
    Einrichtung. Danach sind sie nur noch gehasht vorhanden und niemand - auch
    kein Administrator - kann sie noch einmal ausgeben."""
    s = angemeldet(request)
    if not s:
        return RedirectResponse("/login", 303)
    keks = request.cookies.get("codes")
    if not keks:
        return RedirectResponse("/", 303)
    try:
        d = einrichtung.loads(keks, max_age=900)
    except BadSignature:
        return RedirectResponse("/", 303)
    if d.get("nutzer") != s["nutzer"]:
        return RedirectResponse("/", 303)

    liste = "".join(f"<div>{esc(code_lesbar(c))}</div>" for c in d.get("codes", []))
    antwort = HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"""<h1>Wiederherstellungscodes</h1>
<div class=warn><b>Diese Liste wird nur dieses eine Mal angezeigt.</b> Drucke sie aus
oder schreibe sie ab und lege sie dorthin, wo du wichtige Papiere aufbewahrst.
Danach sind die Codes nur noch verschlüsselt gespeichert — auch ein Administrator
kann sie nicht mehr sichtbar machen.</div>
<div style="font-family:ui-monospace,monospace;font-size:17px;line-height:2;
            background:var(--k);padding:16px 20px;border-radius:10px;
            display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));margin:14px 0">
{liste}</div>
<div class=m>Jeder Code funktioniert <b>einmal</b> und tritt an die Stelle der sechs
Ziffern aus der App — das Passwort brauchst du weiterhin. Sie sind für den Fall
gedacht, dass dein Gerät verloren geht oder du gerade keinen Zugriff darauf hast.</div>
<div class=m><a class=b href="/">weiter zur Übersicht</a></div>""" + FUSS)
    # Den Keks sofort wieder wegnehmen: ein zweiter Aufruf der Seite - auch aus
    # dem Verlauf - soll nichts mehr zeigen.
    # *Cleared immediately, so a second visit shows nothing, history included.*
    antwort.delete_cookie("codes")
    return antwort


@app.get("/abmelden")
def abmelden():
    a = RedirectResponse("/login", 303)
    a.delete_cookie("sitzung")
    return a


@app.post("/aktion")
def steuern(request: Request, csrf: str = Form(""), stack: str = Form(""), was: str = Form("")):
    s = pruefe(request, csrf)
    if not s:
        return RedirectResponse("/login", 303)
    if was in ("start", "stop", "restart"):
        rc, aus = aktion(was, stack, timeout=180)
        protokoll(s, {"start": "gestartet", "stop": "angehalten",
                      "restart": "neu gestartet"}[was], stack,
                  "ok" if rc == 0 else "fehlgeschlagen")
    return RedirectResponse("/", 303)


def sicherung_aus_seite(s: dict):
    """Antwort auf einen Archivweg bei abgeschalteter Sicherung. Bewusst eine
    erklaerende Seite und keine Umleitung auf die Uebersicht: wer hier landet,
    hat einen alten Lesezeichen- oder Verlaufseintrag und soll den Grund lesen,
    statt sich zu fragen, warum der Klick nichts tut."""
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF
        + '<h1>Keine Sicherungen</h1>'
          '<div class=warn>Die Sicherung ist abgeschaltet (<code>BORG_REPO=aus</code>). '
          'Es gibt keine Archive, und es lässt sich nichts zurückspielen.</div>'
          '<div class=m><a class=b href=/>zurück zur Übersicht</a></div>' + FUSS)


@app.get("/archive/{stack}", response_class=HTMLResponse)
def archive(request: Request, stack: str):
    s = angemeldet(request)
    if not s:
        return RedirectResponse("/login", 303)
    if not SICHERUNG_AN:
        return sicherung_aus_seite(s)
    rc, aus = aktion("archive", stack, timeout=180)
    if rc != 0:
        return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"<h1>{stack}</h1><div class=f>{aus}</div><a class=b href=/>zurück</a>" + FUSS)
    zeilen = []
    for z in reversed(aus.splitlines()):
        if "\t" not in z:
            continue
        name, zeit = z.split("\t", 1)
        knopf = (f'<a class=b href="/restore-fragen/{stack}/{name}">zurückspielen</a>'
                 if darf_verwalten(s) else '<span class=z>nur Admin</span>')
        zeilen.append(f"<tr><td><code>{name}</code></td><td>{zeit}</td><td style=text-align:right>{knopf}</td></tr>")
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"<h1>Sicherungen: {stack}</h1>"
        f"<div class=d><a class=b href=/>zurück zur Übersicht</a></div>"
        f"<table><tr><th>Archiv</th><th>Zeitpunkt</th><th></th></tr>"
        f"{''.join(zeilen) or '<tr><td colspan=3>noch keine</td></tr>'}</table>" + FUSS)


@app.get("/restore-fragen/{stack}/{archiv}", response_class=HTMLResponse)
def restore_fragen(request: Request, stack: str, archiv: str):
    """Serverseitige Rueckfrage — ohne JavaScript, damit sie nicht an der
    Content-Security-Policy scheitert und dabei unbemerkt ausfaellt."""
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    if not SICHERUNG_AN:
        return sicherung_aus_seite(s)
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"""<h1>Wirklich zurückspielen?</h1>
<div class=d>{stack} &larr; <code>{archiv}</code></div>
<div class=warn>Der Server wird angehalten, der <b>aktuelle Stand als Kopie gesichert</b>
und danach der gewählte Stand eingespielt. Anschließend startet er wieder — aber
nur, wenn er vorher lief.</div>
<form method=post action=/restore><input type=hidden name=csrf value="{s['csrf']}">
<input type=hidden name=stack value="{stack}"><input type=hidden name=archiv value="{archiv}">
<button class=x>Ja, diesen Stand einspielen</button></form>
<a class=b href="/archive/{stack}">Abbrechen</a>""" + FUSS)


@app.post("/aktualisieren")
def aktualisieren(request: Request, csrf: str = Form(""), stack: str = Form("")):
    """Neue Fassung des Images holen. Die Sicherung davor ist Bedingung, nicht
    Schritt — scheitert sie, unterbleibt das Update (siehe panel-aktion)."""
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    rc, aus = aktion("aktualisieren", stack, timeout=1800)
    teile = aus.strip().split("\t")
    art = teile[1] if len(teile) > 2 else ""
    protokoll(s, "Server aktualisiert", stack,
              "ok" if rc == 0 else "fehlgeschlagen", ergebnis_art=art or "—")
    m = (teile[2] if rc == 0 and len(teile) > 2 else
         f"Nicht aktualisiert: {aus.strip()[:220]}")
    return RedirectResponse(f"/?meldung={quote(m)}", 303)


@app.post("/auto-update")
def auto_update_schalten(request: Request, csrf: str = Form(""),
                         stack: str = Form(""), wert: str = Form("")):
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    rc, aus = aktion("auto-update", stack, wert, timeout=30)
    protokoll(s, "Automatische Updates umgestellt", stack,
              "ok" if rc == 0 else "fehlgeschlagen", auf=wert)
    m = (f"Automatische Updates für {stack}: {wert}." if rc == 0
         else f"Nicht umgestellt: {aus.strip()[:200]}")
    return RedirectResponse(f"/?meldung={quote(m)}", 303)


@app.post("/alle")
def alle_steuern(request: Request, csrf: str = Form(""), was: str = Form("")):
    """Alles anhalten oder die zuletzt laufenden wieder starten."""
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    if was not in ("anhalten", "starten"):
        return RedirectResponse("/", 303)
    rc, aus = aktion(f"alle-{was}", timeout=900)
    protokoll(s, f"Alle Server {'angehalten' if was == 'anhalten' else 'gestartet'}",
              "", "ok" if rc == 0 else "fehlgeschlagen", meldung=aus.strip()[:120])
    m = aus.strip().split("\t")[-1] if rc == 0 else f"Fehlgeschlagen: {aus.strip()[:200]}"
    return RedirectResponse(f"/?meldung={quote(m)}", 303)


@app.post("/restore", response_class=HTMLResponse)
def restore(request: Request, csrf: str = Form(""), stack: str = Form(""), archiv: str = Form("")):
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    if not SICHERUNG_AN:
        return sicherung_aus_seite(s)
    rc, aus = aktion("restore", stack, archiv, timeout=1800)
    protokoll(s, "Wiederherstellung", stack,
              "ok" if rc == 0 else "fehlgeschlagen", archiv=archiv)
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"<h1>{'Zurückgespielt' if rc == 0 else 'Fehlgeschlagen'}</h1>"
        f"<div class=d>{stack} &larr; <code>{archiv}</code></div>"
        f"<pre style=\"background:var(--k);padding:12px;border-radius:8px;white-space:pre-wrap\">{aus}</pre>"
        f"<a class=b href=/>zur Übersicht</a>" + FUSS)


@app.get("/konfig/{stack}", response_class=HTMLResponse)
def konfig(request: Request, stack: str, meldung: str = ""):
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    zeilen = []

    # Zuerst ALLE Umgebungsvariablen des Stacks. Bis 2026-09-07 standen hier nur
    # 12 Felder aus einer festen Liste - von 69 Variablen der acht Server waren
    # 15 erreichbar, der Rest ging nur per SSH.
    # *Until 2026-09-07 only 12 allow-listed fields appeared here: 15 of the
    #  eight servers' 69 variables were reachable, the rest needed SSH.*
    rc_env, aus_env = aktion("compose-lesen", stack, timeout=60)
    for z in aus_env.splitlines():
        teile = z.split("\t")
        if len(teile) < 3:
            continue
        name, wert, zustand = teile[0], teile[1], teile[2]
        if zustand == "gesperrt":
            # Gesperrte Variablen werden GEZEIGT, aber nicht bearbeitbar - wer
            # sie sucht, soll sehen, dass es sie gibt und warum sie fest ist.
            # *Shown but not editable: anyone looking for them should see that
            #  they exist and why they are fixed.*
            zeilen.append(f'<tr><td><code>{esc(name)}</code></td><td>'
                          f'<input type=text value="{esc(wert)}" disabled style="width:220px">'
                          f' <span class=z>fest</span></td></tr>')
        else:
            zeilen.append(
                f'<tr><td><code>{esc(name)}</code></td><td>'
                f'<form method=post action=/konfig-setzen style="display:inline">'
                f'<input type=hidden name=csrf value="{s["csrf"]}">'
                f'<input type=hidden name=stack value="{esc(stack)}">'
                f'<input type=hidden name=feld value="env:{esc(name)}">'
                f'<input type=text name=wert value="{esc(wert)}" style="width:220px">'
                f'<button class=p>speichern</button></form></td></tr>')

    # Danach die Sonderfaelle, die NICHT in der Umgebung stehen (Palworld fuehrt
    # die wirksamen Werte in seiner eigenen Datei) und die Speichergrenze.
    rc, aus = aktion("konfig-lesen", stack, timeout=60)
    for z in aus.splitlines():
        if "\t" not in z:
            continue
        feld, wert = z.split("\t", 1)
        if not (feld.startswith("ini:") or feld == "mem_limit"):
            continue          # steht schon oben als Umgebungsvariable
        beschriftung = feld.replace("ini:", "").replace("_", " ")
        hinweis = " <span class=z>(wirksam)</span>" if feld.startswith("ini:") else ""
        zeilen.append(f"""<tr><td>{esc(beschriftung)}{hinweis}</td><td>
<form method=post action=/konfig-setzen style="display:inline">
<input type=hidden name=csrf value="{s['csrf']}"><input type=hidden name=stack value="{esc(stack)}">
<input type=hidden name=feld value="{esc(feld)}">
<input type=text name=wert value="{esc(wert)}" style="width:220px">
<button class=p>speichern</button></form></td></tr>""")
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + f"<h1>Einstellungen: {stack}</h1>"
        f"{f'<div class=warn>{meldung}</div>' if meldung else ''}"
        f"<table><tr><th>Feld</th><th>Wert</th></tr>{''.join(zeilen)}</table>"
        "<div class=warn>Änderungen wirken erst nach einem <b>Neustart</b> des Servers.</div>"
        f'<a class=b href="/dateien/{stack}">Konfigdateien des Servers</a> '
        f"<a class=b href=/>zurück</a>"
        "<div class=m>Hier stehen die Werte aus der <b>compose-Datei</b> (Container). Die "
        "Einstellungen des Spiels selbst — Weltname, Schwierigkeit, Regeln — liegen in den "
        "<b>Konfigdateien</b> nebenan. "
        "Bearbeitbar sind nur einzelne Felder aus einer festen Liste — nie die "
        "compose-Datei als Ganzes. Bei Palworld sind die mit „wirksam“ markierten Werte "
        "maßgeblich: der Container erzeugt seine Einstellungsdatei nicht mehr selbst.</div>" + FUSS)


@app.post("/konfig-setzen")
def konfig_setzen(request: Request, csrf: str = Form(""), stack: str = Form(""),
                  feld: str = Form(""), wert: str = Form("")):
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    # "env:NAME" geht an compose-feld (alle Umgebungsvariablen), alles andere
    # an den alten Weg (Palworlds eigene Datei, mem_limit). Der Wert geht ueber
    # stdin, nicht als Parameter: er kann Leerzeichen und Sonderzeichen
    # enthalten, und in der Prozessliste hat er nichts zu suchen.
    # *"env:NAME" goes to compose-feld; the value travels via stdin, never as an
    #  argument - it may contain spaces and has no business in the process list.*
    if feld.startswith("env:"):
        try:
            p = subprocess.run(AKTION + ["compose-setzen", stack, feld[4:]],
                               input=wert, capture_output=True, text=True, timeout=60)
            rc, aus = p.returncode, (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired:
            rc, aus = 1, "Zeitüberschreitung"
    else:
        rc, aus = aktion("konfig-setzen", stack, feld, wert, timeout=60)
    protokoll(s, "Konfigurationsfeld gesetzt", stack,
              "ok" if rc == 0 else "fehlgeschlagen",
              feld=feld, wert=ohne_geheimnis(feld, wert))
    m = ("Gespeichert. Wirkt nach einem Neustart des Servers."
         if rc == 0 else f"Nicht gespeichert: {aus.strip()[:200]}")
    return RedirectResponse(f"/konfig/{stack}?meldung={quote(m)}", 303)


# ==========================================================================
#  Konfigurationsdateien der Spiele
# ==========================================================================
# WICHTIG, und der Grund warum das hier ueberhaupt erlaubt ist: Bearbeitet
# werden die Dateien der SPIELE unter /srv/games, nicht die compose.yaml. Eine
# compose-Datei beschreibt den Container - wer dort ein Volume "/:/host"
# eintraegt, ist root. Eine Spielkonfiguration liest der Spielprozess IM
# Container, der als UID 4711 ohne Rechte laeuft; schlimmster Fall ist ein
# Server, der nicht mehr startet. Die Pfadpruefung sitzt vollstaendig in
# konfig-datei (aufloesen, DANN pruefen - wegen des Symlinks "z: -> /" im
# Wine-Praefix von StarRupture).
# *These are the games' own config files, not compose.yaml. A compose file
#  describes the container and "/:/host" means root; a game config is read by an
#  unprivileged process inside the container, so the worst case is a server that
#  will not start. Path validation lives entirely in konfig-datei.*

SCHLUESSEL_ZEILE = re.compile(r"^([ \t]*)([A-Za-z_][A-Za-z0-9_.\- ]*?)([ \t]*[:=][ \t]*)(.*)$")


def konf_parsen(text: str, endung: str) -> list:
    """Liefert [(schluessel, wert, abschnitt)] fuer die Formularansicht.

    Flaches JSON wird ueber json geparst, alles andere zeilenweise. Verschachtelte
    Strukturen bekommen KEIN Feld - sie liessen sich ueber ein Formular nicht
    verlustfrei zurueckschreiben. Fuer sie gibt es den Rohtext.
    *Nested structures deliberately get no form field: they cannot be written
     back losslessly. The raw editor covers them.*
    """
    if endung == ".json":
        try:
            d = json.loads(text)
        except json.JSONDecodeError:
            return []
        if not isinstance(d, dict):
            return []
        return [(k, "" if v is None else str(v), "")
                for k, v in d.items() if not isinstance(v, (dict, list))]

    raus, abschnitt = [], ""
    for z in text.splitlines():
        roh = z.strip()
        if not roh or roh[0] in "#;":
            continue
        if roh.startswith("[") and roh.endswith("]"):
            abschnitt = roh[1:-1]
            continue
        m = SCHLUESSEL_ZEILE.match(z)
        if m:
            wert = m.group(4)
            # Kommentar am Zeilenende gehoert nicht in das Eingabefeld.
            k = re.search(r"\s+(?://|#|;).*$", wert)
            if k:
                wert = wert[:k.start()]
            raus.append((m.group(2).strip(), wert.strip(), abschnitt))
    return raus


def konf_ersetzen(text: str, endung: str, neue: dict) -> str:
    """Setzt Werte, ERHAELT Kommentare, Reihenfolge und Formatierung.

    Die Datei wird nicht neu geschrieben, sondern zeilenweise angefasst. Ein
    Neuschreiben aus dem geparsten Zustand wuerde jeden Kommentar vernichten -
    und in server.properties oder PalWorldSettings.ini steht die halbe
    Dokumentation in den Kommentaren.
    *Rewritten line by line rather than regenerated: regenerating would destroy
     every comment, and half the documentation lives in them.*
    """
    if endung == ".json":
        d = json.loads(text)
        for k, v in neue.items():
            if k in d and not isinstance(d[k], (dict, list)):
                alt = d[k]
                if isinstance(alt, bool):
                    d[k] = v.strip().lower() in ("true", "1", "ja", "on")
                elif isinstance(alt, int):
                    try:
                        d[k] = int(v)
                    except ValueError:
                        d[k] = alt
                elif isinstance(alt, float):
                    try:
                        d[k] = float(v)
                    except ValueError:
                        d[k] = alt
                else:
                    d[k] = v
        return json.dumps(d, indent=1, ensure_ascii=False) + "\n"

    zeilen = text.splitlines(keepends=True)
    for i, z in enumerate(zeilen):
        m = SCHLUESSEL_ZEILE.match(z.rstrip("\r\n"))
        if not m:
            continue
        k = m.group(2).strip()
        if k not in neue:
            continue
        rest, schwanz = m.group(4), ""
        kom = re.search(r"\s+(?://|#|;).*$", rest)
        if kom:
            schwanz = kom.group(0)
        ende = "\r\n" if z.endswith("\r\n") else ("\n" if z.endswith("\n") else "")
        zeilen[i] = f"{m.group(1)}{m.group(2)}{m.group(3)}{neue[k]}{schwanz}{ende}"
    return "".join(zeilen)


KONFIGZAHLEN = Path("/opt/panel/daten/konfigzahlen.json")


def konfigzahlen() -> dict:
    """Anzahl der Konfigurationsdateien je Server, gepflegt von spiel-einrichtung.
    Faellt sie aus, fehlt nur eine Zahl in der Anzeige."""
    try:
        return json.loads(KONFIGZAHLEN.read_text())
    except Exception:
        return {}


def konf_dateien(stack: str) -> list:
    rc, aus = aktion("konfig-dateien", stack, timeout=60)
    if rc != 0:
        return []
    return [(z.split("\t")[0], int(z.split("\t")[1]))
            for z in aus.splitlines() if "\t" in z]


@app.get("/dateien/{stack}", response_class=HTMLResponse)
def dateien(request: Request, stack: str, meldung: str = ""):
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    liste = konf_dateien(stack)
    if not liste:
        # Eine leere Liste hat zwei sehr verschiedene Ursachen: der Server laedt
        # noch herunter und hat seine Konfiguration schlicht noch nicht
        # geschrieben - oder es gibt dauerhaft keine. Ohne diese Unterscheidung
        # sieht ein frisch installiertes Spiel wie ein Fehler aus, und man sucht
        # eine Stunde nach etwas, das einfach noch nicht existiert.
        # *An empty list has two very different causes: the server is still
        #  downloading, or there genuinely is no config file. Without telling
        #  them apart, a fresh install looks like a fault.*
        pi = stackinfo(stack)
        if pi.get("einrichtung_offen"):
            hinweis = ('Der Server ist frisch installiert und hat seine Konfiguration '
                       'noch nicht angelegt. Stand: <b>'
                       + esc(pi.get("einrichtung_stand", "wartet")) + '</b><br>'
                       'Die meisten Server laden erst mehrere Gigabyte herunter; '
                       'danach erscheinen die Dateien hier von selbst.')
        else:
            hinweis = ('Keine Konfigurationsdatei gefunden. Dieser Server führt seine '
                       'Einstellungen möglicherweise woanders — in einem Spielstand, '
                       'einer Datenbank oder ausschließlich über die '
                       '<b>Umgebungsvariablen</b>.')
        zeilen = f'<tr><td colspan=3 class=z>{hinweis}</td></tr>'
    else:
        zeilen = "".join(
            f'<tr><td><code>{esc(p)}</code></td><td class=z>{g} B</td>'
            f'<td><a class=b href="/datei/{esc(stack)}?p={quote(p)}">bearbeiten</a></td></tr>'
            for p, g in liste)
    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF
        + f"<h1>Konfigurationsdateien: {esc(stack)}</h1>"
        + (f'<div class=warn>{esc(meldung)}</div>' if meldung else "")
        + f"<table><tr><th>Datei</th><th>Größe</th><th></th></tr>{zeilen}</table>"
        + '<div class=m>Dies sind die Dateien des <b>Spielservers</b>, nicht die '
          'compose-Datei. Vor jeder Änderung wird eine Sicherung neben der Datei '
          'abgelegt (<code>.vor-panel-…</code>). Änderungen wirken erst nach einem '
          '<b>Neustart</b> des Servers.</div>'
        + f'<a class=b href="/konfig/{esc(stack)}">Container-Einstellungen</a> '
          f'<a class=b href="/">zurück</a>' + FUSS)


@app.get("/datei/{stack}", response_class=HTMLResponse)
def datei(request: Request, stack: str, p: str = "", modus: str = "formular", meldung: str = ""):
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    rc, inhalt = aktion("konfig-datei-lesen", stack, p, timeout=60)
    if rc != 0:
        return RedirectResponse(f"/dateien/{stack}?meldung={quote(inhalt.strip()[:200])}", 303)

    endung = ("." + p.rsplit(".", 1)[-1].lower()) if "." in p else ""
    kopf = (f"<h1>{esc(p)}</h1><div class=z>{esc(stack)}</div>"
            + (f'<div class=warn>{esc(meldung)}</div>' if meldung else ""))
    reiter = (f'<a class="b{" p" if modus == "formular" else ""}" '
              f'href="/datei/{esc(stack)}?p={quote(p)}&modus=formular">Felder</a> '
              f'<a class="b{" p" if modus == "text" else ""}" '
              f'href="/datei/{esc(stack)}?p={quote(p)}&modus=text">Rohtext</a>')

    if modus == "text":
        koerper = (f'<form method=post action=/datei-speichern>'
                   f'<input type=hidden name=csrf value="{s["csrf"]}">'
                   f'<input type=hidden name=stack value="{esc(stack)}">'
                   f'<input type=hidden name=pfad value="{esc(p)}">'
                   f'<input type=hidden name=modus value="text">'
                   f'<textarea name=inhalt rows=26 style="width:100%;font-family:monospace;'
                   f'font-size:13px;background:var(--k);color:var(--t);border:1px solid var(--r);'
                   f'border-radius:6px;padding:10px">{esc(inhalt)}</textarea>'
                   f'<div style="margin-top:10px"><button class=p>speichern</button></div></form>')
    else:
        felder = konf_parsen(inhalt, endung)
        if not felder:
            koerper = ('<div class=warn>Diese Datei lässt sich nicht in Felder zerlegen — '
                       'sie ist verschachtelt oder hat kein Schlüssel-Wert-Format. '
                       'Bitte den <b>Rohtext</b> verwenden.</div>')
        else:
            zeilen, letzter = [], None
            for k, w, ab in felder:
                if ab != letzter:
                    if ab:
                        zeilen.append(f'<tr><td colspan=2 class=z style="padding-top:14px">'
                                      f'<b>[{esc(ab)}]</b></td></tr>')
                    letzter = ab
                # true/false wird zur Auswahl - das ist der haeufigste Fall und
                # der, bei dem sich am leichtesten vertippt (True, yes, 1 ...).
                # *Booleans become a dropdown: the most common field and the
                #  easiest to mistype.*
                if w.strip().lower() in ("true", "false"):
                    ja = ' selected' if w.strip().lower() == "true" else ''
                    nein = '' if ja else ' selected'
                    eingabe = (f'<select name="f:{esc(k)}">'
                               f'<option value=true{ja}>true</option>'
                               f'<option value=false{nein}>false</option></select>')
                else:
                    eingabe = (f'<input type=text name="f:{esc(k)}" value="{esc(w)}" '
                               f'style="width:280px">')
                zeilen.append(f'<tr><td><code>{esc(k)}</code></td><td>{eingabe}</td></tr>')
            koerper = (f'<form method=post action=/datei-speichern>'
                       f'<input type=hidden name=csrf value="{s["csrf"]}">'
                       f'<input type=hidden name=stack value="{esc(stack)}">'
                       f'<input type=hidden name=pfad value="{esc(p)}">'
                       f'<input type=hidden name=modus value="formular">'
                       f'<table><tr><th>Schlüssel</th><th>Wert</th></tr>{"".join(zeilen)}</table>'
                       f'<div style="margin-top:12px"><button class=p>speichern</button></div></form>')

    return HTMLResponse(KOPF + kopfleiste(s) + RUMPF + kopf
        + f'<div style="margin:12px 0">{reiter}</div>' + koerper
        + '<div class=m>Vor dem Speichern wird eine Sicherung neben der Datei abgelegt '
          '(<code>.vor-panel-…</code>). Änderungen wirken erst nach einem <b>Neustart</b> '
          'des Servers.<br>'
          'Viele Spielserver schreiben ihre Konfiguration beim Start <b>selbst neu</b> — '
          'gemessen bei Minecraft: geänderte Werte bleiben erhalten, eigene Kommentare und '
          'unbekannte Zeilen verschwinden. Wo es darauf ankommt, den Server vorher anhalten.'
          '</div>'
        + f'<a class=b href="/dateien/{esc(stack)}">zurück</a>' + FUSS)


@app.post("/datei-speichern")
async def datei_speichern(request: Request):
    formular = await request.form()
    s = pruefe(request, str(formular.get("csrf", "")))
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    stack = str(formular.get("stack", ""))
    pfad = str(formular.get("pfad", ""))
    modus = str(formular.get("modus", "formular"))
    endung = ("." + pfad.rsplit(".", 1)[-1].lower()) if "." in pfad else ""

    if modus == "text":
        neu = str(formular.get("inhalt", ""))
    else:
        # Immer vom AKTUELLEN Dateiinhalt ausgehen, nicht von dem, der beim
        # Oeffnen des Formulars galt: der Server selbst schreibt seine
        # Konfiguration mitunter waehrenddessen um. Geaendert wird nur, was im
        # Formular steht - der Rest der Datei bleibt Zeile fuer Zeile stehen.
        # *Always start from the file's current content, not the state when the
        #  form was opened: the server rewrites its own config at times.*
        rc, jetzt = aktion("konfig-datei-lesen", stack, pfad, timeout=60)
        if rc != 0:
            return RedirectResponse(f"/dateien/{stack}?meldung={quote(jetzt.strip()[:200])}", 303)
        aenderungen = {k[2:]: str(v) for k, v in formular.items() if k.startswith("f:")}
        # Zeilenumbrueche in einem Wert wuerden die Datei zerlegen.
        if any("\n" in v or "\r" in v for v in aenderungen.values()):
            return RedirectResponse(
                f"/datei/{stack}?p={quote(pfad)}&meldung={quote('Zeilenumbrüche sind in einem Wert nicht erlaubt.')}", 303)
        try:
            neu = konf_ersetzen(jetzt, endung, aenderungen)
        except Exception as e:
            return RedirectResponse(
                f"/datei/{stack}?p={quote(pfad)}&meldung={quote(f'Nicht gespeichert: {e}')}", 303)

    rc, aus = subprocess_schreiben(stack, pfad, neu)
    # Der Dateiinhalt selbst gehoert nicht ins Protokoll: er enthaelt regelmaessig
    # Beitrittspasswoerter, und das Protokoll soll nachvollziehbar machen, WER
    # WAS angefasst hat - nicht Geheimnisse an einer zweiten Stelle sammeln.
    # *The file content itself stays out: it routinely holds join passwords.*
    protokoll(s, "Konfigurationsdatei geschrieben", stack,
              "ok" if rc == 0 else "fehlgeschlagen",
              datei=pfad, modus=modus, zeilen=neu.count("\n") + 1, zeichen=len(neu))
    ziel = f"/datei/{stack}?p={quote(pfad)}&modus={modus}"
    return RedirectResponse(f"{ziel}&meldung={quote(aus.strip()[:250])}", 303)


def subprocess_schreiben(stack: str, pfad: str, inhalt: str) -> tuple:
    """Schreibt ueber die sudo-Bruecke; der Inhalt geht ueber stdin, NICHT als
    Parameter - ein Konfigurationstext in einer Kommandozeile waere sowohl in
    der Prozessliste sichtbar als auch laengenbegrenzt.
    *Content goes through stdin, never as an argument: it would be visible in the
     process list and subject to the length limit.*"""
    try:
        p = subprocess.run(AKTION + ["konfig-datei-schreiben", stack, pfad],
                           input=inhalt, capture_output=True, text=True, timeout=60)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 1, "Zeitüberschreitung beim Speichern"


@app.get("/neustart-fragen", response_class=HTMLResponse)
def neustart_fragen(request: Request):
    s = angemeldet(request)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    rc, laufende = aktion("laufende-vorher", timeout=60)
    return HTMLResponse(KOPF + kopfleiste(s, "reboot") + RUMPF + f"""<h1>Server neu starten?</h1>
<div class=warn>Das startet die <b>ganze Maschine</b> neu, nicht einen einzelnen Spielserver.
Alle Verbindungen brechen ab, auch diese Oberfläche ist ein bis zwei Minuten weg.</div>
<p style=font-size:14px>Vorher werden alle laufenden Container <b>sauber angehalten</b>,
damit die Spiele ihre Stände schreiben.{" Läuft gerade eine Sicherung, wird der Neustart abgebrochen — ein unterbrochener Borg-Lauf hinterlässt eine Sperre, die man von Hand lösen muss." if SICHERUNG_AN else ""}</p>
<p style=font-size:14px>Läuft gerade: <b>{laufende.strip() or "nichts"}</b><br>
<span class=z>Diese Server werden nach dem Hochfahren <b>wieder gestartet</b> — genau
diese und keine anderen. StarRupture bleibt bewusst aus.</span></p>
<form method=post action=/neustart><input type=hidden name=csrf value="{s['csrf']}">
<button class=x>Ja, Maschine neu starten</button></form> <a class=b href=/>Abbrechen</a>""" + FUSS)


@app.post("/neustart", response_class=HTMLResponse)
def neustart(request: Request, csrf: str = Form("")):
    s = pruefe(request, csrf)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    rc, aus = aktion("neustart", timeout=120)
    protokoll(s, "Maschine neu gestartet", "", "ok" if rc == 0 else "abgebrochen",
              meldung=aus.strip()[:200])
    if rc != 0:
        return HTMLResponse(KOPF + kopfleiste(s) + RUMPF +
            f"<h1>Neustart abgebrochen</h1><div class=warn>{aus}</div><a class=b href=/>zurück</a>" + FUSS)
    return HTMLResponse(KOPF + RUMPF + """<div class=card><h1>Server startet neu</h1>
<p style=font-size:14px;color:var(--d)>Die Maschine fährt gerade herunter. Diese Seite
ist in ein bis zwei Minuten wieder erreichbar — einfach neu laden.</p>
<a class=b href=/>erneut versuchen</a></div>""" + FUSS)


@app.get("/auth-check")
def auth_check(request: Request):
    """Wird von Caddy vor JEDEM Terminalaufruf gefragt (forward_auth).
    Nur eine gueltige ADMIN-Sitzung kommt durch. So haengt das Terminal an
    derselben Anmeldung wie der Rest — ttyd selbst hat keine eigene Pruefung."""
    s = angemeldet(request)
    if ist_admin(s):
        return Response(status_code=204)
    return Response(status_code=401)


@app.get("/passwoerter", response_class=HTMLResponse)
def passwoerter(request: Request):
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    rc, aus = aktion("passwoerter", timeout=60)
    auto = [f"<tr><td>{t[0]}</td><td>{t[1]}</td><td><code>{t[2]}</code></td></tr>"
            for t in (z.split("\t") for z in aus.splitlines()) if len(t) >= 3]

    eigene = eigene_laden()
    zeilen_eigen = []
    for i, e in enumerate(eigene):
        zeilen_eigen.append(f"""<tr><td>{e['server']}</td><td>{e['feld']}</td>
<td><code>{e['wert']}</code></td><td style=text-align:right>
<form method=post action=/zugang-loeschen><input type=hidden name=csrf value="{s['csrf']}">
<input type=hidden name=nr value="{i}"><button class=x>löschen</button></form></td></tr>""")

    # Welche Server liefern gar nichts automatisch?
    genannt = {z.split("\t")[0].split(" ")[0] for z in aus.splitlines() if "\t" in z}
    genannt |= {e["server"] for e in eigene}
    rc2, alle = aktion("status", timeout=60)
    stacks = [z.split("\t")[0] for z in alle.splitlines()
              if "\t" in z and not z.startswith("SYSTEM")]
    fehlend = [n for n in stacks if n not in genannt]
    hinweis = ""
    if fehlend:
        hinweis = ("<div class=warn>Ohne Eintrag: <b>" + ", ".join(fehlend) + "</b>. "
                   "Diese Server legen ihre Passwörter nur gehasht oder verschlüsselt ab — "
                   "sie lassen sich nicht auslesen. Unten von Hand eintragen.</div>")

    auswahl = "".join(f'<option value="{n}">{n}</option>' for n in stacks)
    return HTMLResponse(KOPF + kopfleiste(s, "pw") + RUMPF + f"""<h1>Zugangsdaten der Server</h1>
<h2 style=font-size:15px;margin:18px 0 8px>Aus der Serverkonfiguration gelesen</h2>
<div class=z style=margin-bottom:8px>Diese Werte kommen direkt von der Maschine und sind
damit immer aktuell.</div>
<table><tr><th>Server</th><th>Feld</th><th>Wert</th></tr>{''.join(auto)}</table>
{hinweis}
<h2 style=font-size:15px;margin:26px 0 8px>Von Hand hinterlegt</h2>
<div class=z style=margin-bottom:8px>Selbst eingetragen — <b>kann veralten</b>, wenn das
Passwort später im Spiel geändert wird. Der Server bestätigt diese Werte nicht.</div>
<table><tr><th>Server</th><th>Feld</th><th>Wert</th><th></th></tr>
{''.join(zeilen_eigen) or '<tr><td colspan=4>noch nichts hinterlegt</td></tr>'}</table>
<form method=post action=/zugang-anlegen style="display:flex;gap:8px;align-items:flex-end;margin-top:14px;flex-wrap:wrap">
<input type=hidden name=csrf value="{s['csrf']}">
<div><label>Server</label><select name=server>{auswahl}</select></div>
<div><label>Feld</label><input type=text name=feld placeholder="z. B. ClientPassword" style=width:190px></div>
<div><label>Wert</label><input type=text name=wert style=width:190px></div>
<button class=p>hinzufügen</button></form>""" + FUSS)


@app.post("/zugang-anlegen")
def zugang_anlegen(request: Request, csrf: str = Form(""), server: str = Form(""),
                   feld: str = Form(""), wert: str = Form("")):
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    feld, wert, server = feld.strip(), wert.strip(), server.strip()
    if feld and wert and server and len(feld) <= 40 and len(wert) <= 120:
        eigene = eigene_laden()
        eigene.append({"server": server, "feld": feld, "wert": wert})
        eigene_speichern(eigene)
        protokoll(s, "Zugangsdatum hinterlegt", server, feld=feld,
                  wert=ohne_geheimnis(feld, wert))
    return RedirectResponse("/passwoerter", 303)


@app.post("/zugang-loeschen")
def zugang_loeschen(request: Request, csrf: str = Form(""), nr: str = Form("")):
    s = pruefe(request, csrf)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    eigene = eigene_laden()
    if nr.isdigit() and 0 <= int(nr) < len(eigene):
        weg = eigene[int(nr)]
        del eigene[int(nr)]
        eigene_speichern(eigene)
        protokoll(s, "Zugangsdatum geloescht", weg.get("server", "?"),
                  feld=weg.get("feld", "?"))
    return RedirectResponse("/passwoerter", 303)


@app.get("/nutzer", response_class=HTMLResponse)
def nutzer_liste(request: Request, neu: str = "", fehler: str = ""):
    s = angemeldet(request)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    d = laden()
    zeilen = []
    for name, n in sorted(d["nutzer"].items()):
        fertig = n.get("totp_bestaetigt")
        mfa = ('<span class="s on">eingerichtet</span>' if fertig
               else '<span class="s off">wartet auf erste Anmeldung</span>')
        knoepfe = ""
        if fertig:
            knoepfe += (f'<form method=post action=/mfa-zuruecksetzen>'
                        f'<input type=hidden name=csrf value="{s["csrf"]}">'
                        f'<input type=hidden name=name value="{name}">'
                        f'<button class=y>2FA zurücksetzen</button></form> ')
        knoepfe += ("<span class=z>(eigenes Konto)</span>" if name == s["nutzer"] else
                    f'<form method=post action=/nutzer-loeschen><input type=hidden name=csrf value="{s["csrf"]}">'
                    f'<input type=hidden name=name value="{name}"><button class=x>löschen</button></form>')
        # Der Codevorrat gehoert in die Uebersicht: geht er zur Neige, faellt es
        # sonst erst auf, wenn jemand ausgesperrt vor der Anmeldung steht.
        # *The remaining codes belong here; otherwise a depleted list is noticed
        #  only when somebody is already locked out.*
        rest = len(n.get("codes") or [])
        vorrat = (f'<span class="s off">keine</span>' if rest == 0 and fertig
                  else f'<span class="s on">{rest}</span>' if rest > 3
                  else f'<span class="s off">{rest}</span>' if fertig
                  else '<span class=z>—</span>')
        zeilen.append(f"<tr><td><b>{name}</b></td><td>{n['rolle']}</td><td>{mfa}</td>"
                      f"<td>{vorrat}</td>"
                      f"<td style=text-align:right>{knoepfe}</td></tr>")
    # Eine still abgewiesene Eingabe ist die schlechteste Rueckmeldung: die Seite
    # sieht danach genauso aus wie vorher, und niemand weiss, ob etwas passiert
    # ist. Genau daran scheiterte am 08.09. das Anlegen eines Benutzers - der
    # Grund stand nirgends, weil die Route wortlos zurueckleitete.
    # *A silently rejected form is the worst feedback: the page looks unchanged
    #  and nobody can tell whether anything happened.*
    frisch = f'<div class=warn>{esc(fehler)}</div>' if fehler else ""
    if neu:
        frisch = (f"<div class=warn><b>{neu}</b> angelegt. Gib Name und Passwort weiter — "
                  "den QR-Code für die Authenticator-App bekommt der Benutzer bei seiner "
                  "<b>ersten Anmeldung</b> selbst angezeigt. Du siehst das Geheimnis nie.</div>")
    return HTMLResponse(KOPF + kopfleiste(s, "nutzer") + RUMPF + f"<h1>Benutzer</h1>{frisch}"
        f"<table><tr><th>Name</th><th>Rolle</th><th>Zwei-Faktor</th><th>Codes</th><th></th></tr>{''.join(zeilen)}</table>"
        f"""<h1 style=margin-top:28px;font-size:16px>Neuen Benutzer anlegen</h1>
<form method=post action=/nutzer-anlegen>
<input type=hidden name=csrf value="{s['csrf']}">
<label>Name</label><input type=text name=name style=max-width:220px required pattern="[A-Za-z0-9]{{1,20}}" title="nur Buchstaben und Ziffern, höchstens 20 Zeichen">
<div class=z style=margin-top:-6px>nur Buchstaben und Ziffern, höchstens 20 Zeichen</div>
<label>Passwort</label><input type=text name=passwort style=max-width:220px required minlength=10>
<div class=z style=margin-top:-6px>mindestens 10 Zeichen</div>
<label>Rolle</label><select name=rolle>
<option value=bedienen>bedienen (starten/anhalten/neu starten)</option>
<option value=verwalten>verwalten (dazu: Spiele installieren, entfernen, einstellen)</option>
<option value=admin>admin (alles)</option></select>
<div style=margin-top:14px><button class=p>anlegen</button></div></form>
<div class=m><b>bedienen</b> darf Server starten, anhalten und neu starten{" sowie Sicherungen einsehen" if SICHERUNG_AN else ""}
 — aber keine Passwörter sehen,{" nichts zurückspielen," if SICHERUNG_AN else ""} keine Einstellungen ändern
und keine Benutzer verwalten.<br>
<b>verwalten</b> darf zusätzlich Spiele installieren und entfernen, ihre Einstellungen und
Konfigurationsdateien ändern, Zugangsdaten sehen{" und Sicherungen zurückspielen" if SICHERUNG_AN else ""} —
also alles rund um die <b>Spieleserver</b>. Nicht dabei: Benutzerverwaltung, Webterminal,
Neustart der Maschine und das Protokoll.<br>
<b>admin</b> darf alles, auch die Maschine und die Benutzer.</div>""" + FUSS)


@app.post("/codes-neu")
def codes_neu_erzeugen(request: Request, csrf: str = Form("")):
    """Neue Wiederherstellungscodes fuer das EIGENE Konto. Jeder darf das, nicht
    nur Administratoren: ohne diesen Weg waere man nach zehn Einloesungen wieder
    da, wo man ohne Codes war."""
    s = pruefe(request, csrf)
    if not s:
        return RedirectResponse("/login", 303)
    d = laden()
    if s["nutzer"] not in d["nutzer"]:
        return RedirectResponse("/", 303)
    klar, hashes = codes_neu()
    d["nutzer"][s["nutzer"]]["codes"] = hashes
    speichern(d)
    protokoll(s, "Wiederherstellungscodes neu erzeugt", s["nutzer"], anzahl=len(hashes))
    a = RedirectResponse("/codes", 303)
    a.set_cookie("codes", einrichtung.dumps({"nutzer": s["nutzer"], "codes": klar}),
                 httponly=True, secure=True, samesite="strict", max_age=900)
    return a


@app.get("/konto", response_class=HTMLResponse)
def konto(request: Request, meldung: str = ""):
    """Das eigene Konto: wie viele Wiederherstellungscodes noch da sind, und der
    Weg zu neuen. Bewusst fuer JEDE Rolle erreichbar - es geht um den eigenen
    Zugang, nicht um die Verwaltung anderer."""
    s = angemeldet(request)
    if not s:
        return RedirectResponse("/login", 303)
    n = laden()["nutzer"].get(s["nutzer"]) or {}
    rest = len(n.get("codes") or [])
    pk = n.get("passkeys") or []
    if pk:
        zeilen = "".join(
            f'<tr><td>angelegt {esc(p.get("angelegt", "?"))}</td>'
            f'<td class=z><code>{esc(p["id"][:14])}…</code></td>'
            f'<td style=text-align:right><form method=post action=/passkey-loeschen>'
            f'<input type=hidden name=csrf value="{s["csrf"]}">'
            f'<input type=hidden name=id value="{esc(p["id"])}">'
            f'<button class=x>entfernen</button></form></td></tr>' for p in pk)
        pk_liste = f"<table><tr><th>Passkey</th><th>Kennung</th><th></th></tr>{zeilen}</table>"
    else:
        pk_liste = ('<div class=m>Noch kein Passkey hinterlegt.</div>'
                    if PASSKEY_MOEGLICH else
                    '<div class=warn>Passkeys sind auf diesem Server nicht eingerichtet '
                    '(die Bibliothek <code>webauthn</code> fehlt).</div>')
    warn = ""
    if rest == 0:
        warn = ('<div class=warn><b>Du hast keine Wiederherstellungscodes.</b> '
                'Geht dein Gerät verloren, kommst du ohne fremde Hilfe nicht mehr '
                'herein. Erzeuge jetzt welche.</div>')
    elif rest <= 3:
        warn = (f'<div class=warn>Nur noch <b>{rest}</b> Wiederherstellungscodes übrig. '
                'Erzeuge rechtzeitig neue — die alten verlieren dabei ihre Gültigkeit.</div>')
    return HTMLResponse(KOPF + kopfleiste(s, "konto") + RUMPF + f"""<h1>Mein Konto</h1>
<table><tr><th>Benutzer</th><td><b>{esc(s["nutzer"])}</b></td></tr>
<tr><th>Rolle</th><td>{esc(s["rolle"])}</td></tr>
<tr><th>Wiederherstellungscodes</th><td><b>{rest}</b> von {CODE_ANZAHL} übrig</td></tr></table>
{warn}
{f'<div class=m>{esc(meldung)}</div>' if meldung else ''}
<form method=post action=/codes-neu style=margin-top:18px>
<input type=hidden name=csrf value="{s['csrf']}">
<button class=y>neue Wiederherstellungscodes erzeugen</button></form>

<h1 style=margin-top:30px;font-size:16px>Passkeys</h1>
<div class=z style=margin-bottom:10px>Ein Passkey tritt an die Stelle der sechs Ziffern.
Er liegt in deinem Gerät — Windows Hello, Touch ID, Android oder ein Sicherheitsschlüssel —
und wird mit Fingerabdruck, Gesicht oder Geräte-PIN freigegeben. <b>Es gibt kein
Geheimnis, das dieser Server kennt</b>, und er funktioniert nur auf dieser Adresse:
eine nachgebaute Anmeldeseite bekommt schlicht keine Antwort.</div>
{pk_liste}
<button type=button class=p data-passkey=anlegen data-csrf="{s['csrf']}" hidden>Passkey auf diesem Gerät anlegen</button>
<div id=pk-meldung></div>
<noscript><div class=warn>Passkeys brauchen JavaScript — es gibt dafür keinen anderen Weg.
Ohne JavaScript funktionieren Passwort, Einmalcode und Wiederherstellungscodes
unverändert.</div></noscript>
<script src="/passkey.js" defer></script>
<div class=m>Ein Wiederherstellungscode tritt an die Stelle der sechs Ziffern aus der
App — das Passwort brauchst du weiterhin. Jeder Code funktioniert genau einmal.
<b>Beim Erzeugen verlieren alle bisherigen Codes ihre Gültigkeit</b>, und die neue
Liste wird nur ein einziges Mal angezeigt.</div>""" + FUSS)


# --- Passkey: Anlegen (angemeldet) -------------------------------------------

@app.post("/passkey/anlegen-start")
def passkey_anlegen_start(request: Request, csrf: str = Form("")):
    s = pruefe(request, csrf)
    if not s:
        return Response(status_code=401)
    if not PASSKEY_MOEGLICH:
        return Response("Passkeys sind auf diesem Server nicht eingerichtet.", status_code=501)
    vorhanden = [PublicKeyCredentialDescriptor(id=base64url_to_bytes(p["id"]))
                 for p in passkeys_von(s["nutzer"])]
    opt = generate_registration_options(
        rp_id=RP_ID, rp_name=RP_NAME,
        user_name=s["nutzer"], user_display_name=s["nutzer"],
        # Schon hinterlegte Schluessel ausschliessen, sonst legt derselbe
        # Sicherheitsschluessel stillschweigend einen zweiten Eintrag an.
        exclude_credentials=vorhanden,
        authenticator_selection=AuthenticatorSelectionCriteria(
            user_verification=UserVerificationRequirement.PREFERRED),
    )
    a = Response(options_to_json(opt), media_type="application/json")
    # Die Challenge muss den Weg zurueck ueberleben, ohne dass der Server sie
    # sich merkt. Signiert und kurzlebig, wie das Einrichtungs-Token - und an
    # den Benutzer gebunden, damit sie nicht in einer fremden Sitzung gilt.
    # *The challenge survives the round trip signed and short-lived rather than
    #  in server state, bound to the user so it cannot be replayed elsewhere.*
    a.set_cookie("pk_anlegen",
                 einrichtung.dumps({"nutzer": s["nutzer"],
                                    "challenge": bytes_zu_b64url(opt.challenge)}),
                 httponly=True, secure=True, samesite="strict", max_age=300)
    return a


@app.post("/passkey/anlegen-fertig")
async def passkey_anlegen_fertig(request: Request):
    s = angemeldet(request)
    if not s:
        return Response(status_code=401)
    if not PASSKEY_MOEGLICH:
        return Response(status_code=501)
    keks = request.cookies.get("pk_anlegen")
    if not keks:
        return Response("Sitzung abgelaufen, bitte neu versuchen.", status_code=400)
    try:
        merk = einrichtung.loads(keks, max_age=300)
    except BadSignature:
        return Response("Sitzung abgelaufen, bitte neu versuchen.", status_code=400)
    if merk.get("nutzer") != s["nutzer"]:
        return Response(status_code=400)
    try:
        antwort = await request.json()
        erg = verify_registration_response(
            credential=antwort,
            expected_challenge=base64url_to_bytes(merk["challenge"]),
            expected_origin=RP_HERKUNFT, expected_rp_id=RP_ID)
    except Exception as e:
        protokoll(s, "Passkey anlegen fehlgeschlagen", s["nutzer"], "abgelehnt",
                  grund=type(e).__name__)
        return Response(f"Nicht angenommen: {type(e).__name__}", status_code=400)

    passkey_speichern(s["nutzer"], {
        "id": bytes_zu_b64url(erg.credential_id),
        "pubkey": bytes_zu_b64url(erg.credential_public_key),
        "zaehler": erg.sign_count,
        "angelegt": time.strftime("%Y-%m-%d %H:%M:%S%z"),
    })
    protokoll(s, "Passkey angelegt", s["nutzer"], "ok",
              anzahl=len(passkeys_von(s["nutzer"])))
    a = Response(status_code=204)
    a.delete_cookie("pk_anlegen")
    return a


@app.post("/passkey-loeschen")
def passkey_loeschen(request: Request, csrf: str = Form(""), id: str = Form("")):
    s = pruefe(request, csrf)
    if not s:
        return RedirectResponse("/login", 303)
    d = laden()
    n = d["nutzer"].get(s["nutzer"]) or {}
    vorher = len(n.get("passkeys") or [])
    n["passkeys"] = [p for p in (n.get("passkeys") or []) if p["id"] != id]
    speichern(d)
    if len(n["passkeys"]) != vorher:
        protokoll(s, "Passkey entfernt", s["nutzer"], "ok", verbleibend=len(n["passkeys"]))
    return RedirectResponse("/konto?meldung=" + quote("Passkey entfernt."), 303)


# --- Passkey: Anmelden --------------------------------------------------------

@app.post("/passkey/anmelden-start")
def passkey_anmelden_start(request: Request, nutzer: str = Form(""),
                           passwort: str = Form("")):
    """Das PASSWORT bleibt Faktor 1. Der Passkey tritt an die Stelle der sechs
    Ziffern, nicht an die des Passworts - sonst waere aus zwei Faktoren einer
    geworden, ohne dass es jemand entschieden haette."""
    ip = request.client.host if request.client else "?"
    if gesperrt(ip):
        return Response("Zu viele Fehlversuche.", status_code=429)
    if not PASSKEY_MOEGLICH:
        return Response(status_code=501)
    n = laden()["nutzer"].get(nutzer)
    passwort_ok = False
    if n:
        try:
            hasher.verify(n["passwort_hash"], passwort)
            passwort_ok = True
        except (VerifyMismatchError, InvalidHashError):
            passwort_ok = False
    # Bewusst dieselbe Antwort fuer "kein solcher Benutzer", "falsches Passwort"
    # und "keine Passkeys hinterlegt": sonst verraet diese Route, welche Konten
    # es gibt und welche einen Passkey haben.
    # *Deliberately one answer for all three cases, so this route does not reveal
    #  which accounts exist or which have a passkey.*
    liste = (n or {}).get("passkeys") or []
    if not passwort_ok or not liste:
        fehlversuche.setdefault(ip, []).append(time.time())
        protokoll({"nutzer": nutzer or "—", "rolle": "—"},
                  "Passkey-Anmeldung fehlgeschlagen", "", "abgelehnt", ip=ip)
        return Response("Anmeldung fehlgeschlagen.", status_code=401)

    opt = generate_authentication_options(
        rp_id=RP_ID,
        allow_credentials=[PublicKeyCredentialDescriptor(id=base64url_to_bytes(p["id"]))
                           for p in liste],
        user_verification=UserVerificationRequirement.PREFERRED)
    a = Response(options_to_json(opt), media_type="application/json")
    a.set_cookie("pk_anmelden",
                 einrichtung.dumps({"nutzer": nutzer,
                                    "challenge": bytes_zu_b64url(opt.challenge)}),
                 httponly=True, secure=True, samesite="strict", max_age=300)
    return a


@app.post("/passkey/anmelden-fertig")
async def passkey_anmelden_fertig(request: Request):
    ip = request.client.host if request.client else "?"
    if gesperrt(ip):
        return Response(status_code=429)
    if not PASSKEY_MOEGLICH:
        return Response(status_code=501)
    keks = request.cookies.get("pk_anmelden")
    if not keks:
        return Response(status_code=400)
    try:
        merk = einrichtung.loads(keks, max_age=300)
    except BadSignature:
        return Response(status_code=400)
    name = merk.get("nutzer")
    d = laden()
    n = d["nutzer"].get(name)
    if not n:
        return Response(status_code=400)
    try:
        antwort = await request.json()
        roh_id = antwort.get("id") or antwort.get("rawId")
        eintrag = next(p for p in (n.get("passkeys") or []) if p["id"] == roh_id)
        erg = verify_authentication_response(
            credential=antwort,
            expected_challenge=base64url_to_bytes(merk["challenge"]),
            expected_origin=RP_HERKUNFT, expected_rp_id=RP_ID,
            credential_public_key=base64url_to_bytes(eintrag["pubkey"]),
            credential_current_sign_count=eintrag.get("zaehler", 0))
    except Exception as e:
        fehlversuche.setdefault(ip, []).append(time.time())
        protokoll({"nutzer": name or "—", "rolle": "—"},
                  "Passkey-Anmeldung fehlgeschlagen", "", "abgelehnt",
                  ip=ip, grund=type(e).__name__)
        return Response("Anmeldung fehlgeschlagen.", status_code=401)

    # Der Signaturzaehler steigt bei jeder Nutzung. Ihn zurueckzuschreiben ist
    # der Hinweis auf einen geklonten Schluessel - py_webauthn wirft, wenn er
    # nicht gewachsen ist, und der Fehlerpfad oben faengt das ab.
    # *The signature counter is how a cloned authenticator becomes visible.*
    eintrag["zaehler"] = erg.new_sign_count
    speichern(d)
    fehlversuche.pop(ip, None)
    protokoll({"nutzer": name, "rolle": n.get("rolle", "?")},
              "Mit Passkey angemeldet", "", "ok", ip=ip)
    a = Response(status_code=204)
    a.set_cookie("sitzung", signierer.dumps({"nutzer": name,
                                             "csrf": secrets.token_urlsafe(24)}),
                 httponly=True, secure=True, samesite="strict", max_age=SITZUNG_MAXALTER)
    a.delete_cookie("pk_anmelden")
    return a


@app.get("/logs/{stack}", response_class=HTMLResponse)
def logs(request: Request, stack: str, n: int = 200):
    """Die letzten Zeilen aus "docker logs".

    Fuer "verwalten" und "admin", nicht fuer "bedienen": Manche Spieleserver
    schreiben ihre Konfiguration beim Start ins Log, Beitrittspasswort
    eingeschlossen. Wer die Zugangsdaten ohnehin sehen darf, sieht hier nichts
    Neues; wer nur starten und stoppen darf, soll sie nicht auf diesem Umweg
    bekommen.
    *Some servers echo their config on start, join password included, so this
     matches the credentials permission rather than the start/stop one.*
    """
    s = angemeldet(request)
    if not darf_verwalten(s):
        return RedirectResponse("/", 303)
    n = max(50, min(n, 2000))
    rc, aus = aktion("logs", stack, str(n), timeout=60)

    if rc != 0:
        inhalt = f'<div class=warn>{esc(aus.strip()[:400]) or "Keine Logs abrufbar."}</div>'
    elif not aus.strip():
        # Leer ist nicht dasselbe wie "nicht abrufbar" - ohne diesen Unterschied
        # sucht man den Fehler an der falschen Stelle.
        # *Empty is not the same as unavailable.*
        inhalt = ('<div class=m>Der Container hat nichts protokolliert. '
                  'Das ist kein Fehler — manche Server schreiben erst beim ersten '
                  'Start etwas, andere nur bei Problemen.</div>')
    else:
        # ESCAPEN, immer: hier steht beliebiger Text aus dem Spielserver, samt
        # allem, was Spieler in den Chat geschrieben haben.
        # *Escaped without exception: this is arbitrary text from the game server,
        #  including whatever players typed into chat.*
        zeilen = aus.rstrip().splitlines()
        inhalt = ('<pre style="background:var(--k);padding:14px;border-radius:8px;'
                  'white-space:pre-wrap;word-break:break-word;font-size:12.5px;'
                  'line-height:1.5;max-height:70vh;overflow:auto;margin:0">'
                  + esc("\n".join(zeilen)) + "</pre>")
        inhalt += (f'<div class=z style=margin-top:8px>{len(zeilen)} Zeilen, '
                   f'die neuesten unten.</div>')

    stufen = "".join(
        f'<a class="b{" p" if m == n else ""}" href="/logs/{esc(stack)}?n={m}">{m}</a> '
        for m in (50, 200, 500, 2000))
    return HTMLResponse(KOPF + kopfleiste(s) + '<div class="w breit">'
        + f"<h1>Protokoll: {esc(stack)}</h1>"
        + f'<div class=z style=margin-bottom:10px>Ausgabe des Containers '
          f'<code>{esc(stack)}</code>, mit Zeitstempeln. Auch dann vorhanden, wenn '
          f'der Server gerade nicht läuft — gerade dann ist sie interessant.</div>'
        + f'<div style=margin-bottom:12px>Zeilen: {stufen}</div>'
        + inhalt
        + f'<div class=m><a class=b href="/logs/{esc(stack)}?n={n}">neu laden</a> '
          f'<a class=b href="/">zurück zur Übersicht</a></div>'
        + "</div>" + FUSS)


@app.get("/protokoll", response_class=HTMLResponse)
def protokoll_seite(request: Request, n: int = 200):
    """Wer hat wann was getan. Nur fuer Admins - das Protokoll nennt Benutzernamen
    und gescheiterte Anmeldungen."""
    s = angemeldet(request)
    if not s or not ist_admin(s):
        return RedirectResponse("/", 303)

    eintraege = protokoll_lesen(max(20, min(n, 1000)))

    # Ein Protokoll, das nichts mehr schreibt, sieht aus wie eines, in dem nichts
    # passiert ist. Beide Faelle bekommen deshalb einen eigenen, deutlichen Text.
    # *A log that cannot write looks exactly like a log where nothing happened.*
    warnung = ""
    if AUDIT_FEHLER:
        warnung = (f'<div class=warn><b>Das Protokoll kann gerade nicht schreiben:</b> '
                   f'{esc(AUDIT_FEHLER)}<br>Die Eintraege unten sind womöglich '
                   f'unvollständig — Aktionen laufen weiter, werden aber nicht '
                   f'aufgezeichnet.</div>')
    elif not eintraege:
        warnung = ('<div class=m>Noch keine Einträge. Das Protokoll beginnt mit '
                   'dieser Fassung — ältere Änderungen stehen nicht darin.</div>')

    zeilen = []
    for e in eintraege:
        d = e.get("details") or {}
        klein = " · ".join(f"{esc(str(k))}: {esc(str(v))}" for k, v in d.items())
        erg = e.get("ergebnis", "")
        farbe = "var(--g)" if erg == "ok" else "var(--x)"
        zeilen.append(
            f'<tr><td style=white-space:nowrap>{esc(str(e.get("zeit", "?")))}</td>'
            f'<td><b>{esc(str(e.get("nutzer", "?")))}</b>'
            f'<span class=z> {esc(str(e.get("rolle", "")))}</span></td>'
            f'<td>{esc(str(e.get("aktion", "?")))}</td>'
            f'<td>{esc(str(e.get("ziel", "")))}</td>'
            f'<td style="color:{farbe}">{esc(str(erg))}</td>'
            f'<td class=z>{klein}</td></tr>')

    return HTMLResponse(KOPF + kopfleiste(s, "prot") + '<div class="w breit">'
        + '<h1>Protokoll</h1>'
        + '<div class=z style=margin-bottom:10px>Wer hat wann was geändert. '
          'Passwörter und Dateiinhalte stehen bewusst <b>nicht</b> darin — nur, '
          'welches Feld angefasst wurde.</div>'
        + warnung
        + '<table><tr><th>Zeit</th><th>Wer</th><th>Was</th><th>Ziel</th>'
          '<th>Ergebnis</th><th>Einzelheiten</th></tr>'
        + "".join(zeilen) + '</table>'
        + f'<div class=m>{len(eintraege)} Einträge angezeigt. '
          f'<a class=b href="/protokoll?n=1000">mehr laden</a></div>'
        + '</div>' + FUSS)


@app.post("/nutzer-anlegen")
def nutzer_anlegen(request: Request, csrf: str = Form(""), name: str = Form(""),
                   passwort: str = Form(""), rolle: str = Form("bedienen")):
    s = pruefe(request, csrf)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    d = laden()
    name = name.strip()
    # Jede Bedingung einzeln, mit eigenem Text. Vorher war es eine einzige
    # Sammelbedingung mit wortloser Umleitung - man sah nur, dass nichts geschah.
    # *Each condition on its own, with its own message.*
    if not name:
        grund = "Bitte einen Benutzernamen eingeben."
    elif not name.isalnum():
        grund = ("Der Benutzername darf nur Buchstaben und Ziffern enthalten — "
                 "keine Leerzeichen, Punkte, Bindestriche oder Unterstriche.")
    elif len(name) > 20:
        grund = f"Der Benutzername ist zu lang ({len(name)} Zeichen, erlaubt sind 20)."
    elif name in d["nutzer"]:
        grund = f"Den Benutzer „{name}“ gibt es bereits."
    elif len(passwort) < 10:
        grund = (f"Das Passwort ist zu kurz ({len(passwort)} Zeichen, "
                 "nötig sind mindestens 10).")
    elif rolle not in ROLLEN:
        grund = f"Unbekannte Rolle „{rolle}“."
    else:
        grund = ""
    if grund:
        protokoll(s, "Benutzer anlegen abgelehnt", name, "abgelehnt", grund=grund)
        return RedirectResponse(f"/nutzer?fehler={quote(grund)}", 303)
    # Das TOTP-Geheimnis wird erzeugt, aber NICHT angezeigt: der Benutzer
    # bekommt es bei seiner ersten Anmeldung selbst als QR-Code. So muss es
    # niemand weitergeben, und der Administrator sieht es nie.
    d["nutzer"][name] = {"passwort_hash": hasher.hash(passwort), "totp": pyotp.random_base32(),
                         "rolle": rolle, "totp_bestaetigt": False}
    speichern(d)
    protokoll(s, "Benutzer angelegt", name, rolle=rolle)
    return RedirectResponse(f"/nutzer?neu={name}", 303)


@app.post("/mfa-zuruecksetzen")
def mfa_zuruecksetzen(request: Request, csrf: str = Form(""), name: str = Form("")):
    """Neues Geheimnis, Bestaetigung zurueck auf offen — fuer den Fall, dass
    jemand sein Geraet verliert. Danach richtet er bei der naechsten Anmeldung
    neu ein."""
    s = pruefe(request, csrf)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    d = laden()
    if name in d["nutzer"]:
        d["nutzer"][name]["totp"] = pyotp.random_base32()
        d["nutzer"][name]["totp_bestaetigt"] = False
        # Die alten Wiederherstellungscodes MUESSEN mit weg. Sie gehoeren zum
        # alten zweiten Faktor; blieben sie liegen, waere das Zuruecksetzen
        # keines - wer die Liste hat, kaeme weiterhin herein.
        # *The old recovery codes must go with it: they belong to the old second
        #  factor, and leaving them would make the reset meaningless.*
        alt_anzahl = len(d["nutzer"][name].get("codes") or [])
        d["nutzer"][name]["codes"] = []
        speichern(d)
        protokoll(s, "Zweiter Faktor zurueckgesetzt", name, entwertete_codes=alt_anzahl)
    return RedirectResponse("/nutzer", 303)


@app.post("/nutzer-loeschen")
def nutzer_loeschen(request: Request, csrf: str = Form(""), name: str = Form("")):
    s = pruefe(request, csrf)
    if not ist_admin(s):
        return RedirectResponse("/", 303)
    d = laden()
    # Das eigene Konto bleibt tabu — sonst sperrt man sich mit einem Klick aus,
    # und ohne Admin kaeme niemand mehr an die Benutzerverwaltung.
    if name in d["nutzer"] and name != s["nutzer"]:
        rolle_war = d["nutzer"][name].get("rolle", "?")
        del d["nutzer"][name]
        speichern(d)
        protokoll(s, "Benutzer geloescht", name, rolle=rolle_war)
    return RedirectResponse("/nutzer", 303)
