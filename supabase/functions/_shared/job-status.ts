import { getSupabaseAdmin } from "./supabase.ts";

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

// Valid state transitions for import jobs
const VALID_TRANSITIONS: Record<ImportJobStatus, ImportJobStatus[]> = {
  received: ["failed_validation", "validated", "cancelled"],
  failed_validation: ["received", "cancelled"],
  validated: ["build_ready", "failed", "cancelled"],
  build_ready: ["under_review", "failed", "cancelled"],
  under_review: ["approved", "cancelled", "failed"],
  approved: ["promoted", "failed", "cancelled"],
  promoted: [],
  failed: ["received"],
  cancelled: [],
};

export async function updateJobStatus(
  jobId: string,
  status: ImportJobStatus,
  metadataPatch?: Record<string, unknown>,
) {
  const admin = getSupabaseAdmin();

  const { data: current, error: currentError } = await admin
    .from("import_jobs")
    .select("status, metadata")
    .eq("id", jobId)
    .single();

  if (currentError) {
    throw currentError;
  }

  // Validate state transition
  const currentStatus = current.status as ImportJobStatus;
  const allowedNext = VALID_TRANSITIONS[currentStatus];

  if (!allowedNext.includes(status)) {
    throw new Error(
      `Invalid status transition: ${currentStatus} → ${status}. ` +
        `Allowed: ${allowedNext.join(", ") || "none (terminal state)"}`,
    );
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
  const admin = getSupabaseAdmin();

  const { error } = await admin.from("import_job_artifacts").upsert(
    {
      import_job_id: jobId,
      artifact_type: artifactType,
      relative_path: relativePath ?? "",
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
