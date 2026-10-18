import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { maxGeneratedBytes, maxUploadBytes, retentionDays } from "./config";
import { filesDir, readJson, updateJson } from "./store";

export type AssetKind = "image" | "document" | "video";
export type Asset = { id: string; name: string; ext: string; mime: string; kind: AssetKind; size: number; origin: "upload" | "generated"; createdAt: number };

export class AssetError extends Error {
  constructor(
    message: string,
    public status = 400,
  ) {
    super(message);
    this.name = "AssetError";
  }
}

type Rule = { mime: string; kind: AssetKind; check: (b: Buffer) => boolean };
const starts = (b: Buffer, sig: number[], at = 0) => sig.every((v, i) => b[at + i] === v);
const text = (b: Buffer) => !b.subarray(0, 8192).includes(0);
const zip = (b: Buffer) => starts(b, [0x50, 0x4b]);

/**
 * Allow-list by extension; the content must also match (magic bytes), so a renamed file is refused.
 * SVG and HTML-like active content for images is deliberately NOT accepted as an image.
 */
const RULES: Record<string, Rule> = {
  png: { mime: "image/png", kind: "image", check: (b) => starts(b, [0x89, 0x50, 0x4e, 0x47]) },
  jpg: { mime: "image/jpeg", kind: "image", check: (b) => starts(b, [0xff, 0xd8, 0xff]) },
  jpeg: { mime: "image/jpeg", kind: "image", check: (b) => starts(b, [0xff, 0xd8, 0xff]) },
  webp: { mime: "image/webp", kind: "image", check: (b) => b.subarray(0, 4).toString("latin1") === "RIFF" && b.subarray(8, 12).toString("latin1") === "WEBP" },
  gif: { mime: "image/gif", kind: "image", check: (b) => b.subarray(0, 4).toString("latin1") === "GIF8" },
  pdf: { mime: "application/pdf", kind: "document", check: (b) => b.subarray(0, 5).toString("latin1") === "%PDF-" },
  docx: { mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", kind: "document", check: zip },
  xlsx: { mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", kind: "document", check: zip },
  pptx: { mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation", kind: "document", check: zip },
  odt: { mime: "application/vnd.oasis.opendocument.text", kind: "document", check: zip },
  epub: { mime: "application/epub+zip", kind: "document", check: zip },
  txt: { mime: "text/plain; charset=utf-8", kind: "document", check: text },
  md: { mime: "text/markdown; charset=utf-8", kind: "document", check: text },
  csv: { mime: "text/csv; charset=utf-8", kind: "document", check: text },
  json: { mime: "application/json", kind: "document", check: text },
  html: { mime: "text/html; charset=utf-8", kind: "document", check: text },
  mp4: { mime: "video/mp4", kind: "video", check: (b) => b.subarray(4, 8).toString("latin1") === "ftyp" },
  webm: { mime: "video/webm", kind: "video", check: (b) => starts(b, [0x1a, 0x45, 0xdf, 0xa3]) },
};

const TEXT_EXTS = new Set(["txt", "md", "csv", "json", "html"]);
export const isTextExt = (ext: string) => TEXT_EXTS.has(ext);
export const supportedExtensions = () => Object.keys(RULES);

const ID_RE = /^[a-f0-9]{32}$/;

/** Display name only (never used as a path): basename, no control characters, bounded length. */
export function cleanName(raw: string): string {
  const base = raw.replace(/\\/g, "/").split("/").pop() ?? "";
  const n = base.replace(/[\u0000-\u001f\u007f<>:"|?*]/g, "").replace(/^\.+/, "").trim();
  return (n || "file").slice(0, 120);
}

export async function saveAsset(o: { name: string; data: Buffer; origin: "upload" | "generated" }): Promise<Asset> {
  const name = cleanName(o.name);
  const ext = path.extname(name).slice(1).toLowerCase();
  const rule = RULES[ext];
  if (!rule) throw new AssetError(`Files of type ".${ext || "?"}" are not supported (allowed: ${supportedExtensions().join(", ")})`);
  const limit = o.origin === "upload" ? maxUploadBytes() : maxGeneratedBytes();
  if (o.data.length === 0) throw new AssetError("The file is empty");
  if (o.data.length > limit) throw new AssetError(`The file is larger than the ${Math.round(limit / 1048576)} MB limit`, 413);
  if (!rule.check(o.data)) throw new AssetError(`The content does not look like a valid .${ext} file`);
  const id = randomBytes(16).toString("hex");
  const dir = await filesDir();
  await fs.writeFile(path.join(dir, id), o.data, { mode: 0o600 });
  const asset: Asset = { id, name, ext, mime: rule.mime, kind: rule.kind, size: o.data.length, origin: o.origin, createdAt: Date.now() };
  await updateJson<Asset[]>("assets", [], (list) => [asset, ...list]);
  return asset;
}

export async function getAsset(id: string): Promise<Asset | undefined> {
  if (!ID_RE.test(id)) return undefined;
  return (await readJson<Asset[]>("assets", [])).find((a) => a.id === id);
}

export async function assetPath(id: string): Promise<string> {
  if (!ID_RE.test(id)) throw new AssetError("File not found", 404);
  return path.join(await filesDir(), id);
}

export async function readAssetData(id: string): Promise<{ asset: Asset; data: Buffer }> {
  const asset = await getAsset(id);
  if (!asset) throw new AssetError("File not found", 404);
  try {
    return { asset, data: await fs.readFile(await assetPath(id)) };
  } catch {
    throw new AssetError("File not found", 404);
  }
}

export async function listAssets(o: { limit?: number; offset?: number; kind?: AssetKind } = {}): Promise<{ items: Asset[]; total: number }> {
  const all = (await readJson<Asset[]>("assets", [])).filter((a) => !o.kind || a.kind === o.kind);
  const limit = Math.min(Math.max(o.limit ?? 50, 1), 200);
  const offset = Math.max(o.offset ?? 0, 0);
  return { items: all.slice(offset, offset + limit), total: all.length };
}

export async function deleteAsset(id: string): Promise<boolean> {
  if (!ID_RE.test(id)) return false;
  let found = false;
  await updateJson<Asset[]>("assets", [], (list) => {
    found = list.some((a) => a.id === id);
    return list.filter((a) => a.id !== id);
  });
  if (found) await fs.rm(await assetPath(id), { force: true });
  return found;
}

/** Deletes files older than the retention period (WAHA_RETENTION_DAYS; 0 = keep forever). */
export async function purgeExpired(now = Date.now()): Promise<number> {
  const days = retentionDays();
  if (!days) return 0;
  const cutoff = now - days * 86_400_000;
  const old = (await readJson<Asset[]>("assets", [])).filter((a) => a.createdAt < cutoff);
  for (const a of old) await deleteAsset(a.id);
  return old.length;
}
