/**
 * The whole Waha AI "backend" running inside the app. In the Android app there is no server: the UI still calls
 * /api/..., and this module answers those calls on the phone (providers kept in the app's own storage, chat and
 * images sent directly from the phone to the providers the user added, files kept on the phone).
 */
import { PRESETS } from "../lib/presets";
import { capabilitiesOf, toPublic } from "../lib/providers-core";
import { redact } from "../lib/redact";
import { RouterError, chatOnce, routeChat } from "../lib/router";
import { describeStatus, errorDetail } from "../lib/router";
import { describeNetError } from "../lib/net-errors";
import { fetchModelIds, ModelListError } from "../lib/model-list";
import type { Provider } from "../lib/providers-core";
import { modelsPath, providerFetch } from "../lib/provider-http";
import { testProvider } from "../lib/provider-test";
import { validateBook } from "../lib/books-core";
import { validateProductVideo, validateSlideshow } from "../lib/video-core";
import { AssetError, deleteAsset, getAsset, listAssets, readAssetData, saveAsset, toBase64 } from "./assets";
import { runBook } from "./books";
import { buildMessages, extractDocumentText, type IncomingMessage } from "./chat";
import { convertAsset, listConversions } from "./convert";
import { generateImages, ImageError } from "./images";
import { cancelJob, getJob, listJobs, startJob } from "./jobs";
import { baseFetch, chatFetchImpl, netFetch, providerFetchImpl } from "./net";
import { createProvider, deleteProvider, loadAllProviders, reorderProviders, updateProvider, validateProviderInput } from "./providers";
import { shrinkImage } from "./pdf";
import { canRecordVideo, generateProviderVideo, renderSlideshow, runProductVideo } from "./video";

const json = (status: number, body: unknown, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers } });
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

async function body(req: Request): Promise<unknown> {
  try {
    const t = await req.text();
    return t ? JSON.parse(t) : {};
  } catch {
    return undefined;
  }
}

function fail(e: unknown): Response {
  if (e instanceof AssetError) return json(e.status, { error: e.message });
  const msg = e instanceof Error ? e.message : String(e);
  return json(500, { error: msg.slice(0, 300) });
}

const providerStatus = (msg: string) => (/not found/i.test(msg) ? 404 : /set at least|needs videoApi/.test(msg) ? 400 : 0);

async function chatRoute(req: Request): Promise<Response> {
  const b = await body(req);
  if (!isRecord(b)) return json(400, { error: "Invalid request body" });
  const v = b.messages;
  if (!Array.isArray(v) || v.length < 1 || v.length > 200) return json(400, { error: "messages must be a list of 1 to 200 items" });
  const msgs: IncomingMessage[] = [];
  for (const m of v) {
    if (!isRecord(m) || !["system", "user", "assistant"].includes(m.role as string) || typeof m.content !== "string") return json(400, { error: "each message needs a valid role and text content" });
    const att = m.attachments;
    if (att !== undefined && (!Array.isArray(att) || att.length > 6 || att.some((a) => typeof a !== "string"))) return json(400, { error: "attachments must be a list of file ids" });
    msgs.push({ role: m.role as IncomingMessage["role"], content: m.content, attachments: att as string[] | undefined });
  }
  const providerId = typeof b.providerId === "string" ? b.providerId : undefined;
  const autoFallback = b.autoFallback !== false;
  try {
    const { providers } = await loadAllProviders();
    if (providers.length === 0) return json(503, { error: "No provider configured. Add one in Settings." });
    let ordered = providers;
    if (providerId) {
      const chosen = providers.find((p) => p.id === providerId);
      if (!chosen) return json(400, { error: `Unknown provider "${providerId}"` });
      ordered = [chosen, ...providers.filter((p) => p.id !== chosen.id)];
    }
    const built = await buildMessages(msgs);
    try {
      const { response, provider, attempts } = await routeChat(ordered, built.messages, { autoFallback, signal: req.signal, requireVision: built.hasImages, hasAttachments: built.hasAttachments, fetchImpl: chatFetchImpl });
      return new Response(response.body, {
        status: 200,
        headers: {
          "content-type": "text/event-stream; charset=utf-8",
          "cache-control": "no-store",
          "x-waha-provider": encodeURIComponent(provider.name),
          "x-waha-model": encodeURIComponent(provider.model),
          "x-waha-fallback": encodeURIComponent(JSON.stringify(attempts)),
        },
      });
    } catch (e) {
      if (e instanceof RouterError) return json(502, { error: redact(e.message, providers.map((p) => p.apiKey)), attempts: e.attempts });
      throw e;
    }
  } catch (e) {
    return fail(e);
  }
}

