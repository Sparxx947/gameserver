# ziel.sh — wie die Werkzeuge auf der Maschine zu root werden. Wird gesourct
# von ausrollen.sh, rueckbau.sh, aufraeumen.sh und abgleich.sh; erwartet $ZIEL.
#
# Zwei Wege (#214, Jens am 2026-09-11: "auch ohne root sollte das moeglich sein"):
#
#   root-Login per Schluessel   -> Befehle laufen direkt
#   Benutzer mit sudo OHNE       -> jeder Befehl laeuft als sudo -n bash -c <gequotet>
#   Passwortabfrage
#
# Nur passwortloses sudo: Die Werkzeuge schicken Dutzende einzelner Befehle ueber
# SSH ohne Terminal; bei jedem nach dem Passwort zu fragen, ginge nicht. Das ist
# sicherheitlich GLEICHWERTIG mit dem root-Login per Schluessel - wer den
# Schluessel hat, ist root. Es auf einer Maschine einzurichten, ist Sache des
# Betreibers; diese Datei macht die Werkzeuge nur faehig, es zu nutzen.
#
# Gequotet wird mit printf %q: Der Befehl kommt bei sudo bash -c als EIN Argument
# an, genau wie beim root-Login bei der Login-Shell. Das setzt auf dem Ziel eine
# bash als Login-Shell voraus (Debian: root und angelegte Benutzer).
#
# PLATZWART_MIT_SUDO=1 erzwingt den sudo-Weg auch bei root-Login - so laesst
# sich die Verpackung gegen eine echte Maschine pruefen, ohne einen zweiten
# Zugang einzurichten (root darf sudo ohne Passwort).
#
# *How the tools become root on the target: a root key login runs commands
#  directly; a user with passwordless sudo gets every command wrapped as
#  "sudo -n bash -c <quoted>". Only passwordless sudo works over a terminal-less
#  SSH; it is equivalent to a root key login security-wise. PLATZWART_MIT_SUDO=1
#  forces the sudo path so the wrapping can be tested against a real machine.*

ALS_ROOT=""

# ziel_rechte [weich]: ALS_ROOT setzen. Ohne "weich" Abbruch, wenn keins geht;
# mit "weich" (abgleich.sh liest nur) eine Warnung und weiter ohne root.
ziel_rechte() {
  local wer
  wer=$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" 'id -u' 2>/dev/null || true)
  if [ "$wer" = "0" ] && [ -z "${PLATZWART_MIT_SUDO:-}" ]; then
    ALS_ROOT=""; return 0
  fi
  if ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" 'sudo -n true' 2>/dev/null; then
    ALS_ROOT="sudo -n"; return 0
  fi
  if [ "${1:-}" = "weich" ]; then
    echo "Hinweis: auf $ZIEL weder root noch passwortloses sudo (id -u: ${wer:-keine Antwort})" >&2
    echo "         - Dateien, die nur root lesen darf, erscheinen als abweichend." >&2
    ALS_ROOT=""; return 0
  fi
  cat >&2 <<TEXT
FEHLER: $ZIEL meldet sich weder als root an noch mit sudo ohne Passwort
        (id -u: ${wer:-keine Antwort}). Einer von zwei Wegen ist noetig:

  1. root-Login per Schluessel: in ~/.ssh/config fuer das Ziel "User root",
     der Schluessel in /root/.ssh/authorized_keys (SSH_ROOT_LOGIN=
     prohibit-password, die Vorgabe).
  2. ein Benutzer mit sudo OHNE Passwortabfrage, z. B. in /etc/sudoers.d/:
       <benutzer> ALL=(ALL) NOPASSWD: ALL
     Sicherheitlich gleichwertig mit Weg 1 - wer den Schluessel hat, ist root.

  Siehe docs/09-referenz.md.
TEXT
  exit 2
}

# am_ziel "<befehl>": laeuft als root auf dem Ziel, liest KEINE Standardeingabe
# (sonst frisst ssh die Eingabe einer umgebenden Schleife oder Rueckfrage).
am_ziel() {
  if [ -z "$ALS_ROOT" ]; then
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "$1"
  else
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "sudo -n bash -c $(printf '%q' "$1")"
  fi
}

# am_ziel_mit_eingabe "<befehl>": dasselbe, reicht aber die Standardeingabe
# durch - fuer ausrollen.sh, das den Dateiinhalt ueber stdin schickt.
am_ziel_mit_eingabe() {
  if [ -z "$ALS_ROOT" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$ZIEL" "sudo -n bash -c $(printf '%q' "$1")"
  fi
}
