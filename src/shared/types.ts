export const PET_STAGES = ["egg", "hatchling", "juvenile", "ascended", "legendary"] as const;
export type PetStage = (typeof PET_STAGES)[number];

export const CODEX_ACTIVITIES = ["idle", "running", "completed", "failed"] as const;
export type CodexActivity = (typeof CODEX_ACTIVITIES)[number];
export const AGENT_PROVIDERS = ["codex", "claude"] as const;
export type AgentProvider = (typeof AGENT_PROVIDERS)[number];
export type AgentActivity = CodexActivity;
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
  status: Exclude<AgentActivity, "idle"> | "interrupted";
  provider?: AgentProvider;
  sessionID?: string;
  startedAt: string;
  updatedAt: string;
  durationMs?: number;
}

export type PetTemperament = "steady" | "playful" | "focused";

export interface GrowthJournalEntry {
  id: string;
  type: "care" | "task" | "evolution" | "milestone";
  title: string;
  detail: string;
  timestamp: string;
}

export interface CareAvailability {
  available: boolean;
  reason?: string;
  nextAvailableAt?: string;
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
  processedAgentSignals: string[];
  lastAgentSignalAt?: string | null;
  lastAgentSignalActivity?: AgentActivity | null;
  lastCareAt: Partial<Record<CareAction, string>>;
  activeTaskDays: string[];
  currentStreak: number;
  growthJournal: GrowthJournalEntry[];
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
  tags: string[];
  artStyle: string;
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
  packFormat?: "sidekin.pet-pack";
  minSidekinVersion?: string;
  id: string;
  name: string;
  author?: string;
  license?: string;
  motionProfile?: string;
  contentHashes?: Record<string, string>;
  basePrompt: string;
  artDirection: string;
  generationMode: GenerationMode;
  generationQuality?: GenerationQuality;
  referenceFileName?: string | null;
  createdAt: string;
  fallbackTheme: string;
  stages: CustomPetStageDefinition[];
}

export interface PublicCustomPetStage {
  index: number;
  name: string;
  experienceThreshold: number;
  assetFileName: string;
}

export interface PublicCustomPetTemplate {
  id: string;
  name: string;
  author?: string;
  license?: string;
  motionProfile?: string;
  generationQuality?: GenerationQuality;
  createdAt: string;
  stages: PublicCustomPetStage[];
}

export interface CustomPetTemplateView extends PublicCustomPetTemplate {
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
  motionProfile?: string;
  referenceToken?: string | null;
}

export interface StoredGenerationRequest extends Omit<GenerationRequest, "referenceToken"> {
  referencePath?: string | null;
}

export interface GenerationJob {
  schemaVersion: number;
  id: string;
  templateID: string;
  state: "ready" | "running" | "failed" | "cancelled";
  createdAt: string;
  updatedAt: string;
  request: StoredGenerationRequest;
  completedStages: CustomPetStageDefinition[];
  errorMessage?: string | null;
}

export interface GenerationJobView {
  id: string;
  state: GenerationJob["state"];
  request: Pick<StoredGenerationRequest, "templateName" | "quality" | "stageNames">;
  completedStageCount: number;
  errorMessage?: string | null;
  stageViews: Array<{
    index: number;
    name: string;
    rawURL?: string;
    processedURL?: string;
    complete: boolean;
  }>;
}

export interface PublicPetSnapshot {
  name: string;
  stats: PetStats;
  experience: number;
  stage: PetStage;
  isSleeping: boolean;
  codexActivity: CodexActivity;
  wardrobe: PetSnapshot["wardrobe"];
  currentStreak: number;
  growthJournal: GrowthJournalEntry[];
  activityFeed: Array<Omit<ActivityFeedItem, "sessionID">>;
}

export interface RuntimeSettings {
  petVisible: boolean;
  launchAtLogin: boolean;
  monitorSessionLogs: boolean;
  clickThroughTransparency: boolean;
  floatingBounds?: { x: number; y: number; width: number; height: number };
}

export interface PublicPetState {
  pet: PublicPetSnapshot;
  activeTheme: ThemeProfile;
  assetURL: string;
  thumbnailBaseURL: string;
  customTemplate?: PublicCustomPetTemplate | null;
  motion: PetMotion;
  temperament: PetTemperament;
  careAvailability: Record<CareAction, CareAvailability>;
  settings: RuntimeSettings;
}

export interface IntegrationStatus {
  provider: AgentProvider;
  displayName: string;
  installed: boolean;
  mode: "hooks" | "session-fallback" | "disconnected";
  lastEventAt?: string | null;
  lastError?: string | null;
}

export interface ReferenceSelection {
  token: string;
  displayName: string;
}

export interface BootstrapPayload extends PublicPetState {
  catalog: ThemeProfile[];
  templates: CustomPetTemplateView[];
  jobs: GenerationJobView[];
  integrations: IntegrationStatus[];
  hasAPIKey: boolean;
  platform: "darwin" | "win32" | "linux";
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
  installIntegration(provider: AgentProvider): Promise<IntegrationStatus[]>;
  uninstallIntegration(provider: AgentProvider): Promise<IntegrationStatus[]>;
  setRuntimeSetting(key: "launchAtLogin" | "monitorSessionLogs" | "clickThroughTransparency", value: boolean): Promise<PublicPetState>;
  clearInterruptedTasks(): Promise<PublicPetState>;
  saveAPIKey(key: string): Promise<boolean>;
  removeAPIKey(): Promise<boolean>;
  chooseReference(): Promise<ReferenceSelection | null>;
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
  setPointerInteractive(interactive: boolean): Promise<void>;
  quit(): Promise<void>;
  onState(listener: (state: PublicPetState) => void): () => void;
  onProgress(listener: (progress: WorkshopProgress) => void): () => void;
}

declare global {
  interface Window {
    sidekin: SidekinAPI;
  }
}
