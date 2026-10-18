import { fileBase, LANG_NAMES, planAndWrite, type BookFormat, type BookInput } from "../lib/books-core";
import { capabilitiesOf, type Provider } from "../lib/providers-core";
import { type Asset, readAssetData, saveAsset, utf8 } from "./assets";
import { parseMarkdown, writeDocx, writeEpub, type Block } from "./docs";
import { generateImages } from "./images";
import type { JobContext } from "./jobs";
import { renderPdf } from "./pdf";

const imgExt = (a: Asset) => (a.ext === "jpeg" ? "jpg" : a.ext) as "png" | "jpg" | "webp";

/** Outline -> chapters -> illustrations -> DOCX / PDF / EPUB / MD, all produced on the phone. */
export async function runBook(input: BookInput, providers: Provider[], ctx: JobContext): Promise<string[]> {
  const warn = (m: string) => ctx.warn(m);
  const made: Asset[] = [];
  const { plan, bodies } = await planAndWrite(input, providers, ctx);

  const images = new Map<string, Asset>();
  const wantImages = input.illustrate || input.cover;
  const canImage = providers.some((p) => p.enabled && capabilitiesOf(p).image);
  if (wantImages && !canImage) warn("No image provider is configured, so the book has no illustrations or cover. Add one in Settings.");
  if (wantImages && canImage) {
    const style = input.style || (input.kind === "story" ? "soft watercolor children's book illustration" : "clean, modern editorial illustration");
    const jobs: { key: string; prompt: string; label: string }[] = [];
    if (input.cover) jobs.push({ key: "cover", label: "cover", prompt: `${style}. Book cover for "${plan.title}". ${plan.characters} No text, no letters.` });
    if (input.illustrate) plan.chapters.forEach((c, i) => jobs.push({ key: `ch${i + 1}`, label: `chapter ${i + 1}`, prompt: `${style}. ${c.illustration}. ${plan.characters} No text, no letters.` }));
    for (let i = 0; i < jobs.length; i++) {
      if (ctx.signal.aborted) throw new Error("cancelled");
      ctx.setProgress(55 + (25 * i) / jobs.length, `Drawing ${jobs[i].label}`);
      try {
        const r = await generateImages(providers, { prompt: jobs[i].prompt.slice(0, 1800), n: 1, size: "1024x1024", signal: ctx.signal });
        images.set(jobs[i].key, r.assets[0]);
        made.push(r.assets[0]);
      } catch (e) {
        if (ctx.signal.aborted) throw new Error("cancelled");
        warn(`The ${jobs[i].label} illustration failed: ${(e as Error).message}`);
      }
    }
  }

  ctx.setProgress(82, "Building the files");
  const base = fileBase(plan.title);
  const outputs: Asset[] = [];
  const blocks: Block[] = [];
  const cover = images.get("cover");
  if (cover) blocks.push({ t: "img", data: (await readAssetData(cover.id)).data, ext: imgExt(cover) });
  blocks.push({ t: "h", level: 1, text: plan.title });
  for (let i = 0; i < plan.chapters.length; i++) {
    blocks.push({ t: "h", level: 2, text: plan.chapters[i].title });
    const a = images.get(`ch${i + 1}`);
    if (a) blocks.push({ t: "img", data: (await readAssetData(a.id)).data, ext: imgExt(a) });
    blocks.push(...parseMarkdown(bodies[i]));
  }
  const meta = { title: plan.title, lang: input.language };
  const need = (f: BookFormat) => input.formats.includes(f);
  if (need("docx")) outputs.push(await saveAsset({ name: `${base}.docx`, data: writeDocx(blocks, { ...meta, pageSize: input.pageSize }), origin: "generated" }));
  if (need("pdf")) {
    ctx.setProgress(88, "Typesetting the PDF");
    outputs.push(await saveAsset({ name: `${base}.pdf`, data: await renderPdf(blocks, { ...meta, pageSize: input.pageSize }), origin: "generated" }));
  }
  if (need("epub")) {
    const c = cover ? { data: (await readAssetData(cover.id)).data, ext: imgExt(cover) } : undefined;
    outputs.push(await saveAsset({ name: `${base}.epub`, data: writeEpub(blocks.filter((b, i) => !(i === 0 && cover && b.t === "img")), { ...meta, cover: c }), origin: "generated" }));
  }
  if (need("md")) {
    const textOnly = `# ${plan.title}\n\n${plan.chapters.map((c, i) => `## ${c.title}\n\n${bodies[i]}\n`).join("\n")}`;
    outputs.push(await saveAsset({ name: `${base}.md`, data: utf8(textOnly), origin: "generated" }));
  }
  void LANG_NAMES;
  return [...outputs.map((a) => a.id), ...made.map((a) => a.id)];
}
