import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const bunnyLibraryId = Deno.env.get("BUNNY_LIBRARY_ID")!;
const bunnyApiKey = Deno.env.get("BUNNY_API_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });


type R2MediaObject = { key: string; url: string | null };

function collectR2Objects(objects: Map<string, R2MediaObject>, value: unknown) {
  if (Array.isArray(value)) {
    for (const item of value) collectR2Objects(objects, item);
    return;
  }
  if (!value || typeof value !== "object") return;
  const item = value as Record<string, unknown>;
  if (String(item.storage ?? "").toLowerCase() === "r2") {
    const key = typeof item.object_key === "string" ? item.object_key.trim() : "";
    if (key) objects.set(key, { key, url: typeof item.url === "string" && item.url.trim() ? item.url.trim() : null });
    if (String(item.thumbnail_storage ?? "").toLowerCase() === "r2") {
      const thumbnailKey = typeof item.thumbnail_object_key === "string" ? item.thumbnail_object_key.trim() : "";
      if (thumbnailKey) {
        objects.set(thumbnailKey, {
          key: thumbnailKey,
          url: typeof item.thumbnail_url === "string" && item.thumbnail_url.trim() ? item.thumbnail_url.trim() : null,
        });
      }
    }
  }
  for (const child of Object.values(item)) collectR2Objects(objects, child);
}

function isAllowedPostR2Key(key: string, post: Record<string, unknown>): boolean {
  if (!key || key.startsWith("/") || key.includes("..") || key.includes("\\") ||
      key.includes("?") || key.includes("#") || key.split("/").some((part) => !part)) return false;
  const authorId = String(post.author_id ?? "");
  const communityId = typeof post.community_id === "string" ? post.community_id : "";
  if (!authorId) return false;
  if (communityId) {
    // Public community media and thumbnails use different subpaths. Private
    // community thumbnails include /thumbnails/ before the author's ID.
    return key.startsWith(`communities/${communityId}/posts/`) ||
      key.startsWith(`private/communities/${communityId}/posts/${authorId}/`) ||
      key.startsWith(`private/communities/${communityId}/posts/thumbnails/${authorId}/`);
  }
  // Public feed video thumbnails are stored separately from the original video
  // under thumbnails/posts/<authorId>/<uploadId>.<ext>.
  return key.startsWith(`posts/${authorId}/`) ||
    key.startsWith(`thumbnails/posts/${authorId}/`) ||
    key.startsWith(`users/${authorId}/posts/`);
}

function getR2Configuration(key: string) {
  const accountId = Deno.env.get("R2_ACCOUNT_ID")?.trim();
  if (key.startsWith("private/")) {
    const bucket = Deno.env.get("R2_PRIVATE_BUCKET_NAME")?.trim();
    const accessKeyId = Deno.env.get("R2_PRIVATE_ACCESS_KEY_ID")?.trim();
    const secretAccessKey = Deno.env.get("R2_PRIVATE_SECRET_ACCESS_KEY")?.trim();
    const endpoint = Deno.env.get("R2_PRIVATE_ENDPOINT")?.trim() ||
      (accountId ? `https://${accountId}.r2.cloudflarestorage.com` : "");
    if (!bucket || !accessKeyId || !secretAccessKey || !endpoint) throw new Error("Configuration du stockage R2 privé incomplète");
    return { bucket, accessKeyId, secretAccessKey, endpoint };
  }
  const bucket = Deno.env.get("R2_BUCKET_NAME")?.trim();
  const accessKeyId = Deno.env.get("R2_ACCESS_KEY_ID")?.trim();
  const secretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY")?.trim();
  const endpoint = accountId ? `https://${accountId}.r2.cloudflarestorage.com` : "";
  if (!bucket || !accessKeyId || !secretAccessKey || !endpoint) throw new Error("Configuration du stockage R2 public incomplète");
  return { bucket, accessKeyId, secretAccessKey, endpoint };
}

async function deleteR2Object(key: string) {
  const config = getR2Configuration(key);
  const client = new S3Client({ region: "auto", endpoint: config.endpoint, credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey } });
  await client.send(new DeleteObjectCommand({ Bucket: config.bucket, Key: key }));
}

