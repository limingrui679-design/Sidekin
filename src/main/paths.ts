import { app } from "electron";
import { existsSync } from "node:fs";
import { mkdir, rename } from "node:fs/promises";
import path from "node:path";

export interface SidekinPaths {
  userData: string;
  state: string;
  settings: string;
  eventInbox: string;
  templates: string;
  jobs: string;
  secret: string;
  catalog: string;
  characters: string;
  codexHooks: string;
  codexSessions: string;
}

export async function resolvePaths(): Promise<SidekinPaths> {
  const userData = app.getPath("userData");
  const legacy = path.join(path.dirname(userData), "CainiaoPet");
  if (!existsSync(userData) && existsSync(legacy)) {
    try { await rename(legacy, userData); } catch { /* best-effort migration */ }
  }
  await mkdir(userData, { recursive: true });
  const root = app.isPackaged ? process.resourcesPath : app.getAppPath();
  const resources = app.isPackaged ? root : path.join(root, "Sources/SidekinApp/Resources");
  return {
    userData,
    state: path.join(userData, "pet-state.json"),
    settings: path.join(userData, "settings.json"),
    eventInbox: path.join(userData, "codex-events.jsonl"),
    templates: path.join(userData, "PetTemplates"),
    jobs: path.join(userData, "GenerationJobs"),
    secret: path.join(userData, "api-key.bin"),
    catalog: app.isPackaged
      ? path.join(resources, "PET_THEME_CATALOG.json")
      : path.join(root, "ArtSources/PET_THEME_CATALOG.json"),
    characters: app.isPackaged
      ? path.join(resources, "Characters")
      : path.join(resources, "Characters"),
    codexHooks: path.join(app.getPath("home"), ".codex", "hooks.json"),
    codexSessions: path.join(app.getPath("home"), ".codex", "sessions")
  };
}
