/**
 * End-to-end tests of the real route handlers against a mock OpenAI-compatible provider, using the real
 * system tools (ffmpeg, pandoc, LibreOffice, poppler, tesseract). Run with: npm test
 */
import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import type { AddressInfo } from "node:net";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "waha-test-"));
const TOKEN = "test-token-123456";
const KEY = "mock-key-12345";
const OUT = process.env.TEST_OUT;
process.env.WAHA_DATA_DIR = path.join(root, "data");
process.env.WAHA_ALLOW_LOCAL = "true";
process.env.WAHA_ACCESS_TOKEN = TOKEN;
delete process.env.WAHA_PROVIDERS;
delete process.env.WAHA_ENCRYPTION_KEY;

import * as providersRoute from "../src/app/api/providers/route";
import * as providerRoute from "../src/app/api/providers/[id]/route";
import * as providerTest from "../src/app/api/providers/[id]/test/route";
import * as providerModels from "../src/app/api/providers/[id]/models/route";
import * as reorderRoute from "../src/app/api/providers/reorder/route";
import * as chatRoute from "../src/app/api/chat/route";
import * as filesRoute from "../src/app/api/files/route";
import * as fileRoute from "../src/app/api/files/[id]/route";
import * as fileText from "../src/app/api/files/[id]/text/route";
import * as convertRoute from "../src/app/api/convert/route";
import * as imageRoute from "../src/app/api/studio/image/route";
import * as videoRoute from "../src/app/api/studio/video/route";
import * as bookRoute from "../src/app/api/studio/book/route";
import * as jobRoute from "../src/app/api/jobs/[id]/route";
import * as healthRoute from "../src/app/api/health/route";
import { purgeExpired } from "../src/lib/assets";
import { resetRateLimits } from "../src/lib/http";
import { resetBreakers } from "../src/lib/router";

// ---------- fixtures ----------
const fx = path.join(root, "fx");
fs.mkdirSync(fx, { recursive: true });
const ff = (args: string[]) => execFileSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "pipe" });
ff(["-f", "lavfi", "-i", "testsrc=s=640x480:d=1", "-frames:v", "1", path.join(fx, "a.png")]);
ff(["-f", "lavfi", "-i", "smptebars=s=640x480:d=1", "-frames:v", "1", path.join(fx, "b.png")]);
ff(["-f", "lavfi", "-i", "testsrc=s=320x240:d=1", "-pix_fmt", "yuv420p", path.join(fx, "v.mp4")]);
const PNG_A = fs.readFileSync(path.join(fx, "a.png"));
const PNG_B = fs.readFileSync(path.join(fx, "b.png"));
const MP4 = fs.readFileSync(path.join(fx, "v.mp4"));

// ---------- mock provider ----------
type Call = { path: string; body: any; auth?: string };
const calls: Call[] = [];
let server: http.Server;
let base = "";
let videoPolls = 0;
let imageCounter = 0;

