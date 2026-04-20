import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = string | number | boolean | null | { [key: string]: Json } | Json[];

type IntakeRequest = {
  sourceName: string;
  stories: Json;
  note?: string;
  externalRequester?: {
    name?: string;
    email?: string;
    organization?: string;
  };
  metadata?: Record<string, Json>;
};

type TriggerPayload = {
  jobId: string;
  sourceStoragePath: string;
  requestedByUserId: string | null;
  environment: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const storyImportsBucket = Deno.env.get("STORY_IMPORTS_BUCKET") ?? "import-jobs";
const deploymentEnvironment = Deno.env.get("DEPLOYMENT_ENVIRONMENT") ?? "staging";

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

function jsonResponse(status: number, payload: Record<string, Json>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function normalizeSourceName(value: string) {
  const trimmed = value.trim();
  if (!trimmed) {
    return "story-import.json";
  }
  return trimmed.endsWith(".json") ? trimmed : `${trimmed}.json`;
}

async function sha256Hex(input: string) {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = Array.from(new Uint8Array(digest));
  return bytes.map((value) => value.toString(16).padStart(2, "0")).join("");
}

async function maybeResolveSubmittedByUserId(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }

  const jwt = authHeader.slice("Bearer ".length);
  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    },
    auth: { persistSession: false },
  });

  const { data, error } = await userClient.auth.getUser(jwt);
  if (error) {
    return null;
  }
  return data.user?.id ?? null;
}

async function invokeValidateFunction(payload: {
  jobId: string;
  sourceStoragePath: string;
}) {
  const validateUrl = `${supabaseUrl}/functions/v1/story-import-validate`;

  const response = await fetch(validateUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `Validate function failed: ${response.status} ${detail}`,
    );
  }

  return await response.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, {
      error: "method_not_allowed",
      message: "Use POST for story import intake.",
    });
  }

  let body: IntakeRequest;
  try {
    body = (await req.json()) as IntakeRequest;
  } catch {
    return jsonResponse(400, {
      error: "invalid_json",
      message: "Request body must be valid JSON.",
    });
  }

  if (!body || typeof body !== "object") {
    return jsonResponse(400, {
      error: "invalid_payload",
      message: "Request body must be a JSON object.",
    });
  }

  const sourceName = normalizeSourceName(String(body.sourceName ?? ""));
  const stories = body.stories;
  if (!Array.isArray(stories)) {
    return jsonResponse(400, {
      error: "invalid_stories",
      message: "`stories` must be a JSON array.",
    });
  }

  const rawJson = JSON.stringify(stories, null, 2);
  const sourceSha256 = await sha256Hex(rawJson);
  const submittedByUserId = await maybeResolveSubmittedByUserId(req);

  const metadata = {
    note: body.note ?? null,
    externalRequester: body.externalRequester ?? null,
    requestMetadata: body.metadata ?? {},
    intakeSource: "story-import-intake",
  };

  const { data: insertedJob, error: insertError } = await admin
    .from("import_jobs")
    .insert({
      submitted_by_user_id: submittedByUserId,
      source_name: sourceName,
      source_sha256: sourceSha256,
      status: "received",
      notes: body.note ?? null,
      metadata,
    })
    .select("id")
    .single();

  if (insertError || !insertedJob) {
    return jsonResponse(500, {
      error: "job_insert_failed",
      message: insertError?.message ?? "Failed to create import job.",
    });
  }

  const jobId = insertedJob.id as string;
  const storagePath = `raw/${jobId}/${sourceName}`;

  const upload = await admin.storage
    .from(storyImportsBucket)
    .upload(storagePath, new Blob([rawJson], { type: "application/json" }), {
      contentType: "application/json",
      upsert: false,
    });

  if (upload.error) {
    await admin.from("import_jobs").update({
      status: "failed",
      metadata: { ...metadata, uploadError: upload.error.message },
    }).eq("id", jobId);

    return jsonResponse(500, {
      error: "storage_upload_failed",
      message: upload.error.message,
      jobId,
    });
  }

  await admin.from("import_jobs").update({
    source_storage_key: storagePath,
  }).eq("id", jobId);

  await admin.from("import_job_artifacts").insert({
    import_job_id: jobId,
    artifact_type: "raw_input",
    relative_path: storagePath,
    payload: {
      sourceName,
      sourceSha256,
      storyCount: stories.length,
    },
  });

  // Invoke validate function asynchronously (don't wait for completion)
  invokeValidateFunction({
    jobId,
    sourceStoragePath: storagePath,
  }).catch(async (error) => {
    // Log error and update job status on failure
    console.error("Validation invocation failed:", error);
    await admin.from("import_jobs").update({
      status: "failed",
      metadata: {
        ...metadata,
        validationInvokeError: error instanceof Error
          ? error.message
          : String(error),
      },
    }).eq("id", jobId);
  });

  return jsonResponse(202, {
    ok: true,
    jobId,
    status: "received",
    sourceStoragePath: storagePath,
  });
});
