// passkey.js — der einzige JavaScript-Code im Panel.
//
// WebAuthn ist ausschliesslich ueber navigator.credentials erreichbar; einen Weg
// ohne JavaScript gibt es nicht und wird es nicht geben (w3c/webauthn#1255,
// geschlossen im Februar 2025). Deshalb diese Datei — als eigene Datei und nicht
// inline, damit die Sicherheitsrichtlinie mit "script-src 'self'" auskommt und
// kein 'unsafe-inline' braucht.
//
// Ohne JavaScript bleibt alles benutzbar: Die Anmeldung mit TOTP ist ein
// gewoehnliches Formular, und die Passkey-Knoepfe sind bis zum Laden dieser
// Datei ausgeblendet.
'use strict';

// WebAuthn spricht base64url ohne Auffuellzeichen, die Browser-APIs sprechen
// ArrayBuffer. Diese beiden Funktionen sind die ganze Uebersetzung.
function vonB64(s) {
  const t = s.replace(/-/g, '+').replace(/_/g, '/');
  const roh = atob(t + '='.repeat((4 - t.length % 4) % 4));
  return Uint8Array.from(roh, c => c.charCodeAt(0));
}
function nachB64(b) {
  return btoa(String.fromCharCode(...new Uint8Array(b)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function melde(text, fehler) {
  const el = document.getElementById('pk-meldung');
  if (!el) { return; }
  el.textContent = text;
  el.className = fehler ? 'f' : 'm';
}

// --- Passkey anlegen (auf der Kontoseite) ---------------------------------
async function anlegen(knopf) {
  const csrf = knopf.dataset.csrf;
  melde('Dein Gerät fragt gleich nach Fingerabdruck, Gesicht oder PIN …', false);
  try {
    const r = await fetch('/passkey/anlegen-start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'csrf=' + encodeURIComponent(csrf),
    });
    if (!r.ok) { melde(await r.text() || 'Nicht möglich.', true); return; }
    const opt = await r.json();

    opt.challenge = vonB64(opt.challenge);
    opt.user.id = vonB64(opt.user.id);
    (opt.excludeCredentials || []).forEach(c => { c.id = vonB64(c.id); });

    const cred = await navigator.credentials.create({ publicKey: opt });
    const fertig = await fetch('/passkey/anlegen-fertig', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: cred.id,
        rawId: nachB64(cred.rawId),
        type: cred.type,
        response: {
          clientDataJSON: nachB64(cred.response.clientDataJSON),
          attestationObject: nachB64(cred.response.attestationObject),
        },
      }),
    });
    if (fertig.ok) { location.href = '/konto?meldung=' + encodeURIComponent('Passkey angelegt.'); }
    else { melde(await fertig.text() || 'Nicht angenommen.', true); }
  } catch (e) {
    // NotAllowedError heisst in aller Regel: abgebrochen oder Zeit abgelaufen.
    melde(e.name === 'NotAllowedError'
      ? 'Abgebrochen oder zu lange gewartet.'
      : 'Nicht möglich: ' + e.name, true);
  }
}

// --- Mit Passkey anmelden --------------------------------------------------
async function anmelden() {
  const nutzer = document.querySelector('input[name=nutzer]');
  const passwort = document.querySelector('input[name=passwort]');
  if (!nutzer.value || !passwort.value) {
    melde('Bitte zuerst Benutzername und Passwort eingeben.', true);
    return;
  }
  melde('Dein Gerät fragt gleich nach Fingerabdruck, Gesicht oder PIN …', false);
  try {
    const r = await fetch('/passkey/anmelden-start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'nutzer=' + encodeURIComponent(nutzer.value) +
            '&passwort=' + encodeURIComponent(passwort.value),
    });
    if (!r.ok) { melde(await r.text() || 'Anmeldung fehlgeschlagen.', true); return; }
    const opt = await r.json();

    opt.challenge = vonB64(opt.challenge);
    (opt.allowCredentials || []).forEach(c => { c.id = vonB64(c.id); });

    const cred = await navigator.credentials.get({ publicKey: opt });
    const fertig = await fetch('/passkey/anmelden-fertig', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: cred.id,
        rawId: nachB64(cred.rawId),
        type: cred.type,
        response: {
          clientDataJSON: nachB64(cred.response.clientDataJSON),
          authenticatorData: nachB64(cred.response.authenticatorData),
          signature: nachB64(cred.response.signature),
          userHandle: cred.response.userHandle ? nachB64(cred.response.userHandle) : null,
        },
      }),
    });
    if (fertig.ok) { location.href = '/'; }
    else { melde(await fertig.text() || 'Anmeldung fehlgeschlagen.', true); }
  } catch (e) {
    melde(e.name === 'NotAllowedError'
      ? 'Abgebrochen oder zu lange gewartet.'
      : 'Nicht möglich: ' + e.name, true);
  }
}

// Erst wenn das Geraet ueberhaupt WebAuthn kann, werden die Knoepfe sichtbar.
// Sonst stuende dort ein Angebot, das ins Leere fuehrt.
document.addEventListener('DOMContentLoaded', () => {
  if (!window.PublicKeyCredential) { return; }
  document.querySelectorAll('[data-passkey]').forEach(el => {
    el.hidden = false;
    el.addEventListener('click', ev => {
      ev.preventDefault();
      if (el.dataset.passkey === 'anlegen') { anlegen(el); } else { anmelden(); }
    });
  });
});
