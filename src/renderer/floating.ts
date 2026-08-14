import type { ActivityFeedItem, PublicPetState } from "../shared/types.js";

let state: PublicPetState;
let timer: number | undefined;
const $ = <T extends HTMLElement>(selector: string): T => document.querySelector<T>(selector)!;

function duration(item: ActivityFeedItem): string {
  const milliseconds = item.status === "running" ? Date.now() - new Date(item.startedAt).getTime() : item.durationMs ?? 0;
  const seconds = Math.max(0, Math.round(milliseconds / 1_000));
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function render(next: PublicPetState): void {
  state = next;
  $("#float-pet").setAttribute("src", next.assetURL);
  $("#pet-motion").className = `pet-motion ${next.motion}`;
  const status = next.pet.isSleeping ? "Sleeping" : next.pet.codexActivity === "idle" ? "Resting" : next.pet.codexActivity === "running" ? "Codex is working" : next.pet.codexActivity === "completed" ? "Task complete" : "Task needs attention";
  $("#float-status").textContent = status;
  $("#float-status-dot").className = next.pet.isSleeping ? "sleeping" : next.pet.codexActivity;
  $("#float-sleep").textContent = next.pet.isSleeping ? "☀" : "☾";
  const cards = next.pet.activityFeed.slice(-3).reverse();
  $("#float-task-stack").innerHTML = cards.map((item) => `<article class="float-task ${item.status}"><i></i><div><strong>${item.title.replaceAll("<", "&lt;")}</strong><small>${item.project.replaceAll("<", "&lt;")} · ${item.status}</small></div><time data-activity-id="${item.id}">${duration(item)}</time></article>`).join("");
  if (timer) window.clearInterval(timer);
  timer = window.setInterval(updateTimers, 1_000);
  updateTimers();
}

function updateTimers(): void {
  if (!state) return;
  for (const element of Array.from(document.querySelectorAll<HTMLElement>("[data-activity-id]"))) {
    const item = state.pet.activityFeed.find((candidate) => candidate.id === element.dataset.activityId);
    if (item) element.textContent = duration(item);
  }
  const running = [...state.pet.activityFeed].reverse().find((item) => item.status === "running");
  $("#float-timer").textContent = running ? duration(running) : "";
}

document.querySelectorAll<HTMLButtonElement>("[data-care]").forEach((button) => button.addEventListener("click", () => void window.sidekin.care(button.dataset.care as any).then(render)));
$("#open-center").addEventListener("click", () => void window.sidekin.openControlCenter());
document.querySelector(".pet-motion")?.addEventListener("dblclick", () => void window.sidekin.openControlCenter());

void window.sidekin.bootstrap().then(render);
window.sidekin.onState(render);
