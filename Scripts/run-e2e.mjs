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
const require = createRequire(import.meta.url);
const electron = require("electron");
const { installSidekinHooks } = require(path.join(root, "dist", "shared", "codex.cjs"));
const transientRemovalErrors = new Set(["EBUSY", "ENOTEMPTY", "EPERM"]);
const transientReadErrors = new Set(["EBUSY", "ENOENT", "EPERM"]);

async function removeTree(target, { allowTransientFailure = false } = {}) {
  try {
    await rm(target, {
      recursive: true,
      force: true,
      maxRetries: 10,
      retryDelay: 250
    });
  } catch (error) {
    if (allowTransientFailure && error && typeof error === "object" && transientRemovalErrors.has(error.code)) {
      console.warn(`Skipped cleanup for a temporarily locked E2E directory: ${target}`);
      return;
    }
    throw error;
  }
}

async function runConcurrentHook() {
  const payload = `${JSON.stringify({ hook_event_name: "Stop", turn_id: "e2e-concurrent-hook", session_id: "e2e-session", cwd: path.join(temporary, "Synthetic workspace"), prompt: "must never be stored" })}\n`;
  const windows = process.platform === "win32";
  let executable = electron;
  let argumentsList = [root, "sidekin-hook", "codex", "completed"];
  if (windows) {
    const installed = installSidekinHooks({}, electron, "win32", root);
    const hooks = installed.hooks;
    const command = hooks?.Stop?.[0]?.hooks?.[0]?.command;
    if (typeof command !== "string") throw new Error("Windows Codex Stop hook command was not generated.");
    executable = process.env.ComSpec || "cmd.exe";
    argumentsList = ["/d", "/s", "/c", command];
  }
  return new Promise((resolve, reject) => {
    const child = spawn(executable, argumentsList, {
      cwd: root,
      env: { ...process.env, SIDEKIN_CAPTURE_DIR: temporary, ELECTRON_ENABLE_LOGGING: "0" },
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => code === 0 ? resolve({ stdout, stderr }) : reject(new Error(`Concurrent hook exited ${code}: ${stderr}`)));
    child.stdin.end(payload);
  });
}

async function readEventually(file, timeout = 5_000) {
  const deadline = Date.now() + timeout;
  let latestError;
  do {
    try {
      return await readFile(file, "utf8");
    } catch (error) {
      latestError = error;
      if (!error || typeof error !== "object" || !transientReadErrors.has(error.code)) throw error;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  } while (Date.now() < deadline);
  throw latestError;
}

async function verifyCapture(file, minimumWidth, minimumHeight) {
  const fullPath = path.join(temporary, file);
  if (!existsSync(fullPath)) throw new Error(`E2E capture is missing ${file}.`);
  const image = sharp(fullPath, { failOn: "error" });
  const [metadata, stats] = await Promise.all([image.metadata(), image.stats()]);
  if ((metadata.width ?? 0) < minimumWidth || (metadata.height ?? 0) < minimumHeight) throw new Error(`${file} has an invalid capture size.`);
  const alpha = stats.channels[3];
  const transparentCapture = alpha && alpha.min < 255;
  if (transparentCapture ? alpha.max === 0 || alpha.mean < 1 : stats.entropy < 0.5) throw new Error(`${file} appears blank.`);
}

let appOutcome;
try {
  appOutcome = run(electron, [root], {
    cwd: root,
    env: { ...process.env, SIDEKIN_CAPTURE_DIR: temporary, ELECTRON_ENABLE_LOGGING: "0" },
    timeout: 90_000,
    maxBuffer: 8 * 1024 * 1024,
    windowsHide: true
  }).then((value) => ({ value }), (error) => ({ error }));
  await new Promise((resolve) => setTimeout(resolve, 900));
  let hookVerificationError;
  try {
    const hook = await runConcurrentHook();
    const acknowledgement = hook.stdout.trim();
    if (acknowledgement !== "{}") {
      throw new Error(`Codex Stop hook did not return the required empty JSON object (stdout=${JSON.stringify(hook.stdout)}, stderr=${JSON.stringify(hook.stderr.slice(-1_000))}).`);
    }
    const inbox = await readEventually(path.join(temporary, ".capture-user-data", "codex-events.jsonl"));
    if (!inbox.includes("e2e-concurrent-hook") || inbox.includes("must never be stored")) {
      throw new Error(`Concurrent hook did not persist minimized lifecycle metadata (stderr=${JSON.stringify(hook.stderr.slice(-1_000))}).`);
    }
  } catch (error) {
    // The main capture must finish before its shared synthetic userData can be
    // removed. Preserve the original hook error and report it after app exit.
    hookVerificationError = error;
  }
  const outcome = await appOutcome;
  if (outcome.error) throw outcome.error;
  if (hookVerificationError) throw hookVerificationError;
  const completedApp = outcome.value;
  if (/Applying inline style violates the following Content Security Policy/i.test(completedApp.stderr)) {
    throw new Error("The renderer attempted a CSP-blocked inline style update.");
  }
  const report = JSON.parse(await readFile(path.join(temporary, "preview-report.json"), "utf8"));
  if (!String(report.control?.status).toLowerCase().includes("working") || report.control?.cards < 3) throw new Error("Command Center did not render live multi-task state.");
  if (!String(report.floating?.motion).includes("profile-") || report.floating?.cards < 3) throw new Error("Floating companion did not render a motion profile and task cards.");
  if (report.workshop?.jobs < 1 || report.workshop?.jobStages < 2 || report.workshop?.templates < 1 || report.workshop?.loadedPreviews < 6) throw new Error("Workshop recovery previews failed to render.");
  if (report.settings?.panels < 2 || report.settings?.retiredControls !== 0) throw new Error("Settings capture failed its retired-control contract.");
  await Promise.all([
    verifyCapture("command-center.png", 960, 680),
    verifyCapture("floating-pet.png", 400, 480),
    verifyCapture("workshop.png", 960, 680),
    verifyCapture("settings.png", 960, 680)
  ]);
  if (process.argv.includes("--keep")) {
    const destination = path.join(root, "artifacts", "previews");
    await removeTree(destination);
    await mkdir(destination, { recursive: true });
    await Promise.all(["command-center.png", "floating-pet.png", "workshop.png", "settings.png", "preview-report.json"]
      .map((file) => cp(path.join(temporary, file), path.join(destination, file))));
  }
  console.log("Verified the real Electron Command Center, floating companion, Agent Live state, Workshop recovery, Settings, and nonblank screenshots.");
} finally {
  // Settle the Electron child before cleanup even when a concurrent hook
  // assertion fails, otherwise cleanup can erase storage from under the app.
  if (appOutcome) await appOutcome;
  // Chromium helpers can briefly retain DIPS and cache handles after Electron
  // exits on Windows. Retry first; a synthetic CI directory must not turn an
  // otherwise successful product verification into a false failure.
  await removeTree(temporary, { allowTransientFailure: process.platform === "win32" });
}
