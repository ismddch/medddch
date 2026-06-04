import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const PROJECT_ID            = Deno.env.get('FIREBASE_PROJECT_ID')!;
const SERVICE_ACCOUNT_JSON  = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')!;
const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── Google OAuth2 token (service account → access_token) ─────────────────────

async function getAccessToken(): Promise<string> {
  const sa  = JSON.parse(SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);

  const header  = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = btoa(
    JSON.stringify({
      iss:   sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud:   'https://oauth2.googleapis.com/token',
      iat:   now,
      exp:   now + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;
  const pemBody = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const keyBytes  = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
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
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  return data.access_token;
}

// ── Send one FCM message ──────────────────────────────────────────────────────

async function sendFcm(
  token: string,
  title: string,
  body:  string,
  data:  Record<string, string>,
): Promise<void> {
  const accessToken = await getAccessToken();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`,
    {
      method:  'POST',
      headers: {
        Authorization:  `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default', badge: 1 } },
          },
        },
      }),
    },
  );
  if (!res.ok) {
    const err = await res.text();
    console.error('[FCM] send error:', err);
  }
}

// ── Supabase helpers ──────────────────────────────────────────────────────────

const dbHeaders = {
  apikey:        SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
};

async function getFcmToken(userId: string): Promise<string | null> {
  const res  = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${userId}&select=fcm_token`,
    { headers: dbHeaders },
  );
  const rows = await res.json();
  return rows?.[0]?.fcm_token ?? null;
}

async function getBarberFcmToken(barberId: string): Promise<string | null> {
  const res  = await fetch(
    `${SUPABASE_URL}/rest/v1/users?barber_id=eq.${barberId}&role=eq.barber&select=fcm_token`,
    { headers: dbHeaders },
  );
  const rows = await res.json();
  return rows?.[0]?.fcm_token ?? null;
}

async function getBarberName(barberId: string): Promise<string> {
  const res  = await fetch(
    `${SUPABASE_URL}/rest/v1/barbers?id=eq.${barberId}&select=name`,
    { headers: dbHeaders },
  );
  const rows = await res.json();
  return rows?.[0]?.name ?? '';
}

async function getUserName(userId: string): Promise<string> {
  const res  = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${userId}&select=name`,
    { headers: dbHeaders },
  );
  const rows = await res.json();
  return rows?.[0]?.name ?? '';
}

async function getUserQueuePosition(
  userId: string,
  barberId: string,
): Promise<number | null> {
  const res  = await fetch(
    `${SUPABASE_URL}/rest/v1/queues?user_id=eq.${userId}&barber_id=eq.${barberId}&select=position`,
    { headers: dbHeaders },
  );
  const rows = await res.json();
  return rows?.[0]?.position ?? null;
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const payload = await req.json();
    const { type, table, record, old_record } = payload;

    // ════════════════════════════════════════════════════════════════════════
    // QUEUES table events
    // ════════════════════════════════════════════════════════════════════════

    // ── INSERT on queues → notify barber: new customer joined ───────────────
    if (type === 'INSERT' && table === 'queues') {
      const barberId = record.barber_id;
      const token    = await getBarberFcmToken(barberId);
      if (token) {
        const barberName = await getBarberName(barberId);
        await sendFcm(
          token,
          'عميل جديد في الطابور',
          barberName
            ? `انضم عميل جديد إلى طابور ${barberName}`
            : 'انضم عميل جديد إلى الطابور',
          { type: 'new_customer', barber_id: barberId },
        );
      }
    }

    // ── UPDATE on queues → notify customer on position drop ─────────────────
    if (type === 'UPDATE' && table === 'queues') {
      const newPos: number     = record.position;
      const oldPos: number     = old_record?.position ?? newPos + 1;
      const userId: string     = record.user_id;

      if (userId && [1, 2, 3].includes(newPos) && newPos < oldPos) {
        const token = await getFcmToken(userId);
        if (token) {
          let title: string;
          let body:  string;
          if (newPos === 1) {
            title = 'حان دورك! 🎉';
            body  = 'أنت الآن الأول في الطابور — توجه للكرسي الآن.';
          } else if (newPos === 2) {
            title = 'استعد، أنت التالي!';
            body  = 'أنت في المرتبة الثانية — لم يتبقَّ سوى شخص واحد!';
          } else {
            title = 'اقترب دورك';
            body  = 'أنت في المرتبة الثالثة — استعد قريباً!';
          }
          await sendFcm(token, title, body, {
            type:     'position',
            position: String(newPos),
          });
        }
      }
    }

    // ════════════════════════════════════════════════════════════════════════
    // PAYMENT_REQUESTS table events
    // ════════════════════════════════════════════════════════════════════════

    // ── INSERT on payment_requests → notify barber: new prepaid booking ─────
    if (type === 'INSERT' && table === 'payment_requests') {
      const barberId   = record.barber_id;
      const userId     = record.user_id;
      const walletType = record.wallet_type ?? '';
      const amount     = record.amount;

      const token = await getBarberFcmToken(barberId);
      if (token) {
        const customerName = await getUserName(userId);
        const detail = [
          walletType,
          amount != null ? `${Number(amount).toFixed(0)} MRU` : '',
        ].filter(Boolean).join(' · ');

        const bodyParts = [
          customerName ? `${customerName} أرسل طلب حجز` : 'طلب حجز مدفوع جديد',
          detail,
          'راجع الإيصال وأكّد الدفع',
        ].filter(Boolean);

        await sendFcm(
          token,
          'طلب حجز مدفوع جديد 💰',
          bodyParts.join(' — '),
          {
            type:       'paid_booking',
            barber_id:  barberId,
            user_id:    userId,
            wallet:     walletType,
            amount:     String(amount ?? ''),
          },
        );
      }
    }

    // ── UPDATE on payment_requests → notify customer: approved or rejected ──
    if (type === 'UPDATE' && table === 'payment_requests') {
      const newStatus = record.status    as string;
      const oldStatus = old_record?.status as string | undefined;

      // Only fire when status actually changed
      if (newStatus === oldStatus) {
        return new Response(JSON.stringify({ ok: true, skipped: 'no status change' }), {
          headers: { 'Content-Type': 'application/json' },
        });
      }

      const userId   = record.user_id  as string;
      const barberId = record.barber_id as string;
      const token    = await getFcmToken(userId);

      if (token) {
        const barberName = await getBarberName(barberId);
        const who        = barberName || 'الحلاق';

        if (newStatus === 'approved') {
          // Get the queue position that was just assigned
          const position = await getUserQueuePosition(userId, barberId);
          const posText  = position === 1
            ? 'أنت الأول في الطابور — توجه الآن!'
            : position != null
              ? `أنت في المرتبة ${position} في الطابور`
              : 'تمت إضافتك إلى الطابور';

          await sendFcm(
            token,
            'تم قبول حجزك! 🎉',
            `قبل ${who} طلبك — ${posText}`,
            {
              type:      'booking_approved',
              barber_id: barberId,
              position:  String(position ?? 1),
            },
          );
        } else if (newStatus === 'rejected') {
          await sendFcm(
            token,
            'تم رفض طلب الحجز',
            `رفض ${who} طلب حجزك — يمكنك إعادة المحاولة أو اختيار حلاق آخر`,
            {
              type:      'booking_rejected',
              barber_id: barberId,
            },
          );
        }
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[queue-notifications]', err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