async function isR2ObjectReferencedElsewhere(
  adminClient: ReturnType<typeof createClient>, postId: string, object: R2MediaObject,
): Promise<boolean> {
  for (const column of ["media", "videos"] as const) {
    const keyQuery = await adminClient.from("community_posts").select("id").neq("id", postId).filter(column, "cs", JSON.stringify([{ object_key: object.key }])).limit(1);
    if (keyQuery.error) throw new Error(`Vérification R2 échouée (${column}.object_key): ${keyQuery.error.message}`);
    if ((keyQuery.data ?? []).length > 0) return true;
    const thumbnailKeyQuery = await adminClient.from("community_posts").select("id").neq("id", postId).filter(column, "cs", JSON.stringify([{ thumbnail_object_key: object.key }])).limit(1);
    if (thumbnailKeyQuery.error) throw new Error(`Vérification R2 échouée (${column}.thumbnail_object_key): ${thumbnailKeyQuery.error.message}`);
    if ((thumbnailKeyQuery.data ?? []).length > 0) return true;
    if (object.url) {
      const urlQuery = await adminClient.from("community_posts").select("id").neq("id", postId).filter(column, "cs", JSON.stringify([{ url: object.url }])).limit(1);
      if (urlQuery.error) throw new Error(`Vérification R2 échouée (${column}.url): ${urlQuery.error.message}`);
      if ((urlQuery.data ?? []).length > 0) return true;
    }
  }
  if (object.url) {
    const checks = await Promise.all([
      adminClient.from("community_posts").select("id").neq("id", postId).contains("photos", [object.url]).limit(1),
      adminClient.from("community_posts").select("id").neq("id", postId).eq("photo", object.url).limit(1),
      adminClient.from("community_posts").select("id").neq("id", postId).eq("video_url", object.url).limit(1),
      adminClient.from("community_posts").select("id").neq("id", postId).eq("video_thumbnail_url", object.url).limit(1),
    ]);
    for (const result of checks) {
      if (result.error) throw new Error(`Vérification R2 échouée (référence URL): ${result.error.message}`);
      if ((result.data ?? []).length > 0) return true;
    }
  }
  return false;
}

function addFile(files: Map<string, Set<string>>, bucket: string, path: string) {
  const clean = path.trim().replace(/^\/+/, "");
  if (!clean) return;
  if (!files.has(bucket)) files.set(bucket, new Set());
  files.get(bucket)!.add(clean);
}

function addValue(
  files: Map<string, Set<string>>,
  value: unknown,
  fallbackBucket?: string,
) {
  if (typeof value !== "string" || !value.trim()) return;
  const raw = value.trim();

  const match = raw.match(
    /\/storage\/v1\/object\/(?:public|authenticated|sign)\/([^/?#]+)\/([^?#]+)/,
  );
  if (match) {
    addFile(files, match[1], decodeURIComponent(match[2]));
    return;
  }
  if (/^https?:\/\//i.test(raw)) return;
  if (fallbackBucket) addFile(files, fallbackBucket, raw);
}

function walkJson(
  files: Map<string, Set<string>>,
  value: unknown,
  keyHint = "",
) {
  if (typeof value === "string") {
    const hint = keyHint.toLowerCase();
    const bucket =
      hint.includes("thumbnail") ||
      hint.includes("photo") ||
      hint.includes("image")
        ? "community-media"
        : hint.includes("video")
          ? "community-videos"
          : undefined;
    addValue(files, value, bucket);
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) walkJson(files, item, keyHint);
    return;
  }

  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(
      value as Record<string, unknown>,
    )) {
      walkJson(files, child, key);
    }
  }
}

function collectBunnyIds(
  ids: Set<string>,
  value: unknown,
  keyHint = "",
) {
  if (typeof value === "string") {
    if (keyHint.toLowerCase().includes("video_id")) {
      ids.add(value.trim());
    }
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) collectBunnyIds(ids, item, keyHint);
    return;
  }

  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(
      value as Record<string, unknown>,
    )) {
      collectBunnyIds(ids, child, key);
    }
  }
}

