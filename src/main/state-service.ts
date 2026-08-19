import { readFile } from "node:fs/promises";
import type {
  PetMotion,
  PetSnapshot,
  PublicCustomPetTemplate,
  PublicPetState,
  PublicPetSnapshot,
  RuntimeSettings,
  ThemeCatalog,
  ThemeProfile
} from "../shared/types.js";
import { advance, applyActivity, careAvailability, clearInterruptedTasks, makeDefaultSnapshot, migrateSnapshot, motionFor, performCare, temperamentFor } from "../shared/lifecycle.js";
import type { CodexActivityRecord } from "../shared/codex.js";
import type { SidekinPaths } from "./paths.js";
import { readJSON, writeJSON } from "./file-store.js";
import { TemplateStore } from "./template-store.js";
import { mediaURL } from "../shared/media.js";

const DEFAULT_SETTINGS: RuntimeSettings = {
  petVisible: true,
  launchAtLogin: false,
  monitorSessionLogs: false,
  clickThroughTransparency: true
};

function sanitizeSettings(raw: unknown): RuntimeSettings {
  const source = typeof raw === "object" && raw !== null && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : {};
  const bounds = typeof source.floatingBounds === "object" && source.floatingBounds !== null && !Array.isArray(source.floatingBounds)
    ? source.floatingBounds as Record<string, unknown>
    : undefined;
  const finite = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);
  const floatingBounds = bounds && finite(bounds.x) && finite(bounds.y) && finite(bounds.width) && finite(bounds.height)
    ? {
        x: Math.round(Math.min(100_000, Math.max(-100_000, bounds.x))),
        y: Math.round(Math.min(100_000, Math.max(-100_000, bounds.y))),
        width: Math.round(Math.min(1_200, Math.max(240, bounds.width))),
        height: Math.round(Math.min(1_200, Math.max(240, bounds.height)))
      }
    : undefined;
  return {
    petVisible: typeof source.petVisible === "boolean" ? source.petVisible : DEFAULT_SETTINGS.petVisible,
    launchAtLogin: typeof source.launchAtLogin === "boolean" ? source.launchAtLogin : DEFAULT_SETTINGS.launchAtLogin,
    monitorSessionLogs: typeof source.monitorSessionLogs === "boolean" ? source.monitorSessionLogs : DEFAULT_SETTINGS.monitorSessionLogs,
    clickThroughTransparency: typeof source.clickThroughTransparency === "boolean" ? source.clickThroughTransparency : DEFAULT_SETTINGS.clickThroughTransparency,
    floatingBounds
  };
}

export class StateService {
  pet!: PetSnapshot;
  settings!: RuntimeSettings;
  catalog!: ThemeProfile[];
  motion: PetMotion = "idle-float";
  private motionTimer?: NodeJS.Timeout;

  constructor(
    readonly paths: SidekinPaths,
    private readonly templates: TemplateStore,
    private readonly onChange: (state: PublicPetState) => void
  ) {}

  async initialize(): Promise<void> {
    const raw = await readJSON<unknown>(this.paths.state);
    this.pet = advance(raw ? migrateSnapshot(raw) : makeDefaultSnapshot());
    this.settings = sanitizeSettings(await readJSON<unknown>(this.paths.settings));
    const catalog = JSON.parse(await readFile(this.paths.catalog, "utf8")) as ThemeCatalog;
    if (!Array.isArray(catalog.themes) || catalog.themes.length === 0) throw new Error("The built-in lineage catalog is missing or invalid.");
    this.catalog = catalog.themes;
    if (!this.catalog.some((theme) => theme.id === this.pet.wardrobe.theme)) this.pet.wardrobe.theme = "nova";
    await this.persist();
    setInterval(() => void this.tick(), 60_000);
  }

  activeTheme(): ThemeProfile {
    return this.catalog.find((theme) => theme.id === this.pet.wardrobe.theme) ?? this.catalog[0]!;
  }

  private publicPet(): PublicPetSnapshot {
    return {
      name: this.pet.name,
      stats: { ...this.pet.stats },
      experience: this.pet.experience,
      stage: this.pet.stage,
      isSleeping: this.pet.isSleeping,
      codexActivity: this.pet.codexActivity,
      wardrobe: { ...this.pet.wardrobe },
      currentStreak: this.pet.currentStreak,
      growthJournal: this.pet.growthJournal.map((entry) => ({ ...entry })),
      activityFeed: this.pet.activityFeed.map((item, index) => {
        const { sessionID: _sessionID, id: _internalID, ...view } = item;
        return { ...view, id: `activity-${index}` };
      })
    };
  }

