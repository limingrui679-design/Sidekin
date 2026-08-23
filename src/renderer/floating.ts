import type { ActivityFeedItem, PublicPetState } from "../shared/types.js";

let state: PublicPetState;
let timer: number | undefined;
const $ = <T extends HTMLElement>(selector: string): T => document.querySelector<T>(selector)!;
const escapeHTML = (value: string): string => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");

function duration(item: ActivityFeedItem): string {
  const milliseconds = item.status === "running" ? Date.now() - new Date(item.startedAt).getTime() : item.durationMs ?? 0;
  const seconds = Math.max(0, Math.round(milliseconds / 1_000));
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function render(next: PublicPetState): void {
  state = next;
  $("#float-pet").setAttribute("src", next.assetURL);
  const profile = (next.customTemplate?.motionProfile ?? next.activeTheme.motionProfile).replaceAll(/[^a-z0-9-]/gi, "-").toLowerCase();
  $("#pet-motion").className = `pet-motion ${next.motion} profile-${profile} temperament-${next.temperament}`;
  const latest = [...next.pet.activityFeed].reverse().find((item) => item.status !== "interrupted");
  const provider = latest?.provider === "claude" ? "Claude Code" : "Codex";
  const status = next.pet.isSleeping ? "Sleeping" : next.pet.codexActivity === "idle" ? "Resting" : next.pet.codexActivity === "running" ? `${provider} is working` : next.pet.codexActivity === "completed" ? `${provider} task complete` : `${provider} task needs attention`;
  $("#float-status").textContent = status;
  $("#float-status-dot").className = next.pet.isSleeping ? "sleeping" : next.pet.codexActivity;
  $("#float-sleep").textContent = next.pet.isSleeping ? "☀" : "☾";
  const cards = next.pet.activityFeed.slice(-3).reverse();
  $("#float-task-stack").innerHTML = cards.map((item) => `<article class="float-task ${item.status}"><i></i><div><strong>${escapeHTML(item.title)}</strong><small>${escapeHTML(item.project)} · ${item.provider === "claude" ? "Claude" : "Codex"} · ${item.status}</small></div><time data-activity-id="${escapeHTML(item.id)}">${duration(item)}</time></article>`).join("");
  document.querySelectorAll<HTMLButtonElement>("[data-care]").forEach((button) => {
    const action = button.dataset.care as "feed" | "play" | "sleepOrWake";
    const availability = next.careAvailability[action];
    button.disabled = !availability.available;
    button.title = availability.available ? action === "sleepOrWake" ? "Sleep or wake" : action[0]!.toUpperCase() + action.slice(1) : availability.reason ?? "Not ready";
  });
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

let pointerInteractive = false;
document.addEventListener("mousemove", (event) => {
  const target = document.elementFromPoint(event.clientX, event.clientY);
  const interactive = Boolean(target?.closest(".pet-motion,.quick-actions,.task-stack,.status-pill"));
  if (interactive === pointerInteractive) return;
  pointerInteractive = interactive;
  void window.sidekin.setPointerInteractive(interactive);
});
document.addEventListener("mouseleave", () => { pointerInteractive = false; void window.sidekin.setPointerInteractive(false); });

void window.sidekin.bootstrap().then(render);
window.sidekin.onState(render);
