import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  nativeImage,
  session,
  shell,
  Tray
} from "electron";
import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { CareAction, CodexActivity, CustomPetTemplate, GenerationRequest, PublicPetState, WorkshopProgress } from "../shared/types.js";
import { resolvePaths, type SidekinPaths } from "./paths.js";
import { StateService } from "./state-service.js";
import { TemplateStore } from "./template-store.js";
import { SecretStore } from "./secret-store.js";
import { WorkshopService } from "./workshop.js";
import { CodexMonitor } from "./codex-monitor.js";

app.setName("Sidekin");
if (process.platform === "win32") app.setAppUserModelId("app.sidekin.desktop");
const captureDirectory = process.env.SIDEKIN_CAPTURE_DIR
  ? path.resolve(process.env.SIDEKIN_CAPTURE_DIR)
  : undefined;
if (captureDirectory) {
  app.setPath("userData", path.join(captureDirectory, ".capture-user-data"));
}

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
  if (floatingWindow) state.settings.petVisible ? floatingWindow.showInactive() : floatingWindow.hide();
  updateTrayMenu();
}

function sendProgress(progress: WorkshopProgress): void {
  if (controlWindow && !controlWindow.isDestroyed()) controlWindow.webContents.send("sidekin:progress", progress);
}

function createFloatingWindow(): void {
  const saved = state.settings.floatingBounds;
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
  floatingWindow.once("ready-to-show", () => { if (state.settings.petVisible) floatingWindow?.showInactive(); });
  floatingWindow.on("moved", () => saveFloatingBounds());
  floatingWindow.on("closed", () => { floatingWindow = undefined; });
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
  if (!url.startsWith("file://")) throw new Error("Untrusted renderer request.");
}

async function bootstrap() {
  return {
    ...(await state.publicState()),
    catalog: state.catalog,
    templates: await templates.loadViews(),
    jobs: await workshop.loadViews(),
    hooksInstalled: await monitor.isInstalled(),
    hasAPIKey: await secrets.hasKey(),
    platform: process.platform,
    paths: { userData: paths.userData, codexSessions: paths.codexSessions, codexHooks: paths.codexHooks }
  };
}

function registerIPC(): void {
  const handle = (name: string, action: (event: Electron.IpcMainInvokeEvent, ...args: any[]) => unknown) => {
    ipcMain.handle(name, async (event, ...args) => { assertTrustedSender(event); return action(event, ...args); });
  };
  handle("sidekin:bootstrap", () => bootstrap());
  handle("sidekin:care", (_event, action: CareAction) => state.care(action));
  handle("sidekin:select-theme", (_event, id: string) => state.selectTheme(id));
  handle("sidekin:select-template", (_event, id: string | null) => state.selectTemplate(id));
  handle("sidekin:set-visible", (_event, visible: boolean) => state.setVisible(Boolean(visible)));
  handle("sidekin:simulate", (_event, activity: CodexActivity) => state.receive({ activity, timestamp: new Date(), eventID: `simulation-${Date.now()}`, title: "Status response preview", project: "Sidekin" }).then(() => state.publicState()));
  handle("sidekin:install-hooks", async () => { await monitor.install(); return monitor.isInstalled(); });
  handle("sidekin:uninstall-hooks", async () => { await monitor.uninstall(); return monitor.isInstalled(); });
  handle("sidekin:save-key", async (_event, key: string) => { await secrets.save(key); return true; });
  handle("sidekin:remove-key", async () => { await secrets.remove(); return false; });
  handle("sidekin:choose-reference", async () => {
    const result = await dialog.showOpenDialog(controlWindow!, { properties: ["openFile"], filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }] });
    return result.canceled ? null : result.filePaths[0] ?? null;
  });
  handle("sidekin:start-generation", async (_event, request: GenerationRequest) => {
    const job = await workshop.create(request);
    const key = await secrets.read();
    if (!key) throw new Error("Save your own OpenAI API key before starting generation.");
    const template = await workshop.run(job.id, key, sendProgress);
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:resume-generation", async (_event, jobID: string) => {
    const template = await workshop.run(jobID, await secrets.read() ?? "", sendProgress);
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:reprocess-job-stage", async (_event, jobID: string, stageIndex: number) => {
    await workshop.reprocessJobStage(jobID, stageIndex);
    return true;
  });
  handle("sidekin:restart-job-stage", async (_event, jobID: string, stageIndex: number) => {
    await workshop.restartFromStage(jobID, stageIndex);
    return true;
  });
  handle("sidekin:cancel-generation", () => workshop.cancel());
  handle("sidekin:rename-template", (_event, id: string, name: string) => templates.rename(id, name));
  handle("sidekin:delete-template", async (_event, id: string) => {
    if (state.pet.wardrobe.customTemplateID === id) await state.selectTemplate(null);
    await templates.remove(id);
    return true;
  });
  handle("sidekin:import-template", async () => {
    const result = await dialog.showOpenDialog(controlWindow!, { properties: ["openFile"], filters: [{ name: "Sidekin Template", extensions: ["sidekinpet", "zip"] }] });
    if (result.canceled || !result.filePaths[0]) return null;
    const template = await templates.importPackage(await readFile(result.filePaths[0]));
    await state.selectTemplate(template.id);
    return template;
  });
  handle("sidekin:export-template", async (_event, id: string) => {
    const template = await templates.load(id);
    if (!template) throw new Error("Template was not found.");
    const result = await dialog.showSaveDialog(controlWindow!, { defaultPath: `${template.name.replaceAll(/[^A-Za-z0-9 _-]/g, "")}.sidekinpet` });
    if (result.canceled || !result.filePath) return false;
    await writeFile(result.filePath, await templates.exportPackage(id));
    return true;
  });
  handle("sidekin:replace-template-stage", async (_event, id: string, stageIndex: number) => {
    const result = await dialog.showOpenDialog(controlWindow!, { properties: ["openFile"], filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }] });
    if (result.canceled || !result.filePaths[0]) return false;
    await workshop.replaceTemplateStage(id, stageIndex, await readFile(result.filePaths[0]));
    await state.selectTemplate(id);
    return true;
  });
  handle("sidekin:regenerate-template-stage", async (_event, id: string, stageIndex: number) => {
    const key = await secrets.read();
    if (!key) throw new Error("Save your own OpenAI API key before regenerating a stage.");
    const template = await workshop.regenerateTemplateStage(id, stageIndex, key, sendProgress);
    await state.selectTemplate(id);
    return template;
  });
  handle("sidekin:reprocess-template-stage", async (_event, id: string, stageIndex: number) => {
    const template = await workshop.reprocessTemplateRecovery(id, stageIndex);
    await state.selectTemplate(id);
    return template;
  });
  handle("sidekin:open-user-data", () => shell.openPath(paths.userData));
  handle("sidekin:open-control-center", () => createControlWindow());
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
  await rm(path.join(captureDirectory, ".capture-user-data"), { recursive: true, force: true });
  quitting = true;
  app.quit();
}

