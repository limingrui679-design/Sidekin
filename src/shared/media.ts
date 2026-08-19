export type MediaScope = "runtime" | "templates" | "jobs";

export function safeMediaComponent(value: string): string {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)) throw new Error("Unsafe media identifier.");
  return value;
}

export function mediaURL(scope: MediaScope, ...components: string[]): string {
  if (!components.length) throw new Error("Media URL requires a resource path.");
  return `sidekin-media://${scope}/${components.map((component) => encodeURIComponent(safeMediaComponent(component))).join("/")}`;
}
