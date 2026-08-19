import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { cp, mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const run = promisify(execFile);
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const temporary = await mkdtemp(path.join(tmpdir(), "sidekin-e2e-"));
const electron = createRequire(import.meta.url)("electron");

function runConcurrentHook() {
  return new Promise((resolve, reject) => {
    const child = spawn(electron, [root, "sidekin-hook", "codex", "completed"], {
      cwd: root,
      env: { ...process.env, SIDEKIN_CAPTURE_DIR: temporary },
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => code === 0 ? resolve({ stdout, stderr }) : reject(new Error(`Concurrent hook exited ${code}: ${stderr}`)));
    child.stdin.end(`${JSON.stringify({ hook_event_name: "Stop", turn_id: "e2e-concurrent-hook", session_id: "e2e-session", cwd: path.join(temporary, "Synthetic workspace"), prompt: "must never be stored" })}\n`);
  });
}

async function verifyCapture(file, minimumWidth, minimumHeight) {
  const fullPath = path.join(temporary, file);
  if (!existsSync(fullPath)) throw new Error(`E2E capture is missing ${file}.`);
  const image = sharp(fullPath, { failOn: "error" });
  const [metadata, stats] = await Promise.all([image.metadata(), image.stats()]);
  if ((metadata.width ?? 0) < minimumWidth || (metadata.height ?? 0) < minimumHeight) throw new Error(`${file} has an invalid capture size.`);
  if (stats.entropy < 0.5) throw new Error(`${file} appears blank.`);
}

try {
  const appRun = run(electron, [root], {
    cwd: root,
    env: { ...process.env, SIDEKIN_CAPTURE_DIR: temporary, ELECTRON_ENABLE_LOGGING: "0" },
    timeout: 90_000,
    maxBuffer: 8 * 1024 * 1024,
    windowsHide: true
  });
  await new Promise((resolve) => setTimeout(resolve, 900));
  const hook = await runConcurrentHook();
  if (hook.stdout.trim() !== "{}") throw new Error("Codex Stop hook did not return the required empty JSON object.");
  const inbox = await readFile(path.join(temporary, ".capture-user-data", "codex-events.jsonl"), "utf8");
  if (!inbox.includes("e2e-concurrent-hook") || inbox.includes("must never be stored")) throw new Error("Concurrent hook did not persist minimized lifecycle metadata.");
  const completedApp = await appRun;
  if (/Applying inline style violates the following Content Security Policy/i.test(completedApp.stderr)) {
    throw new Error("The renderer attempted a CSP-blocked inline style update.");
  }
  const report = JSON.parse(await readFile(path.join(temporary, "preview-report.json"), "utf8"));
  if (!String(report.control?.status).toLowerCase().includes("working") || report.control?.cards < 3) throw new Error("Command Center did not render live multi-task state.");
  if (!String(report.floating?.motion).includes("profile-") || report.floating?.cards < 3) throw new Error("Floating companion did not render a motion profile and task cards.");
  if (report.workshop?.jobs < 1 || report.workshop?.jobStages < 2 || report.workshop?.templates < 1 || report.workshop?.loadedPreviews < 5) throw new Error("Workshop recovery previews failed to render.");
  if (report.settings?.panels < 2 || report.settings?.retiredControls !== 0) throw new Error("Settings capture failed its retired-control contract.");
  await Promise.all([
    verifyCapture("command-center.png", 960, 680),
    verifyCapture("floating-pet.png", 400, 480),
    verifyCapture("workshop.png", 960, 680),
    verifyCapture("settings.png", 960, 680)
  ]);
  if (process.argv.includes("--keep")) {
    const destination = path.join(root, "artifacts", "previews");
    await rm(destination, { recursive: true, force: true });
    await mkdir(destination, { recursive: true });
    await Promise.all(["command-center.png", "floating-pet.png", "workshop.png", "settings.png", "preview-report.json"]
      .map((file) => cp(path.join(temporary, file), path.join(destination, file))));
  }
  console.log("Verified the real Electron Command Center, floating companion, Agent Live state, Workshop recovery, Settings, and nonblank screenshots.");
} finally {
  await rm(temporary, { recursive: true, force: true });
}
