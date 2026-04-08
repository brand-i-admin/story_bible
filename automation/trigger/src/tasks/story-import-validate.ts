import { task } from "@trigger.dev/sdk";
import { downloadImportJson } from "../lib/storage.js";
import { recordArtifact, updateJobStatus } from "../lib/job-status.js";
import type { StoryImportJobPayload } from "../lib/payloads.js";

function validateStoriesJson(rawJson: string) {
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

export const storyImportValidate = task({
  id: "story-import-validate",
  run: async (payload: StoryImportJobPayload) => {
    try {
      const rawJson = await downloadImportJson(payload.sourceStoragePath);
      const storyCount = validateStoriesJson(rawJson);

      await recordArtifact(payload.jobId, "raw_validation", payload.sourceStoragePath, {
        storyCount,
      });
      await updateJobStatus(payload.jobId, "validated", {
        validatedStoryCount: storyCount,
      });

      return {
        ok: true,
        storyCount,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await updateJobStatus(payload.jobId, "failed_validation", {
        validationError: message,
      });
      throw error;
    }
  },
});
