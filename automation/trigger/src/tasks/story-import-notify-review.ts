import { task } from "@trigger.dev/sdk";
import { notifyFailureChannel, notifyImportChannel } from "../lib/discord.js";
import type { StoryImportReviewPayload } from "../lib/payloads.js";

export const storyImportNotifyReview = task({
  id: "story-import-notify-review",
  run: async (payload: StoryImportReviewPayload) => {
    const reviewUrl =
      payload.reviewUrl ??
      `${process.env.STORY_IMPORT_REVIEW_BASE_URL ?? ""}/${payload.jobId}`;

    await notifyImportChannel(
      [
        "[story-import] build_ready",
        `job: ${payload.jobId}`,
        `environment: ${payload.environment}`,
        `review: ${reviewUrl}`,
      ].join("\n"),
    );

    return {
      ok: true,
      reviewUrl,
    };
  },
});

export const storyImportNotifyFailure = task({
  id: "story-import-notify-failure",
  run: async (payload: { jobId: string; errorMessage: string }) => {
    await notifyFailureChannel(
      [`[story-import] failed`, `job: ${payload.jobId}`, `error: ${payload.errorMessage}`].join(
        "\n",
      ),
    );
    return { ok: true };
  },
});
