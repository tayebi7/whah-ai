/** PDF output on the phone: pages are drawn on a canvas (so Arabic is shaped by the browser) and embedded as JPEG images in a PDF. */
import { isRtlText, plainOf, type Block, type PageSize } from "./docs";

const enc = new TextEncoder();

/** Pure PDF writer: one full-page JPEG per page. */
export function writePdfFromJpegs(pages: { jpeg: Uint8Array; w: number; h: number }[], pt: [number, number], title = ""): Uint8Array {
  const chunks: Uint8Array[] = [];
  const offsets: number[] = [];
  let len = 0;
  const push = (d: Uint8Array | string) => {
    const b = typeof d === "string" ? enc.encode(d) : d;
    chunks.push(b);
    len += b.length;
  };
  const obj = (n: number, fn: () => void) => {
    offsets[n] = len;
    push(`${n} 0 obj\n`);
    fn();
    push("\nendobj\n");
  };
  const hexTitle = "FEFF" + [...title].map((c) => c.charCodeAt(0).toString(16).padStart(4, "0")).join("");
  push("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
  const n = pages.length;
  obj(1, () => push("<< /Type /Catalog /Pages 2 0 R >>"));
  obj(2, () => push(`<< /Type /Pages /Count ${n} /Kids [${pages.map((_p, i) => `${4 + i * 3} 0 R`).join(" ")}] >>`));
  obj(3, () => push(`<< /Title <${hexTitle}> /Producer (Waha AI) >>`));
  pages.forEach((p, i) => {
    const page = 4 + i * 3;
    obj(page, () => push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pt[0]} ${pt[1]}] /Resources << /XObject << /Im0 ${page + 2} 0 R >> >> /Contents ${page + 1} 0 R >>`));
    const content = `q ${pt[0]} 0 0 ${pt[1]} 0 0 cm /Im0 Do Q`;
    obj(page + 1, () => push(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`));
    obj(page + 2, () => {
      push(`<< /Type /XObject /Subtype /Image /Width ${p.w} /Height ${p.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n`);
      push(p.jpeg);
      push("\nendstream");
    });
  });
  const total = 4 + n * 3;
  const xref = len;
  push(`xref\n0 ${total}\n0000000000 65535 f \n`);
  for (let i = 1; i < total; i++) push(`${String(offsets[i]).padStart(10, "0")} 00000 n \n`);
  push(`trailer\n<< /Size ${total} /Root 1 0 R /Info 3 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  const out = new Uint8Array(len);
  let o = 0;
  for (const c of chunks) (out.set(c, o), (o += c.length));
  return out;
}

// ------------------------------------------------------------------ canvas helpers (browser only)

type Canvas2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;
export function makeCanvas(w: number, h: number): { canvas: HTMLCanvasElement | OffscreenCanvas; ctx: Canvas2D } {
  if (typeof OffscreenCanvas !== "undefined") {
    const canvas = new OffscreenCanvas(w, h);
    return { canvas, ctx: canvas.getContext("2d") as OffscreenCanvasRenderingContext2D };
  }
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  return { canvas, ctx: canvas.getContext("2d") as CanvasRenderingContext2D };
}

export async function canvasToBytes(canvas: HTMLCanvasElement | OffscreenCanvas, type: "image/png" | "image/jpeg" | "image/webp", quality = 0.85): Promise<Uint8Array> {
  const blob: Blob | null = "convertToBlob" in canvas ? await canvas.convertToBlob({ type, quality }) : await new Promise((res) => (canvas as HTMLCanvasElement).toBlob(res, type, quality));
  if (!blob) throw new Error("This device could not encode the image");
  return new Uint8Array(await blob.arrayBuffer());
}

export async function decodeImage(data: Uint8Array, mime = "image/png"): Promise<ImageBitmap> {
  return createImageBitmap(new Blob([data as unknown as BlobPart], { type: mime }));
}

export const FONT = '"Noto Naskh Arabic","Noto Sans Arabic","Droid Arabic Naskh","Segoe UI",system-ui,"Helvetica Neue",Arial,sans-serif';

const PX: Record<PageSize, [number, number]> = { A4: [1240, 1754], Letter: [1275, 1650], A5: [874, 1240] };
const PT: Record<PageSize, [number, number]> = { A4: [595, 842], Letter: [612, 792], A5: [420, 595] };

const mimeOf = (ext: string) => (ext === "png" ? "image/png" : ext === "webp" ? "image/webp" : "image/jpeg");

/** Typesets blocks onto pages (wrapping, headings, lists, images; right-to-left for Arabic text) and returns a PDF. */
export async function renderPdf(blocks: Block[], o: { title: string; lang: string; pageSize?: PageSize }): Promise<Uint8Array> {
  const size = o.pageSize ?? "A4";
  const [W, H] = PX[size];
  const M = Math.round(W * 0.09);
  const contentW = W - 2 * M;
  const pages: { jpeg: Uint8Array; w: number; h: number }[] = [];
  let cur = makeCanvas(W, H);
  let y = M;
  let empty = true;

  const fresh = () => {
    cur.ctx.fillStyle = "#ffffff";
    cur.ctx.fillRect(0, 0, W, H);
    cur.ctx.fillStyle = "#111111";
    y = M;
    empty = true;
  };
  const endPage = async () => {
    if (!empty) pages.push({ jpeg: await canvasToBytes(cur.canvas, "image/jpeg", 0.85), w: W, h: H });
    cur = makeCanvas(W, H);
    fresh();
  };
  fresh();

  const fontFor = (px: number, bold: boolean) => `${bold ? "700 " : ""}${px}px ${FONT}`;

  async function text(src: string, px: number, bold: boolean, opts: { indent?: number; after?: number; center?: boolean } = {}) {
    const t = plainOf(src);
    if (!t.trim()) return;
    const rtl = isRtlText(t.slice(0, 40)) || (o.lang === "ar" && isRtlText(t));
    const ctx = cur.ctx;
    ctx.font = fontFor(px, bold);
    const maxW = contentW - (opts.indent ?? 0);
    const lines: string[] = [];
    let line = "";
    for (const word of t.split(/\s+/)) {
      const test = line ? `${line} ${word}` : word;
      ctx.direction = rtl ? "rtl" : "ltr";
      if (line && ctx.measureText(test).width > maxW) {
        lines.push(line);
        line = word;
      } else line = test;
    }
    if (line) lines.push(line);
    const lh = Math.round(px * 1.55);
    for (const l of lines) {
      if (y + lh > H - M) await endPage();
      const c = cur.ctx;
      c.font = fontFor(px, bold);
      c.direction = rtl ? "rtl" : "ltr";
      c.textBaseline = "top";
      if (opts.center) {
        c.textAlign = "center";
        c.fillText(l, W / 2, y);
      } else if (rtl) {
        c.textAlign = "right";
        c.fillText(l, W - M - (opts.indent ?? 0), y);
      } else {
        c.textAlign = "left";
        c.fillText(l, M + (opts.indent ?? 0), y);
      }
      y += lh;
      empty = false;
    }
    y += opts.after ?? Math.round(px * 0.55);
  }

  let first = true;
  for (const b of blocks) {
    if (b.t === "h") {
      if (b.level === 1 && !first && !empty) await endPage();
      await text(b.text, b.level === 1 ? 56 : b.level === 2 ? 44 : 36, true, { after: 28 });
    } else if (b.t === "p") await text(b.text, 28, false);
    else if (b.t === "li") await text(`${b.n ? `${b.n}.` : "•"} ${b.text}`, 28, false, { indent: 30, after: 10 });
    else if (b.t === "hr") await text("* * *", 28, false, { center: true });
    else {
      const bmp = await decodeImage(b.data, mimeOf(b.ext));
      const scale = Math.min((contentW * 0.85) / bmp.width, (H - 2 * M) / bmp.height);
      const w = Math.round(bmp.width * scale);
      const h = Math.round(bmp.height * scale);
      if (y + h > H - M) await endPage();
      cur.ctx.drawImage(bmp, Math.round((W - w) / 2), y, w, h);
      y += h + 30;
      empty = false;
      bmp.close();
    }
    first = false;
  }
  if (!empty || pages.length === 0) {
    if (empty) cur.ctx.fillText(" ", 0, 0), (empty = false);
    pages.push({ jpeg: await canvasToBytes(cur.canvas, "image/jpeg", 0.85), w: W, h: H });
  }
  return writePdfFromJpegs(pages, PT[size], o.title);
}

/** One image (or several) as a PDF, each on its own page at the image's own aspect ratio. */
export async function imagesToPdf(images: { data: Uint8Array; mime: string }[], title = ""): Promise<Uint8Array> {
  const pages: { jpeg: Uint8Array; w: number; h: number }[] = [];
  for (const im of images) {
    const bmp = await decodeImage(im.data, im.mime);
    const scale = Math.min(1, 2000 / Math.max(bmp.width, bmp.height));
    const w = Math.round(bmp.width * scale);
    const h = Math.round(bmp.height * scale);
    const c = makeCanvas(w, h);
    c.ctx.fillStyle = "#fff";
    c.ctx.fillRect(0, 0, w, h);
    c.ctx.drawImage(bmp, 0, 0, w, h);
    bmp.close();
    pages.push({ jpeg: await canvasToBytes(c.canvas, "image/jpeg", 0.88), w, h });
  }
  const px = pages[0];
  return writePdfFromJpegs(pages, [595, Math.round((595 * px.h) / px.w)], title);
}

export async function convertImage(data: Uint8Array, fromMime: string, to: "png" | "jpg" | "webp"): Promise<Uint8Array> {
  const bmp = await decodeImage(data, fromMime);
  const c = makeCanvas(bmp.width, bmp.height);
  if (to === "jpg") {
    c.ctx.fillStyle = "#fff";
    c.ctx.fillRect(0, 0, bmp.width, bmp.height);
  }
  c.ctx.drawImage(bmp, 0, 0);
  bmp.close();
  return canvasToBytes(c.canvas, to === "png" ? "image/png" : to === "webp" ? "image/webp" : "image/jpeg", 0.92);
}

/** Shrinks big camera photos before they are sent to an AI provider. */
export async function shrinkImage(data: Uint8Array, mime: string, maxSide = 1600): Promise<{ data: Uint8Array; mime: string }> {
  const bmp = await decodeImage(data, mime);
  const scale = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
  const w = Math.max(1, Math.round(bmp.width * scale));
  const h = Math.max(1, Math.round(bmp.height * scale));
  const c = makeCanvas(w, h);
  c.ctx.fillStyle = "#fff";
  c.ctx.fillRect(0, 0, w, h);
  c.ctx.drawImage(bmp, 0, 0, w, h);
  bmp.close();
  return { data: await canvasToBytes(c.canvas, "image/jpeg", 0.85), mime: "image/jpeg" };
}
