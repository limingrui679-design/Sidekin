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
const MAX_RESPONSE_BYTES = 36 * 1024 * 1024;
const MAX_IMAGE_BYTES = 24 * 1024 * 1024;

export class OpenAIImageClient implements ImageClient {
  constructor(private readonly baseURL = "https://api.openai.com/v1") {}

  async generate(prompt: string, apiKey: string, quality: GenerationQuality): Promise<Buffer> {
    const response = await fetch(`${this.baseURL}/images/generations`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "gpt-image-2", prompt, size: "1024x1024", quality, n: 1 }),
      redirect: "error",
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
      redirect: "error",
      signal: AbortSignal.timeout(240_000)
    });
    return this.decode(response);
  }

  private async decode(response: Response): Promise<Buffer> {
    const requestID = response.headers.get("x-request-id");
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) throw new Error("The image service response is too large.");
    if (!response.body) throw new Error("The image service returned an empty response.");
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        throw new Error("The image service response is too large.");
      }
      chunks.push(value);
    }
    const body = Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))).toString("utf8");
    let object: ImageResponse & { error?: { message?: string } };
    try { object = JSON.parse(body) as typeof object; } catch { throw new Error("The image service returned an unrecognized response."); }
    const errorMessage = typeof object.error?.message === "string" ? object.error.message.replaceAll(/\p{Cc}/gu, " ").slice(0, 600) : undefined;
    if (!response.ok) throw new Error(`${errorMessage || `HTTP ${response.status}`}${requestID ? ` (Request ${requestID.slice(0, 160)})` : ""}`);
    const encoded = object.data?.[0]?.b64_json;
    if (!encoded || encoded.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw new Error("The image service did not return a valid image.");
    const image = Buffer.from(encoded, "base64");
    if (image.length < 32 || image.length > MAX_IMAGE_BYTES) throw new Error("The image service returned an invalid image size.");
    return image;
  }
}
