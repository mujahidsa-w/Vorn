// Vexo notification sender for Cloudflare Workers (free plan).
//
// The app calls POST /notify after it writes a message. The request carries the
// sender's Firebase ID token. The Worker reads the message and room through the
// Firestore REST API using that same token, so Firestore rules decide what is
// allowed. Then it sends an FCM push to every other member of the room.
//
// Secrets (set with `wrangler secret put`):
//   FIREBASE_SA_JSON  - the full Service Account JSON from Firebase console
// Vars (wrangler.toml):
//   FIREBASE_PROJECT_ID

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

let cachedAccess = { token: '', exp: 0 };

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ---------- helpers ----------

function b64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem) {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

function decodeJwtPayload(token) {
  const part = token.split('.')[1];
  if (!part) throw new HttpError(401, 'bad token');
  const pad = part.replace(/-/g, '+').replace(/_/g, '/');
  const json = atob(pad + '='.repeat((4 - (pad.length % 4)) % 4));
  return JSON.parse(json);
}

// ---------- Firestore REST (uses the caller's ID token) ----------

function fromValue(v) {
  if (v == null) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromValue);
  if ('mapValue' in v) return fromFields(v.mapValue.fields || {});
  return null;
}

function fromFields(fields) {
  const out = {};
  for (const k of Object.keys(fields)) out[k] = fromValue(fields[k]);
  return out;
}

function fsBase(projectId) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

async function getDoc(projectId, path, idToken) {
  const r = await fetch(`${fsBase(projectId)}/${path}`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new HttpError(r.status, `firestore read failed: ${path}`);
  const j = await r.json();
  return fromFields(j.fields || {});
}

async function listUsers(projectId, idToken) {
  const r = await fetch(`${fsBase(projectId)}/users?pageSize=300`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  if (!r.ok) throw new HttpError(r.status, 'firestore list users failed');
  const j = await r.json();
  return (j.documents || []).map((d) => ({
    uid: d.name.split('/').pop(),
    ...fromFields(d.fields || {}),
  }));
}

// ---------- Google OAuth for FCM (service account) ----------

async function googleAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccess.token && cachedAccess.exp - 60 > now) return cachedAccess.token;

  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: FCM_SCOPE,
      aud: TOKEN_URL,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${b64url(new Uint8Array(sig))}`;

  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!r.ok) throw new HttpError(500, 'google oauth failed');
  const j = await r.json();
  cachedAccess = { token: j.access_token, exp: now + (j.expires_in || 3600) };
  return cachedAccess.token;
}

async function sendPush(projectId, sa, fcmToken, title, body, roomId) {
  const access = await googleAccessToken(sa);
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${access}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        data: { roomId },
        android: { priority: 'HIGH', notification: { tag: roomId } },
      },
    }),
  });
  return r.ok;
}

function previewFor(msg) {
  if (msg.type === 'AUDIO') return '🎤 رسالة صوتية';
  if (msg.type === 'IMAGE') return '📷 صورة';
  const t = String(msg.text || '');
  return t.length > 100 ? t.slice(0, 100) + '…' : t;
}

// ---------- HTTP handler ----------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== 'POST' || url.pathname !== '/notify') {
      return new Response('not found', { status: 404 });
    }

    try {
      const auth = request.headers.get('Authorization') || '';
      const idToken = auth.startsWith('Bearer ') ? auth.slice(7) : '';
      if (!idToken) throw new HttpError(401, 'missing token');

      const { roomId, msgId } = await request.json();
      if (!roomId || !msgId || /[\/]/.test(roomId + msgId)) {
        throw new HttpError(400, 'bad body');
      }

      const projectId = env.FIREBASE_PROJECT_ID;
      const sa = JSON.parse(env.FIREBASE_SA_JSON);
      const uid = decodeJwtPayload(idToken).user_id || decodeJwtPayload(idToken).sub;

      // Firestore rejects this read if the token is invalid or the caller
      // cannot see the message. The check on senderId stops someone from
      // notifying for another user's message.
      const msg = await getDoc(projectId, `rooms/${roomId}/messages/${msgId}`, idToken);
      if (!msg || msg.senderId !== uid) throw new HttpError(403, 'not your message');

      const room = await getDoc(projectId, `rooms/${roomId}`, idToken);
      if (!room) throw new HttpError(404, 'room not found');

      let recipients;
      if (Array.isArray(room.members) && room.members.length) {
        recipients = room.members.filter((m) => m !== uid);
      } else {
        // Group rooms without a member list notify every user.
        recipients = (await listUsers(projectId, idToken))
          .map((u) => u.uid)
          .filter((m) => m !== uid);
      }

      const title = msg.senderName || 'Vexo';
      const body = previewFor(msg);
      let sent = 0;

      for (const member of recipients) {
        const user = await getDoc(projectId, `users/${member}`, idToken);
        const fcm = user && user.fcmToken;
        if (!fcm) continue;
        if (await sendPush(projectId, sa, fcm, title, body, roomId)) sent++;
      }

      return Response.json({ ok: true, sent });
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 500;
      return Response.json({ ok: false, error: e.message }, { status });
    }
  },
};
