import path from "node:path";

export type MediaScope = "runtime" | "templates" | "jobs";

export function safeMediaComponent(value: string): string {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)) throw new Error("Unsafe media identifier.");
  return value;
}

export function mediaURL(scope: MediaScope, ...components: string[]): string {
  if (!components.length) throw new Error("Media URL requires a resource path.");
  return `sidekin-media://${scope}/${components.map((component) => encodeURIComponent(safeMediaComponent(component))).join("/")}`;
}

export function isMediaPathWithin(root: string, target: string, platform = process.platform): boolean {
  const implementation = platform === "win32" ? path.win32 : path.posix;
  const relative = implementation.relative(root, target);
  return Boolean(relative)
    && relative !== ".."
    && !relative.startsWith(`..${implementation.sep}`)
    && !implementation.isAbsolute(relative);
}
