import { AssetError, getAsset, readAssetData, saveAsset, fromUtf8, utf8, type Asset } from "./assets";
import { blocksToMarkdown, blocksToText, htmlToBlocks, isRtlText, parseCsv, parseMarkdown, readOfficeText, readXlsxRows, toCsv, writeDocx, writeEpub, writeHtml, writeXlsx, type Block } from "./docs";
import { convertImage, imagesToPdf, renderPdf } from "./pdf";

type Conversion = { from: string; to: string; note?: string; run: (asset: Asset, data: Uint8Array) => Promise<Uint8Array> };

const plainBlocks = (text: string): Block[] => text.split(/\n{2,}/).map((s) => s.trim()).filter(Boolean).map((s) => ({ t: "p", text: s }) as Block);

async function blocksOf(asset: Asset, data: Uint8Array): Promise<Block[]> {
  const e = asset.ext;
  if (e === "md") return parseMarkdown(fromUtf8(data));
  if (e === "txt") return plainBlocks(fromUtf8(data));
  if (e === "html") return htmlToBlocks(fromUtf8(data));
  if (e === "docx" || e === "odt" || e === "epub" || e === "pptx") return plainBlocks(await readOfficeText(e, data));
  throw new Error(`Cannot read .${e} files`);
}

const langOf = (blocks: Block[]) => (blocks.some((b) => (b.t === "p" || b.t === "h") && isRtlText(b.text.slice(0, 80))) ? "ar" : "en");
const titleOf = (asset: Asset) => asset.name.replace(/\.[^.]+$/, "") || "Document";

type Target = (blocks: Block[], asset: Asset) => Promise<Uint8Array> | Uint8Array;
const TARGETS: Record<string, Target> = {
  html: (b, a) => utf8(writeHtml(b, { title: titleOf(a), lang: langOf(b) })),
  docx: (b, a) => writeDocx(b, { title: titleOf(a), lang: langOf(b) }),
  epub: (b, a) => writeEpub(b, { title: titleOf(a), lang: langOf(b) }),
  pdf: (b, a) => renderPdf(b, { title: titleOf(a), lang: langOf(b) }),
  md: (b) => utf8(blocksToMarkdown(b)),
  txt: (b) => utf8(blocksToText(b)),
};

const via = (to: keyof typeof TARGETS) => async (asset: Asset, data: Uint8Array) => TARGETS[to](await blocksOf(asset, data), asset);

const SIMPLE = "formatting is simplified (text, headings and lists are kept)";
const fromTo = (from: string, tos: string[], note?: string): Conversion[] => tos.map((to) => ({ from, to, note, run: via(to) }));

const IMAGE_EXTS = ["png", "jpg", "jpeg", "webp", "gif"];

export const CONVERSIONS: Conversion[] = [
  ...fromTo("md", ["html", "docx", "epub", "pdf", "txt"]),
  ...fromTo("txt", ["html", "docx", "epub", "pdf", "md"]),
  ...fromTo("docx", ["txt", "md", "html", "pdf"], SIMPLE),
  ...fromTo("odt", ["docx", "pdf", "txt", "md"], SIMPLE),
  ...fromTo("html", ["docx", "md", "txt", "pdf"]),
  ...fromTo("epub", ["txt", "md"], SIMPLE),
  ...fromTo("pptx", ["txt"], "slide text only"),
  { from: "xlsx", to: "csv", note: "first sheet only", run: async (_a, d) => utf8(toCsv(await readXlsxRows(d))) },
  { from: "csv", to: "xlsx", run: async (_a, d) => writeXlsx(parseCsv(fromUtf8(d))) },
  ...IMAGE_EXTS.flatMap((from) =>
    (["png", "jpg", "webp"] as const)
      .filter((to) => to !== from && !(from === "jpeg" && to === "jpg"))
      .map((to) => ({ from, to, run: (a: Asset, d: Uint8Array) => convertImage(d, a.mime, to) }) as Conversion),
  ),
  ...IMAGE_EXTS.map((from) => ({ from, to: "pdf", note: "one image per page", run: (a: Asset, d: Uint8Array) => imagesToPdf([{ data: d, mime: a.mime }], titleOf(a)) }) as Conversion),
];

export const listConversions = () => CONVERSIONS.map((c) => ({ from: c.from, to: c.to, available: true, tool: "phone", ...(c.note ? { note: c.note } : {}) }));

export async function convertAsset(assetId: string, to: string): Promise<Asset> {
  const asset = await getAsset(assetId);
  if (!asset) throw new AssetError("File not found", 404);
  const conv = CONVERSIONS.find((c) => c.from === asset.ext && c.to === to);
  if (!conv) throw new AssetError(`Converting .${asset.ext} to .${to} is not supported`);
  const { data } = await readAssetData(assetId);
  const out = await conv.run(asset, data);
  if (!out.length) throw new Error("Conversion produced no output");
  return saveAsset({ name: `${titleOf(asset)}.${to}`, data: out, origin: "generated" });
}