  private publicTemplate(template: Awaited<ReturnType<TemplateStore["load"]>>): PublicCustomPetTemplate | null {
    if (!template) return null;
    return {
      id: template.id,
      name: template.name,
      author: template.author,
      license: template.license,
      motionProfile: template.motionProfile,
      generationQuality: template.generationQuality,
      createdAt: template.createdAt,
      stages: template.stages.map((stage) => ({
        index: stage.index,
        name: stage.name,
        experienceThreshold: stage.experienceThreshold,
        assetFileName: stage.assetFileName
      }))
    };
  }

  async publicState(): Promise<PublicPetState> {
    const template = this.pet.wardrobe.customTemplateID
      ? await this.templates.load(this.pet.wardrobe.customTemplateID)
      : undefined;
    const stageIndex = template
      ? Math.min(template.stages.length - 1, this.customStageIndex(template.stages.map((stage) => stage.experienceThreshold)))
      : 0;
    const assetURL = template
      ? mediaURL("templates", template.id, template.stages[stageIndex]!.assetFileName)
      : mediaURL("runtime", "characters", `${this.activeTheme().id}-${this.pet.stage}.webp`);
    return {
      pet: this.publicPet(),
      activeTheme: this.activeTheme(),
      assetURL,
      thumbnailBaseURL: "sidekin-media://runtime/thumbnails/",
      customTemplate: this.publicTemplate(template),
      motion: this.motion,
      temperament: temperamentFor(this.pet),
      careAvailability: careAvailability(this.pet),
      settings: this.settings
    };
  }

  async care(action: "feed" | "play" | "sleepOrWake"): Promise<PublicPetState> {
    const previousStage = this.pet.stage;
    const result = performCare(this.pet, action);
    this.pet = result.snapshot;
    if (result.rewarded) this.setTransientMotion(previousStage !== this.pet.stage ? "evolve" : result.motion, previousStage !== this.pet.stage ? 3_800 : 2_800);
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async receive(record: CodexActivityRecord): Promise<void> {
    const previousStage = this.pet.stage;
    const result = applyActivity(this.pet, record.activity, {
      now: record.timestamp ?? new Date(), provider: record.provider, sessionID: record.sessionID, eventID: record.eventID, title: record.title, project: record.project
    });
    if (!result.applied) return;
    this.pet = result.snapshot;
    this.setTransientMotion(previousStage !== this.pet.stage ? "evolve" : result.motion, previousStage !== this.pet.stage ? 3_800 : 4_000);
    await this.persistAndBroadcast();
  }

  async selectTheme(id: string): Promise<PublicPetState> {
    if (!this.catalog.some((theme) => theme.id === id)) throw new Error("Unknown built-in lineage.");
    this.pet.wardrobe.theme = id;
    this.pet.wardrobe.customTemplateID = null;
    this.setTransientMotion("evolve", 2_500);
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async selectTemplate(id: string | null): Promise<PublicPetState> {
    if (id && !(await this.templates.load(id))) throw new Error("Template was not found.");
    this.pet.wardrobe.customTemplateID = id;
    this.setTransientMotion("evolve", 2_500);
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async setVisible(visible: boolean): Promise<PublicPetState> {
    this.settings.petVisible = visible;
    await writeJSON(this.paths.settings, this.settings);
    await this.broadcast();
    return this.publicState();
  }

  async setRuntimeSetting(key: "launchAtLogin" | "monitorSessionLogs" | "clickThroughTransparency", value: boolean): Promise<PublicPetState> {
    this.settings[key] = value;
    await writeJSON(this.paths.settings, this.settings);
    await this.broadcast();
    return this.publicState();
  }

  async clearInterrupted(): Promise<PublicPetState> {
    this.pet = clearInterruptedTasks(this.pet);
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async saveFloatingBounds(bounds: RuntimeSettings["floatingBounds"]): Promise<void> {
    this.settings = sanitizeSettings({ ...this.settings, floatingBounds: bounds });
    await writeJSON(this.paths.settings, this.settings);
  }

  private customStageIndex(thresholds: number[]): number {
    let index = 0;
    thresholds.forEach((threshold, candidate) => { if (this.pet.experience >= threshold) index = candidate; });
    return index;
  }

  private async tick(): Promise<void> {
    this.pet = advance(this.pet);
    this.motion = motionFor(this.pet);
    await this.persistAndBroadcast();
  }

  private setTransientMotion(motion: PetMotion, duration: number): void {
    if (this.motionTimer) clearTimeout(this.motionTimer);
    this.motion = motion;
    this.motionTimer = setTimeout(() => {
      this.motion = motionFor(this.pet);
      void this.broadcast();
    }, duration);
  }

  private async persist(): Promise<void> { await writeJSON(this.paths.state, this.pet); }
  private async persistAndBroadcast(): Promise<void> { await this.persist(); await this.broadcast(); }
  private async broadcast(): Promise<void> { this.onChange(await this.publicState()); }
}
