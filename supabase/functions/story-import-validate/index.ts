import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { downloadImportJson } from "../_shared/storage.ts";
import { recordArtifact, updateJobStatus } from "../_shared/job-status.ts";

interface ValidatePayload {
  jobId: string;
  sourceStoragePath: string;
}

function validateStoriesJson(rawJson: string): number {
  const payload = JSON.parse(rawJson) as unknown;
  if (!Array.isArray(payload)) {
    throw new Error("stories payload must be a JSON array");
  }

  const seenCodes = new Set<string>();
  for (const [index, row] of payload.entries()) {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw new Error(`row ${index + 1}: each story must be an object`);
    }

    const code = String((row as Record<string, unknown>).code ?? "").trim();
    if (code) {
      if (seenCodes.has(code)) {
        throw new Error(`row ${index + 1}: duplicate code ${code}`);
      }
      seenCodes.add(code);
    }
  }

  return payload.length;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload: ValidatePayload = await req.json();

    const rawJson = await downloadImportJson(payload.sourceStoragePath);
    const storyCount = validateStoriesJson(rawJson);

    await recordArtifact(
      payload.jobId,
      "raw_validation",
      payload.sourceStoragePath,
      { storyCount },
    );
    await updateJobStatus(payload.jobId, "validated", {
      validatedStoryCount: storyCount,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        storyCount,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    // Try to update job status if we have jobId
    try {
      const payload: Partial<ValidatePayload> = await req.clone().json();
      if (payload.jobId) {
        await updateJobStatus(payload.jobId, "failed_validation", {
          validationError: message,
        });
      }
    } catch {
      // Ignore errors in error handler
    }

    return new Response(
      JSON.stringify({
        ok: false,
        error: message,
      }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
