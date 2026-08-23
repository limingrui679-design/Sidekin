import { afterEach, describe, expect, it, vi } from "vitest";
import { OpenAIImageClient } from "../src/main/openai-client.js";

afterEach(() => vi.unstubAllGlobals());

describe("bounded image API client", () => {
  it("accepts a bounded base64 image and refuses redirects", async () => {
    const image = Buffer.alloc(64, 7);
    const fetchMock = vi.fn<typeof fetch>(async (_url, options) => {
      expect(options?.redirect).toBe("error");
      return new Response(JSON.stringify({ data: [{ b64_json: image.toString("base64") }] }), {
        status: 200,
        headers: { "content-type": "application/json" }
      });
    });
    vi.stubGlobal("fetch", fetchMock);
    await expect(new OpenAIImageClient().generate("test", "user-key", "low")).resolves.toEqual(image);
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it("rejects an oversized response before buffering its body", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>(async () => new Response("{}", {
      status: 200,
      headers: { "content-length": String(40 * 1024 * 1024) }
    })));
    await expect(new OpenAIImageClient().generate("test", "user-key", "low")).rejects.toThrow(/too large/i);
  });

  it("rejects malformed base64 image data", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>(async () => new Response(JSON.stringify({ data: [{ b64_json: "not base64***" }] }), { status: 200 })));
    await expect(new OpenAIImageClient().generate("test", "user-key", "low")).rejects.toThrow(/valid image/i);
  });

  it("bounds provider errors while retaining a short request identifier", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>(async () => new Response(JSON.stringify({ error: { message: `Denied\n${"x".repeat(1_000)}` } }), {
      status: 400,
      headers: { "x-request-id": "request-123" }
    })));
    await expect(new OpenAIImageClient().generate("test", "user-key", "low")).rejects.toThrow(/Denied .*request-123/);
  });
});
