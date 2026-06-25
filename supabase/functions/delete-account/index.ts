// Supabase Edge Function: delete-account
//
// A signed-in user calls this from the Flutter app to delete their own account.
// The client must send the account confirmation id shown in the app. The
// function verifies the caller JWT, deletes user-owned Storage files, then uses
// the service role key to delete auth.users. Public DB rows that reference the
// user are removed by `on delete cascade` constraints.
//
// Request:  { confirmationId: string }
// Response: { ok: true, deleted_storage_objects: number }

import { createClient } from "npm:@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";

const USER_OWNED_BUCKETS = [
  "profile-images",
  "proposal-scenes",
  "proposal-characters",
  "proposal-general-images",
];
const PUBLISHED_REFERENCE_BUCKETS = new Set([
  "proposal-scenes",
  "proposal-characters",
]);

interface RequestBody {
  confirmationId?: string;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function err(message: string, status = 500): Response {
  console.error(`[delete-account] ${message}`);
  return json({ error: message }, status);
}

function normalize(value: string): string {
  return value.trim().toLowerCase();
}

function addCandidate(set: Set<string>, value: unknown) {
  if (typeof value !== "string") return;
  const normalized = normalize(value);
  if (normalized.length > 0) set.add(normalized);
}

function isStorageFolder(entry: Record<string, unknown>): boolean {
  const id = entry["id"];
  const metadata = entry["metadata"];
  return (id == null || id === "") && metadata == null;
}

function addPublishedReference(
  refs: Set<string>,
  value: unknown,
  userId: string,
) {
  if (typeof value !== "string") return;
  const storagePath = value.trim();
  if (storagePath.length === 0) return;
  for (const bucket of PUBLISHED_REFERENCE_BUCKETS) {
    if (storagePath.startsWith(`${bucket}/${userId}/`)) {
      refs.add(storagePath);
      return;
    }
  }
}

async function loadPublishedStorageReferences(
  admin: any,
  userId: string,
): Promise<Set<string>> {
  const refs = new Set<string>();

  const { data: eventRows, error: eventErr } = await admin
    .from("events")
    .select("scene_image_paths");
  if (eventErr) {
    throw new Error(`events reference lookup failed: ${eventErr.message}`);
  }
  for (
    const row of (eventRows ?? []) as unknown as Array<
      Record<string, unknown>
    >
  ) {
    const paths = row["scene_image_paths"];
    if (!Array.isArray(paths)) continue;
    for (const path of paths) {
      addPublishedReference(refs, path, userId);
    }
  }

  const { data: characterRows, error: characterErr } = await admin
    .from("characters")
    .select("avatar_storage_path");
  if (characterErr) {
    throw new Error(
      `characters reference lookup failed: ${characterErr.message}`,
    );
  }
  for (
    const row of (characterRows ?? []) as unknown as Array<
      Record<string, unknown>
    >
  ) {
    addPublishedReference(refs, row["avatar_storage_path"], userId);
  }

  return refs;
}

async function listStorageFiles(
  admin: any,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const files: string[] = [];
  const pageSize = 1000;
  let offset = 0;

  while (true) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, {
      limit: pageSize,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) {
      throw new Error(`${bucket} list failed: ${error.message}`);
    }
    const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
    for (const row of rows) {
      const name = row["name"];
      if (typeof name !== "string" || name.length === 0) continue;
      const path = prefix ? `${prefix}/${name}` : name;
      if (isStorageFolder(row)) {
        files.push(...(await listStorageFiles(admin, bucket, path)));
      } else {
        files.push(path);
      }
    }
    if (rows.length < pageSize) break;
    offset += pageSize;
  }

  return files;
}

async function removeStorageFiles(
  admin: any,
  bucket: string,
  paths: string[],
): Promise<number> {
  let removed = 0;
  for (let i = 0; i < paths.length; i += 100) {
    const chunk = paths.slice(i, i + 100);
    const { error } = await admin.storage.from(bucket).remove(chunk);
    if (error) {
      throw new Error(`${bucket} remove failed: ${error.message}`);
    }
    removed += chunk.length;
  }
  return removed;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return err("method not allowed", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return err("missing Supabase env", 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return err("unauthorized", 401);
  }

  let input: RequestBody;
  try {
    input = (await req.json()) as RequestBody;
  } catch (_) {
    return err("invalid JSON body", 400);
  }

  const typedConfirmation = normalize(input.confirmationId ?? "");
  if (typedConfirmation.length === 0) {
    return err("confirmationId is required", 400);
  }

  const { data: profile, error: profileErr } = await admin
    .from("user_profiles")
    .select("share_id,nickname")
    .eq("user_id", user.id)
    .maybeSingle();
  if (profileErr) {
    return err(`profile lookup failed: ${profileErr.message}`, 500);
  }

  const accepted = new Set<string>();
  addCandidate(accepted, user.email);
  addCandidate(accepted, profile?.["share_id"]);
  addCandidate(accepted, user.id);
  if (!accepted.has(typedConfirmation)) {
    return err("confirmationId does not match this account", 400);
  }

  let publishedStorageObjects = 0;
  let protectedStoragePaths: Set<string>;
  try {
    protectedStoragePaths = await loadPublishedStorageReferences(
      admin,
      user.id,
    );
  } catch (e) {
    return err(
      `published reference lookup failed: ${
        e instanceof Error ? e.message : String(e)
      }`,
      500,
    );
  }

  let deletedStorageObjects = 0;
  try {
    for (const bucket of USER_OWNED_BUCKETS) {
      const files = await listStorageFiles(admin, bucket, user.id);
      if (files.length === 0) continue;
      const removableFiles = files.filter((path) => {
        const storagePath = `${bucket}/${path}`;
        const shouldPreserve = protectedStoragePaths.has(storagePath);
        if (shouldPreserve) publishedStorageObjects += 1;
        return !shouldPreserve;
      });
      if (removableFiles.length === 0) continue;
      deletedStorageObjects += await removeStorageFiles(
        admin,
        bucket,
        removableFiles,
      );
    }
  } catch (e) {
    return err(
      `storage cleanup failed: ${e instanceof Error ? e.message : String(e)}`,
      500,
    );
  }

  const { error: deleteErr } = await admin.auth.admin.deleteUser(user.id);
  if (deleteErr) {
    return err(`auth user delete failed: ${deleteErr.message}`, 500);
  }

  return json({
    ok: true,
    deleted_storage_objects: deletedStorageObjects,
    preserved_published_storage_objects: publishedStorageObjects,
  });
});
