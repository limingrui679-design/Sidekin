import { describe, expect, it } from "vitest";
import { isMediaPathWithin, mediaURL, safeMediaComponent } from "../src/shared/media.js";

describe("media path boundaries", () => {
  it("accepts Windows descendants even when drive and directory casing differs", () => {
    expect(isMediaPathWithin(
      "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\Sidekin",
      "c:\\users\\runner~1\\AppData\\Local\\Temp\\Sidekin\\PetTemplates\\stage-01.png",
      "win32"
    )).toBe(true);
  });

  it("rejects siblings, parents, and absolute escapes", () => {
    expect(isMediaPathWithin("/tmp/sidekin", "/tmp/sidekin-other/stage.png", "darwin")).toBe(false);
    expect(isMediaPathWithin("/tmp/sidekin", "/tmp/stage.png", "linux")).toBe(false);
    expect(isMediaPathWithin("C:\\Sidekin", "D:\\stage.png", "win32")).toBe(false);
  });

  it("builds encoded media URLs from bounded components", () => {
    expect(safeMediaComponent("capture-template")).toBe("capture-template");
    expect(mediaURL("templates", "capture-template", "stage-01.png"))
      .toBe("sidekin-media://templates/capture-template/stage-01.png");
    expect(() => safeMediaComponent("../escape")).toThrow("Unsafe media identifier");
  });
});
