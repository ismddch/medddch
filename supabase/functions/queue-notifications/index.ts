import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const PROJECT_ID = Deno.env.get('FIREBASE_PROJECT_ID')!;
const SERVICE_ACCOUNT_JSON = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')!;

// ── Google OAuth2 token (service account → access_token) ─────────────────────

async function getAccessToken(): Promise<string> {
  const sa = JSON.parse(SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);

  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = btoa(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;

  // Import the private key
  const pemBody = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)));
  const jwt = `${signingInput}.${sig}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  return data.access_token;
}

// ── Send one FCM message ──────────────────────────────────────────────────────

async function sendFcm(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const accessToken = await getAccessToken();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: 'high' },
          apns: { headers: { 'apns-priority': '10' } },
        },
      }),
    },
  );
  if (!res.ok) {
    const err = await res.text();
    console.error('[FCM] send error:', err);
  }
}

// ── Supabase client (service role) ───────────────────────────────────────────

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function getFcmToken(userId: string): Promise<string | null> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${userId}&select=fcm_token`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  const rows = await res.json();
  return rows?.[0]?.fcm_token ?? null;
}

async function getBarberFcmToken(chairId: string): Promise<string | null> {
  // chairs → barbers → users (barbers.user_id)
  const chairRes = await fetch(
    `${SUPABASE_URL}/rest/v1/chairs?id=eq.${chairId}&select=barber_id`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  const chairs = await chairRes.json();
  const barberId = chairs?.[0]?.barber_id;
  if (!barberId) return null;

  const barberRes = await fetch(
    `${SUPABASE_URL}/rest/v1/barbers?id=eq.${barberId}&select=user_id,name`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  const barbers = await barberRes.json();
  const userId = barbers?.[0]?.user_id;
  if (!userId) return null;

  return getFcmToken(userId);
}

async function getChairName(chairId: string): Promise<string> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/chairs?id=eq.${chairId}&select=name`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  const rows = await res.json();
  return rows?.[0]?.name ?? '';
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const payload = await req.json();
    const { type, table, record, old_record } = payload;

    // ── INSERT on queues → notify barber ────────────────────────────────────
    if (type === 'INSERT' && table === 'queues') {
      const chairId = record.chair_id;
      const token = await getBarberFcmToken(chairId);
      if (token) {
        const chairName = await getChairName(chairId);
        await sendFcm(
          token,
          'عميل جديد في الطابور',
          chairName
            ? `انضم عميل جديد إلى طابور ${chairName}`
            : 'انضم عميل جديد إلى الطابور',
          { type: 'new_customer', chair_id: chairId, chair_name: chairName },
        );
      }
    }

    // ── UPDATE on queues → notify customer on position change ───────────────
    if (type === 'UPDATE' && table === 'queues') {
      const newPos: number = record.position;
      const oldPos: number | null = old_record?.position ?? null;
      const userId: string = record.user_id;

      // Only notify for positions 1, 2, 3 when position actually decreased
      if (
        userId &&
        [1, 2, 3].includes(newPos) &&
        (oldPos === null || newPos < oldPos)
      ) {
        const token = await getFcmToken(userId);
        if (token) {
          let title: string;
          let body: string;
          if (newPos === 1) {
            title = 'حان دورك! 🎉';
            body = 'أنت الآن الأول في الطابور — توجه للكرسي الآن.';
          } else if (newPos === 2) {
            title = 'استعد، أنت التالي!';
            body = 'أنت في المرتبة الثانية، لم يتبقَّ سوى شخص واحد!';
          } else {
            title = 'اقترب دورك';
            body = 'أنت في المرتبة الثالثة — استعد قريباً!';
          }
          await sendFcm(token, title, body, {
            type: 'position',
            position: String(newPos),
          });
        }
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[queue-notifications]', err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
