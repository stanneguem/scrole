import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from "npm:@aws-sdk/client-s3@3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3";

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

const IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/avif": "avif", "image/gif": "gif",
};
const VIDEO_TYPES: Record<string, string> = {
  "video/mp4": "mp4",
  "video/quicktime": "mov",
};
const AUDIO_TYPES: Record<string, string> = {
  "audio/mp4": "m4a", "audio/aac": "aac", "audio/mpeg": "mp3",
  "audio/ogg": "ogg", "audio/wav": "wav", "audio/webm": "webm",
};
const CATEGORIES = new Set([
  "profile_avatar", "profile_cover", "community_avatar", "community_cover",
  "post_media", "story_media", "comment_media", "message_media", "event_media", "bug_report", "salon_avatar", "salon_message_media",
]);

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
  const privateBucket = Deno.env.get("R2_PRIVATE_BUCKET_NAME")?.trim();
  const privateAccessKeyId = Deno.env.get("R2_PRIVATE_ACCESS_KEY_ID")?.trim();
  const privateSecretAccessKey = Deno.env.get("R2_PRIVATE_SECRET_ACCESS_KEY")?.trim();
  const privateEndpoint = Deno.env.get("R2_PRIVATE_ENDPOINT")?.trim() || (accountId ? `https://${accountId}.r2.cloudflarestorage.com` : "");
  const publicBaseUrl = Deno.env.get("R2_PUBLIC_BASE_URL")?.replace(/\/+$/, "");
  if (!supabaseUrl || !anonKey || !serviceKey) return reply(503, { error: "supabase_not_configured" });
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return reply(503, { error: "r2_not_configured", required_secrets: [
      "R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET_NAME", "R2_PUBLIC_BASE_URL",
    ] });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return reply(401, { error: "invalid_session" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (body.action === "delete-failed-post-media") {
    const rawKeys = Array.isArray(body.object_keys) ? body.object_keys : [];
    const communityId = typeof body.community_id === "string" && body.community_id.trim() ? body.community_id.trim() : "";
    const keys = [...new Set(rawKeys.filter((v): v is string => typeof v === "string" && v.trim().length > 0).map(v => v.trim()))];
    if (keys.length === 0 || keys.length > 30) return reply(400, { error: "invalid_object_keys" });

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    if (communityId) {
      const { data: community, error: communityError } = await admin.from("communities").select("creator_id,visibility").eq("id", communityId).maybeSingle();
      if (communityError) return reply(500, { error: "community_check_failed" });
      const { data: membership, error: membershipError } = await admin.from("community_members").select("user_id,role").eq("community_id", communityId).eq("user_id", user.id).maybeSingle();
      if (membershipError) return reply(500, { error: "community_membership_check_failed" });
      if (!community || (community.creator_id !== user.id && !membership)) return reply(403, { error: "post_media_cleanup_denied" });
    }

    const deleted: string[] = [];
    const retained: string[] = [];
    const failed: Array<{ object_key: string; error: string }> = [];
    for (const key of keys) {
      const parts = key.split("/");
      const filename = parts[parts.length - 1] ?? "";
      const validFilename = /^[a-f0-9-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov)$/i.test(filename);
      const userPostKey = !communityId && parts.length === 3 && parts[0] === "posts" && parts[1] === user.id;
      const publicCommunityKey = !!communityId && parts.length === 4 && parts[0] === "communities" && parts[1] === communityId && parts[2] === "posts";
      const privateCommunityKey = !!communityId && parts.length === 6 && parts[0] === "private" && parts[1] === "communities" && parts[2] === communityId && parts[3] === "posts" && parts[4] === user.id;
      if (!validFilename || key.startsWith("/") || key.includes("..") || key.includes(String.fromCharCode(92)) ||
          !(userPostKey || publicCommunityKey || privateCommunityKey)) {
        failed.push({ object_key: key, error: "invalid_or_unauthorized_object_key" });
        continue;
      }
      try {
        const refs = await Promise.all([
          admin.from("community_posts").select("id").filter("media", "cs", JSON.stringify([{ object_key: key }])).limit(1),
          admin.from("community_posts").select("id").filter("media", "cs", JSON.stringify([{ thumbnail_object_key: key }])).limit(1),
        ]);
        if (refs.some(r => r.error)) throw new Error("media_reference_check_failed");
        let referenced = refs.some(r => (r.data ?? []).length > 0);
        const url = publicBaseUrl ? `${publicBaseUrl}/${key.split("/").map(encodeURIComponent).join("/")}` : null;
        if (!referenced && url) {
          const urlRefs = await Promise.all([
            admin.from("community_posts").select("id").filter("media", "cs", JSON.stringify([{ url }])).limit(1),
            admin.from("community_posts").select("id").contains("photos", [url]).limit(1),
            admin.from("community_posts").select("id").eq("photo", url).limit(1),
            admin.from("community_posts").select("id").eq("video_url", url).limit(1),
            admin.from("community_posts").select("id").eq("video_thumbnail_url", url).limit(1),
            admin.from("community_posts").select("id").filter("media", "cs", JSON.stringify([{ thumbnail_url: url }])).limit(1),
          ]);
          if (urlRefs.some(r => r.error)) throw new Error("media_reference_check_failed");
          referenced = urlRefs.some(r => (r.data ?? []).length > 0);
        }
        if (referenced) { retained.push(key); continue; }

        const isPrivate = key.startsWith("private/");
        const targetBucket = isPrivate ? privateBucket : bucket;
        const targetAccessKey = isPrivate ? privateAccessKeyId : accessKeyId;
        const targetSecret = isPrivate ? privateSecretAccessKey : secretAccessKey;
        const targetEndpoint = isPrivate ? privateEndpoint : `https://${accountId}.r2.cloudflarestorage.com`;
        if (!targetBucket || !targetAccessKey || !targetSecret || !targetEndpoint) throw new Error("r2_bucket_not_configured");
        const s3 = new S3Client({ region: "auto", endpoint: targetEndpoint, credentials: { accessKeyId: targetAccessKey, secretAccessKey: targetSecret } });
        await s3.send(new DeleteObjectCommand({ Bucket: targetBucket, Key: key }));
        deleted.push(key);
      } catch (error) {
        failed.push({ object_key: key, error: error instanceof Error ? error.message : String(error) });
      }
    }
    return reply(failed.length ? 502 : 200, { success: failed.length === 0, deleted_count: deleted.length, retained_referenced_count: retained.length, failed });
  }

  if (body.action === "resolve-delete-bug-report") {
    const reportId = typeof body.report_id === "string" ? body.report_id.trim() : "";
    if (!reportId || reportId.length > 80) return reply(400, { error: "invalid_report_id" });

    const { data: permissions, error: permissionError } =
      await userClient.rpc("admin_permissions_for_current_user");
    if (permissionError) return reply(500, { error: "admin_permission_check_failed" });
    const permissionList = Array.isArray(permissions) ? permissions : [];
    const canResolve = permissionList.some((row: { permission?: string }) =>
      ["reports.resolve", "bug_reports.manage"].includes(String(row?.permission ?? ""))
    );
    if (!canResolve) return reply(403, { error: "bug_report_resolution_denied" });

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: report, error: reportError } = await admin
      .from("bug_reports")
      .select("id,user_id,screenshot_object_key")
      .eq("id", reportId)
      .maybeSingle();
    if (reportError) return reply(500, { error: "bug_report_lookup_failed" });
    if (!report) return reply(404, { error: "bug_report_not_found" });

    const objectKey = typeof report.screenshot_object_key === "string"
      ? report.screenshot_object_key.trim()
      : "";
    if (objectKey) {
      const parts = objectKey.split("/");
      const validKey = !!report.user_id &&
        parts.length === 3 &&
        parts[0] === "bug-reports" &&
        parts[1] === report.user_id &&
        /^[a-f0-9-]+\.(jpg|jpeg|png|webp|avif|gif)$/i.test(parts[2]);
      if (!validKey) return reply(409, { error: "bug_report_media_key_invalid" });
      if (!privateBucket || !privateAccessKeyId || !privateSecretAccessKey || !privateEndpoint) {
        return reply(503, { error: "private_media_bucket_not_configured" });
      }
      try {
        const privateS3 = new S3Client({
          region: "auto",
          endpoint: privateEndpoint,
          credentials: { accessKeyId: privateAccessKeyId, secretAccessKey: privateSecretAccessKey },
        });
        await privateS3.send(new DeleteObjectCommand({ Bucket: privateBucket, Key: objectKey }));
      } catch (error) {
        console.error("[r2-media-upload] bug report screenshot deletion failed", {
          reportId, error: error instanceof Error ? error.message : String(error),
        });
        return reply(502, { error: "bug_report_media_delete_failed" });
      }
    }

    const { data: deletedRows, error: deleteError } = await admin
      .from("bug_reports")
      .delete()
      .eq("id", reportId)
      .select("id");
    if (deleteError) return reply(500, {
      error: "bug_report_delete_failed",
      media_deleted: !!objectKey,
    });
    if (!deletedRows || deletedRows.length === 0) return reply(404, {
      error: "bug_report_not_found",
      media_deleted: !!objectKey,
    });
    return reply(200, {
      success: true,
      deleted_report_id: reportId,
      screenshot_deleted: !!objectKey,
    });
  }

  if (body.action === "create-download-url") {
    const key = typeof body.object_key === "string" ? body.object_key.trim() : "";
    if (!key || key.includes("..") || key.startsWith("/") || key.includes("\\\\")) return reply(400, { error: "invalid_object_key" });
    const privatePrefixes = ["private/", "stories/", "messages/", "salon-messages/", "bug-reports/", "comments/"];
    const isPrivate = privatePrefixes.some((prefix) => key.startsWith(prefix));
    if (!isPrivate) {
      const encoded = key.split("/").map(encodeURIComponent).join("/");
      return reply(200, { url: `${publicBaseUrl}/${encoded}`, expires_in: null, is_public: true });
    }
    if (!privateBucket || !privateAccessKeyId || !privateSecretAccessKey || !privateEndpoint) {
      return reply(503, { error: "private_media_bucket_not_configured", required_secrets: [
        "R2_PRIVATE_ACCESS_KEY_ID", "R2_PRIVATE_SECRET_ACCESS_KEY", "R2_PRIVATE_BUCKET_NAME", "R2_PRIVATE_ENDPOINT",
      ] });
    }
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    let allowed = false;
    const parts = key.split("/");
    if (parts[0] === "salon-messages" && parts.length >= 4) {
      const salonId = parts[1];
      const { data: salon } = await admin.from("community_salons").select("id,created_by").eq("id", salonId).maybeSingle();
      const { data: member } = await admin.from("community_salon_members").select("user_id").eq("salon_id", salonId).eq("user_id", user.id).maybeSingle();
      allowed = !!salon && (salon.created_by === user.id || !!member);
    } else if (parts[0] === "messages" && parts.length >= 3) {
      const conversationId = parts[1];
      const { data } = await admin.from("direct_conversations").select("user_one_id,user_two_id").eq("id", conversationId).maybeSingle();
      allowed = !!data && (data.user_one_id === user.id || data.user_two_id === user.id);
    } else if (parts[0] === "private" && parts[1] === "communities" && parts.length >= 6) {
      const communityId = parts[2];
      const { data: member } = await admin.from("community_members").select("user_id").eq("community_id", communityId).eq("user_id", user.id).maybeSingle();
      allowed = !!member;
    } else if (parts[0] === "stories" && parts.length >= 3) {
      const { data: story } = await admin.from("stories").select("id,author_id,audience,status,expires_at,image_url").eq("image_url", key).maybeSingle();
      if (story && story.status === "active" && (!story.expires_at || new Date(story.expires_at).getTime() > Date.now())) {
        if (story.author_id === user.id) allowed = true;
        else {
          const { data: mutual } = await admin.from("friendships").select("user_a_id")
            .or(`and(user_a_id.eq.${user.id},user_b_id.eq.${story.author_id}),and(user_a_id.eq.${story.author_id},user_b_id.eq.${user.id})`).maybeSingle();
          const { data: follow } = await admin.from("user_follows").select("follower_id")
            .eq("follower_id", user.id).eq("followed_id", story.author_id).maybeSingle();
          allowed = !!mutual || !!follow;
        }
      }
    } else if (parts[0] === "bug-reports" && parts.length === 3) {
      // Screenshots are private. The reporter may access their own object;
      // authorized Scrole admins may access them from the bug-report queue.
      allowed = parts[1] === user.id;
      if (!allowed) {
        const { data: permissions, error: permissionError } = await userClient.rpc("admin_permissions_for_current_user");
        if (permissionError) return reply(500, { error: "admin_permission_check_failed" });
        allowed = Array.isArray(permissions) && permissions.some((row: { permission?: string }) =>
          ["reports.view", "bug_reports.view"].includes(String(row?.permission ?? ""))
        );
      }
    }
    if (!allowed) return reply(403, { error: "media_access_denied" });
    const privateS3 = new S3Client({ region: "auto", endpoint: privateEndpoint, credentials: { accessKeyId: privateAccessKeyId, secretAccessKey: privateSecretAccessKey } });
    const url = await getSignedUrl(privateS3, new GetObjectCommand({ Bucket: privateBucket, Key: key }), { expiresIn: 120 });
    return reply(200, { url, expires_in: 120, is_public: false });
  }
  if (body.action === "delete-owned-media" || body.action === "delete-profile-avatar") {
    const objectKey = typeof body.object_key === "string" ? body.object_key.trim() : "";
    const parts = objectKey.split("/");
    if (!objectKey || objectKey.startsWith("/") || objectKey.includes("..") || objectKey.includes(String.fromCharCode(92)) ||
        parts.length !== 4 || !/^[a-f0-9-]+\.(jpg|jpeg|png|webp|avif|gif)$/i.test(parts[3])) {
      return reply(400, { error: "invalid_media_object_key" });
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    let authorized = false;
    let referencedUrl: string | null = null;
    if (parts[0] === "profiles" && parts[1] === user.id && ["avatar", "cover"].includes(parts[2])) {
      const { data: profile, error } = await admin.from("user_profiles")
        .select("account_status,deleted_at,photo_url,cover_url").eq("user_id", user.id).maybeSingle();
      if (error) return reply(500, { error: "profile_check_failed" });
      if (!profile || profile.account_status !== "active" || profile.deleted_at !== null) return reply(403, { error: "account_unavailable" });
      referencedUrl = parts[2] === "avatar" ? profile.photo_url : profile.cover_url;
      authorized = true;
    } else if (parts[0] === "communities" && ["avatar", "cover"].includes(parts[2])) {
      const communityId = parts[1];
      const { data: community, error } = await admin.from("communities")
        .select("creator_id,photo_profile,photo_cover").eq("id", communityId).maybeSingle();
      if (error) return reply(500, { error: "community_check_failed" });
      const { data: membership, error: membershipError } = await admin.from("community_members")
        .select("role").eq("community_id", communityId).eq("user_id", user.id).maybeSingle();
      if (membershipError) return reply(500, { error: "community_membership_check_failed" });
      if (!community || (community.creator_id !== user.id &&
          !["owner", "admin", "moderator"].includes(String(membership?.role ?? "").toLowerCase()))) {
        return reply(403, { error: "community_manager_required" });
      }
      referencedUrl = parts[2] === "avatar" ? community.photo_profile : community.photo_cover;
      authorized = true;
    } else if (parts[0] === "events" && parts.length === 4 && parts[2] === user.id) {
      const eventId = parts[1];
      const { data: event, error } = await admin.from("events")
        .select("creator_id,photo").eq("id", eventId).maybeSingle();
      if (error) return reply(500, { error: "event_check_failed" });
      if (!event || event.creator_id !== user.id) return reply(403, { error: "event_owner_required" });
      referencedUrl = event.photo;
      authorized = true;
    }
    if (!authorized) return reply(403, { error: "media_object_not_owned" });

    if (typeof referencedUrl === "string" && referencedUrl.trim()) {
      try {
        const referenced = new URL(referencedUrl.trim());
        const pathParts = referenced.pathname.split("/").filter(Boolean).map((part) => decodeURIComponent(part));
        const stillReferenced = pathParts.some((part, index) =>
          (part === "profiles" || part === "communities" || part === "events") &&
          pathParts.slice(index).join("/") === objectKey
        );
        if (stillReferenced) return reply(409, { error: "media_still_referenced" });
      } catch { /* Malformed or legacy URL cannot point to this canonical R2 key. */ }
    }
    try {
      const s3 = new S3Client({ region: "auto", endpoint: `https://${accountId}.r2.cloudflarestorage.com`, credentials: { accessKeyId, secretAccessKey } });
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
      return reply(200, { deleted: true, object_key: objectKey });
    } catch (error) {
      console.error("[r2-media-upload] owned media delete failed", { objectKey, error });
      return reply(500, { error: "media_delete_failed" });
    }
  }
  if (body.action !== "create-upload-url") return reply(400, { error: "unsupported_action" });

  const category = String(body.category ?? (body.media_type === "video" ? "post_media" : ""));
  if (!CATEGORIES.has(category)) return reply(400, { error: "unsupported_category" });
  const mediaType = String(body.media_type ?? "");
  const contentType = String(body.content_type ?? "").toLowerCase().split(";")[0].trim();
  const sizeBytes = Number(body.size_bytes);
  const extension = String(body.extension ?? "").toLowerCase().replace(/^\./, "");
  const entityId = typeof body.entity_id === "string" && body.entity_id.trim() ? body.entity_id.trim() : null;
  const isVideo = mediaType === "video";
  const isAudio = mediaType === "audio";
  const expectedExtension = (isVideo ? VIDEO_TYPES : isAudio ? AUDIO_TYPES : IMAGE_TYPES)[contentType];

  if (!expectedExtension || extension !== expectedExtension) {
    return reply(415, { error: "unsupported_media_format", allowed_image_types: Object.keys(IMAGE_TYPES), allowed_video_types: Object.keys(VIDEO_TYPES) });
  }
  if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0) return reply(400, { error: "invalid_size" });
  const maxBytes = isVideo ? 100 * 1024 * 1024 : isAudio ? 25 * 1024 * 1024 : 15 * 1024 * 1024;
  if (sizeBytes > maxBytes) return reply(413, { error: "media_size_limit_exceeded", maximum_bytes: maxBytes });
  const duration = Number(body.duration_seconds);
  if (isVideo && Number.isFinite(duration) && duration > 30) {
    return reply(400, { error: "video_duration_limit_exceeded", maximum_seconds: 30 });
  }

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: profile, error: profileError } = await admin
    .from("user_profiles").select("account_status, deleted_at").eq("user_id", user.id).maybeSingle();
  if (profileError) return reply(500, { error: "profile_check_failed" });
  if (!profile || profile.account_status !== "active" || profile.deleted_at !== null) return reply(403, { error: "account_unavailable" });

  // Validate category-specific authorization before signing an upload.
  if (category === "profile_avatar" || category === "profile_cover") {
    if (entityId && entityId !== user.id) return reply(403, { error: "profile_owner_required" });
  } else if (category === "community_avatar" || category === "community_cover") {
    if (!entityId) return reply(400, { error: "community_id_required" });
    const { data: community } = await admin.from("communities").select("creator_id").eq("id", entityId).maybeSingle();
    const { data: membership } = await admin.from("community_members").select("role").eq("community_id", entityId).eq("user_id", user.id).maybeSingle();
    if (!community || (community.creator_id !== user.id && !["owner","admin","moderator"].includes(String(membership?.role ?? "").toLowerCase()))) return reply(403, { error: "community_manager_required" });
  } else if (category === "salon_message_media") {
    if (!entityId) return reply(400, { error: "salon_id_required" });
    const { data: salon, error: salonError } = await admin
      .from("community_salons").select("id,created_by").eq("id", entityId).maybeSingle();
    if (salonError) return reply(500, { error: "salon_check_failed" });
    if (!salon) return reply(404, { error: "salon_not_found" });
    const { data: membership, error: memberError } = await admin
      .from("community_salon_members").select("user_id").eq("salon_id", entityId).eq("user_id", user.id).maybeSingle();
    if (memberError) return reply(500, { error: "salon_membership_check_failed" });
    if (salon.created_by !== user.id && !membership) return reply(403, { error: "salon_membership_required" });
    if (!privateBucket) return reply(503, { error: "private_media_bucket_not_configured" });
  } else if (category === "salon_avatar") {
    if (!entityId) return reply(400, { error: "salon_id_required" });
    const { data: salon, error: salonError } = await admin
      .from("community_salons").select("id,community_id,created_by").eq("id", entityId).maybeSingle();
    if (salonError) return reply(500, { error: "salon_check_failed" });
    if (!salon) return reply(404, { error: "salon_not_found" });
    let canManage = salon.created_by === user.id;
    if (!canManage) {
      const { data: allowed, error: permissionError } = await userClient.rpc("community_can", {
        p_community_id: salon.community_id,
        p_permission: "can_create_salon",
      });
      if (permissionError) return reply(500, { error: "salon_permission_check_failed" });
      canManage = allowed === true;
    }
    if (!canManage) return reply(403, { error: "salon_manager_required" });
  } else if (category === "event_media") {
    if (!entityId) return reply(400, { error: "event_id_required" });
    const { data: event } = await admin.from("events").select("creator_id").eq("id", entityId).maybeSingle();
    if (!event || event.creator_id !== user.id) return reply(403, { error: "event_owner_required" });
  } else if (category === "message_media") {
    if (!entityId) return reply(400, { error: "conversation_id_required" });
    const { data: conversation } = await admin.from("direct_conversations").select("user_one_id,user_two_id").eq("id", entityId).maybeSingle();
    if (!conversation || (conversation.user_one_id !== user.id && conversation.user_two_id !== user.id)) return reply(403, { error: "conversation_participant_required" });
    if (!privateBucket) return reply(503, { error: "private_media_bucket_not_configured" });
  } else if (category === "story_media") {
    // Story media is uploaded before its database row is created.
    if (!privateBucket) return reply(503, { error: "private_media_bucket_not_configured" });
  } else if (category === "comment_media") {
    return reply(501, { error: "comment_parent_context_required" });
  } else if (category === "bug_report") {
    // Diagnostic media is private to its uploader/support workflow.
    if (!privateBucket) return reply(503, { error: "private_media_bucket_not_configured" });
  } else if (category === "post_media") {
    if (typeof body.community_id === "string" && body.community_id.trim()) {
      const communityId = body.community_id.trim();
      const { data: community } = await admin.from("communities").select("visibility").eq("id", communityId).maybeSingle();
      if (!community) return reply(404, { error: "community_not_found" });
      if (String(community.visibility ?? "").toLowerCase() !== "public") {
        const { data: member } = await userClient.rpc("is_community_member", { p_community_id: communityId });
        if (member !== true) return reply(403, { error: "community_membership_required" });
        if (!privateBucket) return reply(503, { error: "private_media_bucket_not_configured" });
      }
    }
  } else {
    // Community/event/message authorization depends on schema-specific ownership,
    // moderator and privacy rules. Fail closed until those checks are implemented.
    return reply(501, { error: "category_authorization_not_implemented", category });
  }

  const uploadId = crypto.randomUUID();
  let key: string;
  switch (category) {
    case "profile_avatar": key = `profiles/${user.id}/avatar/${uploadId}.${expectedExtension}`; break;
    case "profile_cover": key = `profiles/${user.id}/cover/${uploadId}.${expectedExtension}`; break;
    case "bug_report": key = `bug-reports/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "post_media": {
      const communityId = typeof body.community_id === "string" ? body.community_id.trim() : "";
      const isVideoThumbnail = body.media_role === "video_thumbnail";
      if (body.media_role != null && !isVideoThumbnail) {
        return reply(400, { error: "unsupported_media_role" });
      }
      if (isVideoThumbnail && (isVideo || !contentType.startsWith("image/"))) {
        return reply(400, { error: "invalid_video_thumbnail_format" });
      }
      let privateCommunity = false;
      if (communityId) {
        const { data: community } = await admin.from("communities").select("visibility").eq("id", communityId).maybeSingle();
        privateCommunity = String(community?.visibility ?? "").toLowerCase() !== "public";
      }
      key = isVideoThumbnail
        ? privateCommunity
          ? `private/communities/${communityId}/posts/thumbnails/${user.id}/${uploadId}.${expectedExtension}`
          : communityId
            ? `communities/${communityId}/posts/thumbnails/${uploadId}.${expectedExtension}`
            : `thumbnails/posts/${user.id}/${uploadId}.${expectedExtension}`
        : privateCommunity
          ? `private/communities/${communityId}/posts/${user.id}/${uploadId}.${expectedExtension}`
          : communityId
            ? `communities/${communityId}/posts/${uploadId}.${expectedExtension}`
            : `posts/${user.id}/${uploadId}.${expectedExtension}`;
      break;
    }
    case "community_avatar": key = `communities/${entityId}/avatar/${uploadId}.${expectedExtension}`; break;
    case "community_cover": key = `communities/${entityId}/cover/${uploadId}.${expectedExtension}`; break;
    case "salon_avatar": key = `salons/${entityId}/avatar/${uploadId}.${expectedExtension}`; break;
    case "salon_message_media": key = `salon-messages/${entityId}/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "event_media": key = `events/${entityId}/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "message_media": key = `messages/${entityId}/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "story_media": key = `stories/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "bug_report": key = `bug-reports/${user.id}/${uploadId}.${expectedExtension}`; break;
    default: return reply(501, { error: "category_authorization_not_implemented", category });
  }

  try {
    // Keep the signed request minimal. Content-Type is sent by Flutter and must
    // match this value; omit ContentLength to avoid signing a transport header
    // that HTTP clients/proxies may normalize differently.
    const isPrivateObject = key.startsWith("private/") || key.startsWith("messages/") || key.startsWith("salon-messages/") || key.startsWith("stories/") || key.startsWith("bug-reports/");
    const targetBucket = isPrivateObject ? privateBucket : bucket;
    if (!targetBucket) return reply(503, { error: "private_media_bucket_not_configured" });
    if (isPrivateObject && (!privateAccessKeyId || !privateSecretAccessKey || !privateEndpoint)) {
      return reply(503, { error: "private_media_bucket_not_configured", required_secrets: [
        "R2_PRIVATE_ACCESS_KEY_ID", "R2_PRIVATE_SECRET_ACCESS_KEY", "R2_PRIVATE_BUCKET_NAME", "R2_PRIVATE_ENDPOINT",
      ] });
    }
    // Report the actual target selected without logging credentials or signed URLs.
    console.info("[r2-media-upload] signing upload", {
      storage: isPrivateObject ? "private" : "public",
      targetBucket,
      endpointType: isPrivateObject ? "private_endpoint" : "account_endpoint",
      category,
      objectPrefix: key.split("/").slice(0, 2).join("/") + "/",
      contentType,
      sizeBytes,
      privateCredentialsSelected: isPrivateObject,
    });
    const s3 = new S3Client({
      region: "auto",
      endpoint: isPrivateObject ? privateEndpoint : `https://${accountId}.r2.cloudflarestorage.com`,
      credentials: isPrivateObject
        ? { accessKeyId: privateAccessKeyId!, secretAccessKey: privateSecretAccessKey! }
        : { accessKeyId, secretAccessKey },
    });
    const command = new PutObjectCommand({
      Bucket: targetBucket,
      Key: key,
      ContentType: contentType,
    });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
    const encodedKey = key.split("/").map(encodeURIComponent).join("/");
    return reply(200, {
      upload_url: uploadUrl, object_key: key, ...(isPrivateObject ? {} : { public_url: `${publicBaseUrl}/${encodedKey}` }),
      is_public: !isPrivateObject, content_type: contentType, size_bytes: sizeBytes, expires_in: 300, max_video_duration_seconds: 30,
    });
  } catch (error) {
    console.error("[r2-media-upload] signed URL generation failed", error);
    return reply(500, { error: "upload_authorization_failed" });
  }
});
