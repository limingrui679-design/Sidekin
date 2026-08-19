import { stageProgress } from "../shared/lifecycle.js";
import type {
  ActivityFeedItem,
  AgentProvider,
  BootstrapPayload,
  GenerationMode,
  GenerationQuality,
  PublicPetState,
  ReferenceSelection,
  ThemeProfile,
  WorkshopProgress
} from "../shared/types.js";

let data: BootstrapPayload;
let referenceSelection: ReferenceSelection | null = null;
let toastTimer: number | undefined;

const $ = <T extends HTMLElement>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing element: ${selector}`);
  return element;
};
const $$ = <T extends HTMLElement>(selector: string): T[] => Array.from(document.querySelectorAll<T>(selector));

function setProgress(selector: string, value: number): void {
  const progress = $<HTMLProgressElement>(selector);
  progress.value = Math.min(100, Math.max(0, value));
  progress.setAttribute("aria-valuenow", String(Math.round(progress.value)));
}

function escapeHTML(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}

function toast(message: string, error = false): void {
  const element = $("#toast");
  element.textContent = message;
  element.classList.toggle("error", error);
  element.classList.add("visible");
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => element.classList.remove("visible"), 3_600);
}

async function run<T>(action: () => Promise<T>, success?: string | ((result: T) => string | undefined)): Promise<void> {
  try {
    const result = await action();
    const message = typeof success === "function" ? success(result) : success;
    if (message) toast(message);
  } catch (error) {
    toast(error instanceof Error ? error.message : String(error), true);
  }
}

function setTab(name: string): void {
  $$(".nav-item").forEach((button) => button.classList.toggle("active", button.dataset.tab === name));
  $$(".tab-panel").forEach((panel) => panel.classList.toggle("active", panel.id === `tab-${name}`));
  const label = $<HTMLButtonElement>(`.nav-item[data-tab="${name}"]`).dataset.title || name;
  $("#page-title").textContent = label;
}

function duration(item: ActivityFeedItem): string {
  if (item.status === "running") return "live";
  const ms = item.durationMs ?? 0;
  if (ms < 60_000) return `${Math.max(1, Math.round(ms / 1_000))}s`;
  return `${Math.round(ms / 60_000)}m`;
}

function activityHTML(items: ActivityFeedItem[], limit = 3): string {
  if (!items.length) return '<div class="empty-state">No recent task signals. Install a local agent link or use Live Preview.</div>';
  return items.slice(-limit).reverse().map((item) => `
    <div class="activity-card ${item.status}">
      <i></i><div><strong>${escapeHTML(item.title)}</strong><small>${item.provider === "claude" ? "Claude Code" : "Codex"} · ${escapeHTML(item.project)} · ${item.status}</small></div><time>${duration(item)}</time>
    </div>`).join("");
}

function asset(theme: ThemeProfile, stage: string): string {
  const base = data.assetURL.replace(/[^/]+$/, "");
  return `${base}${theme.id}-${stage}.webp`;
}

function thumbnail(theme: ThemeProfile): string {
  return `${data.thumbnailBaseURL}${theme.id}-legendary.webp`;
}

function formFor(theme: ThemeProfile, stage: string) { return theme.forms.find((form) => form.stage === stage) ?? theme.forms[0]!; }

function taxonomy(theme: ThemeProfile): string {
  return theme.tags.slice(0, 2).join(" · ");
}

function renderState(state: PublicPetState): void {
  data = { ...data, ...state };
  const pet = state.pet;
  const customStageIndex = state.customTemplate
    ? Math.max(0, Math.min(state.customTemplate.stages.length - 1, state.customTemplate.stages.filter((stage) => pet.experience >= stage.experienceThreshold).length - 1))
    : undefined;
  const form = state.customTemplate && customStageIndex !== undefined
    ? state.customTemplate.stages[customStageIndex]
    : formFor(state.activeTheme, pet.stage);
  $("#hero-pet").setAttribute("src", state.assetURL);
  $("#hero-lineage").textContent = state.customTemplate?.name ?? state.activeTheme.displayName;
  $("#hero-form").textContent = form?.name ?? "Current form";
  $("#hero-stage").textContent = state.customTemplate && customStageIndex !== undefined
    ? `STAGE ${customStageIndex + 1} / ${state.customTemplate.stages.length}`
    : pet.stage.toUpperCase();
  $("#hero-level").textContent = `${pet.experience} XP`;
  const progress = Math.round((state.customTemplate
    ? customStageProgress(state.customTemplate.stages.map((stage) => stage.experienceThreshold), pet.experience)
    : stageProgress(pet)) * 100);
  setProgress("#stage-progress", progress);
  const liveProviders = [...new Set(pet.activityFeed.filter((item) => item.status === "running").map((item) => item.provider === "claude" ? "Claude Code" : "Codex"))];
  const status = pet.isSleeping ? "Sleeping" : pet.codexActivity === "idle" ? "Resting" : pet.codexActivity === "running" ? `${liveProviders.join(" + ") || "Agent"} working` : pet.codexActivity === "completed" ? "Task complete" : "Task needs attention";
  $("#hero-status").textContent = status;
  $("#hero-status-dot").className = `status-dot ${pet.isSleeping ? "sleeping" : pet.codexActivity}`;
  const wellbeing = Math.round((pet.stats.hunger + pet.stats.mood + pet.stats.energy) / 3);
  $("#wellbeing").textContent = `${wellbeing}%`;
  for (const key of ["hunger", "mood", "energy"] as const) {
    $(`#${key}-value`).textContent = String(Math.round(pet.stats[key]));
    setProgress(`#${key}-meter`, pet.stats[key]);
  }
  $("#sleep-label").textContent = pet.isSleeping ? "Wake" : "Sleep";
  $$<HTMLButtonElement>("[data-care]").forEach((button) => {
    const action = button.dataset.care as keyof PublicPetState["careAvailability"];
    const availability = state.careAvailability[action];
    button.disabled = !availability.available;
    button.title = availability.reason ?? "";
    button.setAttribute("aria-disabled", String(!availability.available));
  });
  $("#activity-feed").innerHTML = activityHTML(pet.activityFeed, 3);
  $("#codex-activity-feed").innerHTML = activityHTML(pet.activityFeed, 5);
  $<HTMLInputElement>("#pet-visible").checked = state.settings.petVisible;
  $<HTMLInputElement>("#launch-at-login").checked = state.settings.launchAtLogin;
  $<HTMLInputElement>("#monitor-session-logs").checked = state.settings.monitorSessionLogs;
  $<HTMLInputElement>("#click-through-transparency").checked = state.settings.clickThroughTransparency;
  $("#growth-summary").textContent = `${state.temperament.toUpperCase()} · ${pet.currentStreak} DAY${pet.currentStreak === 1 ? "" : "S"} STREAK`;
  $("#growth-journal").innerHTML = pet.growthJournal.length
    ? pet.growthJournal.slice(-6).reverse().map((entry) => `<article><i class="${entry.type}"></i><div><strong>${escapeHTML(entry.title)}</strong><small>${escapeHTML(entry.detail)}</small></div><time>${new Date(entry.timestamp).toLocaleDateString(undefined, { month: "short", day: "numeric" })}</time></article>`).join("")
    : '<div class="empty-state">Care for your Sidekin or complete an agent task to begin its journal.</div>';
  renderEvolution();
  $$(".lineage-card").forEach((card) => card.classList.toggle("active", card.dataset.theme === state.activeTheme.id && !pet.wardrobe.customTemplateID));
}

