import { promises as fs } from "node:fs";
import path from "node:path";
import { type Asset, readAssetData, saveAsset } from "./assets";
import { fileBase, LANG_NAMES, PAGE, planAndWrite, applyPageSize, type BookFormat, type BookInput, type PageSize } from "./books-core";
import { hasTool, run, semaphore, withTempDir } from "./exec";
import { generateImages } from "./images";
import type { JobContext } from "./jobs";
import { capabilitiesOf, type Provider } from "./providers";

export * from "./books-core";

const heavy = semaphore(1);

async function referenceDocx(dir: string, size: PageSize, warn: (m: string) => void): Promise<string | undefined> {
  if (!hasTool("zip") || !hasTool("unzip")) {
    warn(`"zip"/"unzip" are not installed, so the ${size} page size could not be applied`);
    return undefined;
  }
  const ref = path.join(dir, "ref.docx");
  await fs.writeFile(ref, (await run("pandoc", ["--print-default-data-file", "reference.docx"], { home: dir })).stdout);
  const x = path.join(dir, "ref-x");
  await fs.mkdir(x);
  await run("unzip", ["-q", ref, "-d", x]);
  const docXml = path.join(x, "word", "document.xml");
  const [w, h] = PAGE[size];
  await fs.writeFile(docXml, applyPageSize(await fs.readFile(docXml, "utf8"), w, h));
  const out = path.join(dir, "ref-sized.docx");
  const entries = (await fs.readdir(x)).sort((a, b) => (a === "[Content_Types].xml" ? -1 : b === "[Content_Types].xml" ? 1 : 0));
  await run("zip", ["-q", "-X", "-r", out, ...entries], { cwd: x });
  return out;
}

export async function runBook(input: BookInput, providers: Provider[], ctx: JobContext): Promise<string[]> {
  if (!hasTool("pandoc")) throw new Error('"pandoc" is not installed on the server, so books cannot be exported');
  const lang = LANG_NAMES[input.language];
  const warnings = (m: string) => ctx.warn(m);
  const made: Asset[] = [];
  const { plan, bodies } = await planAndWrite(input, providers, ctx);
  const n = plan.chapters.length;

  // 3. illustrations
  const imageFiles = new Map<string, Asset>(); // key: "cover" | "ch1"...
  const wantImages = input.illustrate || input.cover;
  const canImage = providers.some((p) => p.enabled && capabilitiesOf(p).image);
  if (wantImages && !canImage) warnings("No image provider is configured, so the book has no illustrations or cover. Add one in Settings.");
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
        imageFiles.set(jobs[i].key, r.assets[0]);
        made.push(r.assets[0]);
      } catch (e) {
        if (ctx.signal.aborted) throw new Error("cancelled");
        warnings(`The ${jobs[i].label} illustration failed: ${(e as Error).message}`);
      }
    }
  }

  // 4. export
  ctx.setProgress(82, "Building the files");
  const base = fileBase(plan.title);
  const outputs: Asset[] = [];
  await heavy(() =>
    withTempDir(async (dir) => {
      const imgName = new Map<string, string>();
      for (const [key, a] of imageFiles) {
        const { data } = await readAssetData(a.id);
        const name = `${key}.${a.ext === "jpeg" ? "jpg" : a.ext}`;
        await fs.writeFile(path.join(dir, name), data);
        imgName.set(key, name);
      }
      const md = plan.chapters.map((c, i) => `# ${c.title}\n\n${imgName.has(`ch${i + 1}`) ? `![](${imgName.get(`ch${i + 1}`)})\n\n` : ""}${bodies[i]}\n`).join("\n");
      const mdPath = path.join(dir, "book.md");
      await fs.writeFile(mdPath, md);

      const reader = "markdown-raw_html-raw_attribute-yaml_metadata_block-pandoc_title_block-tex_math_dollars";
      const meta = ["--metadata", `title=${plan.title}`, "--metadata", `lang=${input.language}`];
      const rtl = input.language === "ar" ? ["-V", "dir=rtl"] : [];
      const baseArgs = ["-f", reader, `--resource-path=${dir}`, ...meta, ...rtl];
      const need = (f: BookFormat) => input.formats.includes(f);

      let docx = "";
      if (need("docx") || need("pdf")) {
        let ref: string | undefined;
        try {
          ref = await referenceDocx(dir, input.pageSize, warnings);
        } catch (e) {
          warnings(`Page size ${input.pageSize} could not be applied: ${(e as Error).message}`);
        }
        docx = path.join(dir, "book.docx");
        await run("pandoc", [mdPath, ...baseArgs, ...(ref ? [`--reference-doc=${ref}`] : []), "-o", docx], { timeoutMs: 120_000, home: dir, cwd: dir });
      }
      if (need("docx")) outputs.push(await saveAsset({ name: `${base}.docx`, data: await fs.readFile(docx), origin: "generated" }));
      if (need("pdf")) {
        if (!hasTool("soffice")) warnings('PDF was skipped because "soffice" (LibreOffice) is not installed');
        else {
          const outDir = path.join(dir, "pdf");
          await fs.mkdir(outDir);
          await run("soffice", ["--headless", `-env:UserInstallation=file://${dir}/profile`, "--convert-to", "pdf", "--outdir", outDir, docx], { timeoutMs: 180_000, home: dir });
          outputs.push(await saveAsset({ name: `${base}.pdf`, data: await fs.readFile(path.join(outDir, "book.pdf")), origin: "generated" }));
        }
      }
      if (need("epub")) {
        const epub = path.join(dir, "book.epub");
        const cover = imgName.get("cover");
        await run("pandoc", [mdPath, ...baseArgs, ...(cover ? [`--epub-cover-image=${path.join(dir, cover)}`] : []), "-o", epub], { timeoutMs: 120_000, home: dir, cwd: dir });
        outputs.push(await saveAsset({ name: `${base}.epub`, data: await fs.readFile(epub), origin: "generated" }));
      }
      if (need("md")) {
        const textOnly = `# ${plan.title}\n\n${plan.chapters.map((c, i) => `## ${c.title}\n\n${bodies[i]}\n`).join("\n")}`;
        outputs.push(await saveAsset({ name: `${base}.md`, data: Buffer.from(textOnly, "utf8"), origin: "generated" }));
      }
    }),
  );
  return [...outputs.map((a) => a.id), ...made.map((a) => a.id)];
}
