import fs from "node:fs/promises";
import path from "node:path";
import { task } from "@trigger.dev/sdk";
import { createJobWorkspace, repoScript, runPythonScript, writeTempJson } from "../lib/python.js";
import { repoPath } from "../lib/paths.js";
import { downloadImportJson, uploadArtifact } from "../lib/storage.js";
import { recordArtifact, updateJobStatus } from "../lib/job-status.js";
import type { StoryImportJobPayload } from "../lib/payloads.js";

async function maybeUploadBuildArtifact(jobId: string, localPath: string, artifactType: string) {
  try {
    const contents = await fs.readFile(localPath, "utf-8");
    const storagePath = `build/${jobId}/${path.basename(localPath)}`;
    await uploadArtifact(storagePath, contents);
    await recordArtifact(jobId, artifactType, storagePath, { source: "prepare_story_import_job.py" });
    return storagePath;
  } catch {
    return null;
  }
}

export const storyImportBuildBundle = task({
  id: "story-import-build-bundle",
  run: async (payload: StoryImportJobPayload) => {
    const workspaceDir = await createJobWorkspace(payload.jobId);
    const rawJson = await downloadImportJson(payload.sourceStoragePath);
    const inputJsonPath = await writeTempJson(workspaceDir, "input.json", rawJson);

    await runPythonScript([
      repoScript("prepare_story_import_job.py"),
      "--input-json",
      inputJsonPath,
      "--user-id",
      payload.requestedByUserId ?? "external-requester",
      "--job-id",
      payload.jobId,
      "--job-root",
      repoPath(".omx", "import_jobs"),
    ]);

    const jobDir = repoPath(".omx", "import_jobs", payload.jobId);
    const jobJsonPath = path.join(jobDir, "job.json");
    const diffSummaryPath = path.join(jobDir, "review", "diff_summary.json");
    const normalizedPath = path.join(jobDir, "build", "200_stories_normalized.json");
    const seedSqlPath = path.join(jobDir, "build", "200_stories_seed.sql");

    const [jobJsonStoragePath, diffStoragePath, normalizedStoragePath, seedSqlStoragePath] =
      await Promise.all([
        maybeUploadBuildArtifact(payload.jobId, jobJsonPath, "job_metadata"),
        maybeUploadBuildArtifact(payload.jobId, diffSummaryPath, "diff_summary"),
        maybeUploadBuildArtifact(payload.jobId, normalizedPath, "normalized_json"),
        maybeUploadBuildArtifact(payload.jobId, seedSqlPath, "seed_sql"),
      ]);

    const jobJsonRaw = await fs.readFile(jobJsonPath, "utf-8");
    const jobJson = JSON.parse(jobJsonRaw) as Record<string, unknown>;
    const buildStatus = String(jobJson.status ?? "build_ready");

    if (buildStatus === "build_ready") {
      await updateJobStatus(payload.jobId, "build_ready", {
        buildJobJsonPath: jobJsonStoragePath,
        buildDiffSummaryPath: diffStoragePath,
        normalizedStoragePath,
        seedSqlStoragePath,
      });
    } else if (buildStatus === "validated_only") {
      await updateJobStatus(payload.jobId, "validated", {
        buildJobJsonPath: jobJsonStoragePath,
        missingPrerequisites: jobJson.missing_prerequisites ?? [],
      });
    } else {
      await updateJobStatus(payload.jobId, "failed", {
        buildStatus,
        buildJobJsonPath: jobJsonStoragePath,
      });
    }

    return {
      ok: true,
      buildStatus,
      jobJsonStoragePath,
      diffStoragePath,
      normalizedStoragePath,
      seedSqlStoragePath,
    };
  },
});
