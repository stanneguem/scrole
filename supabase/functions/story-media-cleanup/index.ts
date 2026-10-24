import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

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

  if (!supabaseUrl || !serviceKey || !accountId || !accessKeyId || !secretAccessKey || !bucket || !endpoint) {
    return json({ error: "cleanup_not_configured" }, 503);
  }

  // This endpoint is for trusted scheduler/service-role calls only.
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token || token !== serviceKey) return json({ error: "service_role_required" }, 401);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const s3 = new S3Client({
    region: "auto",
    endpoint,
    credentials: { accessKeyId, secretAccessKey },
  });

  try {
    // Expiration is handled server-side, independently of clients opening the app.
    // The DELETE trigger queues only the story's own canonical R2 media key.
    const { data: expired, error: expiredError } = await admin
      .from("stories")
      .select("id")
      .lte("expires_at", new Date().toISOString())
      .limit(200);
    if (expiredError) throw expiredError;

    let expiredRowsDeleted = 0;
    for (const row of expired ?? []) {
      const { error } = await admin.from("stories").delete().eq("id", row.id).lte("expires_at", new Date().toISOString());
      if (error) {
        console.error("[story-media-cleanup] expired story deletion failed", { storyId: row.id, error: error.message });
      } else {
        expiredRowsDeleted++;
      }
    }

    const { data: queued, error: queueError } = await admin
      .from("story_media_cleanup_queue")
      .select("id,object_key,attempts")
      .order("created_at", { ascending: true })
      .limit(100);
    if (queueError) throw queueError;

    let deletedCount = 0;
    let failedCount = 0;
    for (const item of queued ?? []) {
      const key = String(item.object_key ?? "");
      // Revalidate keys before passing them to R2; never allow arbitrary object deletion.
      if (!/^stories\/[0-9a-f-]+\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov)$/i.test(key)) {
        await admin.from("story_media_cleanup_queue").update({
          attempts: Number(item.attempts ?? 0) + 1,
          last_error: "invalid_story_object_key",
          last_attempt_at: new Date().toISOString(),
        }).eq("id", item.id);
        failedCount++;
        continue;
      }
      try {
        await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
        const { error } = await admin.from("story_media_cleanup_queue").delete().eq("id", item.id);
        if (error) throw error;
        deletedCount++;
      } catch (error) {
        failedCount++;
        const message = error instanceof Error ? error.message : String(error);
        console.error("[story-media-cleanup] R2 deletion failed", { key, error: message });
        await admin.from("story_media_cleanup_queue").update({
          attempts: Number(item.attempts ?? 0) + 1,
          last_error: message.slice(0, 1000),
          last_attempt_at: new Date().toISOString(),
        }).eq("id", item.id);
      }
    }

    return json({
      success: failedCount === 0,
      expired_rows_deleted: expiredRowsDeleted,
      media_deleted: deletedCount,
      media_failures: failedCount,
      queued_remaining: Math.max(0, (queued?.length ?? 0) - deletedCount),
    }, failedCount ? 207 : 200);
  } catch (error) {
    console.error("[story-media-cleanup] run failed", error);
    return json({ error: "cleanup_run_failed" }, 500);
  }
});