function mockHandler(req: http.IncomingMessage, res: http.ServerResponse) {
  const chunks: Buffer[] = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const raw = Buffer.concat(chunks).toString("utf8");
    const body = raw ? JSON.parse(raw) : undefined;
    const url = req.url ?? "";
    calls.push({ path: url, body, auth: req.headers.authorization });
    const send = (code: number, obj: unknown) => (res.writeHead(code, { "content-type": "application/json" }), res.end(JSON.stringify(obj)));
    if (url.startsWith("/bad/")) return send(500, { error: { message: "boom" } });
    if (url === "/files/i.png") return (res.writeHead(200, { "content-type": "image/png" }), res.end(PNG_B));
    if (url === "/files/v.mp4") return (res.writeHead(200, { "content-type": "video/mp4" }), res.end(MP4));
    if (req.headers.authorization !== `Bearer ${KEY}`) return send(401, { error: { message: "bad key" } });

    if (url === "/v1/models") return send(200, { data: [{ id: "m2" }, { id: "m1" }] });
    if (url === "/v1/images/generations") {
      const n = body.n ?? 1;
      const data = Array.from({ length: n }, (_, i) => (i % 2 === 0 ? { b64_json: (imageCounter++ % 2 ? PNG_B : PNG_A).toString("base64") } : { url: `${base}/files/i.png` }));
      return send(200, { data });
    }
    if (url === "/v1/videos" && req.method === "POST") return send(200, { id: "vid-1" });
    if (url === "/v1/videos/vid-1") return send(200, ++videoPolls < 2 ? { status: "running", progress: 40 } : { status: "completed", video_url: `${base}/files/v.mp4` });
    if (url === "/v1/chat/completions") {
      const last = body.messages[body.messages.length - 1];
      const text: string = typeof last.content === "string" ? last.content : last.content.filter((p: any) => p.type === "text").map((p: any) => p.text).join("\n");
      if (!body.stream) {
        let content = "ok";
        let m: RegExpMatchArray | null;
        if ((m = text.match(/exactly (\d+) short captions/))) content = JSON.stringify(Array.from({ length: Number(m[1]) }, (_, i) => `Caption number ${i + 1}`));
        else if ((m = text.match(/Chapters: exactly (\d+)/))) {
          const ar = /Arabic/.test(text);
          content =
            "Here is the plan:\n```json\n" +
            JSON.stringify({ title: ar ? "رحلة إلى الواحة" : "Journey to the Oasis", characters: "A small fox with a red scarf", chapters: Array.from({ length: Number(m[1]) }, (_, i) => ({ title: ar ? `الفصل ${i + 1}` : `Chapter ${i + 1}`, summary: "The fox walks on", illustration: "a fox in the desert" })) }) +
            "\n```";
        } else if ((m = text.match(/Write chapter (\d+)/))) {
          const ar = /Arabic/.test(text);
          content =
            (ar ? "كان يا ما كان ثعلب صغير يعيش قرب الواحة. مشى الثعلب كثيراً تحت الشمس.\n\nوفي النهاية وجد الماء." : "A little fox lived near the oasis.\n\nHe walked far under the sun.") +
            (m[1] === "1" ? "\n\n![x](/etc/passwd)\n<script>alert(1)</script>\n\n---\ntitle: hacked\n---" : "");
        }
        return send(200, { choices: [{ message: { content } }] });
      }
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: "Hel" } }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: "lo" } }] })}\n\n`);
      return res.end("data: [DONE]\n\n");
    }
    send(404, { error: { message: "no route" } });
  });
}

// ---------- helpers ----------
const rq = (p: string, init: RequestInit & { json?: unknown; noToken?: boolean } = {}) => {
  const { json, noToken, ...rest } = init;
  return new Request(`http://localhost${p}`, {
    ...rest,
    headers: { ...(noToken ? {} : { "x-waha-token": TOKEN }), ...(json !== undefined ? { "content-type": "application/json" } : {}), ...(rest.headers as Record<string, string> | undefined) },
    body: json !== undefined ? JSON.stringify(json) : rest.body,
  });
};
const idp = (id: string) => ({ params: Promise.resolve({ id }) });
const J = async (r: Response) => (await r.json()) as any;
async function upload(name: string, data: Buffer | string) {
  const fd = new FormData();
  fd.append("file", new File([data as BlobPart], name));
  return filesRoute.POST(rq("/api/files", { method: "POST", body: fd }));
}
async function waitJob(id: string, ms = 120_000) {
  const end = Date.now() + ms;
  for (;;) {
    const j = (await J(await jobRoute.GET(rq(`/api/jobs/${id}`), idp(id)))).job;
    if (["done", "failed", "cancelled"].includes(j.status)) return j;
    if (Date.now() > end) throw new Error("job timeout: " + JSON.stringify(j));
    await new Promise((r) => setTimeout(r, 200));
  }
}
async function assetBytes(id: string) {
  const r = await fileRoute.GET(rq(`/api/files/${id}`), idp(id));
  assert.equal(r.status, 200);
  return Buffer.from(await r.arrayBuffer());
}
const keep = (name: string, data: Buffer) => OUT && (fs.mkdirSync(OUT, { recursive: true }), fs.writeFileSync(path.join(OUT, name), data));

let providerId = "";
let pngId = "";
let txtId = "";

before(async () => {
  server = http.createServer(mockHandler);
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  fs.rmSync(root, { recursive: true, force: true });
});

