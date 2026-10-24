import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geocodeUrl = Deno.env.get("GEOLOCATION_VERIFY_URL");
  const geocodeToken = Deno.env.get("GEOLOCATION_VERIFY_TOKEN");
  if (!supabaseUrl || !anonKey || !serviceKey || !geocodeUrl) {
    return reply(503, { error: "country_verification_not_configured" });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }

  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  const accuracy = Number(body.accuracy_m);
  const deviceId = typeof body.device_id === "string" ? body.device_id : "";
  const requestId = typeof body.request_id === "string" ? body.request_id : "";
  // GPS country detection is independent of the declared profile location.
  const capturedAt = new Date(typeof body.captured_at === "string" ? body.captured_at : "");

  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return reply(400, { error: "invalid_coordinates" });
  }
  if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > 1000) {
    return reply(400, { error: "gps_accuracy_insufficient", maximum_accuracy_m: 1000 });
  }
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!deviceId || !uuidPattern.test(requestId)) {
    return reply(400, { error: "invalid_device_or_request" });
  }
  const ageMs = Date.now() - capturedAt.getTime();
  if (!Number.isFinite(capturedAt.getTime()) || ageMs < -30_000 || ageMs > 120_000) {
    return reply(400, { error: "gps_fix_too_old" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return reply(401, { error: "invalid_session" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: device, error: deviceError } = await admin.from("user_devices")
    .select("id").eq("id", deviceId).eq("user_id", user.id).maybeSingle();
  if (deviceError) return reply(500, { error: "device_lookup_failed" });
  if (!device) return reply(403, { error: "device_not_owned_by_user" });

  let countryCode = "";
  try {
    const url = new URL(geocodeUrl);
    url.searchParams.set("lat", String(latitude));
    url.searchParams.set("lon", String(longitude));
    // Geoapify uses an apiKey query parameter. Keep this key server-side in Edge Function secrets.
    if (geocodeToken) url.searchParams.set("apiKey", geocodeToken);
    const geoResponse = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(5000),
    });
    if (!geoResponse.ok) return reply(502, { error: "geolocation_provider_failed" });
    const geo = await geoResponse.json();
    // Geoapify returns GeoJSON: features[0].properties.country_code.
    // Keep compatible with providers returning address.country_code or country_code at the root.
    const rawCode = geo?.features?.[0]?.properties?.country_code ??
      geo?.address?.country_code ?? geo?.country_code ?? geo?.countryCode;
    countryCode = typeof rawCode === "string" ? rawCode.toUpperCase() : "";
  } catch {
    return reply(502, { error: "geolocation_provider_unavailable" });
  }
  if (!/^[A-Z]{2}$/.test(countryCode)) return reply(422, { error: "country_could_not_be_resolved" });

  const { data: country, error: countryError } = await admin.from("countries")
    .select("id,code_iso").ilike("code_iso", countryCode).eq("is_active", true).maybeSingle();
  if (countryError) return reply(500, { error: "country_lookup_failed" });
  if (!country) return reply(422, { error: "country_not_supported", country_code: countryCode });
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 15 * 60 * 1000);
  const { data: verification, error: insertError } = await admin.from("user_country_verifications")
    .insert({
      user_id: user.id,
      country_id: country.id,
      country_code: countryCode,
      status: "verified",
      method: "gps",
      accuracy_m: accuracy,
      captured_at: capturedAt.toISOString(),
      verified_at: now.toISOString(),
      expires_at: expiresAt.toISOString(),
      request_id: requestId,
    }).select("id").single();

  if (insertError) {
    if (insertError.code === "23505") return reply(409, { error: "request_already_used" });
    return reply(500, { error: "verification_record_failed" });
  }

  const { error: deviceUpdateError } = await admin.from("user_devices").update({
    detected_country_id: country.id,
    last_seen_at: now.toISOString(),
  }).eq("id", deviceId).eq("user_id", user.id);
  if (deviceUpdateError) return reply(500, { error: "device_country_update_failed" });

  return reply(200, {
    status: "verified",
    detected_country_id: country.id,
    detected_country_code: countryCode,
    verified_at: now.toISOString(),
    expires_at: expiresAt.toISOString(),
    verification_id: verification.id,
  });
});