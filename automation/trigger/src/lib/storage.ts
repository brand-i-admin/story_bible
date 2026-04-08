import { admin, importsBucket } from "./supabase.js";

export async function downloadImportJson(storagePath: string) {
  const { data, error } = await admin.storage.from(importsBucket).download(storagePath);
  if (error) {
    throw error;
  }
  return await data.text();
}

export async function uploadArtifact(
  storagePath: string,
  contents: string,
  contentType = "application/json",
) {
  const { error } = await admin.storage
    .from(importsBucket)
    .upload(storagePath, new Blob([contents], { type: contentType }), {
      upsert: true,
      contentType,
    });

  if (error) {
    throw error;
  }
}
