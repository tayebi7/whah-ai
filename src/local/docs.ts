/** Document model + writers (HTML, DOCX, EPUB, XLSX) and readers, with no external libraries. Used for books and conversions on the phone. */
import { readZip, readZipText, writeZip, type ZipEntry } from "./zip";

export type Block =
  | { t: "h"; level: number; text: string }
  | { t: "p"; text: string }
  | { t: "li"; text: string; n?: number }
  | { t: "hr" }
  | { t: "img"; data: Uint8Array; ext: "png" | "jpg" | "webp" };
export type Run = { text: string; b?: boolean; i?: boolean; code?: boolean };
export type PageSize = "A4" | "Letter" | "A5";
export const PAGE_TWIPS: Record<PageSize, [number, number]> = { A4: [11906, 16838], Letter: [12240, 15840], A5: [8391, 11906] };

const enc = new TextEncoder();
export const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
/** Text for XML: also drops characters XML 1.0 cannot hold. */
const xml = (s: string) => esc(s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f￾￿]/g, "");
const RTL_RE = /[֐-ࣿיִ-﷿ﹰ-﻿]/;
export const isRtlText = (s: string) => RTL_RE.test(s);

// ------------------------------------------------------------------ Markdown / plain text -> blocks

export function inlineRuns(src: string): Run[] {
  const s = src.replace(/!\[[^\]]*\]\([^)]*\)/g, "").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
  const out: Run[] = [];
  const re = /(\*\*|__)(?=\S)([\s\S]*?\S)\1|(\*|_)(?=\S)([^*_\n]*?\S)\3|`([^`\n]+)`/g;
  let last = 0;
  for (let m = re.exec(s); m; m = re.exec(s)) {
    if (m.index > last) out.push({ text: s.slice(last, m.index) });
    if (m[2] !== undefined) out.push({ text: m[2], b: true });
    else if (m[4] !== undefined) out.push({ text: m[4], i: true });
    else out.push({ text: m[5], code: true });
    last = m.index + m[0].length;
  }
  if (last < s.length) out.push({ text: s.slice(last) });
  return out.filter((r) => r.text !== "");
}
export const plainOf = (text: string) => inlineRuns(text).map((r) => r.text).join("");

export function parseMarkdown(md: string): Block[] {
  const blocks: Block[] = [];
  let para: string[] = [];
  let fence = false;
  const flush = () => {
    if (para.length) blocks.push({ t: "p", text: para.join(" ").replace(/\s+/g, " ").trim() });
    para = [];
  };
  for (const raw of md.replace(/\r\n?/g, "\n").split("\n")) {
    const line = raw.trimEnd();
    if (/^\s*(```|~~~)/.test(line)) {
      flush();
      fence = !fence;
      continue;
    }
    if (fence) {
      if (line.trim()) blocks.push({ t: "p", text: line });
      continue;
    }
    let m: RegExpMatchArray | null;
    if (!line.trim()) flush();
    else if ((m = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/))) {
      flush();
      blocks.push({ t: "h", level: m[1].length, text: m[2] });
    } else if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
      flush();
      blocks.push({ t: "hr" });
    } else if ((m = line.match(/^\s*[-*+]\s+(.*)$/))) {
      flush();
      blocks.push({ t: "li", text: m[1] });
    } else if ((m = line.match(/^\s*(\d{1,3})[.)]\s+(.*)$/))) {
      flush();
      blocks.push({ t: "li", text: m[2], n: Number(m[1]) });
    } else if ((m = line.match(/^\s*>\s?(.*)$/))) para.push(m[1]);
    else para.push(line.trim());
  }
  flush();
  return blocks;
}

export const blocksToMarkdown = (blocks: Block[]) =>
  blocks
    .map((b) => (b.t === "h" ? `${"#".repeat(b.level)} ${b.text}` : b.t === "li" ? `${b.n ? `${b.n}.` : "-"} ${b.text}` : b.t === "hr" ? "***" : b.t === "img" ? "" : b.text))
    .filter((x) => x !== "")
    .join("\n\n");

export const blocksToText = (blocks: Block[]) =>
  blocks
    .map((b) => (b.t === "h" ? plainOf(b.text) : b.t === "li" ? `${b.n ? `${b.n}.` : "•"} ${plainOf(b.text)}` : b.t === "hr" ? "* * *" : b.t === "img" ? "" : plainOf(b.text)))
    .filter((x) => x !== "")
    .join("\n\n");

