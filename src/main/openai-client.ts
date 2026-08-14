import type { GenerationQuality } from "../shared/types.js";

export interface ImageInput {
  data: Buffer;
  fileName: string;
}

export interface ImageClient {
  generate(prompt: string, apiKey: string, quality: GenerationQuality): Promise<Buffer>;
  edit(prompt: string, images: ImageInput[], apiKey: string, quality: GenerationQuality): Promise<Buffer>;
}

interface ImageResponse { data?: Array<{ b64_json?: string }> }

export class OpenAIImageClient implements ImageClient {
  constructor(private readonly baseURL = "https://api.openai.com/v1") {}

  async generate(prompt: string, apiKey: string, quality: GenerationQuality): Promise<Buffer> {
    const response = await fetch(`${this.baseURL}/images/generations`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "gpt-image-2", prompt, size: "1024x1024", quality, n: 1 }),
      signal: AbortSignal.timeout(240_000)
    });
    return this.decode(response);
  }

  async edit(prompt: string, images: ImageInput[], apiKey: string, quality: GenerationQuality): Promise<Buffer> {
    if (!images.length) throw new Error("At least one image is required for editing.");
    const form = new FormData();
    form.set("model", "gpt-image-2");
    form.set("prompt", prompt);
    form.set("size", "1024x1024");
    form.set("quality", quality);
    for (const image of images) {
      form.append("image[]", new Blob([new Uint8Array(image.data)], { type: "image/png" }), image.fileName);
    }
    const response = await fetch(`${this.baseURL}/images/edits`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
      signal: AbortSignal.timeout(240_000)
    });
    return this.decode(response);
  }

  private async decode(response: Response): Promise<Buffer> {
    const requestID = response.headers.get("x-request-id");
    const body = await response.text();
    let object: ImageResponse & { error?: { message?: string } };
    try { object = JSON.parse(body) as typeof object; } catch { throw new Error("The image service returned an unrecognized response."); }
    if (!response.ok) throw new Error(`${object.error?.message || `HTTP ${response.status}`}${requestID ? ` (Request ${requestID})` : ""}`);
    const encoded = object.data?.[0]?.b64_json;
    if (!encoded) throw new Error("The image service did not return an image.");
    return Buffer.from(encoded, "base64");
  }
}
