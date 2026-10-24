import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3";

const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return respond(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const account = Deno.env.get("R2_ACCOUNT_ID");
  const bucket = Deno.env.get("R2_PRIVATE_BUCKET_NAME");
  const access = Deno.env.get("R2_PRIVATE_ACCESS_KEY_ID");
  const secret = Deno.env.get("R2_PRIVATE_SECRET_ACCESS_KEY");
  const endpoint = Deno.env.get("R2_PRIVATE_ENDPOINT") || (account ? `https://${account}.r2.cloudflarestorage.com` : "");
  if (!url || !anon || !service || !account || !bucket || !access || !secret || !endpoint) return respond(503, { error: "message_media_storage_not_configured" });
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return respond(401, { error: "authentication_required" });
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return respond(401, { error: "invalid_session" });
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return respond(400, { error: "invalid_json" }); }
  const messageId = typeof body.message_id === "string" ? body.message_id.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(messageId)) return respond(400, { error: "invalid_message_id" });
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: message, error: messageError } = await admin.from("direct_messages").select("id,conversation_id,sender_id,audio_url,media_urls").eq("id", messageId).maybeSingle();
  if (messageError) return respond(500, { error: "message_lookup_failed" });
  if (!message) return respond(404, { error: "message_not_found" });
  if (message.sender_id === user.id) return respond(403, { error: "recipient_only" });
  const { data: conversation, error: conversationError } = await admin.from("direct_conversations").select("user_one_id,user_two_id").eq("id", message.conversation_id).maybeSingle();
  if (conversationError) return respond(500, { error: "conversation_lookup_failed" });
  if (!conversation || ![conversation.user_one_id, conversation.user_two_id].includes(user.id)) return respond(403, { error: "conversation_participant_required" });
  const { data: receipt, error: receiptError } = await admin.from("direct_message_receipts").select("delivered_at").eq("message_id", messageId).eq("user_id", user.id).maybeSingle();
  if (receiptError) return respond(500, { error: "receipt_lookup_failed" });
  if (!receipt?.delivered_at) return respond(409, { error: "message_not_confirmed_delivered" });
  const toKey = (value: unknown): string | null => {
    if (typeof value !== "string" || !value.trim()) return null;
    let key = value.trim();
    // Never interpret legacy Supabase Storage URLs as R2 keys. Historical
    // media stays in its original bucket and is intentionally not deleted here.
    if (/^https?:\/\//i.test(key)) return null;
    if (key.startsWith("/") || key.includes("..") || key.includes("\\") || !key.startsWith(`messages/${message.conversation_id}/`) || key.split("/").length !== 4) return null;
    const parts = key.split("/");
    if (parts[2] !== message.sender_id || !/^[a-f0-9-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$/i.test(parts[3])) return null;
    return key;
  };
  const raw = [...(Array.isArray(message.media_urls) ? message.media_urls : []), message.audio_url].filter((v) => typeof v === "string" && v.trim()) as string[];
  // Legacy Supabase Storage URLs and unknown historical formats are deliberately
  // skipped. They must never block cleanup of valid new R2 keys in the same message.
  const recognized = raw.map(toKey);
  const keys = [...new Set(recognized.filter((k): k is string => k !== null))];
  const skippedLegacyReferences = recognized.filter((k) => k === null).length;
  try {
    if (keys.length > 0) {
      const s3 = new S3Client({ region: "auto", endpoint, credentials: { accessKeyId: access, secretAccessKey: secret } });
      for (const key of keys) await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
    }
  } catch (error) {
    console.error("[delete-delivered-message-media] R2 deletion failed", { messageId, error });
    return respond(502, { error: "r2_delete_failed", deleted: false });
  }
  // Keep the message's media references as metadata. The recipient has already
  // cached the bytes locally before the delivery receipt was recorded; clearing
  // these columns would make the attachment disappear from the conversation UI.
  return respond(200, { deleted: true, count: keys.length, skipped_legacy_references: skippedLegacyReferences, message_id: messageId });
});