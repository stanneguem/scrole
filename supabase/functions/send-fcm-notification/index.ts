import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const legacyServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const secretKeys = secretKeysRaw ? JSON.parse(secretKeysRaw) : null;
const supabaseSecret = secretKeys?.default ?? legacyServiceRole;
const supabaseAdmin = createClient(supabaseUrl, supabaseSecret!);

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
function base64Url(value: string) {
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
async function getFirebaseAccessToken(sa: any) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const b64 = pem.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`)));
  let binary = ""; sig.forEach(b => binary += String.fromCharCode(b));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${header}.${claim}.${base64Url(binary)}`,
  });
  const body = await response.json();
  if (!response.ok || !body.access_token) throw new Error("firebase_auth_failed");
  return body.access_token as string;
}
const SUPPORTED_LANGUAGES = ["fr", "en", "es", "de", "it", "pt", "zh", "ja", "ru"];

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountRaw) return json({ error: "firebase_service_account_not_configured" }, 503);

  try {
    const webhook = await req.json();
    const record = webhook?.record;
    const userId = record?.user_id as string | undefined;
    if (!userId) return json({ error: "missing_user_id" }, 400);

    const [{ data: devices, error: devicesError }, { data: preferences, error: preferencesError }] = await Promise.all([
      supabaseAdmin.from("user_devices").select("id,device_token,platform,device_brand,device_model,push_enabled")
        .eq("user_id", userId).eq("push_enabled", true).not("device_token", "is", null),
      supabaseAdmin.from("user_preferences")
        .select("language,notifications_enabled,notif_push,notif_messages,notif_evenements,notif_communautes,notif_social")
        .eq("user_id", userId).maybeSingle(),
    ]);
    if (devicesError || preferencesError) {
      console.error("recipient lookup failed", { devicesError, preferencesError });
      return json({ error: "recipient_lookup_failed" }, 500);
    }

    const type = String(record.type ?? "info").toLowerCase();
    const pref = preferences ?? {};
    const categoryEnabled = type.includes("message")
      ? pref.notif_messages !== false
      : (type.includes("event") || type.includes("evenement"))
        ? pref.notif_evenements !== false
        : (type.includes("community") || type.includes("communaute"))
          ? pref.notif_communautes !== false
          : pref.notif_social !== false;

    // Honor preferences on the server as well, including background push
    // notifications that Flutter cannot filter in its background isolate.
    if (pref.notifications_enabled === false || pref.notif_push === false || !categoryEnabled) {
      return json({ ok: true, sent: 0, reason: "disabled_by_user_preferences", type });
    }

    const tokens = (devices ?? []).map((d: any) => ({ ...d, device_token: String(d.device_token ?? "").trim() }))
      .filter((d: any) => d.device_token.length > 0);
    if (tokens.length === 0) return json({ ok: true, sent: 0, reason: "no_push_device" });

    const sa = JSON.parse(serviceAccountRaw);
    const accessToken = await getFirebaseAccessToken(sa);
    const recordData = record.data && typeof record.data === "object" ? record.data : {};
    const dataBase: Record<string, string> = { type, notification_id: String(record.id ?? "") };
    for (const [key, value] of Object.entries(recordData)) if (value != null)
      dataBase[key] = typeof value === "string" ? value : JSON.stringify(value);

    const requestedLanguage = String(pref.language ?? "").toLowerCase().split(/[-_]/)[0];
    const language = SUPPORTED_LANGUAGES.includes(requestedLanguage) ? requestedLanguage : "fr";

    // The database row's title/body are often authored in French. Never use
    // them as the primary copy when a localized template exists for the user.
    const { data: localized, error: locError } = await supabaseAdmin.rpc("render_notification_for_push", {
      p_type: type, p_data: recordData, p_language: language,
      p_fallback_title: "Scrole", p_fallback_body: "",
    });
    if (locError) console.error("notification localization failed", { type, language, error: locError });

    // Some legacy notification types have no template yet. Keep a localized,
    // non-French fallback rather than leaking the French DB title/body.
    const genericCopy: Record<string, { title: string; body: string }> = {
      fr: { title: "Scrole", body: "Vous avez une nouvelle notification." },
      en: { title: "Scrole", body: "You have a new notification." },
      es: { title: "Scrole", body: "Tienes una nueva notificación." },
      de: { title: "Scrole", body: "Du hast eine neue Benachrichtigung." },
      it: { title: "Scrole", body: "Hai una nuova notifica." },
      pt: { title: "Scrole", body: "Você tem uma nova notificação." },
      zh: { title: "Scrole", body: "你有一条新通知。" },
      ja: { title: "Scrole", body: "新しい通知があります。" },
      ru: { title: "Scrole", body: "У вас новое уведомление." },
    };
    const fallback = genericCopy[language] ?? genericCopy.fr;
    const title = String(localized?.title || fallback.title);
    const body = String(localized?.body || fallback.body);
    const data = { ...dataBase, language, title, body };
    const results = [];

    for (const device of tokens) {
      const isIos = String(device.platform ?? "").toLowerCase() === "ios";
      const message: any = { token: device.device_token, data, android: { priority: "HIGH" } };
      if (type === "message_received") {
        message.apns = { payload: { aps: { "content-available": 1 } } };
      } else if (isIos) {
        // iOS : bloc notification conservé. Android : message data seul, l'app affiche une seule notification locale.
        message.notification = { title, body };
      }

      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message }),
      });
      const responseBody = await response.json();
      results.push({ token_suffix: device.device_token.slice(-8), platform: device.platform, language, ok: response.ok, status: response.status });
      if (!response.ok) {
        console.error("FCM send failed", response.status, responseBody);
        const fcmErrorCode = (responseBody?.error?.details ?? [])
          .map((detail: any) => String(detail?.errorCode ?? ""))
          .find((code: string) => code.length > 0) ?? "";
        const fcmMessage = String(responseBody?.error?.message ?? "");
        const invalidToken =
          response.status === 404 &&
          (fcmErrorCode === "UNREGISTERED" ||
            fcmMessage === "NotRegistered" ||
            String(responseBody?.error?.status ?? "") === "NOT_FOUND");
        if (invalidToken) {
          const { error: disableError } = await supabaseAdmin
            .from("user_devices")
            .update({ push_enabled: false })
            .eq("id", device.id)
            .eq("user_id", userId);
          if (disableError) {
            console.error("Failed to disable unregistered FCM token", {
              device_id: device.id,
              error: disableError,
            });
          } else {
            console.warn("Disabled unregistered FCM token", {
              device_id: device.id,
              platform: device.platform,
            });
          }
        }
      }
    }

    const sent = results.filter(r => r.ok).length;
    return json({ ok: sent > 0 || results.length === 0, sent, total: results.length, language, results });
  } catch (error) {
    console.error("send-fcm-notification failed", error);
    return json({ error: "send_fcm_notification_failed" }, 500);
  }
});
