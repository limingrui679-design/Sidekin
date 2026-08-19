import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  nativeImage,
  net,
  protocol,
  screen,
  session,
  shell,
  Tray
} from "electron";
import { existsSync } from "node:fs";
import { mkdir, readFile, realpath, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { AgentProvider, CareAction, CodexActivity, CustomPetTemplate, GenerationRequest, PublicPetState, ReferenceSelection, StoredGenerationRequest, WorkshopProgress } from "../shared/types.js";
import { resolvePaths, type SidekinPaths } from "./paths.js";
import { StateService } from "./state-service.js";
import { TemplateStore } from "./template-store.js";
import { SecretStore } from "./secret-store.js";
import { WorkshopService } from "./workshop.js";
import { CodexMonitor } from "./codex-monitor.js";
import { normalizeReference } from "./image-processor.js";
import { safeMediaComponent, type MediaScope } from "../shared/media.js";

protocol.registerSchemesAsPrivileged([{
  scheme: "sidekin-media",
  privileges: { standard: true, secure: true, supportFetchAPI: true }
}]);

app.setName("Sidekin");
if (process.platform === "win32") app.setAppUserModelId("app.sidekin.desktop");
const captureDirectory = process.env.SIDEKIN_CAPTURE_DIR
  ? path.resolve(process.env.SIDEKIN_CAPTURE_DIR)
  : undefined;
if (captureDirectory) {
  app.setPath("userData", path.join(captureDirectory, ".capture-user-data"));
}
const bridgeInvocation = process.argv.includes("sidekin-hook");
const ownsSingleInstance = bridgeInvocation || app.requestSingleInstanceLock();
if (!ownsSingleInstance) app.quit();

let controlWindow: BrowserWindow | undefined;
let floatingWindow: BrowserWindow | undefined;
let tray: Tray | undefined;
let paths: SidekinPaths;
let templates: TemplateStore;
let secrets: SecretStore;
let workshop: WorkshopService;
let monitor: CodexMonitor;
let state: StateService;
let quitting = false;
const referenceSelections = new Map<string, { path: string; createdAt: number }>();

async function readBoundedFile(file: string, maximumBytes: number, label: string): Promise<Buffer> {
  const info = await stat(file);
  if (!info.isFile() || info.size < 1 || info.size > maximumBytes) throw new Error(`${label} size is invalid.`);
  return readFile(file);
}

const rendererFile = (name: string): string => path.join(app.getAppPath(), "dist", "renderer", name);
const preloadFile = (): string => path.join(app.getAppPath(), "dist", "preload", "index.cjs");

function secureWebPreferences(): Electron.WebPreferences {
  return {
    preload: preloadFile(),
    nodeIntegration: false,
    contextIsolation: true,
    sandbox: true,
    webSecurity: true,
    allowRunningInsecureContent: false
  };
}

function sendState(payload: PublicPetState): void {
  for (const window of [controlWindow, floatingWindow]) {
    if (window && !window.isDestroyed()) window.webContents.send("sidekin:state", payload);
  }
  if (floatingWindow) {
    if (state.settings.petVisible) floatingWindow.showInactive();
    else floatingWindow.hide();
  }
  updateTrayMenu();
}

function sendProgress(progress: WorkshopProgress): void {
  if (controlWindow && !controlWindow.isDestroyed()) controlWindow.webContents.send("sidekin:progress", progress);
}

function createFloatingWindow(): void {
  const saved = clampFloatingBounds(state.settings.floatingBounds);
  floatingWindow = new BrowserWindow({
    width: saved?.width ?? 440,
    height: saved?.height ?? 520,
    x: saved?.x,
    y: saved?.y,
    transparent: true,
    frame: false,
    resizable: false,
    alwaysOnTop: true,
    hasShadow: false,
    skipTaskbar: true,
    show: false,
    focusable: true,
    fullscreenable: false,
    webPreferences: secureWebPreferences()
  });
  floatingWindow.setAlwaysOnTop(true, "floating");
  if (process.platform === "darwin") {
    floatingWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    floatingWindow.setHiddenInMissionControl(true);
  }
  floatingWindow.loadFile(rendererFile("floating.html"));
  if (state.settings.clickThroughTransparency) floatingWindow.setIgnoreMouseEvents(true, { forward: true });
  floatingWindow.once("ready-to-show", () => { if (state.settings.petVisible) floatingWindow?.showInactive(); });
  floatingWindow.on("moved", () => saveFloatingBounds());
  floatingWindow.on("closed", () => { floatingWindow = undefined; });
}

function clampFloatingBounds(saved: PublicPetState["settings"]["floatingBounds"]): PublicPetState["settings"]["floatingBounds"] {
  if (!saved || !screen.getAllDisplays().length) return saved;
  const display = screen.getDisplayMatching(saved);
  const area = display.workArea;
  const width = Math.min(saved.width, area.width);
  const height = Math.min(saved.height, area.height);
  return {
    width,
    height,
    x: Math.min(Math.max(saved.x, area.x), area.x + area.width - width),
    y: Math.min(Math.max(saved.y, area.y), area.y + area.height - height)
  };
}

function ensureFloatingVisible(): void {
  if (!floatingWindow || floatingWindow.isDestroyed()) return;
  const clamped = clampFloatingBounds(floatingWindow.getBounds());
  if (clamped) floatingWindow.setBounds(clamped);
}

function createControlWindow(): void {
  if (controlWindow && !controlWindow.isDestroyed()) {
    controlWindow.show();
    controlWindow.focus();
    return;
  }
  controlWindow = new BrowserWindow({
    width: 1_240,
    height: 820,
    minWidth: 960,
    minHeight: 680,
    title: "Sidekin Command Center",
    backgroundColor: "#080b1d",
    show: false,
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "default",
    webPreferences: secureWebPreferences()
  });
  controlWindow.loadFile(rendererFile("index.html"));
  controlWindow.once("ready-to-show", () => controlWindow?.show());
  controlWindow.on("close", (event) => {
    if (!quitting) {
      event.preventDefault();
      controlWindow?.hide();
    }
  });
  controlWindow.on("closed", () => { controlWindow = undefined; });
}

function saveFloatingBounds(): void {
  if (!floatingWindow || floatingWindow.isDestroyed()) return;
  const bounds = floatingWindow.getBounds();
  void state.saveFloatingBounds(bounds);
}

function updateTrayMenu(): void {
  if (!tray || !state?.pet) return;
  const status = state.pet.isSleeping ? "Sleeping" : state.pet.codexActivity;
  tray.setToolTip(`Sidekin · ${status}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Open Command Center", click: createControlWindow },
    { label: state.settings.petVisible ? "Hide Desktop Pet" : "Show Desktop Pet", click: () => void state.setVisible(!state.settings.petVisible) },
    { type: "separator" },
    { label: "Feed", click: () => void state.care("feed") },
    { label: "Play", click: () => void state.care("play") },
    { label: state.pet.isSleeping ? "Wake Up" : "Sleep", click: () => void state.care("sleepOrWake") },
    { type: "separator" },
    { label: "Quit Sidekin", click: () => { quitting = true; app.quit(); } }
  ]));
}

function createTray(): void {
  const source = app.isPackaged
    ? path.join(process.resourcesPath, "tray-template.png")
    : path.join(app.getAppPath(), "assets", "tray-template.png");
  const fallback = path.join(app.getAppPath(), "assets", "app-icon.png");
  let icon = nativeImage.createFromPath(existsSync(source) ? source : fallback).resize({ width: 20, height: 20 });
  if (process.platform === "darwin") icon.setTemplateImage(true);
  tray = new Tray(icon);
  tray.on("click", createControlWindow);
  updateTrayMenu();
}

function assertTrustedSender(event: Electron.IpcMainInvokeEvent): void {
  const url = event.senderFrame?.url ?? event.sender.getURL();
  if (!isTrustedRendererURL(url)) throw new Error("Untrusted renderer request.");
}

function isTrustedRendererURL(url: string): boolean {
  const normalized = url.split("#", 1)[0]!.split("?", 1)[0]!;
  return ["index.html", "floating.html"].some((file) => normalized === pathToFileURL(rendererFile(file)).href);
}

function notFoundMediaResponse(status = 404): Response {
  return new Response("Media not found.", { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}

async function isAllowedMediaFile(scope: MediaScope, components: string[]): Promise<boolean> {
  if (scope === "runtime") {
    return components.length === 2
      && ["characters", "thumbnails"].includes(components[0]!)
      && components[1]!.endsWith(".webp");
  }
  if (scope === "jobs") {
    return components.length === 2 && /^(raw|processed)-stage-0[1-8]\.png$/.test(components[1]!);
  }
  if (scope !== "templates" || components.length !== 2) return false;
  const [templateID, fileName] = components as [string, string];
  if (/^recovery-stage-0[1-8]\.png$/.test(fileName)) return true;
  try {
    const manifest = JSON.parse((await readBoundedFile(path.join(paths.templates, templateID, "template.json"), 1024 * 1024, "Template manifest")).toString("utf8")) as { stages?: Array<{ assetFileName?: unknown }> };
    return Array.isArray(manifest.stages) && manifest.stages.some((stage) => stage.assetFileName === fileName);
  } catch {
    return false;
  }
}

async function handleMediaRequest(request: GlobalRequest): Promise<Response> {
  if (request.method !== "GET") return notFoundMediaResponse(405);
  try {
    const url = new URL(request.url);
    const scope = url.hostname as MediaScope;
    const components = url.pathname.split("/").filter(Boolean).map((value) => safeMediaComponent(decodeURIComponent(value)));
    if (!(await isAllowedMediaFile(scope, components))) return notFoundMediaResponse();
    let root: string;
    let relative: string[];
    if (scope === "runtime") {
      root = components[0] === "characters" ? paths.characters : paths.thumbnails;
      relative = [components[1]!];
    } else if (scope === "templates") {
      root = paths.templates;
      relative = components;
    } else if (scope === "jobs") {
      root = paths.jobs;
      relative = components;
    } else {
      return notFoundMediaResponse();
    }
    const [trustedRoot, target] = await Promise.all([realpath(root), realpath(path.join(root, ...relative))]);
    if (!target.startsWith(`${trustedRoot}${path.sep}`)) return notFoundMediaResponse();
    return net.fetch(pathToFileURL(target).href);
  } catch {
    return notFoundMediaResponse();
  }
}

function assertProvider(provider: AgentProvider): void {
  if (!(["codex", "claude"] as string[]).includes(provider)) throw new Error("Unknown agent provider.");
}

function assertBoolean(value: unknown, label: string): asserts value is boolean {
  if (typeof value !== "boolean") throw new Error(`${label} must be a boolean.`);
}

function assertIdentifier(value: unknown, label: string): asserts value is string {
  if (typeof value !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(value)) throw new Error(`${label} is invalid.`);
}

function assertStageIndex(value: unknown): asserts value is number {
  if (!Number.isInteger(value) || Number(value) < 0 || Number(value) > 7) throw new Error("Stage index is invalid.");
}

function assertCareAction(value: unknown): asserts value is CareAction {
  if (!(["feed", "play", "sleepOrWake"] as unknown[]).includes(value)) throw new Error("Care action is invalid.");
}

function assertActivity(value: unknown): asserts value is CodexActivity {
  if (!(["idle", "running", "completed", "failed"] as unknown[]).includes(value)) throw new Error("Preview activity is invalid.");
}

function assertGenerationRequest(value: unknown): asserts value is GenerationRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Generation request is invalid.");
  const request = value as Record<string, unknown>;
  const bounded = (key: string, maximum: number, required = true) => {
    const field = request[key];
    if (typeof field !== "string" || field.length > maximum || (required && !field.trim())) throw new Error(`${key} is invalid.`);
  };
  bounded("templateName", 60);
  bounded("description", 2_000);
  bounded("artDirection", 1_000);
  bounded("fallbackTheme", 96);
  if (!(["text", "restyle", "faithful"] as unknown[]).includes(request.mode)) throw new Error("Generation mode is invalid.");
  if (!(["low", "medium", "high"] as unknown[]).includes(request.quality)) throw new Error("Generation quality is invalid.");
  if (!Array.isArray(request.stageNames) || request.stageNames.length < 1 || request.stageNames.length > 8 || request.stageNames.some((name) => typeof name !== "string" || !name.trim() || name.length > 64)) throw new Error("Generation stages are invalid.");
  if (request.motionProfile !== undefined && (typeof request.motionProfile !== "string" || !/^[a-z-]{3,24}$/.test(request.motionProfile))) throw new Error("Motion profile is invalid.");
  if (request.referenceToken !== undefined && request.referenceToken !== null && (typeof request.referenceToken !== "string" || !/^[0-9a-f-]{36}$/i.test(request.referenceToken))) throw new Error("Reference token is invalid.");
}

function applyLoginSetting(enabled: boolean): void {
  const options: Electron.Settings = { openAtLogin: enabled, openAsHidden: true, args: ["--hidden"] };
  if (process.defaultApp) {
    options.path = process.execPath;
    options.args = [app.getAppPath(), "--hidden"];
  }
  app.setLoginItemSettings(options);
}

async function bootstrap() {
  return {
    ...(await state.publicState()),
    catalog: state.catalog,
    templates: await templates.loadViews(),
    jobs: await workshop.loadViews(),
    integrations: await monitor.statuses(),
    hasAPIKey: await secrets.hasKey(),
    platform: process.platform
  };
}

function registerIPC(): void {
  const handle = (name: string, action: (event: Electron.IpcMainInvokeEvent, ...args: any[]) => unknown) => {
    ipcMain.handle(name, async (event, ...args) => { assertTrustedSender(event); return action(event, ...args); });
  };
  handle("sidekin:bootstrap", () => bootstrap());
  handle("sidekin:care", (_event, action: CareAction) => { assertCareAction(action); return state.care(action); });
  handle("sidekin:select-theme", (_event, id: string) => { assertIdentifier(id, "Theme ID"); return state.selectTheme(id); });
  handle("sidekin:select-template", (_event, id: string | null) => { if (id !== null) assertIdentifier(id, "Template ID"); return state.selectTemplate(id); });
  handle("sidekin:set-visible", (_event, visible: boolean) => { assertBoolean(visible, "Visibility"); return state.setVisible(visible); });
  handle("sidekin:simulate", (_event, activity: CodexActivity) => { assertActivity(activity); return state.receive({ provider: "codex", activity, timestamp: new Date(), eventID: `simulation-${Date.now()}`, title: "Status response preview", project: "Sidekin" }).then(() => state.publicState()); });
  handle("sidekin:install-integration", async (_event, provider: AgentProvider) => { assertProvider(provider); await monitor.install(provider); return monitor.statuses(); });
  handle("sidekin:uninstall-integration", async (_event, provider: AgentProvider) => { assertProvider(provider); await monitor.uninstall(provider); return monitor.statuses(); });
  handle("sidekin:set-runtime-setting", async (_event, key: "launchAtLogin" | "monitorSessionLogs" | "clickThroughTransparency", value: boolean) => {
    if (!["launchAtLogin", "monitorSessionLogs", "clickThroughTransparency"].includes(key)) throw new Error("Unknown runtime setting.");
    assertBoolean(value, "Runtime setting");
    const result = await state.setRuntimeSetting(key, value);
    if (key === "monitorSessionLogs") await monitor.setSessionFallback(value);
    if (key === "launchAtLogin") applyLoginSetting(value);
    return result;
  });
  handle("sidekin:clear-interrupted", () => state.clearInterrupted());
  handle("sidekin:save-key", async (_event, key: string) => {
    if (typeof key !== "string" || !key.trim() || key.length > 512 || /[\r\n\0]/.test(key)) throw new Error("API key is invalid.");
    await secrets.save(key);
    return true;
  });
  handle("sidekin:remove-key", async () => { await secrets.remove(); return false; });
  handle("sidekin:choose-reference", async (): Promise<ReferenceSelection | null> => {
    const options: Electron.OpenDialogOptions = { properties: ["openFile"], filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }] };
    const result = controlWindow && !controlWindow.isDestroyed()
      ? await dialog.showOpenDialog(controlWindow, options)
      : await dialog.showOpenDialog(options);
    const selectedPath = result.canceled ? undefined : result.filePaths[0];
    if (!selectedPath) return null;
    for (const [token, selection] of referenceSelections) {
      if (Date.now() - selection.createdAt > 30 * 60 * 1_000) referenceSelections.delete(token);
    }
    const token = crypto.randomUUID();
    referenceSelections.set(token, { path: selectedPath, createdAt: Date.now() });
    return { token, displayName: path.basename(selectedPath) };
  });
  handle("sidekin:start-generation", async (_event, request: GenerationRequest) => {
    assertGenerationRequest(request);
    const key = await secrets.read();
    if (!key) throw new Error("Save your own OpenAI API key before starting generation.");
    const selection = request.referenceToken ? referenceSelections.get(request.referenceToken) : undefined;
    if (request.referenceToken && !selection) throw new Error("The reference selection expired. Choose the image again.");
    const storedRequest: StoredGenerationRequest = {
      templateName: request.templateName,
      description: request.description,
      artDirection: request.artDirection,
      mode: request.mode,
      quality: request.quality,
      stageNames: [...request.stageNames],
      fallbackTheme: request.fallbackTheme,
      motionProfile: request.motionProfile,
      referencePath: selection?.path
    };
    const job = await workshop.create(storedRequest);
    if (selection) referenceSelections.delete(request.referenceToken!);
    const template = await workshop.run(job.id, key, sendProgress);
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:resume-generation", async (_event, jobID: string) => {
    assertIdentifier(jobID, "Job ID");
    const needsKey = await workshop.requiresAPIKey(jobID);
    const key = needsKey ? await secrets.read() : undefined;
    if (needsKey && !key) throw new Error("Save your own OpenAI API key before continuing paid stages.");
    const template = await workshop.run(jobID, key ?? "", sendProgress);
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:reprocess-job-stage", async (_event, jobID: string, stageIndex: number) => {
    assertIdentifier(jobID, "Job ID"); assertStageIndex(stageIndex);
    await workshop.reprocessJobStage(jobID, stageIndex);
    return true;
  });
  handle("sidekin:restart-job-stage", async (_event, jobID: string, stageIndex: number) => {
    assertIdentifier(jobID, "Job ID"); assertStageIndex(stageIndex);
    await workshop.restartFromStage(jobID, stageIndex);
    return true;
  });
  handle("sidekin:cancel-generation", () => workshop.cancel());
  handle("sidekin:rename-template", (_event, id: string, name: string) => { assertIdentifier(id, "Template ID"); if (typeof name !== "string") throw new Error("Template name is invalid."); return templates.rename(id, name); });
  handle("sidekin:delete-template", async (_event, id: string) => {
    assertIdentifier(id, "Template ID");
    if (state.pet.wardrobe.customTemplateID === id) await state.selectTemplate(null);
    await templates.remove(id);
    return true;
  });
  handle("sidekin:import-template", async () => {
    const options: Electron.OpenDialogOptions = { properties: ["openFile"], filters: [{ name: "Sidekin Template", extensions: ["sidekinpet", "zip"] }] };
    const result = controlWindow && !controlWindow.isDestroyed()
      ? await dialog.showOpenDialog(controlWindow, options)
      : await dialog.showOpenDialog(options);
    if (result.canceled || !result.filePaths[0]) return null;
    const template = await templates.importPackage(await readBoundedFile(result.filePaths[0], 96 * 1024 * 1024, "Pet Pack"));
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:export-template", async (_event, id: string) => {
    assertIdentifier(id, "Template ID");
    const template = await templates.load(id);
    if (!template) throw new Error("Template was not found.");
    const options: Electron.SaveDialogOptions = { defaultPath: `${template.name.replaceAll(/[^A-Za-z0-9 _-]/g, "")}.sidekinpet` };
    const result = controlWindow && !controlWindow.isDestroyed()
      ? await dialog.showSaveDialog(controlWindow, options)
      : await dialog.showSaveDialog(options);
    if (result.canceled || !result.filePath) return false;
    await writeFile(result.filePath, await templates.exportPackage(id));
    return true;
  });
  handle("sidekin:replace-template-stage", async (_event, id: string, stageIndex: number) => {
    assertIdentifier(id, "Template ID"); assertStageIndex(stageIndex);
    const options: Electron.OpenDialogOptions = { properties: ["openFile"], filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }] };
    const result = controlWindow && !controlWindow.isDestroyed()
      ? await dialog.showOpenDialog(controlWindow, options)
      : await dialog.showOpenDialog(options);
    if (result.canceled || !result.filePaths[0]) return false;
    await workshop.replaceTemplateStage(id, stageIndex, await readBoundedFile(result.filePaths[0], 24 * 1024 * 1024, "Replacement image"));
    await state.selectTemplate(id);
    return true;
  });
  handle("sidekin:regenerate-template-stage", async (_event, id: string, stageIndex: number) => {
    assertIdentifier(id, "Template ID"); assertStageIndex(stageIndex);
    const key = await secrets.read();
    if (!key) throw new Error("Save your own OpenAI API key before regenerating a stage.");
    const template = await workshop.regenerateTemplateStage(id, stageIndex, key, sendProgress);
    await state.selectTemplate(id);
    return template;
  });
  handle("sidekin:reprocess-template-stage", async (_event, id: string, stageIndex: number) => {
    assertIdentifier(id, "Template ID"); assertStageIndex(stageIndex);
    const template = await workshop.reprocessTemplateRecovery(id, stageIndex);
    await state.selectTemplate(id);
    return template;
  });
  handle("sidekin:open-user-data", async () => {
    const error = await shell.openPath(paths.userData);
    if (error) throw new Error(error);
  });
  handle("sidekin:open-control-center", () => createControlWindow());
  handle("sidekin:set-pointer-interactive", (_event, interactive: boolean) => {
    assertBoolean(interactive, "Pointer interaction");
    if (!floatingWindow || floatingWindow.isDestroyed() || !state.settings.clickThroughTransparency) return;
    floatingWindow.setIgnoreMouseEvents(!interactive, { forward: !interactive });
  });
  handle("sidekin:quit", () => { quitting = true; app.quit(); });
}

async function capturePreviewsIfRequested(): Promise<void> {
  if (!captureDirectory || !controlWindow || !floatingWindow) return;
  await mkdir(captureDirectory, { recursive: true });
  await Promise.all([
    new Promise<void>((resolve) => controlWindow!.webContents.isLoading() ? controlWindow!.webContents.once("did-finish-load", () => resolve()) : resolve()),
    new Promise<void>((resolve) => floatingWindow!.webContents.isLoading() ? floatingWindow!.webContents.once("did-finish-load", () => resolve()) : resolve())
  ]);
  controlWindow.show();
  controlWindow.focus();
  floatingWindow.showInactive();
  await Promise.all([
    controlWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => { const deadline = Date.now() + 15000; const timer = setInterval(() => { const image = document.querySelector('#hero-pet'); if (image?.complete && image.naturalWidth > 0 && document.querySelectorAll('.activity-card').length >= 3 && document.querySelector('#hero-status')?.textContent?.includes('working')) { clearInterval(timer); resolve(true); } else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Command Center did not finish rendering.')); } }, 100); })`),
    floatingWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => { const deadline = Date.now() + 15000; const timer = setInterval(() => { const image = document.querySelector('#float-pet'); if (image?.complete && image.naturalWidth > 0 && document.querySelectorAll('.float-task').length >= 3) { clearInterval(timer); resolve(true); } else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Floating companion did not finish rendering.')); } }, 100); })`)
  ]);
  floatingWindow.webContents.invalidate();
  await new Promise((resolve) => setTimeout(resolve, 700));
  const floating = await floatingWindow.webContents.capturePage();
  await controlWindow.webContents.executeJavaScript(`document.querySelector('[data-tab="workshop"]')?.click()`);
  await controlWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => { const deadline = Date.now() + 15000; const timer = setInterval(() => { const images = [...document.querySelectorAll('.recovery-stage img,.template-stage img')]; if (document.querySelector('#tab-workshop')?.classList.contains('active') && images.length >= 6 && images.every((image) => image.complete && image.naturalWidth > 0)) { clearInterval(timer); resolve(true); } else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Workshop did not finish rendering.')); } }, 100); })`);
  controlWindow.webContents.invalidate();
  await new Promise((resolve) => setTimeout(resolve, 350));
  const workshopReport = await controlWindow.webContents.executeJavaScript(`(() => ({ jobs: document.querySelectorAll('.recovery-item').length, jobStages: document.querySelectorAll('.recovery-stage').length, templates: document.querySelectorAll('.template-item').length, templateStages: document.querySelectorAll('.template-stage').length, loadedPreviews: [...document.querySelectorAll('.recovery-stage img,.template-stage img')].filter((image) => image.complete && image.naturalWidth > 0).length }))()`);
  const workshopCapture = await controlWindow.webContents.capturePage();
  await controlWindow.webContents.executeJavaScript(`document.querySelector('[data-tab="settings"]')?.click()`);
  await controlWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => { const deadline = Date.now() + 15000; const timer = setInterval(() => { if (document.querySelector('#tab-settings')?.classList.contains('active')) { clearInterval(timer); requestAnimationFrame(() => requestAnimationFrame(resolve)); } else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Settings did not finish rendering.')); } }, 100); })`);
  controlWindow.webContents.invalidate();
  await new Promise((resolve) => setTimeout(resolve, 350));
  const settingsReport = await controlWindow.webContents.executeJavaScript(`(() => ({ panels: document.querySelectorAll('#tab-settings .panel').length, retiredControls: document.querySelectorAll('#tab-settings select').length }))()`);
  if (settingsReport.retiredControls !== 0) throw new Error("Retired cosmetic controls remain in Settings.");
  const settingsCapture = await controlWindow.webContents.capturePage();
  await controlWindow.webContents.executeJavaScript(`document.querySelector('[data-tab="home"]')?.click()`);
  await controlWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => { const deadline = Date.now() + 15000; const timer = setInterval(() => { const image = document.querySelector('#hero-pet'); if (document.querySelector('#tab-home')?.classList.contains('active') && image?.complete && image.naturalWidth > 0 && document.querySelectorAll('.activity-card').length >= 3 && document.querySelector('#hero-status')?.textContent?.includes('working')) { clearInterval(timer); requestAnimationFrame(() => requestAnimationFrame(resolve)); } else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Command Center did not finish its final render.')); } }, 100); })`);
  controlWindow.webContents.invalidate();
  await new Promise((resolve) => setTimeout(resolve, 700));
  const control = await controlWindow.webContents.capturePage();
  const report = await Promise.all([
    controlWindow.webContents.executeJavaScript(`(() => { const image = document.querySelector('#hero-pet'); return { title: document.title, status: document.querySelector('#hero-status')?.textContent, cards: document.querySelectorAll('.activity-card').length, image: { src: image?.src, complete: image?.complete, width: image?.naturalWidth, height: image?.naturalHeight }, bodyBackground: getComputedStyle(document.body).backgroundColor }; })()`),
    floatingWindow.webContents.executeJavaScript(`(() => { const image = document.querySelector('#float-pet'); return { status: document.querySelector('#float-status')?.textContent, cards: document.querySelectorAll('.float-task').length, motion: document.querySelector('#pet-motion')?.className, image: { src: image?.src, complete: image?.complete, width: image?.naturalWidth, height: image?.naturalHeight } }; })()`)
  ]);
  await Promise.all([
    writeFile(path.join(captureDirectory, "command-center.png"), control.toPNG()),
    writeFile(path.join(captureDirectory, "floating-pet.png"), floating.toPNG()),
    writeFile(path.join(captureDirectory, "workshop.png"), workshopCapture.toPNG()),
    writeFile(path.join(captureDirectory, "settings.png"), settingsCapture.toPNG()),
    writeFile(path.join(captureDirectory, "preview-report.json"), `${JSON.stringify({ control: report[0], floating: report[1], workshop: workshopReport, settings: settingsReport }, null, 2)}\n`)
  ]);
  quitting = true;
  app.quit();
}

async function handleBridgeMode(): Promise<boolean> {
  const marker = process.argv.indexOf("sidekin-hook");
  if (marker < 0) return false;
  const provider = process.argv[marker + 1] as AgentProvider | undefined;
  const activity = process.argv[marker + 2] as CodexActivity | undefined;
  if (!provider || !["codex", "claude"].includes(provider)) return true;
  if (!activity || !["running", "completed", "failed"].includes(activity)) return true;
  paths = await resolvePaths();
  const input: Buffer[] = [];
  let inputBytes = 0;
  for await (const chunk of process.stdin) {
    const buffer = Buffer.from(chunk);
    inputBytes += buffer.length;
    if (inputBytes > 4 * 1024 * 1024) return true;
    input.push(buffer);
  }
  const payload = Buffer.concat(input);
  monitor = new CodexMonitor(paths, () => undefined);
  try { await monitor.writeHookEvent(provider, activity, payload); }
  catch { return true; }
  if (provider === "codex") {
    try {
      const hook = JSON.parse(payload.toString("utf8")) as Record<string, unknown>;
      if (hook.hook_event_name === "Stop") process.stdout.write("{}\n");
    } catch { /* no hook output is required for malformed optional metadata */ }
  }
  return true;
}

app.whenReady().then(async () => {
  if (!ownsSingleInstance) return;
  if (await handleBridgeMode()) { app.quit(); return; }
  paths = await resolvePaths();
  protocol.handle("sidekin-media", handleMediaRequest);
  templates = new TemplateStore(paths);
  secrets = new SecretStore(paths);
  workshop = new WorkshopService(paths, templates);
  state = new StateService(paths, templates, sendState);
  await state.initialize();
  if (captureDirectory) {
    const base = new Date();
    await state.receive({ provider: "codex", activity: "completed", timestamp: new Date(base.getTime() - 72_000), eventID: "capture-complete", title: "Cross-platform runtime", project: "Sidekin" });
    await state.receive({ provider: "claude", activity: "failed", timestamp: new Date(base.getTime() - 35_000), eventID: "capture-failed", title: "Asset continuity review", project: "Art audit" });
    await state.receive({ provider: "codex", activity: "running", timestamp: new Date(base.getTime() - 18_000), eventID: "capture-running", title: "Windows packaging verification", project: "Sidekin" });
    const rawOne = await normalizeReference(await readFile(path.join(paths.characters, "nova-hatchling.webp")));
    const rawTwo = await normalizeReference(await readFile(path.join(paths.characters, "nova-juvenile.webp")));
    const captureJob = await workshop.create({
      templateName: "Prism familiar",
      description: "A clearly nonhuman crystal familiar",
      artDirection: "premium competitive-game mascot",
      mode: "text",
      quality: "medium",
      stageNames: ["Core", "Awakening", "Crown"],
      fallbackTheme: "nova"
    });
    const captureJobDirectory = path.join(paths.jobs, captureJob.id);
    await writeFile(path.join(captureJobDirectory, "raw-stage-01.png"), rawOne);
    await workshop.reprocessJobStage(captureJob.id, 0);
    await writeFile(path.join(captureJobDirectory, "raw-stage-02.png"), rawTwo);
    const captureTemplate: CustomPetTemplate = {
      schemaVersion: 2,
      packFormat: "sidekin.pet-pack",
      minSidekinVersion: "2.2.0",
      id: "capture-template",
      name: "Local prism lineage",
      author: "Sidekin preview",
      license: "Preview only",
      motionProfile: "poised",
      contentHashes: {},
      basePrompt: "A nonhuman prism familiar",
      artDirection: "premium competitive-game mascot",
      generationMode: "text",
      generationQuality: "medium",
      referenceFileName: null,
      createdAt: base.toISOString(),
      fallbackTheme: "nova",
      stages: [
        { id: "capture-stage-1", index: 0, name: "Core", prompt: "Core", experienceThreshold: 0, assetFileName: "stage-01.png" },
        { id: "capture-stage-2", index: 1, name: "Awakening", prompt: "Awakening", experienceThreshold: 75, assetFileName: "stage-02.png" },
        { id: "capture-stage-3", index: 2, name: "Crown", prompt: "Crown", experienceThreshold: 360, assetFileName: "stage-03.png" }
      ]
    };
    await templates.install(captureTemplate, [
      await normalizeReference(await readFile(path.join(paths.characters, "nova-egg.webp"))),
      rawOne,
      await normalizeReference(await readFile(path.join(paths.characters, "nova-legendary.webp")))
    ]);
  }
  monitor = new CodexMonitor(paths, (record) => void state.receive(record));
  if (!captureDirectory) await monitor.start(state.settings.monitorSessionLogs);

  // oxlint-disable-next-line promise/no-callback-in-promise -- Electron requires this permission callback API.
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  // oxlint-disable-next-line promise/no-callback-in-promise -- Electron requires this webRequest callback API.
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => callback({
    responseHeaders: {
      ...details.responseHeaders,
      "Content-Security-Policy": ["default-src 'self'; img-src 'self' sidekin-media: data:; style-src 'self'; script-src 'self'; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'"]
    }
  }));
  app.on("web-contents-created", (_event, contents) => {
    contents.setWindowOpenHandler(() => ({ action: "deny" }));
    contents.on("will-navigate", (event, url) => { if (!isTrustedRendererURL(url)) event.preventDefault(); });
  });
  registerIPC();
  createFloatingWindow();
  const startHidden = process.argv.includes("--hidden") || app.getLoginItemSettings().wasOpenedAtLogin;
  if (!startHidden) createControlWindow();
  createTray();
  if (!captureDirectory) applyLoginSetting(state.settings.launchAtLogin);
  screen.on("display-removed", ensureFloatingVisible);
  screen.on("display-metrics-changed", ensureFloatingVisible);
  void capturePreviewsIfRequested().catch((error) => {
    process.stderr.write(`Sidekin capture failed: ${error instanceof Error ? error.message : String(error)}\n`);
    app.exit(1);
  });
  app.on("activate", createControlWindow);
}).catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  if (!bridgeInvocation) dialog.showErrorBox("Sidekin could not start", message);
  app.exit(1);
});

app.on("second-instance", () => { if (app.isReady() && state) createControlWindow(); });

app.on("window-all-closed", () => {
  // Sidekin remains available from the tray until the user explicitly quits.
});
app.on("before-quit", () => { quitting = true; monitor?.stop(); saveFloatingBounds(); });