describe("auth", () => {
  it("rejects requests without the access token", async () => {
    assert.equal((await providersRoute.GET(rq("/api/providers", { noToken: true }))).status, 401);
    assert.equal((await filesRoute.GET(rq("/api/files", { noToken: true }))).status, 401);
    assert.equal((await chatRoute.POST(rq("/api/chat", { noToken: true, method: "POST", json: {} }))).status, 401);
    assert.equal((await videoRoute.POST(rq("/api/studio/video", { noToken: true, method: "POST", json: {} }))).status, 401);
  });
});

describe("provider settings (manual add, encrypted at rest)", () => {
  it("adds a provider; the key is never returned and never stored in clear text", async () => {
    const res = await providersRoute.POST(rq("/api/providers", { method: "POST", json: { name: "Mock AI", baseUrl: `${base}/v1`, apiKey: KEY, model: "chat-1", supportsVision: true, imageModel: "img-1", videoModel: "vid-1", videoApi: { pollMs: 1000, maxPolls: 10 }, priority: 20 } }));
    const text = await res.text();
    assert.equal(res.status, 201, text);
    assert.ok(!text.includes(KEY));
    const p = JSON.parse(text).provider;
    providerId = p.id;
    assert.equal(p.hasKey, true);
    assert.deepEqual(p.capabilities, { chat: true, vision: true, image: true, video: true });
    const onDisk = fs.readFileSync(path.join(process.env.WAHA_DATA_DIR!, "providers.json"), "utf8");
    assert.ok(!onDisk.includes(KEY), "API key must not be stored in clear text");
    assert.ok(onDisk.includes("apiKeyEnc"));
    assert.ok(fs.existsSync(path.join(process.env.WAHA_DATA_DIR!, ".secret-key")));
  });
  it("rejects invalid or unsafe providers with details", async () => {
    const bad = await providersRoute.POST(rq("/api/providers", { method: "POST", json: { name: "X", baseUrl: "ftp://x", model: "m" } }));
    assert.equal(bad.status, 400);
    assert.ok((await J(bad)).details.length);
  });
  it("lists providers (with presets) without secrets and edits while keeping the stored key", async () => {
    const listRes = await providersRoute.GET(rq("/api/providers"));
    const list = await listRes.text();
    assert.ok(!list.includes(KEY));
    assert.ok(JSON.parse(list).presets.length > 5);
    const put = await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { name: "Mock AI 2" } }), idp(providerId));
    assert.equal(put.status, 200);
    assert.equal((await J(put)).provider.name, "Mock AI 2");
    const t = await J(await providerTest.POST(rq(`/api/providers/${providerId}/test`, { method: "POST", json: { chat: true } }), idp(providerId)));
    assert.equal(t.ok, true, JSON.stringify(t));
  });
  it("tests connections, detects a wrong key, and lists models", async () => {
    const m = await J(await providerModels.GET(rq(`/api/providers/${providerId}/models`), idp(providerId)));
    assert.deepEqual(m.models, ["m1", "m2"]);
    const badKey = await J(await providersRoute.POST(rq("/api/providers", { method: "POST", json: { id: "wrongkey", name: "Wrong", baseUrl: `${base}/v1`, apiKey: "nope-nope-nope", model: "x", priority: 500 } })));
    const t = await J(await providerTest.POST(rq("/api/providers/wrongkey/test", { method: "POST", json: {} }), idp("wrongkey")));
    assert.equal(t.ok, false);
    assert.match(t.steps[0].detail, /invalid credentials/);
    assert.ok(badKey.provider);
    await providerRoute.DELETE(rq("/api/providers/wrongkey", { method: "DELETE" }), idp("wrongkey"));
  });
  it("reorders and deletes", async () => {
    await providersRoute.POST(rq("/api/providers", { method: "POST", json: { id: "second", name: "Second", baseUrl: `${base}/v1`, apiKey: KEY, model: "m" } }));
    assert.equal((await reorderRoute.POST(rq("/api/providers/reorder", { method: "POST", json: { ids: ["second", providerId] } }))).status, 200);
    let list = (await J(await providersRoute.GET(rq("/api/providers")))).providers;
    assert.deepEqual(list.map((p: any) => p.id), ["second", providerId]);
    assert.equal((await providerRoute.DELETE(rq("/api/providers/second", { method: "DELETE" }), idp("second"))).status, 200);
    assert.equal((await providerRoute.DELETE(rq("/api/providers/second", { method: "DELETE" }), idp("second"))).status, 404);
    await reorderRoute.POST(rq("/api/providers/reorder", { method: "POST", json: { ids: [providerId] } }));
    list = (await J(await providersRoute.GET(rq("/api/providers")))).providers;
    assert.equal(list.length, 1);
  });
  it("refuses duplicate ids", async () => {
    const r = await providersRoute.POST(rq("/api/providers", { method: "POST", json: { id: providerId, name: "Dup", baseUrl: `${base}/v1`, model: "m" } }));
    assert.equal(r.status, 409);
  });
});