function customStageProgress(thresholds: number[], experience: number): number {
  if (thresholds.length <= 1) return 1;
  let index = 0;
  thresholds.forEach((threshold, candidate) => { if (experience >= threshold) index = candidate; });
  if (index >= thresholds.length - 1) return 1;
  const current = thresholds[index] ?? 0;
  const next = thresholds[index + 1] ?? current;
  return next > current ? Math.min(1, Math.max(0, (experience - current) / (next - current))) : 0;
}

function renderEvolution(): void {
  if (data.customTemplate) {
    const currentIndex = Math.max(0, data.customTemplate.stages.filter((stage) => data.pet.experience >= stage.experienceThreshold).length - 1);
    $("#evolution-strip").className = `evolution-strip stage-count-${data.customTemplate.stages.length}`;
    $("#evolution-strip").innerHTML = data.customTemplate.stages.map((stage, index) => {
      const src = new URL(stage.assetFileName, data.assetURL).href;
      return `<div class="evolution-form ${index === currentIndex ? "active" : ""}"><img src="${escapeHTML(src)}" alt="${escapeHTML(stage.name)}"><strong>${escapeHTML(stage.name)}</strong><small>STAGE ${index + 1}</small></div>`;
    }).join("");
    return;
  }
  const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];
  $("#evolution-strip").className = "evolution-strip";
  $("#evolution-strip").innerHTML = stages.map((stage) => {
    const form = formFor(data.activeTheme, stage);
    const current = data.pet.stage === stage;
    const src = asset(data.activeTheme, stage);
    return `<div class="evolution-form ${current ? "active" : ""}"><img src="${src}" alt="${escapeHTML(form.name)}"><strong>${escapeHTML(form.name)}</strong><small>${stage.toUpperCase()}</small></div>`;
  }).join("");
}

