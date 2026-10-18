import { promises as fs } from "node:fs";
import path from "node:path";
import { AssetError, getAsset, assetPath, saveAsset, type Asset } from "./assets";
import { hasTool, run, semaphore, withTempDir } from "./exec";

type Tool = "soffice" | "pandoc" | "pdftotext" | "pdftoppm" | "ffmpeg";
type Ctx = { input: string; output: string; dir: string; asset: Asset };
type Conversion = { from: string; to: string; tool: Tool; note?: string; run: (c: Ctx) => Promise<void> };

const heavy = semaphore(2);

/** soffice writes <dir>/<input name>.<target>; we move it to the expected output path. */
const soffice = (target: string, filter?: string) => async (c: Ctx) => {
  const outDir = path.join(c.dir, "out");
  await fs.mkdir(outDir, { recursive: true });
  await run("soffice", ["--headless", `-env:UserInstallation=file://${c.dir}/profile`, ...(filter ? [`--infilter=${filter}`] : []), "--convert-to", target, "--outdir", outDir, c.input], { timeoutMs: 180_000, home: c.dir });
  await fs.rename(path.join(outDir, `${path.basename(c.input, path.extname(c.input))}.${target.split(":")[0]}`), c.output);
};

// pandoc --sandbox: pandoc may not read other files or use the network while converting untrusted input.
// Some distribution builds of pandoc (e.g. Debian/Ubuntu 3.1.x) keep their DOCX/EPUB/ODT data files on
// disk, which --sandbox forbids reading, so those targets fail with "Could not find data file".
const NEEDS_DATA_FILES = new Set(["docx", "epub", "odt"]);

/** Removes inline and reference-style images from Markdown, so pandoc has nothing to read or fetch. */
export function stripMarkdownResources(md: string): string {
  return md.replace(/!\[[^\]]*\]\s*(?:\([^)]*\)|\[[^\]]*\])(?:\{[^}]*\})?/g, "");
}

/**
 * Removes HTML from untrusted Markdown: comments, <script>/<style> blocks with their content, and other
 * tags. Code (fenced blocks and inline `code`) is left untouched, as are autolinks such as
 * <https://example.com> and <me@example.com>, which are Markdown and not HTML.
 */
export function stripMarkdownHtml(md: string): string {
  return md
    .split(/(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`)/g)
    .map((part, i) =>
      i % 2 === 1
        ? part
        : part
            .replace(/<!--[\s\S]*?-->/g, "")
            .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "")
            .replace(/<\/?[A-Za-z][A-Za-z0-9-]*(?:[ \t/][^>\n]*)?>/g, ""),
    )
    .join("");
}

async function runPandoc(c: Ctx, args: string[], output: string = c.output) {
  if (c.input.endsWith(".md")) {
    const clean = path.join(c.dir, "clean.md"); // never hand untrusted Markdown to pandoc as-is
    await fs.writeFile(clean, stripMarkdownHtml(await fs.readFile(c.input, "utf8")));
    c = { ...c, input: clean };
  }
  try {
    await run("pandoc", ["--sandbox", c.input, ...args, "-o", output], { timeoutMs: 120_000, home: c.dir });
    return;
  } catch (e) {
    const target = args[args.indexOf("-t") + 1] ?? path.extname(output).slice(1);
    if (!/Could not find data file/.test((e as Error).message) || !NEEDS_DATA_FILES.has(target)) throw e;
    if (!c.input.endsWith(".md")) {
      throw new Error(`This server's pandoc build cannot write .${target} in sandbox mode, and ${path.extname(c.input)} input is not safe to convert without the sandbox. Install the official pandoc release (data files built in) to enable it.`);
    }
    const safe = path.join(c.dir, "safe.md"); // Markdown only: images dropped first, so pandoc has nothing to read or fetch
    await fs.writeFile(safe, stripMarkdownResources(await fs.readFile(c.input, "utf8")));
    const fixed = args.map((a) => (a === "markdown-raw_html" ? "markdown-raw_html-raw_attribute" : a));
    await run("pandoc", [safe, ...fixed, "-o", output], { timeoutMs: 120_000, home: c.dir, cwd: c.dir });
  }
}

const pandoc = (args: string[]) => (c: Ctx) => runPandoc(c, args);

const mdToPdf = async (c: Ctx) => {
  const docx = path.join(c.dir, "mid.docx");
  await runPandoc(c, ["-f", "markdown-raw_html", "-t", "docx"], docx);
  await soffice("pdf")({ ...c, input: docx });
};

const ffmpegImage = (c: Ctx) =>
  run("ffmpeg", ["-v", "error", "-y", "-i", c.input, "-frames:v", "1", ...(c.output.endsWith(".jpg") ? ["-q:v", "2"] : []), c.output], { timeoutMs: 60_000 }).then(() => undefined);