describe("file upload and download", () => {
  it("accepts images and text, and downloads them byte-for-byte as attachments", async () => {
    const a = await J(await upload("صورة المنتج.png", PNG_A));
    pngId = a.assets[0].id;
    assert.equal(a.assets[0].kind, "image");
    const t = await J(await upload("notes.txt", "The secret launch code is BLUE-42."));
    txtId = t.assets[0].id;
    const r = await fileRoute.GET(rq(`/api/files/${pngId}`), idp(pngId));
    assert.match(r.headers.get("content-disposition")!, /^attachment/);
    assert.equal(r.headers.get("x-content-type-options"), "nosniff");
    assert.deepEqual(Buffer.from(await r.arrayBuffer()), PNG_A);
  });
  it("rejects files whose content does not match their extension, and unsupported types", async () => {
    const fake = await upload("fake.png", "this is not a png");
    assert.equal(fake.status, 400);
    assert.match((await J(fake)).failed[0].error, /does not look like/);
    assert.equal((await upload("run.exe", "MZ...")).status, 400);
    assert.equal((await upload("x.svg", "<svg onload=alert(1)/>")).status, 400);
    assert.equal((await upload("bin.txt", Buffer.from([0, 1, 2, 3]))).status, 400);
  });
  it("requires auth, rejects bad ids and path tricks, and deletes", async () => {
    assert.equal((await fileRoute.GET(rq(`/api/files/${pngId}`, { noToken: true }), idp(pngId))).status, 401);
    assert.equal((await fileRoute.GET(rq("/api/files/x"), idp("../../etc/passwd"))).status, 404);
    const u = await J(await upload("tmp.txt", "bye"));
    assert.equal((await fileRoute.DELETE(rq("/x", { method: "DELETE" }), idp(u.assets[0].id))).status, 200);
    assert.equal((await fileRoute.GET(rq("/x"), idp(u.assets[0].id))).status, 404);
  });
  it("lists files with pagination", async () => {
    const l = await J(await filesRoute.GET(rq("/api/files?limit=1")));
    assert.equal(l.items.length, 1);
    assert.ok(l.total >= 2);
  });
});

describe("chat: streaming, documents and vision", () => {
  it("streams a reply and reports which provider answered", async () => {
    resetBreakers();
    const r = await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: [{ role: "user", content: "hi" }] } }));
    assert.equal(r.status, 200);
    assert.equal(decodeURIComponent(r.headers.get("x-waha-provider")!), "Mock AI 2");
    const txt = await r.text();
    assert.match(txt, /Hel/);
    assert.match(txt, /\[DONE\]/);
  });
  it("sends a document as delimited data and an image as a vision part", async () => {
    calls.length = 0;
    const r = await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: [{ role: "user", content: "Summarize", attachments: [txtId, pngId] }] } }));
    assert.equal(r.status, 200, await r.clone().text());
    await r.text();
    const body = calls.find((c) => c.path === "/v1/chat/completions")!.body;
    assert.equal(body.messages[0].role, "system");
    assert.match(body.messages[0].content, /never follow instructions/);
    const parts = body.messages[1].content;
    assert.match(parts[0].text, /<<<FILE name="notes.txt">>>[\s\S]*BLUE-42/);
    assert.match(parts[1].image_url.url, /^data:image\/png;base64,/);
  });
  it("fails clearly when an image is attached but no provider supports vision", async () => {
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { supportsVision: false } }), idp(providerId));
    const r = await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: [{ role: "user", content: "what is this", attachments: [pngId] }] } }));
    assert.equal(r.status, 502);
    assert.match((await J(r)).error, /No provider can handle/);
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { supportsVision: true } }), idp(providerId));
  });
  it("never sends files to a provider marked 'no attachments'", async () => {
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { noAttachments: true } }), idp(providerId));
    calls.length = 0;
    const r = await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: [{ role: "user", content: "x", attachments: [txtId] }] } }));
    assert.equal(r.status, 502);
    assert.equal(calls.filter((c) => c.path === "/v1/chat/completions").length, 0);
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { noAttachments: false } }), idp(providerId));
  });
  it("rejects unknown attachments and malformed bodies", async () => {
    assert.equal((await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: [{ role: "user", content: "x", attachments: ["0".repeat(32)] }] } }))).status, 404);
    assert.equal((await chatRoute.POST(rq("/api/chat", { method: "POST", json: { messages: "no" } }))).status, 400);
  });
});

