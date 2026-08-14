import sharp from "sharp";

const OUTPUT_SIZE = 1_254;
const MAX_INPUT_BYTES = 24 * 1024 * 1024;

function distanceSquared(a: [number, number, number], b: [number, number, number]): number {
  return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
}

export async function normalizeReference(input: Buffer): Promise<Buffer> {
  if (input.length > MAX_INPUT_BYTES) throw new Error("Reference image is too large.");
  return sharp(input, { failOn: "error" })
    .rotate()
    .resize(1_536, 1_536, { fit: "inside", withoutEnlargement: true })
    .png({ compressionLevel: 8 })
    .toBuffer();
}

export async function prepareGeneratedAsset(input: Buffer): Promise<Buffer> {
  if (input.length > MAX_INPUT_BYTES) throw new Error("Generated image is too large.");
  const { data, info } = await sharp(input, { failOn: "error" })
    .rotate()
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  if (info.width < 32 || info.height < 32) throw new Error("Generated image is too small.");

  const pixel = (x: number, y: number): [number, number, number] => {
    const offset = (y * info.width + x) * 4;
    return [data[offset]!, data[offset + 1]!, data[offset + 2]!];
  };
  const corners: Array<[number, number, number]> = [
    pixel(0, 0), pixel(info.width - 1, 0), pixel(0, info.height - 1), pixel(info.width - 1, info.height - 1)
  ];
  const background: [number, number, number] = [
    Math.round(corners.reduce((sum, value) => sum + value[0], 0) / corners.length),
    Math.round(corners.reduce((sum, value) => sum + value[1], 0) / corners.length),
    Math.round(corners.reduce((sum, value) => sum + value[2], 0) / corners.length)
  ];

  const count = info.width * info.height;
  const visited = new Uint8Array(count);
  const queue = new Int32Array(count);
  let head = 0;
  let tail = 0;
  const seed = (x: number, y: number): void => {
    const index = y * info.width + x;
    if (visited[index]) return;
    const color = pixel(x, y);
    if (distanceSquared(color, background) <= 88 ** 2 || (color[0] > 205 && color[2] > 170 && color[1] < 100)) {
      visited[index] = 1;
      queue[tail++] = index;
    }
  };
  for (let x = 0; x < info.width; x += 1) { seed(x, 0); seed(x, info.height - 1); }
  for (let y = 0; y < info.height; y += 1) { seed(0, y); seed(info.width - 1, y); }
  while (head < tail) {
    const index = queue[head++]!;
    const x = index % info.width;
    const y = Math.floor(index / info.width);
    if (x > 0) seed(x - 1, y);
    if (x + 1 < info.width) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y + 1 < info.height) seed(x, y + 1);
  }

  let minX = info.width;
  let minY = info.height;
  let maxX = -1;
  let maxY = -1;
  let foreground = 0;
  for (let index = 0; index < count; index += 1) {
    const offset = index * 4;
    if (visited[index]) {
      data[offset + 3] = 0;
      continue;
    }
    const alpha = data[offset + 3]!;
    if (alpha > 20) {
      const x = index % info.width;
      const y = Math.floor(index / info.width);
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);
      foreground += 1;
    }
  }
  if (foreground < count * 0.02 || maxX < minX || maxY < minY) throw new Error("Background removal found no usable subject.");

  const padding = Math.round(Math.max(maxX - minX, maxY - minY) * 0.08);
  const left = Math.max(0, minX - padding);
  const top = Math.max(0, minY - padding);
  const width = Math.min(info.width - left, maxX - minX + 1 + padding * 2);
  const height = Math.min(info.height - top, maxY - minY + 1 + padding * 2);
  const subject = await sharp(data, { raw: info }).extract({ left, top, width, height }).png().toBuffer();
  return sharp({
    create: { width: OUTPUT_SIZE, height: OUTPUT_SIZE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } }
  }).composite([{ input: await sharp(subject).resize(1_080, 1_080, { fit: "inside" }).toBuffer(), gravity: "center" }])
    .png({ compressionLevel: 9 })
    .toBuffer();
}