const MD_IN = ["md", "txt"]; // plain .txt goes through the same Markdown pipeline
const mdTargets: [string, Tool, ((c: Ctx) => Promise<void>), string?][] = [
  ["docx", "pandoc", pandoc(["-f", "markdown-raw_html", "-t", "docx"])],
  ["html", "pandoc", pandoc(["-f", "markdown-raw_html", "-t", "html", "-s", "--metadata", "title=Document"])],
  ["epub", "pandoc", pandoc(["-f", "markdown-raw_html", "-t", "epub", "--metadata", "title=Document"])],
  ["pdf", "soffice", mdToPdf],
];

export const CONVERSIONS: Conversion[] = [
  ...MD_IN.flatMap((from) => mdTargets.map(([to, tool, fn, note]) => ({ from, to, tool, run: fn, note }) as Conversion)),
  { from: "md", to: "txt", tool: "pandoc", run: pandoc(["-f", "markdown-raw_html", "-t", "plain", "--wrap=none"]) },
  { from: "docx", to: "pdf", tool: "soffice", run: soffice("pdf") },
  { from: "docx", to: "md", tool: "pandoc", note: "images are not exported", run: pandoc(["-t", "gfm", "--wrap=none"]) },
  { from: "docx", to: "txt", tool: "pandoc", run: pandoc(["-t", "plain", "--wrap=none"]) },
  { from: "docx", to: "html", tool: "pandoc", run: pandoc(["-t", "html", "-s"]) },
  { from: "docx", to: "odt", tool: "soffice", run: soffice("odt") },
  { from: "odt", to: "docx", tool: "soffice", run: soffice("docx") },
  { from: "odt", to: "pdf", tool: "soffice", run: soffice("pdf") },
  { from: "xlsx", to: "csv", tool: "soffice", note: "first sheet only", run: soffice("csv") },
  { from: "xlsx", to: "pdf", tool: "soffice", run: soffice("pdf") },
  { from: "csv", to: "xlsx", tool: "soffice", run: soffice("xlsx", "CSV:44,34,76,1") }, // comma, quote, UTF-8
  { from: "pptx", to: "pdf", tool: "soffice", run: soffice("pdf") },
  { from: "html", to: "docx", tool: "pandoc", run: pandoc(["-f", "html", "-t", "docx"]) },
  { from: "html", to: "md", tool: "pandoc", run: pandoc(["-f", "html", "-t", "gfm", "--wrap=none"]) },
  { from: "pdf", to: "txt", tool: "pdftotext", note: "text PDFs only (scanned PDFs: use Send text to chat, which tries OCR)", run: async (c) => void (await fs.writeFile(c.output, (await run("pdftotext", ["-layout", c.input, "-"], { timeoutMs: 60_000, home: c.dir })).stdout)) },
  {
    from: "pdf",
    to: "png",
    tool: "pdftoppm",
    note: "first page",
    run: async (c) => {
      const base = path.join(c.dir, "page");
      await run("pdftoppm", ["-png", "-r", "130", "-f", "1", "-l", "1", "-singlefile", c.input, base], { timeoutMs: 60_000, home: c.dir });
      await fs.rename(`${base}.png`, c.output);
    },
  },
  ...["png", "jpg", "jpeg", "webp", "gif"].flatMap((from) => ["png", "jpg", "webp"].filter((to) => to !== from && !(from === "jpeg" && to === "jpg")).map((to) => ({ from, to, tool: "ffmpeg" as Tool, run: ffmpegImage }))),
];

export function listConversions() {
  return CONVERSIONS.map((c) => ({ from: c.from, to: c.to, available: hasTool(c.tool), tool: c.tool, ...(c.note ? { note: c.note } : {}) }));
}


export async function convertAsset(assetId: string, to: string): Promise<Asset> {
  const asset = await getAsset(assetId);
  if (!asset) throw new AssetError("File not found", 404);
  const conv = CONVERSIONS.find((c) => c.from === asset.ext && c.to === to);
  if (!conv) throw new AssetError(`Converting .${asset.ext} to .${to} is not supported`);
  if (!hasTool(conv.tool)) throw new AssetError(`"${conv.tool}" is not installed on the server, so this conversion is unavailable`, 501);
  const src = await assetPath(asset.id);
  const outName = `${path.basename(asset.name, path.extname(asset.name)) || "file"}.${to}`;

  const data = await heavy(() =>
    withTempDir(async (dir) => {
      const inExt = MD_IN.includes(asset.ext) ? "md" : asset.ext;
      const input = path.join(dir, `in.${inExt}`);
      const output = path.join(dir, `result.${to}`);
      await fs.copyFile(src, input);
      await conv.run({ input, output, dir, asset });
      let buf: Buffer;
      try {
        buf = await fs.readFile(output);
      } catch {
        throw new Error("Conversion produced no output");
      }
      if (buf.length === 0) throw new Error("Conversion produced no output");
      return buf;
    }),
  );
  return saveAsset({ name: outName, data, origin: "generated" });
}