function renderLineages(filter = ""): void {
  const query = filter.trim().toLowerCase();
  const themes = data.catalog.filter((theme) => [
    theme.displayName,
    taxonomy(theme),
    ...theme.tags,
    theme.existenceAnchor,
    theme.artStyle
  ].join(" ").toLowerCase().includes(query));
  $("#lineage-grid").innerHTML = themes.map((theme) => `
    <button class="lineage-card ${theme.id === data.activeTheme.id && !data.pet.wardrobe.customTemplateID ? "active" : ""}" data-theme="${theme.id}">
      <img loading="lazy" decoding="async" src="${thumbnail(theme)}" alt="${escapeHTML(theme.displayName)} legendary form">
      <strong>${escapeHTML(theme.displayName)}</strong><small>${escapeHTML(taxonomy(theme))}</small>
    </button>`).join("");
  $$(".lineage-card").forEach((card) => card.addEventListener("click", () => void run(async () => renderState(await window.sidekin.selectTheme(card.dataset.theme!)), "Lineage selected.")));
}

function renderManagement(): void {
  $("#job-list").innerHTML = data.jobs.length ? data.jobs.map((job) => `
    <article class="management-item recovery-item">
      <div class="management-heading"><div><strong>${escapeHTML(job.request.templateName)}</strong><small>${job.completedStageCount} / ${job.request.stageNames.length} cutouts saved · ${job.state}</small></div><button data-resume="${job.id}">Continue</button></div>
      ${job.errorMessage ? `<p class="management-error">${escapeHTML(job.errorMessage)}</p>` : ""}
      <div class="recovery-stage-grid">${job.stageViews.map((stage) => `
        <section class="recovery-stage">
          <header><strong>${stage.index + 1}. ${escapeHTML(stage.name)}</strong><small>${stage.complete ? "READY" : stage.rawURL ? "RAW SAVED" : "NOT REQUESTED"}</small></header>
          <div class="preview-pair">
            ${stage.rawURL ? `<figure><img src="${escapeHTML(stage.rawURL)}" alt="Raw ${escapeHTML(stage.name)}"><figcaption>PAID RAW</figcaption></figure>` : '<figure class="preview-empty"><span>—</span><figcaption>NO RAW</figcaption></figure>'}
            ${stage.processedURL ? `<figure><img src="${escapeHTML(stage.processedURL)}" alt="Cutout ${escapeHTML(stage.name)}"><figcaption>CUTOUT</figcaption></figure>` : '<figure class="preview-empty"><span>—</span><figcaption>NO CUTOUT</figcaption></figure>'}
          </div>
          <div class="management-actions">${stage.rawURL ? `<button data-reprocess-job="${job.id}" data-stage="${stage.index}">Retry cutout free</button>` : ""}<button data-restart-job="${job.id}" data-stage="${stage.index}">Restart here</button></div>
        </section>`).join("")}</div>
    </article>`).join("") : '<div class="empty-state">No interrupted jobs.</div>';
  $("#template-list").innerHTML = data.templates.length ? data.templates.map((template) => `
    <article class="management-item template-item">
      <div class="management-heading"><div><strong>${escapeHTML(template.name)}</strong><small>${template.stages.length} stages · ${template.generationQuality ?? "medium"}</small></div><div class="management-actions"><button data-use-template="${template.id}">Use</button><button data-rename-template="${template.id}">Rename</button><button data-export-template="${template.id}">Export</button><button data-delete-template="${template.id}">Delete</button></div></div>
      <div class="template-stage-grid">${template.stageViews.map((view) => {
        const stage = template.stages[view.index]!;
        return `<section class="template-stage"><img src="${escapeHTML(view.assetURL)}" alt="${escapeHTML(stage.name)}"><strong>${escapeHTML(stage.name)}</strong><div class="management-actions"><button data-replace-template="${template.id}" data-stage="${view.index}">Replace</button><button data-regenerate-template="${template.id}" data-stage="${view.index}">Regenerate</button>${view.recoveryRawURL ? `<button data-reprocess-template="${template.id}" data-stage="${view.index}">Retry saved raw free</button>` : ""}</div>${view.recoveryRawURL ? `<figure class="recovery-raw"><img src="${escapeHTML(view.recoveryRawURL)}" alt="Saved paid recovery"><figcaption>PAID RAW RECOVERY</figcaption></figure>` : ""}</section>`;
      }).join("")}</div>
    </article>`).join("") : '<div class="empty-state">No custom templates installed.</div>';
  $$<HTMLButtonElement>("[data-resume]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const job = data.jobs.find((candidate) => candidate.id === button.dataset.resume);
    if (!job) return false;
    const newRequests = job.stageViews.filter((stage) => !stage.rawURL).length;
    if (newRequests && !window.confirm(`Continue ${newRequests} new image request${newRequests === 1 ? "" : "s"}? Estimated output: $${(qualityCost(job.request.quality) * newRequests).toFixed(3)}, excluding reference input cost. Your own API account is charged.`)) return false;
    await window.sidekin.resumeGeneration(job.id); data = await window.sidekin.bootstrap(); renderAll();
    return true;
  }, (completed) => completed ? "Generation completed." : undefined)));
  $$<HTMLButtonElement>("[data-reprocess-job]").forEach((button) => button.addEventListener("click", () => void run(async () => { await window.sidekin.reprocessJobStage(button.dataset.reprocessJob!, Number(button.dataset.stage)); data = await window.sidekin.bootstrap(); renderAll(); }, "Saved paid image reprocessed locally with no API call.")));
  $$<HTMLButtonElement>("[data-restart-job]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    if (!window.confirm("Clear this stage and every later saved recovery stage? A future Continue may create new paid requests.")) return false;
    await window.sidekin.restartJobFromStage(button.dataset.restartJob!, Number(button.dataset.stage)); data = await window.sidekin.bootstrap(); renderAll();
    return true;
  }, (restarted) => restarted ? "Recovery restarted from the selected stage." : undefined)));
  $$<HTMLButtonElement>("[data-use-template]").forEach((button) => button.addEventListener("click", () => void run(async () => renderState(await window.sidekin.selectTemplate(button.dataset.useTemplate!)), "Custom template selected.")));
  $$<HTMLButtonElement>("[data-export-template]").forEach((button) => button.addEventListener("click", () => void run(
    () => window.sidekin.exportTemplate(button.dataset.exportTemplate!),
    (exported) => exported ? "Template exported." : undefined
  )));
  $$<HTMLButtonElement>("[data-rename-template]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const template = data.templates.find((candidate) => candidate.id === button.dataset.renameTemplate);
    if (!template) return;
    const name = window.prompt("New template name", template.name);
    if (!name) return;
    await window.sidekin.renameTemplate(template.id, name);
    data = await window.sidekin.bootstrap(); renderAll();
  }, "Template renamed.")));
  $$<HTMLButtonElement>("[data-delete-template]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const template = data.templates.find((candidate) => candidate.id === button.dataset.deleteTemplate);
    if (!template || !window.confirm(`Permanently delete “${template.name}” and all of its local stage images? Export a Pet Pack first if you need a backup.`)) return false;
    await window.sidekin.deleteTemplate(template.id); data = await window.sidekin.bootstrap(); renderAll();
    return true;
  }, (deleted) => deleted ? "Template deleted." : undefined)));
  $$<HTMLButtonElement>("[data-replace-template]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const changed = await window.sidekin.replaceTemplateStage(button.dataset.replaceTemplate!, Number(button.dataset.stage));
    if (changed) { data = await window.sidekin.bootstrap(); renderAll(); }
    return changed;
  }, (changed) => changed ? "Stage replaced from a local image." : undefined)));
  $$<HTMLButtonElement>("[data-regenerate-template]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const template = data.templates.find((candidate) => candidate.id === button.dataset.regenerateTemplate);
    if (!template) return false;
    const quality = template.generationQuality ?? "medium";
    if (!window.confirm(`Regenerate only this stage? Estimated output: $${qualityCost(quality).toFixed(3)}, excluding reference input cost. Your own API account is charged.`)) return false;
    await window.sidekin.regenerateTemplateStage(template.id, Number(button.dataset.stage)); data = await window.sidekin.bootstrap(); renderAll();
    return true;
  }, (regenerated) => regenerated ? "Stage regenerated and replaced." : undefined)));
  $$<HTMLButtonElement>("[data-reprocess-template]").forEach((button) => button.addEventListener("click", () => void run(async () => { await window.sidekin.reprocessTemplateStage(button.dataset.reprocessTemplate!, Number(button.dataset.stage)); data = await window.sidekin.bootstrap(); renderAll(); }, "Saved paid image reprocessed locally with no API call.")));
}

