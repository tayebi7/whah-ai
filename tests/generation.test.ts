import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildImageRequest, imageStyle, parseImageResponse } from "../src/lib/image-requests";
import { runVeo, veoUri } from "../src/lib/veo";
import { capabilitiesOf } from "../src/lib/providers-core";
import type { Provider } from "../src/lib/providers-core";

const mk = (over: Partial<Provider>): Provider => ({
  id: "p", name: "P", baseUrl: "https://x.example.com/v1", apiKey: "k", model: "m", imageModel: "", videoModel: "", priority: 1, enabled: true,
  timeoutMs: 5000, maxRetries: 1, supportsVision: false, noAttachments: false, ...over,
});

describe("image requests", () => {
  it("detects dialects", () => {
    assert.equal(imageStyle(mk({ protocol: "gemini", imageModel: "gemini-2.5-flash-image" })), "gemini-native");
    assert.equal(imageStyle(mk({ protocol: "gemini", imageModel: "models/imagen-4.0-generate" })), "imagen");
    assert.equal(imageStyle(mk({ baseUrl: "https://openrouter.ai/api/v1", imageModel: "x" })), "openrouter");
    assert.equal(imageStyle(mk({ imageModel: "dall-e-3" })), "openai");
  });
  it("builds and parses Gemini native", () => {
    const p = mk({ protocol: "gemini", imageModel: "gemini-2.5-flash-image" });
    const r = buildImageRequest(p, "a cat");
    assert.equal(r.path, "/models/gemini-2.5-flash-image:generateContent");
    assert.deepEqual(JSON.parse(r.body).generationConfig.responseModalities, ["TEXT", "IMAGE"]);
    const out = parseImageResponse("gemini-native", { candidates: [{ content: { parts: [{ text: "ok" }, { inlineData: { mimeType: "image/png", data: "AAA" } }] } }] });
    assert.deepEqual(out, [{ b64: "AAA" }]);
  });
  it("parses Imagen, OpenRouter (data URL and URL) and OpenAI", () => {
    assert.deepEqual(parseImageResponse("imagen", { predictions: [{ bytesBase64Encoded: "BBB" }] }), [{ b64: "BBB" }]);
    assert.deepEqual(parseImageResponse("openrouter", { choices: [{ message: { images: [{ image_url: { url: "data:image/png;base64,CCC" } }, { image_url: { url: "https://h/x.png" } }] } }] }), [{ b64: "CCC" }, { url: "https://h/x.png" }]);
    assert.deepEqual(parseImageResponse("openai", { data: [{ b64_json: "D" }, { url: "https://h/y.png" }] }), [{ b64: "D" }, { url: "https://h/y.png" }]);
    assert.deepEqual(parseImageResponse("openai", null), []);
  });
  it("openrouter request asks for image modality", () => {
    const r = buildImageRequest(mk({ baseUrl: "https://openrouter.ai/api/v1", imageModel: "google/gemini-2.5-flash-image" }), "hi");
    assert.equal(r.path, "/chat/completions");
    assert.deepEqual(JSON.parse(r.body).modalities, ["image", "text"]);
  });
  it("capabilities: gemini image/video need no extra settings, anthropic has no image", () => {
    assert.equal(capabilitiesOf(mk({ protocol: "gemini", imageModel: "a", videoModel: "veo-3.0" })).image, true);
    assert.equal(capabilitiesOf(mk({ protocol: "gemini", imageModel: "a", videoModel: "veo-3.0" })).video, true);
    assert.equal(capabilitiesOf(mk({ protocol: "anthropic", imageModel: "a" })).image, false);
    assert.equal(capabilitiesOf(mk({ videoModel: "v" })).video, false);
  });
});

describe("veo", () => {
  const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status });
  it("submits, polls and downloads", async () => {
    const calls: string[] = [];
    let polls = 0;
    const bytes = await runVeo(mk({ protocol: "gemini", videoModel: "veo-3.0-generate-001" }), "a dog", "16:9", {
      call: async (path, body) => {
        calls.push(`${body ? "POST" : "GET"} ${path}`);
        if (body) return json({ name: "models/veo/operations/abc" });
        return ++polls < 2 ? json({ done: false }) : json({ done: true, response: { generateVideoResponse: { generatedSamples: [{ video: { uri: "https://generativelanguage.googleapis.com/v1/files/x:download" } }] } } });
      },
      download: async () => new Uint8Array([1, 2, 3]),
      sleep: async () => undefined, setProgress: () => undefined, aborted: () => false,
    });
    assert.deepEqual([...bytes], [1, 2, 3]);
    assert.deepEqual(calls, ["POST /models/veo-3.0-generate-001:predictLongRunning", "GET /models/veo/operations/abc", "GET /models/veo/operations/abc"]);
  });
  it("reports filtered and failed operations", async () => {
    const io = (resp: unknown) => ({ call: async (_p: string, b?: string) => (b ? json({ name: "operations/z1" }) : json(resp)), download: async () => new Uint8Array(), sleep: async () => undefined, setProgress: () => undefined, aborted: () => false });
    await assert.rejects(runVeo(mk({ protocol: "gemini", videoModel: "v" }), "x", undefined, io({ done: true, response: { generateVideoResponse: { raiMediaFilteredReasons: ["blocked"] } } })), /blocked/);
    await assert.rejects(runVeo(mk({ protocol: "gemini", videoModel: "v" }), "x", undefined, io({ error: { message: "quota" } })), /quota/);
    assert.equal(veoUri({}), undefined);
  });
  it("surfaces a rejected submit with the provider text, key redacted", async () => {
    const io = { call: async () => new Response("bad key k", { status: 400 }), download: async () => new Uint8Array(), sleep: async () => undefined, setProgress: () => undefined, aborted: () => false };
    await assert.rejects(runVeo(mk({ protocol: "gemini", videoModel: "v", apiKey: "k-secret-123" }), "x", undefined, io), (e: Error) => /HTTP 400/.test(e.message) && !e.message.includes("k-secret-123"));
  });
});

