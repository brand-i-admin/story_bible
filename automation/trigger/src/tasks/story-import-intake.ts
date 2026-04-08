import { task } from "@trigger.dev/sdk";
import { updateJobStatus } from "../lib/job-status.js";
import type { StoryImportJobPayload } from "../lib/payloads.js";
import { storyImportAwaitApproval } from "./story-import-await-approval.js";
import { storyImportBuildBundle } from "./story-import-build-bundle.js";
import { storyImportGenerateMedia } from "./story-import-generate-media.js";
import { storyImportNotifyFailure, storyImportNotifyReview } from "./story-import-notify-review.js";
import { storyImportPromote } from "./story-import-promote.js";
import { storyImportValidate } from "./story-import-validate.js";

export const storyImportIntakeReceived = task({
  id: "story-import-intake-received",
  run: async (payload: StoryImportJobPayload) => {
    try {
      await storyImportValidate.triggerAndWait(payload).unwrap();

      const buildResult = await storyImportBuildBundle.triggerAndWait(payload).unwrap();
      if (buildResult.buildStatus !== "build_ready") {
        return {
          ok: true,
          haltedAt: buildResult.buildStatus,
        };
      }

      const reviewResult = await storyImportNotifyReview
        .triggerAndWait({
          ...payload,
        })
        .unwrap();

      const approval = await storyImportAwaitApproval
        .triggerAndWait({
          ...payload,
          reviewUrl: reviewResult.reviewUrl,
        })
        .unwrap();

      if (approval.status !== "approved") {
        await updateJobStatus(payload.jobId, "cancelled", {
          rejectedBy: approval.reviewer ?? null,
          rejectionNote: approval.note ?? null,
        });
        return {
          ok: true,
          haltedAt: "rejected",
        };
      }

      await updateJobStatus(payload.jobId, "approved", {
        approvedBy: approval.reviewer ?? null,
        approvalNote: approval.note ?? null,
      });

      const mediaResult = await storyImportGenerateMedia.triggerAndWait(payload).unwrap();
      const promoteResult = await storyImportPromote
        .triggerAndWait({
          jobId: payload.jobId,
          environment: payload.environment,
          approvedBy: approval.reviewer,
        })
        .unwrap();

      return {
        ok: true,
        approved: true,
        mediaSkipped: Boolean(mediaResult.skipped),
        promoteSkipped: Boolean(promoteResult.skipped),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await updateJobStatus(payload.jobId, "failed", {
        pipelineError: message,
      });
      await storyImportNotifyFailure.trigger({
        jobId: payload.jobId,
        errorMessage: message,
      });
      throw error;
    }
  },
});