function renderAll(): void {
  $("#platform-pill").textContent = data.platform === "win32" ? "Windows desktop" : "macOS desktop";
  $("#key-status").textContent = data.hasAPIKey ? "Saved securely" : "Not saved";
  $("#key-status").classList.toggle("saved", data.hasAPIKey);
  renderIntegrations();
  renderState(data);
  renderLineages($<HTMLInputElement>("#lineage-search").value);
  renderManagement();
}

function renderIntegrations(): void {
  $("#integration-list").innerHTML = data.integrations.map((integration) => `
    <article class="integration-card ${integration.installed ? "installed" : ""}">
      <div><span class="status-dot ${integration.installed ? "completed" : "idle"}"></span><strong>${escapeHTML(integration.displayName)}</strong><small>${integration.mode === "hooks" ? integration.provider === "codex" ? "Hook added · approve it in /hooks if Codex requests review" : "Lifecycle hooks connected" : integration.mode === "session-fallback" ? "Best-effort read-only fallback" : "Not connected"}</small></div>
      <button class="${integration.installed ? "secondary-button" : "generate-button"}" data-integration="${integration.provider}" data-integration-action="${integration.installed ? "remove" : "install"}">${integration.installed ? "Remove" : "Connect"}</button>
      ${integration.lastError ? `<p>${escapeHTML(integration.lastError)}</p>` : ""}
    </article>`).join("");
  $("#hook-status").textContent = "Codex hooks: ~/.codex/hooks.json\nClaude Code settings: ~/.claude/settings.json\nCodex fallback: local sessions (optional)";
  $$<HTMLButtonElement>("[data-integration]").forEach((button) => button.addEventListener("click", () => void run(async () => {
    const provider = button.dataset.integration as AgentProvider;
    data.integrations = button.dataset.integrationAction === "install"
      ? await window.sidekin.installIntegration(provider)
      : await window.sidekin.uninstallIntegration(provider);
    renderIntegrations();
  }, `${button.dataset.integration === "claude" ? "Claude Code" : "Codex"} integration ${button.dataset.integrationAction === "install" ? "connected" : "removed"}; unrelated hooks were preserved.`)));
}

