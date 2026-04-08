import { task, wait } from "@trigger.dev/sdk";
import { recordArtifact, updateJobStatus } from "../lib/job-status.js";
import type { StoryImportApprovalOutput, StoryImportReviewPayload } from "../lib/payloads.js";

export const storyImportAwaitApproval = task({
  id: "story-import-await-approval",
  run: async (payload: StoryImportReviewPayload) => {
    await updateJobStatus(payload.jobId, "under_review");

    const approvalToken = await wait.createToken({
      timeout: "7d",
      idempotencyKey: `story-import-approval-${payload.jobId}`,
      tags: ["story-import", payload.jobId],
    });

    await recordArtifact(payload.jobId, "approval_token", null, {
      tokenId: approvalToken.id,
      tokenUrl: approvalToken.url,
      publicAccessToken: approvalToken.publicAccessToken,
    });

    const approval = await wait.forToken<StoryImportApprovalOutput>(approvalToken.id).unwrap();
    return approval;
  },
});