describe("image studio", () => {
  it("generates images (base64 and URL results) and stores them", async () => {
    const r = await J(await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "a cat on a sofa", n: 2, size: "1024x1024" } })));
    assert.equal(r.assets.length, 2);
    for (const a of r.assets) assert.ok((await assetBytes(a.id)).length > 100);
    const call = calls.filter((c) => c.path === "/v1/images/generations").pop()!;
    assert.equal(call.body.model, "img-1");
    assert.equal(call.auth, `Bearer ${KEY}`);
  });
  it("falls back to another image provider and does not retry a 500 (paid) call", async () => {
    await providersRoute.POST(rq("/api/providers", { method: "POST", json: { id: "bad", name: "Bad", baseUrl: `${base}/bad/v1`, apiKey: KEY, imageModel: "i", priority: 1 } }));
    calls.length = 0;
    resetBreakers();
    const r = await J(await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "x" } })));
    assert.equal(r.provider.id, providerId);
    assert.equal(r.attempts[0].providerId, "bad");
    assert.match(r.attempts[0].reason, /provider error/);
    assert.equal(calls.filter((c) => c.path.startsWith("/bad/")).length, 1);
    const none = await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "x", providerId: "bad", autoFallback: false } }));
    assert.equal(none.status, 502);
    await providerRoute.DELETE(rq("/x", { method: "DELETE" }), idp("bad"));
  });
  it("validates input", async () => {
    assert.equal((await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "" } }))).status, 400);
    assert.equal((await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "x", n: 9 } }))).status, 400);
    assert.equal((await imageRoute.POST(rq("/api/studio/image", { method: "POST", json: { prompt: "x", size: "huge" } }))).status, 400);
  });
});