/** HTML (own or pasted) -> blocks, dropping scripts/styles and every attribute. */
export function htmlToBlocks(html: string): Block[] {
  const s = html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<(script|style|head)\b[\s\S]*?<\/\1\s*>/gi, "")
    .replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_m, l, t) => `\n\n${"#".repeat(Number(l))} ${t.replace(/<[^>]+>/g, "")}\n\n`)
    .replace(/<li\b[^>]*>([\s\S]*?)<\/li>/gi, (_m, t) => `\n- ${t.replace(/<[^>]+>/g, "")}\n`)
    .replace(/<\/(p|div|section|article|tr|blockquote)>/gi, "\n\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "");
  return parseMarkdown(decodeEntities(s));
}

export function decodeEntities(s: string): string {
  return s
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;|&#39;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_m, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_m, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, "&");
}

// ------------------------------------------------------------------ images

export function imageSize(b: Uint8Array): { w: number; h: number } | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b.length > 24) {
    const v = new DataView(b.buffer, b.byteOffset);
    return { w: v.getUint32(16), h: v.getUint32(20) };
  }
  if (b[0] === 0xff && b[1] === 0xd8) {
    let i = 2;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) return null;
      const marker = b[i + 1];
      const len = (b[i + 2] << 8) | b[i + 3];
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) return { h: (b[i + 5] << 8) | b[i + 6], w: (b[i + 7] << 8) | b[i + 8] };
      i += 2 + len;
    }
  }
  return null;
}

const MIME = { png: "image/png", jpg: "image/jpeg", webp: "image/webp" } as const;

// ------------------------------------------------------------------ HTML

const CSS = "body{font-family:system-ui,'Noto Naskh Arabic',serif;line-height:1.7;max-width:42em;margin:2em auto;padding:0 1em}h1,h2,h3{line-height:1.3}img{max-width:100%;height:auto;display:block;margin:1em auto}hr{border:0;text-align:center}hr:before{content:'* * *'}";

function runsHtml(text: string) {
  return inlineRuns(text)
    .map((r) => {
      const t = esc(r.text);
      return r.code ? `<code>${t}</code>` : r.b ? `<strong>${t}</strong>` : r.i ? `<em>${t}</em>` : t;
    })
    .join("");
}

/** Blocks -> XHTML body markup; images are written through `img(n, block)` so EPUB can reference files and HTML can inline them. */
export function blocksToBody(blocks: Block[], img: (b: Extract<Block, { t: "img" }>) => string): string {
  const out: string[] = [];
  let list: string[] = [];
  let ordered = false;
  const flush = () => {
    if (list.length) out.push(`<${ordered ? "ol" : "ul"}>${list.join("")}</${ordered ? "ol" : "ul"}>`);
    list = [];
  };
  for (const b of blocks) {
    if (b.t === "li") {
      if (list.length && ordered !== !!b.n) flush();
      ordered = !!b.n;
      list.push(`<li>${runsHtml(b.text)}</li>`);
      continue;
    }
    flush();
    if (b.t === "h") out.push(`<h${Math.min(b.level, 6)}>${runsHtml(b.text)}</h${Math.min(b.level, 6)}>`);
    else if (b.t === "p") out.push(`<p>${runsHtml(b.text)}</p>`);
    else if (b.t === "hr") out.push("<hr/>");
    else out.push(img(b));
  }
  flush();
  return out.join("\n");
}

export function writeHtml(blocks: Block[], o: { title: string; lang: string }): string {
  const rtl = o.lang === "ar";
  const body = blocksToBody(blocks, (b) => {
    let s = "";
    for (let i = 0; i < b.data.length; i += 0x8000) s += String.fromCharCode(...b.data.subarray(i, i + 0x8000));
    return `<img alt="" src="data:${MIME[b.ext]};base64,${btoa(s)}"/>`;
  });
  return `<!doctype html>\n<html lang="${esc(o.lang)}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.title)}</title><style>${CSS}</style></head><body>\n${body}\n</body></html>\n`;
}

// ------------------------------------------------------------------ DOCX

