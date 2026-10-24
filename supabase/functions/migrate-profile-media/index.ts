import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3@3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/avif": "avif",
};
const isLegacyUrl = (value: unknown, allowedBuckets: string[]) => {
  if (typeof value !== "string" || !value.trim()) return false;
  try {
    const url = new URL(value);
    if (url.hostname !== "djvmxrwfchnqdtzayhwf.supabase.co" || url.protocol !== "https:") return false;
    const parts = url.pathname.split("/").filter(Boolean);
    return parts.length >= 5 && parts[0] === "storage" && parts[1] === "v1" &&
      parts[2] === "object" && parts[3] === "public" && allowedBuckets.includes(parts[4]);
  } catch { return false; }
};
const extensionFromType = (type: string, sourceUrl: string) => {
  const normalized = type.toLowerCase().split(";")[0].trim();
  if (EXTENSIONS[normalized]) return { contentType: normalized, extension: EXTENSIONS[normalized] };
  const pathname = new URL(sourceUrl).pathname.toLowerCase();
  const ext = pathname.split(".").pop() ?? "";
  if (["jpg", "jpeg", "png", "webp", "avif"].includes(ext)) {
    return { contentType: ext === "jpg" || ext === "jpeg" ? "image/jpeg" : `image/${ext}`, extension: ext === "jpeg" ? "jpg" : ext };
  }
  throw new Error("unsupported_source_content_type");
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const accountId = Deno.env.get("R2_ACCOUNT_ID");
  const accessKeyId = Deno.env.get("R2_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const bucket = Deno.env.get("R2_BUCKET_NAME")?.trim();
  const publicBaseUrl = Deno.env.get("R2_PUBLIC_BASE_URL")?.replace(/\/+$/, "");
  if (!supabaseUrl || !anonKey || !serviceKey || !accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return reply(503, { error: "migration_storage_not_configured" });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  // This endpoint is intentionally not callable by ordinary app users. A trusted
  // server-side operator may use the service-role JWT; otherwise require an explicit
  // platform-admin role in app_metadata or public.user_roles.
  let userId: string | null = null;
  let isServiceRole = authorization === `Bearer ${serviceKey}`;
  if (!isServiceRole) {
    if (!authorization.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error } = await userClient.auth.getUser();
    if (error || !user) return reply(401, { error: "invalid_session" });
    userId = user.id;
    const appMeta = user.app_metadata ?? {};
    const metaRoles = [
      appMeta.role, appMeta.user_role, appMeta.platform_role,
      ...(Array.isArray(appMeta.roles) ? appMeta.roles : []),
    ].map((role) => String(role).toLowerCase());
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: roleRows } = await admin.from("user_roles").select("role").eq("user_id", user.id);
    const dbRoles = (roleRows ?? []).map((row) => String(row.role).toLowerCase());
    const allowedRoles = new Set(["admin", "super_admin", "platform_admin", "administrateur"]);
    if (![...metaRoles, ...dbRoles].some((role) => allowedRoles.has(role))) {
      return reply(403, { error: "platform_admin_required" });
    }
  }
  if (!isServiceRole && !userId) return reply(403, { error: "trusted_operator_required" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (body.confirm !== "MIGRATE_PUBLIC_PROFILE_MEDIA") {
    return reply(400, { error: "explicit_confirmation_required", expected: "MIGRATE_PUBLIC_PROFILE_MEDIA" });
  }
  const dryRun = body.dry_run === true;
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const s3 = new S3Client({
    region: "auto",
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId, secretAccessKey },
  });

  const summary = { scanned: 0, migrated: 0, skipped: 0, failed: 0, dry_run: dryRun, errors: [] as Array<Record<string, string>> };
  const migrateOne = async (
    kind: "profile_avatar" | "profile_cover" | "community_avatar" | "community_cover",
    entityId: string,
    sourceUrl: string,
  ): Promise<string | null> => {
    const buckets = kind.startsWith("profile_") ? ["avatars"] : ["community-media"];
    if (!isLegacyUrl(sourceUrl, buckets)) { summary.skipped++; return null; }
    summary.scanned++;
    const source = new URL(sourceUrl);
    const pathParts = source.pathname.split("/").filter(Boolean);
    const objectPath = pathParts.slice(5).map(decodeURIComponent).join("/");
    if (!objectPath || objectPath.includes("..") || objectPath.includes("\\")) {
      throw new Error("invalid_legacy_object_path");
    }
    const response = await fetch(sourceUrl, { redirect: "error" });
    if (!response.ok) throw new Error(`legacy_download_http_${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!bytes.length || bytes.length > 15 * 1024 * 1024) throw new Error("legacy_image_size_invalid");
    const type = extensionFromType(response.headers.get("content-type") ?? "", sourceUrl);
    const id = crypto.randomUUID();
    const key = kind === "profile_avatar" ? `profiles/${entityId}/avatar/${id}.${type.extension}`
      : kind === "profile_cover" ? `profiles/${entityId}/cover/${id}.${type.extension}`
      : kind === "community_avatar" ? `communities/${entityId}/avatar/${id}.${type.extension}`
      : `communities/${entityId}/cover/${id}.${type.extension}`;
    if (dryRun) { summary.skipped++; return null; }
    await s3.send(new PutObjectCommand({
      Bucket: bucket, Key: key, Body: bytes, ContentType: type.contentType,
      CacheControl: "public, max-age=86400",
    }));
    return `${publicBaseUrl}/${key.split("/").map(encodeURIComponent).join("/")}`;
  };

  const migrateField = async (
    table: "user_profiles" | "communities",
    idColumn: "user_id" | "id",
    id: string,
    column: "photo_url" | "cover_url" | "photo_profile" | "photo_cover",
    kind: "profile_avatar" | "profile_cover" | "community_avatar" | "community_cover",
    oldUrl: string | null,
  ) => {
    if (!oldUrl || !isLegacyUrl(oldUrl, kind.startsWith("profile_") ? ["avatars"] : ["community-media"])) return;
    try {
      const newUrl = await migrateOne(kind, id, oldUrl);
      if (!newUrl || dryRun) return;
      const { data, error } = await admin.from(table).update({ [column]: newUrl }).eq(idColumn, id).eq(column, oldUrl).select(idColumn).maybeSingle();
      if (error) throw new Error(`database_update_failed:${error.message}`);
      if (!data) {
        // Do not delete the copied object; leave it recoverable and keep the newer
        // database value untouched if the row changed concurrently.
        summary.failed++;
        summary.errors.push({ entity: `${table}:${id}`, field: column, error: "row_changed_during_migration" });
        return;
      }
      summary.migrated++;
    } catch (error) {
      summary.failed++;
      summary.errors.push({ entity: `${table}:${id}`, field: column, error: error instanceof Error ? error.message : String(error) });
    }
  };

  // Query only rows that still point to the legacy public buckets and paginate
  // to avoid silently skipping records after the first 5,000 rows.
  const pageSize = 250;
  for (let offset = 0; ; offset = 0) {
    const { data: profiles, error: profileError } = await admin.from("user_profiles")
      .select("user_id,photo_url,cover_url")
      .or("photo_url.like.%supabase.co/storage/v1/object/public/avatars/%,cover_url.like.%supabase.co/storage/v1/object/public/avatars/%")
      .order("user_id").range(offset, offset + pageSize - 1);
    if (profileError) return reply(500, { error: "profile_scan_failed", offset });
    for (const row of profiles ?? []) {
      await migrateField("user_profiles", "user_id", row.user_id, "photo_url", "profile_avatar", row.photo_url);
      await migrateField("user_profiles", "user_id", row.user_id, "cover_url", "profile_cover", row.cover_url);
    }
    if (!profiles || profiles.length < pageSize) break;
  }

  for (let offset = 0; ; offset = 0) {
    const { data: communities, error: communityError } = await admin.from("communities")
      .select("id,photo_profile,photo_cover")
      .or("photo_profile.like.%supabase.co/storage/v1/object/public/community-media/%,photo_cover.like.%supabase.co/storage/v1/object/public/community-media/%")
      .order("id").range(offset, offset + pageSize - 1);
    if (communityError) return reply(500, { error: "community_scan_failed", offset });
    for (const row of communities ?? []) {
      await migrateField("communities", "id", row.id, "photo_profile", "community_avatar", row.photo_profile);
      await migrateField("communities", "id", row.id, "photo_cover", "community_cover", row.photo_cover);
    }
    if (!communities || communities.length < pageSize) break;
  }
  return reply(summary.failed ? 207 : 200, { ...summary, note: "Source objects were not deleted. Re-run safely to retry failures." });
});
