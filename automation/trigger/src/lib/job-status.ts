import { admin } from "./supabase.js";

export type ImportJobStatus =
  | "received"
  | "failed_validation"
  | "validated"
  | "under_review"
  | "build_ready"
  | "approved"
  | "promoted"
  | "failed"
  | "cancelled";

export async function updateJobStatus(
  jobId: string,
  status: ImportJobStatus,
  metadataPatch?: Record<string, unknown>,
) {
  const { data: current, error: currentError } = await admin
    .from("import_jobs")
    .select("metadata")
    .eq("id", jobId)
    .single();

  if (currentError) {
    throw currentError;
  }

  const metadata = {
    ...((current?.metadata as Record<string, unknown> | null) ?? {}),
    ...(metadataPatch ?? {}),
  };

  const patch: Record<string, unknown> = {
    status,
    metadata,
  };

  if (status === "validated") {
    patch.validated_at = new Date().toISOString();
  }
  if (status === "approved") {
    patch.approved_at = new Date().toISOString();
  }
  if (status === "promoted") {
    patch.promoted_at = new Date().toISOString();
  }

  const { error } = await admin.from("import_jobs").update(patch).eq("id", jobId);
  if (error) {
    throw error;
  }
}

export async function recordArtifact(
  jobId: string,
  artifactType: string,
  relativePath: string | null,
  payload: Record<string, unknown> = {},
) {
  const { error } = await admin.from("import_job_artifacts").upsert(
    {
      import_job_id: jobId,
      artifact_type: artifactType,
      relative_path: relativePath,
      payload,
    },
    {
      onConflict: "import_job_id,artifact_type,relative_path",
    },
  );

  if (error) {
    throw error;
  }
}