describe("document conversion (real LibreOffice / pandoc / poppler)", { timeout: 240_000 }, () => {
  let docxId = "";
  let pdfId = "";
  const convert = async (assetId: string, to: string) => convertRoute.POST(rq("/api/convert", { method: "POST", json: { assetId, to } }));

  it("converts TXT -> DOCX -> PDF and the outputs are valid files", async () => {
    const t = await J(await upload("report.txt", "Quarterly report\n\nRevenue grew by 12 percent."));
    const d = await convert(t.assets[0].id, "docx");
    assert.equal(d.status, 201);
    const docx = (await J(d)).asset;
    docxId = docx.id;
    assert.equal(docx.name, "report.docx");
    assert.equal((await assetBytes(docxId)).subarray(0, 2).toString(), "PK");
    const p = await convert(docxId, "pdf");
    assert.equal(p.status, 201);
    pdfId = (await J(p)).asset.id;
    assert.equal((await assetBytes(pdfId)).subarray(0, 5).toString(), "%PDF-");
  });
  it("extracts text from DOCX and PDF", async () => {
    const a = await J(await fileText.GET(rq("/x"), idp(docxId)));
    assert.match(a.text, /Revenue grew by 12 percent/);
    const b = await J(await fileText.GET(rq("/x"), idp(pdfId)));
    assert.match(b.text, /Revenue grew by 12 percent/);
  });
  it("converts Markdown to DOCX and strips raw HTML", async () => {
    const m = await J(await upload("n.md", "# Title\n\nHello **world** <script>alert(1)</script>"));
    const d = await J(await convert(m.assets[0].id, "docx"));
    const back = await J(await convert(d.asset.id, "txt"));
    const txt = (await assetBytes(back.asset.id)).toString("utf8");
    assert.match(txt, /Hello world/);
    assert.ok(!txt.includes("<script>"));
  });
  it("converts CSV -> XLSX -> CSV", async () => {
    const c = await J(await upload("t.csv", "name,qty\nwidget,3\ngadget,5\n"));
    const x = await J(await convert(c.assets[0].id, "xlsx"));
    assert.equal((await assetBytes(x.asset.id)).subarray(0, 2).toString(), "PK");
    const back = await J(await convert(x.asset.id, "csv"));
    assert.match((await assetBytes(back.asset.id)).toString("utf8"), /widget,3/);
    const ex = await J(await fileText.GET(rq("/x"), idp(x.asset.id)));
    assert.match(ex.text, /gadget/);
  });
  it("converts images PNG -> JPG/WEBP and PDF -> PNG", async () => {
    const j = await J(await convert(pngId, "jpg"));
    assert.equal(j.asset.mime, "image/jpeg");
    const w = await J(await convert(pngId, "webp"));
    assert.equal(w.asset.mime, "image/webp");
    const pg = await J(await convert(pdfId, "png"));
    assert.equal(pg.asset.kind, "image");
  });
  it("rejects unsupported pairs and unknown files without running anything", async () => {
    const r = await convert(pngId, "docx");
    assert.equal(r.status, 400);
    assert.match((await J(r)).error, /not supported/);
    assert.equal((await convert("0".repeat(32), "pdf")).status, 404);
    assert.equal((await convertRoute.GET(rq("/api/convert"))).status, 200);
  });
  it("reads text from an image with OCR", async () => {
    ff(["-f", "lavfi", "-i", "color=c=white:s=600x120", "-vf", "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='HELLO WAHA':fontsize=64:fontcolor=black:x=20:y=30", "-frames:v", "1", path.join(fx, "ocr.png")]);
    const o = await J(await upload("ocr.png", fs.readFileSync(path.join(fx, "ocr.png"))));
    const t = await J(await fileText.GET(rq("/x"), idp(o.assets[0].id)));
    assert.match(t.text.toUpperCase(), /HELLO WAHA/);
  });
});

