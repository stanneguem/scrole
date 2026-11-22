import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const accountId = Deno.env.get("R2_ACCOUNT_ID");
  const accessKeyId = Deno.env.get("R2_PRIVATE_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("R2_PRIVATE_SECRET_ACCESS_KEY");
  const bucket = Deno.env.get("R2_PRIVATE_BUCKET_NAME");
  const endpoint = Deno.env.get("R2_PRIVATE_ENDPOINT") || (accountId ? `https://${accountId}.r2.cloudflarestorage.com` : "");
  if (!supabaseUrl || !serviceKey) return json({ error: "supabase_not_configured" }, 503);
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const workerSecret = req.headers.get("x-worker-secret") ?? "";
  if (workerSecret.length < 32) return json({ error: "worker_secret_required" }, 401);
  const { data: validWorker, error: workerError } = await admin.rpc("verify_worker_secret", { p_name: "media_gc_worker_secret", p_secret: workerSecret });
  if (workerError || validWorker !== true) return json({ error: "worker_secret_invalid" }, 401);
  const r2Configured = !!(accountId && accessKeyId && secretAccessKey && bucket && endpoint);
  const s3 = r2Configured ? new S3Client({ region: "auto", endpoint: endpoint!, credentials: { accessKeyId: accessKeyId!, secretAccessKey: secretAccessKey! } }) : null;
  try {
    const { data: queued, error } = await admin.from("salon_message_media_cleanup_queue").select("id,object_key,attempts").order("created_at", { ascending: true }).order("id", { ascending: true }).limit(100);
    if (error) throw error;
    let deleted = 0, failed = 0, r2Deleted = 0, legacyDeleted = 0;
    for (const item of queued ?? []) {
      const key = String(item.object_key ?? "");
      const isR2 = /^salon-messages\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$/i.test(key);
      const isLegacyStorage = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$/i.test(key);
      try {
        if (isR2) {
          if (!s3 || !bucket) throw new Error("private_r2_not_configured");
          await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
          r2Deleted++;
        } else if (isLegacyStorage) {
          const { error: storageError } = await admin.storage.from("community-salon-media").remove([key]);
          if (storageError) throw storageError;
          legacyDeleted++;
        } else throw new Error("invalid_salon_media_object_key");
        const { error: queueError } = await admin.from("salon_message_media_cleanup_queue").delete().eq("id", item.id);
        if (queueError) throw queueError;
        deleted++;
      } catch (err) {
        failed++;
        const message = err instanceof Error ? err.message : String(err);
        console.error("[salon-media-cleanup] deletion failed", { key, error: message });
        await admin.from("salon_message_media_cleanup_queue").update({ attempts: Number(item.attempts ?? 0) + 1, last_error: message.slice(0, 1000), last_attempt_at: new Date().toISOString() }).eq("id", item.id);
      }
    }
    return json({ success: failed === 0, processed: queued?.length ?? 0, media_deleted: deleted, r2_deleted: r2Deleted, legacy_storage_deleted: legacyDeleted, failures: failed, queued_remaining_estimate: Math.max(0, (queued?.length ?? 0) - deleted) }, failed ? 207 : 200);
  } catch (err) {
    console.error("[salon-media-cleanup] run failed", err);
    return json({ error: "cleanup_run_failed" }, 500);
  }
});
