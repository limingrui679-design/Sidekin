export const PET_STAGES = ["egg", "hatchling", "juvenile", "ascended", "legendary"] as const;
export type PetStage = (typeof PET_STAGES)[number];

export const CODEX_ACTIVITIES = ["idle", "running", "completed", "failed"] as const;
export type CodexActivity = (typeof CODEX_ACTIVITIES)[number];
export type CareAction = "feed" | "play" | "sleepOrWake";
export type PetMotion =
  | "idle-float"
  | "idle-look"
  | "idle-stretch"
  | "idle-hop"
  | "working-scan"
  | "working-run"
  | "celebrate"
  | "fail"
  | "feed"
  | "play"
  | "sleep"
  | "wake"
  | "evolve";

export interface PetStats {
  hunger: number;
  mood: number;
  energy: number;
}

export interface ActivityFeedItem {
  id: string;
  title: string;
  project: string;
  status: Exclude<CodexActivity, "idle">;
  startedAt: string;
  updatedAt: string;
  durationMs?: number;
}

export interface PetSnapshot {
  schemaVersion: number;
  name: string;
  createdAt: string;
  lastUpdatedAt: string;
  activityChangedAt: string;
  stats: PetStats;
  experience: number;
  stage: PetStage;
  isSleeping: boolean;
  codexActivity: CodexActivity;
  wardrobe: {
    theme?: string;
    customTemplateID?: string | null;
  };
  careAffinity: number;
  sparkAffinity: number;
  feedCount: number;
  playCount: number;
  restCount: number;
  completedTasks: number;
  failedTasks: number;
  processedCodexSignals: string[];
  lastCodexSignalAt?: string | null;
  lastCodexSignalActivity?: CodexActivity | null;
  activityFeed: ActivityFeedItem[];
}

export interface ThemeColor {
  red: number;
  green: number;
  blue: number;
}

export interface ThemeForm {
  stage: PetStage;
  name: string;
  introduction: string;
  visualAnchor: string;
}

export interface ThemeProfile {
  id: string;
  displayName: string;
  category?: string;
  tags?: string[];
  artStyle?: string;
  subtitle: string;
  lineageIntroduction: string;
  existenceAnchor: string;
  silhouetteAnchor: string;
  materialAnchor: string;
  energyAnchor: string;
  motionAnchor: string;
  motionProfile: string;
  accent: ThemeColor;
  secondaryAccent: ThemeColor;
  forms: ThemeForm[];
}

export interface ThemeCatalog {
  schemaVersion: number;
  themes: ThemeProfile[];
}

export type GenerationMode = "text" | "restyle" | "faithful";
export type GenerationQuality = "low" | "medium" | "high";

export interface CustomPetStageDefinition {
  id: string;
  index: number;
  name: string;
  prompt: string;
  experienceThreshold: number;
  assetFileName: string;
}

export interface CustomPetTemplate {
  schemaVersion: number;
  id: string;
  name: string;
  basePrompt: string;
  artDirection: string;
  generationMode: GenerationMode;
  generationQuality?: GenerationQuality;
  referenceFileName?: string | null;
  createdAt: string;
  fallbackTheme: string;
  stages: CustomPetStageDefinition[];
}

export interface CustomPetTemplateView extends CustomPetTemplate {
  stageViews: Array<{
    index: number;
    assetURL: string;
    recoveryRawURL?: string;
  }>;
}

export interface GenerationRequest {
  templateName: string;
  description: string;
  artDirection: string;
  mode: GenerationMode;
  quality: GenerationQuality;
  stageNames: string[];
  fallbackTheme: string;
  referencePath?: string | null;
}

export interface GenerationJob {
  schemaVersion: number;
  id: string;
  templateID: string;
  state: "ready" | "running" | "failed" | "cancelled";
  createdAt: string;
  updatedAt: string;
  request: GenerationRequest;
  completedStages: CustomPetStageDefinition[];
  errorMessage?: string | null;
}

export interface GenerationJobView extends GenerationJob {
  stageViews: Array<{
    index: number;
    name: string;
    rawURL?: string;
    processedURL?: string;
    complete: boolean;
  }>;
}

export interface RuntimeSettings {
  petVisible: boolean;
  launchAtLogin: boolean;
  monitorSessionLogs: boolean;
  floatingBounds?: { x: number; y: number; width: number; height: number };
}

export interface PublicPetState {
  pet: PetSnapshot;
  activeTheme: ThemeProfile;
  assetURL: string;
  customTemplate?: CustomPetTemplate | null;
  motion: PetMotion;
  settings: RuntimeSettings;
}

export interface BootstrapPayload extends PublicPetState {
  catalog: ThemeProfile[];
  templates: CustomPetTemplateView[];
  jobs: GenerationJobView[];
  hooksInstalled: boolean;
  hasAPIKey: boolean;
  platform: "darwin" | "win32" | "linux";
  paths: {
    userData: string;
    codexSessions: string;
    codexHooks: string;
  };
}

export interface WorkshopProgress {
  jobID: string;
  completed: number;
  total: number;
  stageName: string;
  state: GenerationJob["state"] | "complete";
  message?: string;
}

export interface SidekinAPI {
  bootstrap(): Promise<BootstrapPayload>;
  care(action: CareAction): Promise<PublicPetState>;
  selectTheme(themeID: string): Promise<PublicPetState>;
  selectTemplate(templateID: string | null): Promise<PublicPetState>;
  setPetVisible(visible: boolean): Promise<PublicPetState>;
  simulateActivity(activity: CodexActivity): Promise<PublicPetState>;
  installHooks(): Promise<boolean>;
  uninstallHooks(): Promise<boolean>;
  saveAPIKey(key: string): Promise<boolean>;
  removeAPIKey(): Promise<boolean>;
  chooseReference(): Promise<string | null>;
  startGeneration(request: GenerationRequest): Promise<CustomPetTemplate>;
  resumeGeneration(jobID: string): Promise<CustomPetTemplate>;
  reprocessJobStage(jobID: string, stageIndex: number): Promise<boolean>;
  restartJobFromStage(jobID: string, stageIndex: number): Promise<boolean>;
  cancelGeneration(): Promise<void>;
  renameTemplate(templateID: string, name: string): Promise<CustomPetTemplate>;
  deleteTemplate(templateID: string): Promise<boolean>;
  importTemplate(): Promise<CustomPetTemplate | null>;
  exportTemplate(templateID: string): Promise<boolean>;
  replaceTemplateStage(templateID: string, stageIndex: number): Promise<boolean>;
  regenerateTemplateStage(templateID: string, stageIndex: number): Promise<CustomPetTemplate>;
  reprocessTemplateStage(templateID: string, stageIndex: number): Promise<CustomPetTemplate>;
  openUserData(): Promise<void>;
  openControlCenter(): Promise<void>;
  quit(): Promise<void>;
  onState(listener: (state: PublicPetState) => void): () => void;
  onProgress(listener: (progress: WorkshopProgress) => void): () => void;
}

declare global {
  interface Window {
    sidekin: SidekinAPI;
  }
}
