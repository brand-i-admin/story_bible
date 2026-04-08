import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { repoPath, repoRoot } from "./paths.js";

export async function createJobWorkspace(jobId: string) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), `${jobId}-`));
  return dir;
}

export async function writeTempJson(
  workspaceDir: string,
  filename: string,
  contents: string,
) {
  const fullPath = path.join(workspaceDir, filename);
  await fs.writeFile(fullPath, contents, "utf-8");
  return fullPath;
}

export async function runPythonScript(args: string[], extraEnv: Record<string, string> = {}) {
  await new Promise<void>((resolve, reject) => {
    const child = spawn("python3", args, {
      cwd: repoRoot(),
      env: {
        ...process.env,
        ...extraEnv,
      },
      stdio: "inherit",
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`python3 ${args[0]} exited with code ${code}`));
    });
  });
}

export function repoScript(scriptName: string) {
  return repoPath("tools", scriptName);
}