import { bestOf } from "../src/lib/model-classify";
describe("model suggestion", () => {
  it("prefers the newest version of a family", () => {
    assert.equal(bestOf(["models/gemini-2.5-flash", "models/gemini-3.8-flash", "models/gemini-2.0-flash"]), "models/gemini-3.8-flash");
    assert.equal(bestOf(["gpt-4o-mini", "gpt-4o"]), "gpt-4o-mini");
  });
});

import { buildChatRequest, normalizeStream } from "../src/lib/adapters";
import { cleanKey, validateProviderInput } from "../src/lib/providers-core";
import { providerUrl, authHeaders } from "../src/lib/provider-http";
import { keyFingerprint } from "../src/lib/router";

describe("more protocols and key hygiene", () => {
  it("cleans keys pasted with invisible marks and rejects non-ASCII", () => {
    assert.equal(cleanKey(" ‏sk-or-v1-abc‎\n"), "sk-or-v1-abc");
    assert.equal(cleanKey("Bearer sk-x1"), "sk-x1");
    assert.equal(validateProviderInput({ name: "a", baseUrl: "https://a.example.com", apiKey: "‏ sk-or-v1-abc ", model: "m" }, { allowLocal: false }).value?.apiKey, "sk-or-v1-abc");
    assert.ok(validateProviderInput({ name: "a", baseUrl: "https://a.example.com", apiKey: "مفتاح" }, { allowLocal: false }).errors.some((e) => /apiKey/.test(e)));
  });
  it("fingerprint never reveals the whole key", () => {
    const f = keyFingerprint("sk-or-v1-0123456789abcdef");
    assert.ok(f.includes("sk-or") && f.includes("cdef") && !f.includes("0123456789"));
  });
  it("azure: api-key header, deployment URL keeps api-version", () => {
    const p = mk({ protocol: "azure", baseUrl: "https://r.openai.azure.com/openai/deployments/d1", apiKey: "k" });
    assert.equal(providerUrl(p, "/chat/completions"), "https://r.openai.azure.com/openai/deployments/d1/chat/completions?api-version=2024-10-21");
    assert.equal(providerUrl({ ...p, baseUrl: `${p.baseUrl}?api-version=2025-01-01` }, "/chat/completions"), "https://r.openai.azure.com/openai/deployments/d1/chat/completions?api-version=2025-01-01");
    assert.equal(authHeaders(p)["api-key"], "k");
    assert.ok(!("model" in JSON.parse(buildChatRequest(p, [{ role: "user", content: "hi" }], true).body)));
  });
  it("ollama native: /api/chat, images as bare base64, NDJSON stream converted", async () => {
    const p = mk({ protocol: "ollama", baseUrl: "http://h:11434", model: "llava" });
    const r = buildChatRequest(p, [{ role: "user", content: [{ type: "text", text: "see" }, { type: "image_url", image_url: { url: "data:image/png;base64,QUJD" } }] }], true);
    assert.equal(r.url, "http://h:11434/api/chat");
    assert.deepEqual(JSON.parse(r.body).messages[0].images, ["QUJD"]);
    const src = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(new TextEncoder().encode('{"message":{"content":"Hel"}}\n{"message":{"content":"lo"},"done":true}\n')); c.close(); } });
    const text = await new Response(normalizeStream(p, src)).text();
    assert.ok(text.includes('"Hel"') && text.includes('"lo"') && text.includes("[DONE]"));
  });
  it("cohere v2: endpoint and content-delta events", async () => {
    const p = mk({ protocol: "cohere", baseUrl: "https://api.cohere.com", model: "command-a" });
    assert.equal(buildChatRequest(p, [{ role: "user", content: "hi" }], true).url, "https://api.cohere.com/v2/chat");
    const src = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(new TextEncoder().encode('event: content-delta\ndata: {"type":"content-delta","delta":{"message":{"content":{"text":"Salam"}}}}\n\n')); c.close(); } });
    assert.ok((await new Response(normalizeStream(p, src)).text()).includes("Salam"));
  });
});
