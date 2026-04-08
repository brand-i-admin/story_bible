import { task } from "@trigger.dev/sdk";
import { recordArtifact, updateJobStatus } from "../lib/job-status.js";
import type { StoryImportPromotePayload } from "../lib/payloads.js";

export const storyImportPromote = task({
  id: "story-import-promote",
  run: async (payload: StoryImportPromotePayload) => {
    if (process.env.ENABLE_STORY_IMPORT_PROMOTE !== "true") {
      await recordArtifact(payload.jobId, "promote_request", null, {
        environment: payload.environment,
        approvedBy: payload.approvedBy ?? null,
        skipped: true,
        reason: "ENABLE_STORY_IMPORT_PROMOTE is not enabled",
      });

      return {
        ok: true,
        skipped: true,
        environment: payload.environment,
      };
    }

    await recordArtifact(payload.jobId, "promote_request", null, {
      environment: payload.environment,
      approvedBy: payload.approvedBy ?? null,
    });

    // TODO: Replace this placeholder with a GitHub Actions workflow dispatch call.
    await updateJobStatus(payload.jobId, "promoted", {
      promotedEnvironment: payload.environment,
      promoteMode: "placeholder",
      approvedBy: payload.approvedBy ?? null,
    });

    return {
      ok: true,
      skipped: false,
      environment: payload.environment,
    };
  },
});
