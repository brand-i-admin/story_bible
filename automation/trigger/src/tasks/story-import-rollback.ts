import { task } from "@trigger.dev/sdk";
import { recordArtifact, updateJobStatus } from "../lib/job-status.js";

export const storyImportRollback = task({
  id: "story-import-rollback",
  run: async (payload: { jobId: string; rollbackToJobId: string; reason?: string }) => {
    await recordArtifact(payload.jobId, "rollback_request", null, {
      rollbackToJobId: payload.rollbackToJobId,
      reason: payload.reason ?? null,
    });

    await updateJobStatus(payload.jobId, "cancelled", {
      rollbackToJobId: payload.rollbackToJobId,
      rollbackReason: payload.reason ?? null,
      rollbackMode: "placeholder",
    });

    return {
      ok: true,
      rollbackToJobId: payload.rollbackToJobId,
    };
  },
});
