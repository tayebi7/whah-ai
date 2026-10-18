import { promises as fs } from "node:fs";
import path from "node:path";
import { type Asset, isTextExt } from "./assets";
import { hasTool, run, semaphore, withTempDir } from "./exec";

export type Extracted = { text: string; truncated: boolean; method: string };
const MAX_CHARS = 200_000;
const heavy = semaphore(2);

const clip = (t: string, method: string): Extracted => {
  const s = t.replace(/\r\n/g, "\n").replace(/\n{4,}/g, "\n\n\n").trim();
  return { text: s.slice(0, MAX_CHARS), truncated: s.length > MAX_CHARS, method };
};

async function ocr(imagePath: string, dir: string): Promise<string> {
  if (!hasTool("tesseract")) throw new Error('Reading text from images needs "tesseract" on the server, which is not installed');
  const langs = (await run("tesseract", ["--list-langs"], { home: dir }).then((r) => r.stdout.toString(), () => "")).split("\n").map((s) => s.trim());
  const want = ["ara", "eng", "fra"].filter((l) => langs.includes(l));
  return (await run("tesseract", [imagePath, "stdout", "-l", (want.length ? want : ["eng"]).join("+")], { timeoutMs: 120_000, home: dir })).stdout.toString("utf8");
}

/** Text from an uploaded file: plain text, Office/ODT/EPUB (pandoc), spreadsheets (LibreOffice), PDF (poppler, OCR fallback), images (OCR). */
export async function extractText(asset: Asset, file: string): Promise<Extracted> {
  const ext = asset.ext;
  if (isTextExt(ext)) {
    const raw = await fs.readFile(file, "utf8");
    return clip(ext === "html" ? raw.replace(/<(script|style)[\s\S]*?<\/\1>/gi, "").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ") : raw, "text");
  }
  return heavy(() =>
    withTempDir(async (dir) => {
      const input = path.join(dir, `in.${ext}`);
      await fs.copyFile(file, input);
      if (["docx", "odt", "epub"].includes(ext)) {
        return clip((await run("pandoc", ["--sandbox", input, "-t", "plain", "--wrap=none"], { home: dir, timeoutMs: 60_000 })).stdout.toString("utf8"), "pandoc");
      }
      if (ext === "pptx" || ext === "xlsx") {
        if (!hasTool("soffice")) throw new Error('Reading this file type needs "soffice" (LibreOffice) on the server, which is not installed');
        const out = ext === "xlsx" ? "csv" : "txt";
        await run("soffice", ["--headless", `-env:UserInstallation=file://${dir}/profile`, "--convert-to", out, "--outdir", dir, input], { home: dir, timeoutMs: 120_000 });
        return clip(await fs.readFile(path.join(dir, `in.${out}`), "utf8"), "libreoffice");
      }
      if (ext === "pdf") {
        const t = (await run("pdftotext", ["-layout", input, "-"], { home: dir, timeoutMs: 60_000 })).stdout.toString("utf8");
        if (t.replace(/\s/g, "").length > 20) return clip(t, "pdftotext");
        await run("pdftoppm", ["-r", "150", "-png", "-l", "10", input, path.join(dir, "pg")], { home: dir, timeoutMs: 120_000 });
        const pages = (await fs.readdir(dir)).filter((f) => f.startsWith("pg") && f.endsWith(".png")).sort();
        const parts: string[] = [];
        for (const p of pages) parts.push(await ocr(path.join(dir, p), dir));
        return clip(parts.join("\n\n"), "ocr");
      }
      if (asset.kind === "image") return clip(await ocr(input, dir), "ocr");
      throw new Error(`Cannot read text from .${ext} files`);
    }),
  );
}