export function writeDocx(blocks: Block[], o: { title: string; lang: string; pageSize?: PageSize }): Uint8Array {
  const rtl = o.lang === "ar" || blocks.some((b) => (b.t === "p" || b.t === "h") && isRtlText(b.text) && o.lang !== "en" && o.lang !== "fr");
  const [pw, ph] = PAGE_TWIPS[o.pageSize ?? "A4"];
  const rels: string[] = [];
  const files: ZipEntry[] = [];
  let imgN = 0;

  const rPr = (r: Run) => `<w:rPr>${r.code ? '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>' : ""}${r.b ? "<w:b/><w:bCs/>" : ""}${r.i ? "<w:i/><w:iCs/>" : ""}${rtl ? "<w:rtl/>" : ""}</w:rPr>`;
  const runs = (text: string) => inlineRuns(text).map((r) => `<w:r>${rPr(r)}<w:t xml:space="preserve">${xml(r.text)}</w:t></w:r>`).join("");
  const para = (inner: string, style?: string, extra = "") => `<w:p><w:pPr>${style ? `<w:pStyle w:val="${style}"/>` : ""}${rtl ? "<w:bidi/>" : ""}${extra}</w:pPr>${inner}</w:p>`;

  const body: string[] = [];
  if (o.title && !blocks.some((b) => b.t === "h" && b.level === 1 && b.text === o.title)) body.push(para(runs(o.title), "Title"));
  for (const b of blocks) {
    if (b.t === "h") body.push(para(runs(b.text), `Heading${Math.min(b.level, 3)}`));
    else if (b.t === "p") body.push(para(runs(b.text)));
    else if (b.t === "li") body.push(para(`<w:r>${rPr({ text: "" })}<w:t xml:space="preserve">${b.n ? `${b.n}. ` : "• "}</w:t></w:r>${runs(b.text)}`, undefined, '<w:ind w:left="360"/>'));
    else if (b.t === "hr") body.push(para('<w:r><w:t>* * *</w:t></w:r>', undefined, '<w:jc w:val="center"/>'));
    else {
      imgN++;
      const name = `image${imgN}.${b.ext}`;
      files.push({ name: `word/media/${name}`, data: b.data });
      rels.push(`<Relationship Id="rIdImg${imgN}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${name}"/>`);
      const sz = imageSize(b.data) ?? { w: 1, h: 1 };
      const maxW = Math.floor(((pw - 2880) / 1440) * 914400 * 0.9);
      const cx = Math.min(maxW, 4_572_000);
      const cy = Math.round((cx * sz.h) / sz.w);
      body.push(
        `<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="${cx}" cy="${cy}"/><wp:docPr id="${imgN}" name="Picture ${imgN}"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="${imgN}" name="${name}"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImg${imgN}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>`,
      );
    }
  }

  const NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';
  const document = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document ${NS}><w:body>${body.join("")}<w:sectPr><w:pgSz w:w="${pw}" w:h="${ph}"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>${rtl ? "<w:bidi/>" : ""}</w:sectPr></w:body></w:document>`;
  const h = (id: string, name: string, size: number) => `<w:style w:type="paragraph" w:styleId="${id}"><w:name w:val="${name}"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="${size}"/><w:szCs w:val="${size}"/></w:rPr></w:style>`;
  const styles = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Arial"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="${esc(o.lang)}" w:bidi="ar-SA"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>${h("Title", "Title", 52)}${h("Heading1", "heading 1", 36)}${h("Heading2", "heading 2", 30)}${h("Heading3", "heading 3", 26)}</w:styles>`;
  const exts = ["png", "jpg", "webp"].filter((e) => files.some((f) => f.name.endsWith(`.${e}`)));
  const types = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${exts.map((e) => `<Default Extension="${e}" ContentType="${MIME[e as keyof typeof MIME]}"/>`).join("")}<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>`;
  const root = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>`;
  const docRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdSt" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>${rels.join("")}</Relationships>`;
  const core = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${xml(o.title)}</dc:title><dc:language>${esc(o.lang)}</dc:language><dcterms:created xsi:type="dcterms:W3CDTF">${new Date().toISOString()}</dcterms:created></cp:coreProperties>`;
  return writeZip([{ name: "[Content_Types].xml", data: types }, { name: "_rels/.rels", data: root }, { name: "word/document.xml", data: document }, { name: "word/styles.xml", data: styles }, { name: "word/_rels/document.xml.rels", data: docRels }, { name: "docProps/core.xml", data: core }, ...files]);
}

// ------------------------------------------------------------------ EPUB

export function writeEpub(blocks: Block[], o: { title: string; lang: string; cover?: { data: Uint8Array; ext: "png" | "jpg" | "webp" } }): Uint8Array {
  const rtl = o.lang === "ar";
  const images: { name: string; data: Uint8Array; ext: "png" | "jpg" | "webp" }[] = [];
  const addImage = (data: Uint8Array, ext: "png" | "jpg" | "webp") => {
    const name = `img${images.length + 1}.${ext}`;
    images.push({ name, data, ext });
    return name;
  };
  const coverName = o.cover ? addImage(o.cover.data, o.cover.ext) : undefined;

  // one chapter file per level-1 heading
  const chapters: { title: string; blocks: Block[] }[] = [];
  for (const b of blocks) {
    if (b.t === "h" && b.level === 1) chapters.push({ title: plainOf(b.text), blocks: [b] });
    else {
      if (!chapters.length) chapters.push({ title: o.title, blocks: [] });
      chapters[chapters.length - 1].blocks.push(b);
    }
  }
  if (!chapters.length) chapters.push({ title: o.title, blocks: [] });

  const page = (title: string, inner: string) => `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="${esc(o.lang)}" xml:lang="${esc(o.lang)}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8"/><title>${esc(title)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>${inner}</body></html>`;
  const chapterFiles = chapters.map((c, i) => ({
    name: `ch${i + 1}.xhtml`,
    title: c.title,
    html: page(c.title, blocksToBody(c.blocks, (b) => `<img alt="" src="${addImage(b.data, b.ext)}"/>`)),
  }));
  const id = `urn:uuid:${crypto.randomUUID()}`;
  const container = `<?xml version="1.0"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`;
  const manifest = [
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    '<item id="css" href="style.css" media-type="text/css"/>',
    ...chapterFiles.map((c, i) => `<item id="c${i + 1}" href="${c.name}" media-type="application/xhtml+xml"/>`),
    ...images.map((im, i) => `<item id="i${i + 1}" href="${im.name}" media-type="${MIME[im.ext]}"${im.name === coverName ? ' properties="cover-image"' : ""}/>`),
  ].join("");
  const opf = `<?xml version="1.0" encoding="UTF-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">${id}</dc:identifier><dc:title>${esc(o.title)}</dc:title><dc:language>${esc(o.lang)}</dc:language><meta property="dcterms:modified">${new Date().toISOString().replace(/\.\d+Z$/, "Z")}</meta>${coverName ? `<meta name="cover" content="i1"/>` : ""}</metadata><manifest>${manifest}</manifest><spine${rtl ? ' page-progression-direction="rtl"' : ""}>${chapterFiles.map((_c, i) => `<itemref idref="c${i + 1}"/>`).join("")}</spine></package>`;
  const nav = page(o.title, `<nav epub:type="toc" id="toc"><h1>${esc(o.title)}</h1><ol>${chapterFiles.map((c) => `<li><a href="${c.name}">${esc(c.title)}</a></li>`).join("")}</ol></nav>`);
  const css = "body{line-height:1.7}img{max-width:100%;height:auto;display:block;margin:1em auto}hr{border:0;text-align:center}hr:before{content:'* * *'}";
  return writeZip([
    { name: "mimetype", data: "application/epub+zip" },
    { name: "META-INF/container.xml", data: container },
    { name: "OEBPS/content.opf", data: opf },
    { name: "OEBPS/nav.xhtml", data: nav },
    { name: "OEBPS/style.css", data: css },
    ...chapterFiles.map((c) => ({ name: `OEBPS/${c.name}`, data: c.html })),
    ...images.map((im) => ({ name: `OEBPS/${im.name}`, data: im.data })),
  ]);
}

// ------------------------------------------------------------------ CSV / XLSX

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let q = false;
  const s = text.replace(/^﻿/, "");
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) {
      if (c === '"') {
        if (s[i + 1] === '"') (cell += '"', i++);
        else q = false;
      } else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") (row.push(cell), (cell = ""));
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && s[i + 1] === "\n") i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else cell += c;
  }
  if (cell !== "" || row.length) (row.push(cell), rows.push(row));
  return rows;
}
export const toCsv = (rows: string[][]) => rows.map((r) => r.map((c) => (/[",\n\r]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c)).join(",")).join("\r\n") + "\r\n";

const colName = (n: number) => {
  let s = "";
  for (n++; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
  return s;
};

export function writeXlsx(rows: string[][]): Uint8Array {
  const sheet = rows
    .slice(0, 100_000)
    .map((r, ri) => `<row r="${ri + 1}">${r.map((c, ci) => (c === "" ? "" : /^-?\d+(\.\d+)?$/.test(c) && c.length < 15 ? `<c r="${colName(ci)}${ri + 1}"><v>${c}</v></c>` : `<c r="${colName(ci)}${ri + 1}" t="inlineStr"><is><t xml:space="preserve">${xml(c)}</t></is></c>`)).join("")}</row>`)
    .join("");
  return writeZip([
    { name: "[Content_Types].xml", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>' },
    { name: "_rels/.rels", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>' },
    { name: "xl/workbook.xml", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>' },
    { name: "xl/_rels/workbook.xml.rels", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>' },
    { name: "xl/worksheets/sheet1.xml", data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${sheet}</sheetData></worksheet>` },
  ]);
}

