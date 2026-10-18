import type { Asset, AssetKind } from "../lib/assets";
import { store } from "./db";

export type { Asset, AssetKind };

export class AssetError extends Error {
  constructor(
    message: string,
    public status = 400,
  ) {
    super(message);
    this.name = "AssetError";
  }
}

const MAX_UPLOAD = 25 * 1024 * 1024;
const MAX_GENERATED = 200 * 1024 * 1024;

type Rule = { mime: string; kind: AssetKind; check: (b: Uint8Array) => boolean };
const starts = (b: Uint8Array, sig: number[], at = 0) => sig.every((v, i) => b[at + i] === v);
const ascii = (b: Uint8Array, from: number, to: number) => String.fromCharCode(...b.subarray(from, to));
const text = (b: Uint8Array) => !b.subarray(0, 8192).includes(0);
const zip = (b: Uint8Array) => starts(b, [0x50, 0x4b]);

const RULES: Record<string, Rule> = {
  png: { mime: "image/png", kind: "image", check: (b) => starts(b, [0x89, 0x50, 0x4e, 0x47]) },
  jpg: { mime: "image/jpeg", kind: "image", check: (b) => starts(b, [0xff, 0xd8, 0xff]) },
  jpeg: { mime: "image/jpeg", kind: "image", check: (b) => starts(b, [0xff, 0xd8, 0xff]) },
  webp: { mime: "image/webp", kind: "image", check: (b) => ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 12) === "WEBP" },
  gif: { mime: "image/gif", kind: "image", check: (b) => ascii(b, 0, 4) === "GIF8" },
  pdf: { mime: "application/pdf", kind: "document", check: (b) => ascii(b, 0, 5) === "%PDF-" },
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
  mp4: { mime: "video/mp4", kind: "video", check: (b) => ascii(b, 4, 8) === "ftyp" },
  webm: { mime: "video/webm", kind: "video", check: (b) => starts(b, [0x1a, 0x45, 0xdf, 0xa3]) },
};

const TEXT_EXTS = new Set(["txt", "md", "csv", "json", "html"]);
export const isTextExt = (ext: string) => TEXT_EXTS.has(ext);
export const supportedExtensions = () => Object.keys(RULES);

export function cleanName(raw: string): string {
  const base = raw.replace(/\\/g, "/").split("/").pop() ?? "";
  const n = base.replace(/[\u0000-\u001f\u007f<>:"|?*]/g, "").replace(/^\.+/, "").trim();
  return (n || "file").slice(0, 120);
}

const newId = () => Array.from(crypto.getRandomValues(new Uint8Array(16)), (x) => x.toString(16).padStart(2, "0")).join("");

export async function saveAsset(o: { name: string; data: Uint8Array; origin: "upload" | "generated" }): Promise<Asset> {
  const name = cleanName(o.name);
  const dot = name.lastIndexOf(".");
  const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
  const rule = RULES[ext];
  if (!rule) throw new AssetError(`Files of type ".${ext || "?"}" are not supported (allowed: ${supportedExtensions().join(", ")})`);
  const limit = o.origin === "upload" ? MAX_UPLOAD : MAX_GENERATED;
  if (o.data.length === 0) throw new AssetError("The file is empty");
  if (o.data.length > limit) throw new AssetError(`The file is larger than the ${Math.round(limit / 1048576)} MB limit`, 413);
  if (!rule.check(o.data)) throw new AssetError(`The content does not look like a valid .${ext} file`);
  const id = newId();
  await store().putBlob(id, o.data);
  const asset: Asset = { id, name, ext, mime: rule.mime, kind: rule.kind, size: o.data.length, origin: o.origin, createdAt: Date.now() };
  await store().update<Asset[]>("assets", [], (list) => [asset, ...list]);
  return asset;
}

export async function getAsset(id: string): Promise<Asset | undefined> {
  return (await store().get<Asset[]>("assets", [])).find((a) => a.id === id);
}

export async function readAssetData(id: string): Promise<{ asset: Asset; data: Uint8Array }> {
  const asset = await getAsset(id);
  const data = asset ? await store().getBlob(id) : undefined;
  if (!asset || !data) throw new AssetError("File not found", 404);
  return { asset, data };
}

export async function listAssets(o: { limit?: number; offset?: number; kind?: AssetKind } = {}): Promise<{ items: Asset[]; total: number }> {
  const all = (await store().get<Asset[]>("assets", [])).filter((a) => !o.kind || a.kind === o.kind);
  const limit = Math.min(Math.max(o.limit ?? 50, 1), 200);
  const offset = Math.max(o.offset ?? 0, 0);
  return { items: all.slice(offset, offset + limit), total: all.length };
}

export async function deleteAsset(id: string): Promise<boolean> {
  let found = false;
  await store().update<Asset[]>("assets", [], (list) => {
    found = list.some((a) => a.id === id);
    return list.filter((a) => a.id !== id);
  });
  if (found) await store().delBlob(id);
  return found;
}

export const bytesOf = async (blob: Blob) => new Uint8Array(await blob.arrayBuffer());
export const utf8 = (s: string) => new TextEncoder().encode(s);
export const fromUtf8 = (b: Uint8Array) => new TextDecoder().decode(b);

export function toBase64(b: Uint8Array): string {
  let s = "";
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s);
}
export const fromBase64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
export function sniffImage(b: Uint8Array): "png" | "jpg" | "webp" | null {
  if (b[0] === 0x89 && b[1] === 0x50) return "png";
  if (b[0] === 0xff && b[1] === 0xd8) return "jpg";
  if (ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 12) === "WEBP") return "webp";
  return null;
}