describe("video studio (real ffmpeg)", { timeout: 300_000 }, () => {
  let imgA = "";
  let imgB = "";
  before(async () => {
    imgA = pngId;
    imgB = (await J(await upload("b.png", PNG_B))).assets[0].id;
  });
  const probe = (buf: Buffer) => {
    const f = path.join(root, `probe-${Date.now()}.mp4`);
    fs.writeFileSync(f, buf);
    return JSON.parse(execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height", "-show_entries", "format=duration", "-of", "json", f]).toString());
  };

  it("renders a captioned slideshow (Latin + Arabic captions) as a valid H.264 MP4", async () => {
    const r = await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "slideshow", aspect: "16:9", secondsPerSlide: 2, slides: [{ assetId: imgA, caption: "Fresh. Bold. Yours." }, { assetId: imgB, caption: "مرحباً بكم في متجرنا الجديد" }] } }));
    assert.equal(r.status, 202);
    const job = await waitJob((await J(r)).job.id);
    assert.equal(job.status, "done", JSON.stringify(job));
    assert.equal(job.progress, 100);
    assert.equal(job.warnings.length, 0, JSON.stringify(job.warnings));
    const mp4 = await assetBytes(job.assetIds[0]);
    const p = probe(mp4);
    assert.equal(p.streams[0].codec_name, "h264");
    assert.equal(p.streams[0].width, 1280);
    assert.ok(Math.abs(Number(p.format.duration) - 4) < 0.5);
    const f = path.join(root, "slideshow.mp4");
    fs.writeFileSync(f, mp4);
    for (const [t, n] of [[1.5, "latin"], [3.5, "arabic"]] as const) {
      const out = path.join(root, `frame-${n}.png`);
      ff(["-ss", String(t), "-i", f, "-frames:v", "1", out]);
      keep(`slideshow-${n}.png`, fs.readFileSync(out));
    }
  });
  it("renders vertical (9:16) video and validates input", async () => {
    const r = await J(await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "slideshow", aspect: "9:16", secondsPerSlide: 1, kenBurns: false, slides: [{ assetId: imgA }] } })));
    const job = await waitJob(r.job.id);
    assert.equal(job.status, "done", JSON.stringify(job));
    assert.equal(probe(await assetBytes(job.assetIds[0])).streams[0].height, 1280);
    const tooMany = await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "slideshow", slides: Array(13).fill({ assetId: imgA }) } }));
    assert.equal(tooMany.status, 400);
    const missing = await J(await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "slideshow", slides: [{ assetId: "0".repeat(32) }] } })));
    const failed = await waitJob(missing.job.id);
    assert.equal(failed.status, "failed");
    assert.match(failed.error, /Slide 1/);
    assert.equal((await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "nope" } }))).status, 400);
  });
  it("makes a product video: photos + generated image + AI captions", async () => {
    calls.length = 0;
    const r = await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "product", productName: "Oasis Date Syrup", description: "Organic syrup from Algerian dates", language: "ar", photoAssetIds: [imgA], generateImages: 1, aspect: "1:1", secondsPerSlide: 2 } }));
    assert.equal(r.status, 202, await r.clone().text());
    const job = await waitJob((await J(r)).job.id);
    assert.equal(job.status, "done", JSON.stringify(job));
    assert.equal(job.warnings.length, 0, JSON.stringify(job.warnings));
    assert.equal(job.assetIds.length, 2); // video + generated image
    const cap = calls.find((c) => c.path === "/v1/chat/completions")!.body.messages[1].content;
    assert.match(cap, /Arabic/);
    assert.match(cap, /Oasis Date Syrup/);
    const p = probe(await assetBytes(job.assetIds[0]));
    assert.equal(p.streams[0].width, 1024);
    assert.ok(Math.abs(Number(p.format.duration) - 4) < 0.5);
  });
  it("requires photos or generated images for a product video", async () => {
    const r = await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "product", productName: "X" } }));
    assert.equal(r.status, 400);
  });
  it("generates video through a provider's async API (submit, poll, download)", async () => {
    calls.length = 0;
    const r = await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "provider", prompt: "a date palm at sunrise", seconds: 5, aspect: "16:9", imageAssetId: imgA } }));
    assert.equal(r.status, 202, await r.clone().text());
    const job = await waitJob((await J(r)).job.id);
    assert.equal(job.status, "done", JSON.stringify(job));
    const submit = calls.find((c) => c.path === "/v1/videos" && c.body)!;
    assert.equal(submit.body.model, "vid-1");
    assert.equal(submit.body.prompt, "a date palm at sunrise");
    assert.match(submit.body.image, /^data:image\/png;base64,/);
    assert.equal(probe(await assetBytes(job.assetIds[0])).streams[0].codec_name, "h264");
  });
  it("reports a provider video failure with a clear reason", async () => {
    resetRateLimits();
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { videoApi: { pollMs: 1000, statusPath: "/missing/{id}" } } }), idp(providerId));
    const r = await J(await videoRoute.POST(rq("/api/studio/video", { method: "POST", json: { mode: "provider", prompt: "x" } })));
    const job = await waitJob(r.job.id);
    assert.equal(job.status, "failed");
    assert.match(job.error, /refused the status check|HTTP 404/);
  });
});