const colIndex = (ref: string) => [...ref.replace(/\d+/g, "")].reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;

/** First worksheet of an XLSX as rows of text (shared strings, inline strings and numbers). */
export async function readXlsxRows(data: Uint8Array): Promise<string[][]> {
  const z = readZip(data);
  const shared: string[] = [];
  const sst = await readZipText(z, "xl/sharedStrings.xml");
  if (sst) for (const m of sst.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) shared.push(decodeEntities([...m[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join("")));
  const names = [...z.keys()].filter((n) => /^xl\/worksheets\/sheet\d+\.xml$/.test(n)).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const sheet = names.length ? await readZipText(z, names[0]) : undefined;
  if (!sheet) throw new Error("This spreadsheet has no readable sheet");
  const rows: string[][] = [];
  for (const rm of sheet.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row: string[] = [];
    for (const cm of rm[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = cm[1];
      const ref = /\br="([A-Z]+\d+)"/.exec(attrs)?.[1];
      const type = /\bt="(\w+)"/.exec(attrs)?.[1];
      const inner = cm[2] ?? "";
      let v = "";
      if (type === "s") v = shared[Number(/<v>([\s\S]*?)<\/v>/.exec(inner)?.[1])] ?? "";
      else if (type === "inlineStr") v = decodeEntities([...inner.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join(""));
      else v = decodeEntities(/<v>([\s\S]*?)<\/v>/.exec(inner)?.[1] ?? "");
      const idx = ref ? colIndex(ref) : row.length;
      while (row.length < idx) row.push("");
      row[idx] = v;
    }
    rows.push(row);
  }
  return rows;
}

// ------------------------------------------------------------------ reading office files as text

const paragraphsOf = (x: string, p: RegExp, t: RegExp) => [...x.matchAll(p)].map((m) => decodeEntities([...m[1].matchAll(t)].map((s) => s[1]).join(""))).filter((s) => s.trim());

/** Plain text from DOCX, PPTX, ODT and EPUB files. */
export async function readOfficeText(ext: string, data: Uint8Array): Promise<string> {
  const z = readZip(data);
  if (ext === "docx") {
    const x = await readZipText(z, "word/document.xml");
    if (!x) throw new Error("This DOCX file has no document.xml");
    return [...x.matchAll(/<w:p\b[^>]*>([\s\S]*?)<\/w:p>/g)]
      .map((m) => decodeEntities([...m[1].matchAll(/<w:t\b[^>]*>([\s\S]*?)<\/w:t>|(<w:tab\s*\/>)|(<w:br\s*\/>)/g)].map((t) => (t[2] ? "\t" : t[3] ? "\n" : t[1])).join("")))
      .filter((s) => s.trim())
      .join("\n\n");
  }
  if (ext === "pptx") {
    const slides = [...z.keys()].filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n)).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    const out: string[] = [];
    for (const [i, n] of slides.entries()) out.push(`--- Slide ${i + 1} ---\n${paragraphsOf((await readZipText(z, n)) ?? "", /<a:p\b[^>]*>([\s\S]*?)<\/a:p>/g, /<a:t\b[^>]*>([\s\S]*?)<\/a:t>/g).join("\n")}`);
    return out.join("\n\n");
  }
  if (ext === "odt") {
    const x = await readZipText(z, "content.xml");
    if (!x) throw new Error("This ODT file has no content.xml");
    return paragraphsOf(x, /<text:(?:p|h)\b[^>]*>([\s\S]*?)<\/text:(?:p|h)>/g, /([^<]+)/g).join("\n\n");
  }
  if (ext === "epub") {
    const files = [...z.keys()].filter((n) => /\.x?html?$/i.test(n) && !/nav\.x?html?$/i.test(n)).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    const out: string[] = [];
    for (const n of files) out.push(blocksToText(htmlToBlocks((await readZipText(z, n)) ?? "")));
    return out.filter(Boolean).join("\n\n");
  }
  throw new Error(`Cannot read text from .${ext} files`);
}

export const utf8 = (s: string) => enc.encode(s);
