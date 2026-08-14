import { pathToFileURL } from "node:url";
import { readFile } from "node:fs/promises";
import type {
  PetMotion,
  PetSnapshot,
  PublicPetState,
  RuntimeSettings,
  ThemeCatalog,
  ThemeProfile
} from "../shared/types.js";
import { advance, applyActivity, makeDefaultSnapshot, migrateSnapshot, motionFor, performCare } from "../shared/lifecycle.js";
import type { CodexActivityRecord } from "../shared/codex.js";
import type { SidekinPaths } from "./paths.js";
import { readJSON, writeJSON } from "./file-store.js";
import { TemplateStore } from "./template-store.js";

const DEFAULT_SETTINGS: RuntimeSettings = {
  petVisible: true,
  launchAtLogin: false,
  monitorSessionLogs: true
};

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
    const raw = await readJSON<Partial<PetSnapshot>>(this.paths.state);
    this.pet = advance(raw ? migrateSnapshot(raw) : makeDefaultSnapshot());
    this.settings = { ...DEFAULT_SETTINGS, ...(await readJSON<RuntimeSettings>(this.paths.settings) ?? {}) };
    this.catalog = (JSON.parse(await readFile(this.paths.catalog, "utf8")) as ThemeCatalog).themes;
    if (!this.catalog.some((theme) => theme.id === this.pet.wardrobe.theme)) this.pet.wardrobe.theme = "nova";
    await this.persist();
    setInterval(() => void this.tick(), 60_000);
  }

  activeTheme(): ThemeProfile {
    return this.catalog.find((theme) => theme.id === this.pet.wardrobe.theme) ?? this.catalog[0]!;
  }

  async publicState(): Promise<PublicPetState> {
    const template = this.pet.wardrobe.customTemplateID
      ? await this.templates.load(this.pet.wardrobe.customTemplateID)
      : undefined;
    const asset = template
      ? this.templates.assetPath(template, Math.min(template.stages.length - 1, this.customStageIndex(template.stages.map((stage) => stage.experienceThreshold))))
      : `${this.activeTheme().id}-${this.pet.stage}.png`;
    const assetPath = template ? asset : `${this.paths.characters}/${asset}`;
    return {
      pet: this.pet,
      activeTheme: this.activeTheme(),
      assetURL: pathToFileURL(assetPath).href,
      customTemplate: template ?? null,
      motion: this.motion,
      settings: this.settings
    };
  }

  async care(action: "feed" | "play" | "sleepOrWake"): Promise<PublicPetState> {
    const previousStage = this.pet.stage;
    const result = performCare(this.pet, action);
    this.pet = result.snapshot;
    this.setTransientMotion(previousStage !== this.pet.stage ? "evolve" : result.motion, previousStage !== this.pet.stage ? 3_800 : 2_800);
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async receive(record: CodexActivityRecord): Promise<void> {
    const previousStage = this.pet.stage;
    const result = applyActivity(this.pet, record.activity, {
      now: record.timestamp ?? new Date(), eventID: record.eventID, title: record.title, project: record.project
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

  async setCosmetic(slot: "hat" | "face" | "aura", value: string): Promise<PublicPetState> {
    if (!/^[a-z0-9-]{1,32}$/.test(value)) throw new Error("Invalid cosmetic value.");
    this.pet.cosmetics[slot] = value;
    await this.persistAndBroadcast();
    return this.publicState();
  }

  async setVisible(visible: boolean): Promise<PublicPetState> {
    this.settings.petVisible = visible;
    await writeJSON(this.paths.settings, this.settings);
    await this.broadcast();
    return this.publicState();
  }

  async saveFloatingBounds(bounds: RuntimeSettings["floatingBounds"]): Promise<void> {
    this.settings.floatingBounds = bounds;
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