async function deleteBunnyVideo(videoId: string): Promise<{
  videoId: string;
  deleted: boolean;
  alreadyAbsent: boolean;
}> {
  const response = await fetch(
    `https://video.bunnycdn.com/library/${encodeURIComponent(
      bunnyLibraryId,
    )}/videos/${encodeURIComponent(videoId)}`,
    {
      method: "DELETE",
      headers: {
        AccessKey: bunnyApiKey,
        Accept: "application/json",
      },
    },
  );

  if (response.ok) {
    return { videoId, deleted: true, alreadyAbsent: false };
  }

  // Deletion is idempotent for our workflow: if a previous attempt already
  // removed this Bunny video, a later retry must be allowed to continue.
  if (response.status === 404) {
    return { videoId, deleted: false, alreadyAbsent: true };
  }

  const details = await response.text().catch(() => "");
  throw new Error(
    `Bunny video ${videoId} deletion failed (${response.status}): ${details}`,
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Authentication required" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();

  if (authError || !user) {
    return json({ error: "Authentication required" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const postId = body?.post_id;

  if (
    typeof postId !== "string" ||
    !/^[0-9a-fA-F-]{36}$/.test(postId)
  ) {
    return json({ error: "post_id invalide" }, 400);
  }

  // This RPC performs the authoritative authorization check first.
  const { data: manifest, error: manifestError } =
    await userClient.rpc("get_community_post_deletion_manifest", {
      p_id: postId,
    });

  if (manifestError) {
    return json({ error: manifestError.message }, 403);
  }

  const { data: post, error: postError } = await adminClient
    .from("community_posts")
    .select(
      "id,author_id,community_id,media,videos,photos,photo,video_url,video_thumbnail_url",
    )
    .eq("id", postId)
    .maybeSingle();

  if (postError || !post) {
    return json(
      { error: postError?.message ?? "Post introuvable" },
      404,
    );
  }

  const bunnyIds = new Set<string>();
  for (const item of manifest?.bunny_videos ?? []) {
    if (item?.video_id) bunnyIds.add(String(item.video_id));
  }

  collectBunnyIds(bunnyIds, post.media, "media");
  collectBunnyIds(bunnyIds, post.videos, "videos");

  const files = new Map<string, Set<string>>();
  const r2Objects = new Map<string, R2MediaObject>();
  collectR2Objects(r2Objects, post.media);
  collectR2Objects(r2Objects, post.videos);

  for (const item of manifest?.files ?? []) {
    if (item?.bucket && item?.path) {
      const path = String(item.path);
      if (/^https?:\/\//i.test(path) && !path.includes("/storage/v1/object/")) continue;
      addFile(files, String(item.bucket), path);
    }
  }

  // Legacy media is also collected so old posts are fully cleaned.
  walkJson(files, post.media, "media");
  walkJson(files, post.videos, "videos");

  for (const value of post.photos ?? []) {
    addValue(files, value, "community-media");
  }
  addValue(files, post.photo, "community-media");
  addValue(files, post.video_url, "community-videos");
  addValue(files, post.video_thumbnail_url, "community-media");

  for (const object of r2Objects.values()) {
    if (!isAllowedPostR2Key(object.key, post as unknown as Record<string, unknown>)) {
      return json({ error: "Clé R2 non autorisée pour cette publication", post_id: postId }, 400);
    }
    try { getR2Configuration(object.key); } catch (error) {
      return json({ error: "Configuration Cloudflare R2 incomplète", details: error instanceof Error ? error.message : String(error), post_id: postId }, 503);
    }
  }

  const deletedR2Objects: string[] = [];
  const retainedSharedR2Objects: string[] = [];
  let currentR2Key: string | null = null;
  let r2FailureStage: "reference_check" | "delete_object" | null = null;
  try {
    for (const object of r2Objects.values()) {
      currentR2Key = object.key;
      r2FailureStage = "reference_check";
      if (await isR2ObjectReferencedElsewhere(adminClient, postId, object)) {
        retainedSharedR2Objects.push(object.key);
        continue;
      }
      r2FailureStage = "delete_object";
      await deleteR2Object(object.key);
      deletedR2Objects.push(object.key);
    }
  } catch (error) {
    const details = error instanceof Error ? error.message : String(error);
    console.error("[delete-community-post] R2 cleanup failed", {
      postId, key: currentR2Key, stage: r2FailureStage, details,
    });
    return json({
      error: "Suppression des médias Cloudflare R2 impossible",
      post_id: postId,
      r2_deleted: deletedR2Objects.length,
      stage: r2FailureStage,
      failed_key: currentR2Key,
      details,
    }, 502);
  }

  const deletedBunnyVideos: string[] = [];
  const alreadyAbsentBunnyVideos: string[] = [];

  try {
    for (const videoId of bunnyIds) {
      const result = await deleteBunnyVideo(videoId);
      if (result.deleted) deletedBunnyVideos.push(videoId);
      if (result.alreadyAbsent) alreadyAbsentBunnyVideos.push(videoId);
    }
  } catch (error) {
    return json(
      {
        error: "Suppression des vidéos Bunny impossible",
        details: error instanceof Error ? error.message : String(error),
        post_id: postId,
      },
      502,
    );
  }

  let deletedStorageFiles = 0;

  for (const [bucket, pathsSet] of files) {
    const paths = [...pathsSet];

    for (let i = 0; i < paths.length; i += 1000) {
      const batch = paths.slice(i, i + 1000);
      if (!batch.length) continue;

      const { error } = await adminClient.storage
        .from(bucket)
        .remove(batch);

      if (error) {
        // Do not delete the DB row: the operation can be retried.
        return json(
          {
            error: "Suppression des fichiers impossible",
            bucket,
            details: error.message,
            post_id: postId,
            bunny_deleted: deletedBunnyVideos.length,
            bunny_already_absent: alreadyAbsentBunnyVideos.length,
          },
          500,
        );
      }

      deletedStorageFiles += batch.length;
    }
  }

  // Hard-delete only after all external media cleanup succeeded.
  const { error: deleteError } =
    await userClient.rpc("delete_community_post", {
      p_id: postId,
      p_reason: body?.reason ?? null,
    });

  if (deleteError) {
    return json(
      {
        error: "Médias supprimés, mais suppression DB échouée",
        details: deleteError.message,
        post_id: postId,
        bunny_deleted: deletedBunnyVideos.length,
        storage_deleted: deletedStorageFiles,
      },
      500,
    );
  }

  return json({
    success: true,
    post_id: postId,
    deleted: true,
    r2_objects_deleted: deletedR2Objects.length,
    r2_objects_retained_shared: retainedSharedR2Objects.length,
    bunny_videos_deleted: deletedBunnyVideos.length,
    bunny_videos_already_absent: alreadyAbsentBunnyVideos.length,
    storage_files_deleted: deletedStorageFiles,
  });
});
