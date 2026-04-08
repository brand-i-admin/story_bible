import path from "node:path";
import { fileURLToPath } from "node:url";

const currentFile = fileURLToPath(import.meta.url);
const currentDir = path.dirname(currentFile);

export function repoRoot() {
  return process.env.STORY_BIBLE_REPO_ROOT
    ? path.resolve(process.env.STORY_BIBLE_REPO_ROOT)
    : path.resolve(currentDir, "../../../..");
}

export function repoPath(...parts: string[]) {
  return path.join(repoRoot(), ...parts);
}
