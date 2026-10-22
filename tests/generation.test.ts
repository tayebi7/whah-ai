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