async function testRoute(id: string, req: Request): Promise<Response> {
  const b = await body(req);
  const wantChat = isRecord(b) && b.chat === true;
  const p = (await loadAllProviders()).providers.find((x) => x.id === id);
  if (!p) return json(404, { error: "Provider not found" });
  const steps = await testProvider(p, { chat: wantChat, signal: req.signal, fetchImpl: providerFetchImpl });
  return json(200, { ok: steps.every((s) => s.ok), steps });
}

async function modelsRoute(id: string, req: Request): Promise<Response> {
  const p = (await loadAllProviders()).providers.find((x) => x.id === id);
  if (!p) return json(404, { error: "Provider not found" });
  try {
    const mp = modelsPath(p);
    if (!mp) return json(502, { error: "This provider type has no model list. Enter the model name manually." });
    const res = await providerFetch(p, mp, { timeoutMs: Math.min(p.timeoutMs, 20_000), signal: req.signal, fetchImpl: providerFetchImpl });
    if (!res.ok) return json(502, { error: `This provider did not list models (HTTP ${res.status}). Enter the model id manually.` });
    const data = (await res.json().catch(() => ({}))) as { data?: unknown[]; models?: unknown[] };
    const raw = (data.data ?? data.models ?? []) as { id?: unknown; name?: unknown }[];
    const ids = raw.map((m) => (typeof m.id === "string" ? m.id : typeof m.name === "string" ? m.name.replace(/^models\//, "") : "")).filter(Boolean);
    return json(200, { models: [...new Set(ids)].sort().slice(0, 500) });
  } catch (e) {
    return json(502, { error: `Could not reach the provider: ${redact(describeNetError(e), [p.apiKey])}. Enter the model id manually.` });
  }
}


/** Models of a provider that is not saved yet (the form's URL + key), or of a saved one when the key is left empty. */
async function previewModelsRoute(req: Request): Promise<Response> {
  const b = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const { value, errors } = validateProviderInput({ baseUrl: b.baseUrl, protocol: b.protocol, headers: b.headers, orgId: b.orgId, apiKey: b.apiKey || undefined }, { partial: true });
  if (errors.length || !value.baseUrl) return json(400, { error: "Invalid provider", details: errors.length ? errors : ["baseUrl: is required"] });
  let apiKey = value.apiKey ?? "";
  let headers = value.headers;
  if (!apiKey && typeof b.providerId === "string") {
    const saved = (await loadAllProviders()).providers.find((p) => p.id === b.providerId);
    if (saved) {
      apiKey = saved.apiKey;
      headers = { ...(saved.headers ?? {}), ...(headers ?? {}) };
    }
  }
  const p: Provider = { id: "preview", name: "preview", protocol: value.protocol ?? "openai", baseUrl: value.baseUrl, apiKey, model: "x", imageModel: "", videoModel: "", priority: 1, enabled: true, timeoutMs: 25_000, maxRetries: 0, supportsVision: false, noAttachments: false, ...(headers ? { headers } : {}), ...(value.orgId ? { orgId: value.orgId } : {}) };
  try {
    return json(200, { models: await fetchModelIds(p, { signal: req.signal, fetchImpl: providerFetchImpl, describe: (e) => redact(describeNetError(e), [apiKey]) }) });
  } catch (e) {
    return json(502, { error: e instanceof ModelListError ? e.message : `Could not list models: ${redact(describeNetError(e), [apiKey])}` });
  }
}

/** Text of an image through the user's vision provider (replaces server-side OCR). */
async function imageText(id: string, req: Request): Promise<{ text: string; truncated: boolean; method: string }> {
  const { asset, data } = await readAssetData(id);
  const img = await shrinkImage(data, asset.mime, 1800).catch(() => ({ data, mime: asset.mime }));
  const { providers } = await loadAllProviders();
  const r = await chatOnce(providers, [{ role: "user", content: [{ type: "text", text: "Transcribe all the text visible in this image exactly as written, in its original language and reading order. Output only the text. If there is no text, describe the image in one sentence." }, { type: "image_url", image_url: { url: `data:${img.mime};base64,${toBase64(img.data)}` } }] }], { requireVision: true, hasAttachments: true, signal: req.signal, fetchImpl: providerFetchImpl });
  return { text: r.text.trim(), truncated: false, method: "vision" };
}

export async function handleApi(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");
  const m = req.method.toUpperCase();
  let g: RegExpMatchArray | null;
  try {
    // ------------------------------------------------ providers
    if (path === "/api/providers" && m === "GET") {
      const { providers, errors } = await loadAllProviders();
      return json(200, { providers: providers.map(toPublic), errors, presets: PRESETS });
    }
    if (path === "/api/providers" && m === "POST") {
      const { value, errors } = validateProviderInput(await body(req), { partial: false });
      if (errors.length) return json(400, { error: "Invalid provider", details: errors });
      try {
        return json(201, { provider: toPublic(await createProvider(value)) });
      } catch (e) {
        const msg = e instanceof Error ? e.message : "";
        return /already exists/.test(msg) ? json(409, { error: msg }) : fail(e);
      }
    }
    if (path === "/api/providers/reorder" && m === "POST") {
      const b = await body(req);
      if (!isRecord(b) || !Array.isArray(b.ids) || b.ids.some((x) => typeof x !== "string")) return json(400, { error: "ids must be a list of provider ids" });
      await reorderProviders(b.ids as string[]);
      return json(200, { ok: true });
    }
    if ((g = path.match(/^\/api\/providers\/([^/]+)\/test$/)) && m === "POST") return testRoute(decodeURIComponent(g[1]), req);
    if (path === "/api/models" && m === "POST") return previewModelsRoute(req);
    if ((g = path.match(/^\/api\/providers\/([^/]+)\/models$/)) && m === "GET") return modelsRoute(decodeURIComponent(g[1]), req);
    if ((g = path.match(/^\/api\/providers\/([^/]+)$/))) {
      const id = decodeURIComponent(g[1]);
      try {
        if (m === "PUT") {
          const { value, errors } = validateProviderInput(await body(req), { partial: true });
          if (errors.length) return json(400, { error: "Invalid provider", details: errors });
          return json(200, { provider: toPublic(await updateProvider(id, value)) });
        }
        if (m === "DELETE") {
          await deleteProvider(id);
          return json(200, { ok: true });
        }
      } catch (e) {
        const s = providerStatus(e instanceof Error ? e.message : "");
        return s ? json(s, { error: (e as Error).message }) : fail(e);
      }
    }

    // ------------------------------------------------ connection check
    if (path === "/api/netcheck" && m === "POST") {
      const { providers } = await loadAllProviders();
      const targets = [
        { name: "Internet (Google)", url: "https://www.google.com/generate_204" },
        { name: "Internet (Cloudflare)", url: "https://www.cloudflare.com/cdn-cgi/trace" },
        ...providers.filter((p) => p.enabled).map((p) => ({ name: p.name, url: p.baseUrl, key: p.apiKey })),
      ];
      const results = await Promise.all(
        targets.map(async (t) => {
          const t0 = Date.now();
          const ctrl = new AbortController();
          const timer = setTimeout(() => ctrl.abort(), 15_000);
          try {
            const r = await netFetch(t.url, { method: "GET", signal: ctrl.signal });
            return { name: t.name, ok: true, ms: Date.now() - t0, detail: `Reachable (HTTP ${r.status})` };
          } catch (e) {
            return { name: t.name, ok: false, ms: Date.now() - t0, detail: redact(ctrl.signal.aborted ? "no answer within 15 seconds (slow or blocked network)" : describeNetError(e), "key" in t && t.key ? [t.key] : []) };
          } finally {
            clearTimeout(timer);
          }
        }),
      );
      return json(200, { results });
    }

    // ------------------------------------------------ health
    if (path === "/api/health" && m === "GET") {
      const { providers } = await loadAllProviders();
      return json(200, {
        local: true,
        tools: {},
        features: { providerStorage: true, slideshowVideo: canRecordVideo(), documentConversion: true, bookExport: true, bookPdf: true, ocr: providers.some((p) => p.enabled && capabilitiesOf(p).vision) },
        tokenConfigured: false,
      });
    }

    // ------------------------------------------------ chat
    if (path === "/api/chat" && m === "POST") return chatRoute(req);

    // ------------------------------------------------ files
    if (path === "/api/files" && m === "GET") {
      const kind = url.searchParams.get("kind");
      return json(200, await listAssets({ limit: Number(url.searchParams.get("limit")) || 50, offset: Number(url.searchParams.get("offset")) || 0, kind: kind === "image" || kind === "document" || kind === "video" ? kind : undefined }));
    }
    if (path === "/api/files" && m === "POST") {
      let form: FormData;
      try {
        form = await req.formData();
      } catch {
        return json(400, { error: "Expected multipart/form-data with a file field" });
      }
      const files = form.getAll("file").filter((f): f is File => typeof f !== "string");
      if (files.length === 0) return json(400, { error: 'No file received (field name must be "file")' });
      if (files.length > 10) return json(400, { error: "At most 10 files per upload" });
      const saved = [];
      const failed: { name: string; error: string }[] = [];
      for (const f of files) {
        try {
          saved.push(await saveAsset({ name: f.name, data: new Uint8Array(await f.arrayBuffer()), origin: "upload" }));
        } catch (e) {
          if (e instanceof AssetError) failed.push({ name: f.name, error: e.message });
          else throw e;
        }
      }
      return json(saved.length ? 201 : 400, { assets: saved, failed });
    }
    if ((g = path.match(/^\/api\/files\/([a-f0-9]{32})\/text$/)) && m === "GET") {
      const a = await getAsset(g[1]);
      if (!a) return json(404, { error: "File not found" });
      try {
        if (a.kind === "image") return json(200, await imageText(a.id, req));
        return json(200, await extractDocumentText(a, (await readAssetData(a.id)).data));
      } catch (e) {
        return json(422, { error: e instanceof Error ? e.message : "Could not read this file" });
      }
    }
    if ((g = path.match(/^\/api\/files\/([a-f0-9]{32})$/))) {
      if (m === "GET") {
        const a = await getAsset(g[1]);
        if (!a) return json(404, { error: "File not found" });
        const { data } = await readAssetData(g[1]);
        return new Response(data as BlobPart, { status: 200, headers: { "content-type": a.mime, "content-length": String(data.length), "cache-control": "no-store" } });
      }
      if (m === "DELETE") return (await deleteAsset(g[1])) ? json(200, { ok: true }) : json(404, { error: "File not found" });
    }

    // ------------------------------------------------ jobs
    if (path === "/api/jobs" && m === "GET") return json(200, { jobs: await listJobs(Number(url.searchParams.get("limit")) || 30) });
    if ((g = path.match(/^\/api\/jobs\/([a-f0-9]{24})$/))) {
      if (m === "GET") {
        const j = await getJob(g[1]);
        return j ? json(200, { job: j }) : json(404, { error: "Job not found" });
      }
      if (m === "DELETE") return cancelJob(g[1]) ? json(200, { ok: true }) : json(404, { error: "No running job with this id" });
    }

    // ------------------------------------------------ convert
    if (path === "/api/convert" && m === "GET") return json(200, { conversions: listConversions() });
    if (path === "/api/convert" && m === "POST") {
      const b = await body(req);
      if (!isRecord(b) || typeof b.assetId !== "string" || typeof b.to !== "string") return json(400, { error: "assetId and to are required" });
      try {
        return json(201, { asset: await convertAsset(b.assetId, b.to.toLowerCase()) });
      } catch (e) {
        if (e instanceof AssetError) return fail(e);
        return json(422, { error: `Conversion failed: ${e instanceof Error ? e.message : "unknown error"}` });
      }
    }

    // ------------------------------------------------ studio
    if (path === "/api/studio/image" && m === "POST") {
      const b = await body(req);
      if (!isRecord(b) || typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
      const n = b.n === undefined ? 1 : Number(b.n);
      if (!Number.isInteger(n) || n < 1 || n > 4) return json(400, { error: "n must be 1 to 4" });
      if (b.size !== undefined && !(typeof b.size === "string" && /^(auto|\d{3,4}x\d{3,4})$/.test(b.size))) return json(400, { error: 'size must be "auto" or like 1024x1024' });
      try {
        const { providers } = await loadAllProviders();
        const r = await generateImages(providers, { prompt: b.prompt.trim(), n, size: b.size as string | undefined, providerId: typeof b.providerId === "string" ? b.providerId : undefined, autoFallback: b.autoFallback !== false, signal: req.signal });
        return json(200, { assets: r.assets, provider: { id: r.provider.id, name: r.provider.name, model: r.provider.imageModel }, attempts: r.attempts });
      } catch (e) {
        if (e instanceof ImageError) return json(e.attempts.length ? 502 : 400, { error: e.message, attempts: e.attempts });
        throw e;
      }
    }
    if (path === "/api/studio/book" && m === "POST") {
      const v = validateBook(await body(req));
      if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
      const input = v.value;
      const { providers } = await loadAllProviders();
      if (!providers.some((p) => p.enabled && p.model)) return json(400, { error: "No chat provider is configured. Add one in Settings." });
      return json(202, { job: await startJob("book", input.title || input.brief.slice(0, 60), (ctx) => runBook(input, providers, ctx)) });
    }
    if (path === "/api/studio/video" && m === "POST") {
      const b = await body(req);
      if (!isRecord(b)) return json(400, { error: "Invalid request body" });
      const mode = b.mode;
      if ((mode === "slideshow" || mode === "product") && !canRecordVideo()) return json(501, { error: "This device cannot record video, so this video mode is unavailable" });
      if (mode === "slideshow") {
        const v = validateSlideshow(b);
        if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
        const input = v.value;
        return json(202, { job: await startJob("video", "Slideshow video", async (ctx) => [(await renderSlideshow(input, ctx)).id]) });
      }
      if (mode === "product") {
        const v = validateProductVideo(b);
        if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
        const input = v.value;
        const { providers } = await loadAllProviders();
        return json(202, { job: await startJob("product-video", input.productName, (ctx) => runProductVideo(input, providers, ctx)) });
      }
      if (mode === "provider") {
        if (typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
        const { providers } = await loadAllProviders();
        const p = providers.find((x) => x.enabled && capabilitiesOf(x).video && (!b.providerId || x.id === b.providerId));
        if (!p) return json(400, { error: "No video provider is configured. Add a provider with a video model and video API settings." });
        const seconds = b.seconds === undefined ? undefined : Number(b.seconds);
        if (seconds !== undefined && !(seconds >= 1 && seconds <= 60)) return json(400, { error: "seconds must be between 1 and 60" });
        const input = { prompt: b.prompt.trim(), imageAssetId: typeof b.imageAssetId === "string" ? b.imageAssetId : undefined, seconds, aspect: typeof b.aspect === "string" && ["16:9", "9:16", "1:1"].includes(b.aspect) ? b.aspect : undefined };
        return json(202, { job: await startJob("video", `${p.name}: ${input.prompt.slice(0, 60)}`, async (ctx) => [(await generateProviderVideo(p, input, ctx)).id]) });
      }
      if (mode === "auto") {
        // Gemini-style "just describe it": real video model if one is configured, otherwise an AI storyboard video.
        if (typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
        const prompt = b.prompt.trim();
        const aspect = typeof b.aspect === "string" && ["16:9", "9:16", "1:1"].includes(b.aspect) ? (b.aspect as "16:9" | "9:16" | "1:1") : "16:9";
        const language = b.language === "en" || b.language === "fr" ? b.language : "ar";
        const { providers } = await loadAllProviders();
        const videoPs = providers.filter((x) => x.enabled && capabilitiesOf(x).video);
        const canStoryboard = canRecordVideo() && providers.some((x) => x.enabled && capabilitiesOf(x).image);
        if (videoPs.length === 0 && !canStoryboard) return json(400, { error: "No video model is configured and no image model is available for a storyboard video. Add one in Settings." });
        return json(202, {
          job: await startJob("video", prompt.slice(0, 60), async (ctx) => {
            const problems: string[] = [];
            for (const p of videoPs) {
              try {
                return [(await generateProviderVideo(p, { prompt, aspect }, ctx)).id];
              } catch (e) {
                if (ctx.signal.aborted) throw e;
                problems.push(`${p.name}: ${(e as Error).message}`);
                ctx.warn(`${p.name}: ${(e as Error).message}`);
              }
            }
            if (!canStoryboard) throw new Error(problems.join(" | ") || "Video generation failed");
            if (problems.length) ctx.warn("Falling back to an AI storyboard video");
            return runProductVideo({ productName: prompt.slice(0, 120), description: prompt.slice(0, 2000), language, photoAssetIds: [], generateImages: 4, aspect, secondsPerSlide: 3, scene: true }, providers, ctx);
          }),
        });
      }
      return json(400, { error: 'mode must be "slideshow", "product", "provider" or "auto"' });
    }
    return json(404, { error: `Not found: ${m} ${path}` });
  } catch (e) {
    return fail(e);
  }
}

let installed = false;
/** Routes the UI's /api/... calls to this module; every other request goes straight to the network (natively on Android, so CORS does not apply). */
export function installLocalApi(): void {
  if (installed || typeof window === "undefined") return;
  installed = true;
  void baseFetch;
  window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const raw = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    let u: URL;
    try {
      u = new URL(raw, window.location.href);
    } catch {
      return netFetch(input, init);
    }
    if (u.origin === window.location.origin && u.pathname.startsWith("/api/")) return handleApi(new Request(u.href, init ?? (input instanceof Request ? input : undefined)));
    return netFetch(input, init);
  }) as typeof fetch;
}