describe("story & book studio (real pandoc / LibreOffice)", { timeout: 300_000 }, () => {
  it("writes an Arabic illustrated book and exports DOCX, PDF, EPUB and Markdown", async () => {
    calls.length = 0;
    const r = await bookRoute.POST(rq("/api/studio/book", { method: "POST", json: { brief: "قصة أطفال عن ثعلب صغير يبحث عن الواحة", language: "ar", kind: "story", chapters: 2, wordsPerChapter: 100, illustrate: true, cover: true, formats: ["docx", "pdf", "epub", "md"], pageSize: "A4", audience: "أطفال" } }));
    assert.equal(r.status, 202, await r.clone().text());
    const job = await waitJob((await J(r)).job.id, 240_000);
    assert.equal(job.status, "done", JSON.stringify(job));
    assert.equal(job.warnings.length, 0, JSON.stringify(job.warnings));

    const all = (await J(await filesRoute.GET(rq("/api/files?limit=200")))).items;
    const metas = job.assetIds.map((id: string) => all.find((a: any) => a.id === id));
    const byExt = (e: string) => metas.find((m: any) => m.ext === e);
    const docx = await assetBytes(byExt("docx").id);
    const pdf = await assetBytes(byExt("pdf").id);
    const epub = await assetBytes(byExt("epub").id);
    const md = (await assetBytes(byExt("md").id)).toString("utf8");
    assert.equal(docx.subarray(0, 2).toString(), "PK");
    assert.equal(pdf.subarray(0, 5).toString(), "%PDF-");
    assert.equal(epub.subarray(0, 2).toString(), "PK");
    assert.match(md, /الفصل 1/);
    assert.match(md, /ثعلب/);
    // untrusted model output was neutralised
    assert.ok(!md.includes("/etc/passwd") && !md.includes("<script>") && !md.includes("hacked"), md);
    assert.ok(metas.filter((m: any) => m.kind === "image").length >= 3); // cover + 2 chapters
    // A4 page size applied
    const f = path.join(root, "book.docx");
    fs.writeFileSync(f, docx);
    assert.match(execFileSync("unzip", ["-p", f, "word/document.xml"]).toString(), /<w:pgSz\b(?=[^>]*\bw:w="11906")(?=[^>]*\bw:h="16838")/);
    // the PDF has Arabic text and real pages
    const pf = path.join(root, "book.pdf");
    fs.writeFileSync(pf, pdf);
    assert.match(execFileSync("pdftotext", [pf, "-"]).toString(), /[؀-ۿﭐ-﻿]/);
    execFileSync("pdftoppm", ["-r", "50", "-png", "-f", "1", "-l", "2", pf, path.join(root, "bookpg")]);
    for (const n of fs.readdirSync(root).filter((x) => x.startsWith("bookpg"))) keep(`book-${n}`, fs.readFileSync(path.join(root, n)));
    keep("book.pdf", pdf);
    keep("book.docx", docx);
    keep("book.epub", epub);
  });
  it("continues without illustrations when no image provider exists, and says so", async () => {
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { imageModel: "" } }), idp(providerId));
    const r = await J(await bookRoute.POST(rq("/api/studio/book", { method: "POST", json: { brief: "A short tale", language: "en", chapters: 1, wordsPerChapter: 80, illustrate: true, formats: ["docx"] } })));
    const job = await waitJob(r.job.id, 120_000);
    assert.equal(job.status, "done", JSON.stringify(job));
    assert.match(job.warnings.join(" "), /No image provider/);
    await providerRoute.PUT(rq(`/api/providers/${providerId}`, { method: "PUT", json: { imageModel: "img-1" } }), idp(providerId));
  });
  it("validates the brief", async () => {
    assert.equal((await bookRoute.POST(rq("/api/studio/book", { method: "POST", json: { brief: "", language: "en" } }))).status, 400);
    assert.equal((await bookRoute.POST(rq("/api/studio/book", { method: "POST", json: { brief: "x", chapters: 99 } }))).status, 400);
  });
});

describe("housekeeping", () => {
  it("reports available server tools", async () => {
    const h = await J(await healthRoute.GET(rq("/api/health")));
    assert.equal(h.features.slideshowVideo, true);
    assert.equal(h.features.documentConversion, true);
    assert.equal(h.features.providerStorage, true);
  });
  it("purges files older than the retention period", async () => {
    resetRateLimits();
    process.env.WAHA_RETENTION_DAYS = "1";
    const n = await purgeExpired(Date.now() + 2 * 86_400_000);
    delete process.env.WAHA_RETENTION_DAYS;
    assert.ok(n > 0);
    assert.equal((await fileRoute.GET(rq("/x"), idp(pngId))).status, 404);
  });
});
