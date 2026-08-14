import { contextBridge, ipcRenderer } from "electron";
import type {
  CareAction,
  CodexActivity,
  CustomPetTemplate,
  GenerationRequest,
  PublicPetState,
  WorkshopProgress
} from "../shared/types.js";

const stateListeners = new Map<(state: PublicPetState) => void, (_event: Electron.IpcRendererEvent, state: PublicPetState) => void>();
const progressListeners = new Map<(progress: WorkshopProgress) => void, (_event: Electron.IpcRendererEvent, progress: WorkshopProgress) => void>();

contextBridge.exposeInMainWorld("sidekin", {
  bootstrap: () => ipcRenderer.invoke("sidekin:bootstrap"),
  care: (action: CareAction) => ipcRenderer.invoke("sidekin:care", action),
  selectTheme: (themeID: string) => ipcRenderer.invoke("sidekin:select-theme", themeID),
  selectTemplate: (templateID: string | null) => ipcRenderer.invoke("sidekin:select-template", templateID),
  setPetVisible: (visible: boolean) => ipcRenderer.invoke("sidekin:set-visible", visible),
  simulateActivity: (activity: CodexActivity) => ipcRenderer.invoke("sidekin:simulate", activity),
  installHooks: () => ipcRenderer.invoke("sidekin:install-hooks"),
  uninstallHooks: () => ipcRenderer.invoke("sidekin:uninstall-hooks"),
  saveAPIKey: (key: string) => ipcRenderer.invoke("sidekin:save-key", key),
  removeAPIKey: () => ipcRenderer.invoke("sidekin:remove-key"),
  chooseReference: () => ipcRenderer.invoke("sidekin:choose-reference"),
  startGeneration: (request: GenerationRequest) => ipcRenderer.invoke("sidekin:start-generation", request),
  resumeGeneration: (jobID: string) => ipcRenderer.invoke("sidekin:resume-generation", jobID),
  reprocessJobStage: (jobID: string, stageIndex: number) => ipcRenderer.invoke("sidekin:reprocess-job-stage", jobID, stageIndex),
  restartJobFromStage: (jobID: string, stageIndex: number) => ipcRenderer.invoke("sidekin:restart-job-stage", jobID, stageIndex),
  cancelGeneration: () => ipcRenderer.invoke("sidekin:cancel-generation"),
  renameTemplate: (templateID: string, name: string): Promise<CustomPetTemplate> => ipcRenderer.invoke("sidekin:rename-template", templateID, name),
  deleteTemplate: (templateID: string) => ipcRenderer.invoke("sidekin:delete-template", templateID),
  importTemplate: () => ipcRenderer.invoke("sidekin:import-template"),
  exportTemplate: (templateID: string) => ipcRenderer.invoke("sidekin:export-template", templateID),
  replaceTemplateStage: (templateID: string, stageIndex: number) => ipcRenderer.invoke("sidekin:replace-template-stage", templateID, stageIndex),
  regenerateTemplateStage: (templateID: string, stageIndex: number) => ipcRenderer.invoke("sidekin:regenerate-template-stage", templateID, stageIndex),
  reprocessTemplateStage: (templateID: string, stageIndex: number) => ipcRenderer.invoke("sidekin:reprocess-template-stage", templateID, stageIndex),
  openUserData: () => ipcRenderer.invoke("sidekin:open-user-data"),
  openControlCenter: () => ipcRenderer.invoke("sidekin:open-control-center"),
  quit: () => ipcRenderer.invoke("sidekin:quit"),
  onState: (listener: (state: PublicPetState) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, state: PublicPetState) => listener(state);
    stateListeners.set(listener, wrapped);
    ipcRenderer.on("sidekin:state", wrapped);
    return () => {
      const current = stateListeners.get(listener);
      if (current) ipcRenderer.removeListener("sidekin:state", current);
      stateListeners.delete(listener);
    };
  },
  onProgress: (listener: (progress: WorkshopProgress) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, progress: WorkshopProgress) => listener(progress);
    progressListeners.set(listener, wrapped);
    ipcRenderer.on("sidekin:progress", wrapped);
    return () => {
      const current = progressListeners.get(listener);
      if (current) ipcRenderer.removeListener("sidekin:progress", current);
      progressListeners.delete(listener);
    };
  }
});
