import { task } from "@trigger.dev/sdk";
import { repoScript, runPythonScript } from "../lib/python.js";
import { recordArtifact } from "../lib/job-status.js";
import type { StoryImportJobPayload } from "../lib/payloads.js";

export const storyImportGenerateMedia = task({
  id: "story-import-generate-media",
  run: async (payload: StoryImportJobPayload) => {
    if (process.env.ENABLE_STORY_IMPORT_MEDIA_TASKS !== "true") {
      await recordArtifact(payload.jobId, "generated_media_merge_sql", null, {
        skipped: true,
        reason: "ENABLE_STORY_IMPORT_MEDIA_TASKS is not enabled",
      });

      return {
        ok: true,
        skipped: true,
      };
    }

    await runPythonScript([repoScript("generate_event_story_images_vertex.py")]);
    await runPythonScript([repoScript("generate_runtime_thumbnails.py")]);
    await runPythonScript([repoScript("build_generated_media_merge_sql.py")]);

    await recordArtifact(payload.jobId, "generated_media_merge_sql", "supabase/generated_media/generated_media_merge.sql", {
      generatedBy: "story-import-generate-media",
    });

    return {
      ok: true,
      skipped: false,
    };
  },
});