function updateCost(): void {
  const quality = $<HTMLSelectElement>("#generation-quality").value as GenerationQuality;
  const count = Number($<HTMLSelectElement>("#stage-count").value);
  const cost = qualityCost(quality) * count;
  $("#cost-estimate").textContent = `Estimated output: $${cost.toFixed(3)}`;
}

function qualityCost(quality: GenerationQuality): number {
  return { low: .006, medium: .053, high: .211 }[quality];
}

function stageNames(count: number): string[] {
  const canonical = ["Core Egg", "First Spark", "Shifting Form", "Ascension", "Crown Form"];
  const extended = ["Origin", "Hatchling", "Sprout", "Shifting Form", "Mature", "Ascension", "Transcendent", "Crown Form"];
  if (count === 1) return ["Complete Form"];
  if (count === 5) return canonical;
  return Array.from({ length: count }, (_, index) => extended[Math.round(index / (count - 1) * (extended.length - 1))]!);
}

function bind(): void {
  $$(".nav-item").forEach((button) => button.addEventListener("click", () => setTab(button.dataset.tab!)));
  $$<HTMLButtonElement>("[data-open-tab]").forEach((button) => button.addEventListener("click", () => setTab(button.dataset.openTab!)));
  $$<HTMLButtonElement>("[data-care]").forEach((button) => button.addEventListener("click", () => void run(async () => renderState(await window.sidekin.care(button.dataset.care as "feed" | "play" | "sleepOrWake")))));
  $<HTMLInputElement>("#lineage-search").addEventListener("input", (event) => renderLineages((event.target as HTMLInputElement).value));
  for (const selector of ["#generation-quality", "#stage-count"]) $(selector).addEventListener("change", updateCost);
  $("#choose-reference").addEventListener("click", () => void run(async () => { referenceSelection = await window.sidekin.chooseReference(); $("#reference-label").textContent = referenceSelection?.displayName ?? "No reference selected"; }));
  $("#save-key").addEventListener("click", () => void run(async () => { await window.sidekin.saveAPIKey($<HTMLInputElement>("#api-key").value); $<HTMLInputElement>("#api-key").value = ""; data.hasAPIKey = true; renderAll(); }, "API key encrypted by the operating system."));
  $("#remove-key").addEventListener("click", () => void run(async () => { await window.sidekin.removeAPIKey(); data.hasAPIKey = false; renderAll(); }, "Saved API key removed."));
  $("#generate-button").addEventListener("click", () => void run(async () => {
    const count = Number($<HTMLSelectElement>("#stage-count").value);
    const quality = $<HTMLSelectElement>("#generation-quality").value as GenerationQuality;
    if (!data.hasAPIKey) throw new Error("Save your own OpenAI API key before starting generation.");
    if (!window.confirm(`Generate ${count} stage${count === 1 ? "" : "s"}? Estimated output: $${(qualityCost(quality) * count).toFixed(3)}, excluding reference input cost. Your own API account is charged.`)) return false;
    await window.sidekin.startGeneration({
      templateName: $<HTMLInputElement>("#template-name").value,
      description: $<HTMLTextAreaElement>("#template-description").value,
      artDirection: $<HTMLInputElement>("#art-direction").value,
      mode: $<HTMLSelectElement>("#generation-mode").value as GenerationMode,
      quality,
      stageNames: stageNames(count),
      fallbackTheme: data.activeTheme.id,
      motionProfile: data.activeTheme.motionProfile,
      referenceToken: referenceSelection?.token ?? null
    });
    data = await window.sidekin.bootstrap(); renderAll();
    return true;
  }, (installed) => installed ? "Custom lineage installed." : undefined));
  $("#cancel-generation").addEventListener("click", () => void window.sidekin.cancelGeneration());
  $("#import-template").addEventListener("click", () => void run(async () => {
    const imported = await window.sidekin.importTemplate();
    if (imported) { data = await window.sidekin.bootstrap(); renderAll(); }
    return imported;
  }, (imported) => imported ? "Template imported." : undefined));
  $$<HTMLButtonElement>("[data-simulate]").forEach((button) => button.addEventListener("click", () => void run(async () => renderState(await window.sidekin.simulateActivity(button.dataset.simulate as any)))));
  $<HTMLInputElement>("#pet-visible").addEventListener("change", (event) => void run(async () => renderState(await window.sidekin.setPetVisible((event.target as HTMLInputElement).checked))));
  for (const [selector, key] of [["#launch-at-login", "launchAtLogin"], ["#monitor-session-logs", "monitorSessionLogs"], ["#click-through-transparency", "clickThroughTransparency"]] as const) {
    $<HTMLInputElement>(selector).addEventListener("change", (event) => void run(async () => renderState(await window.sidekin.setRuntimeSetting(key, (event.target as HTMLInputElement).checked))));
  }
  $("#clear-interrupted").addEventListener("click", () => void run(async () => renderState(await window.sidekin.clearInterruptedTasks()), "Interrupted task cards cleared."));
  $("#open-data").addEventListener("click", () => void window.sidekin.openUserData());
}

function renderProgress(progress: WorkshopProgress): void {
  $("#generation-progress").classList.remove("hidden");
  $("#progress-label").textContent = progress.message || progress.stageName;
  $("#progress-count").textContent = `${progress.completed} / ${progress.total}`;
  setProgress("#generation-meter", progress.total ? progress.completed / progress.total * 100 : 0);
  if (progress.state === "complete") window.setTimeout(() => $("#generation-progress").classList.add("hidden"), 1_500);
}

async function start(): Promise<void> {
  data = await window.sidekin.bootstrap();
  bind();
  renderAll();
  updateCost();
  window.sidekin.onState(renderState);
  window.sidekin.onProgress(renderProgress);
}

void start().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  const title = document.querySelector<HTMLElement>("#page-title");
  if (title) title.textContent = "Sidekin could not start";
  toast(`Local data could not be loaded: ${message}`, true);
});
