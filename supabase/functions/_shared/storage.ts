import { getSupabaseAdmin } from "./supabase.ts";

export async function downloadImportJson(storagePath: string): Promise<string> {
  const admin = getSupabaseAdmin();

  const { data, error } = await admin.storage
    .from("import-jobs")
    .download(storagePath);

  if (error) {
    throw new Error(`Failed to download ${storagePath}: ${error.message}`);
  }

  return await data.text();
}

export async function uploadArtifact(
  storagePath: string,
  content: string,
): Promise<void> {
  const admin = getSupabaseAdmin();

  const { error } = await admin.storage
    .from("import-jobs")
    .upload(storagePath, content, {
      contentType: "application/json",
      upsert: true,
    });

  if (error) {
    throw new Error(`Failed to upload ${storagePath}: ${error.message}`);
  }
}