async function handleBridgeMode(): Promise<boolean> {
  const marker = process.argv.indexOf("sidekin-hook");
  if (marker < 0) return false;
  const activity = process.argv[marker + 1] as CodexActivity | undefined;
  if (!activity || !["running", "completed", "failed"].includes(activity)) return true;
  paths = await resolvePaths();
  const input: Buffer[] = [];
  for await (const chunk of process.stdin) input.push(Buffer.from(chunk));
  monitor = new CodexMonitor(paths, () => undefined);
  await monitor.writeHookEvent(activity, Buffer.concat(input));
  process.stdout.write("{}\n");
  return true;
}

app.whenReady().then(async () => {
  if (await handleBridgeMode()) { app.quit(); return; }
  paths = await resolvePaths();
  templates = new TemplateStore(paths);
  secrets = new SecretStore(paths);
  workshop = new WorkshopService(paths, templates);
  state = new StateService(paths, templates, sendState);
  await state.initialize();
  if (captureDirectory) {
    const base = new Date();
    await state.receive({ activity: "completed", timestamp: new Date(base.getTime() - 72_000), eventID: "capture-complete", title: "Cross-platform runtime", project: "Sidekin" });
    await state.receive({ activity: "failed", timestamp: new Date(base.getTime() - 35_000), eventID: "capture-failed", title: "Asset continuity review", project: "Art audit" });
    await state.receive({ activity: "running", timestamp: new Date(base.getTime() - 18_000), eventID: "capture-running", title: "Windows packaging verification", project: "Sidekin" });
    const rawOne = await readFile(path.join(paths.characters, "nova-hatchling.png"));
    const rawTwo = await readFile(path.join(paths.characters, "nova-juvenile.png"));
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
      schemaVersion: 1,
      id: "capture-template",
      name: "Local prism lineage",
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
      await readFile(path.join(paths.characters, "nova-egg.png")),
      rawOne,
      await readFile(path.join(paths.characters, "nova-legendary.png"))
    ]);
  }
  monitor = new CodexMonitor(paths, (record) => void state.receive(record));
  if (!captureDirectory) await monitor.start();

  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => callback({
    responseHeaders: {
      ...details.responseHeaders,
      "Content-Security-Policy": ["default-src 'self'; img-src 'self' file: data:; style-src 'self'; script-src 'self'; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'"]
    }
  }));
  app.on("web-contents-created", (_event, contents) => {
    contents.setWindowOpenHandler(() => ({ action: "deny" }));
    contents.on("will-navigate", (event, url) => { if (!url.startsWith("file://")) event.preventDefault(); });
  });
  registerIPC();
  createFloatingWindow();
  createControlWindow();
  createTray();
  void capturePreviewsIfRequested();
  app.on("activate", createControlWindow);
});

app.on("window-all-closed", () => {
  // Sidekin remains available from the tray until the user explicitly quits.
});
app.on("before-quit", () => { quitting = true; monitor?.stop(); saveFloatingBounds(); });
