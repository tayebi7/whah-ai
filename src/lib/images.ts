import { saveAsset, type Asset } from "./assets";
import { maxGeneratedBytes } from "./config";
import { providerFetch, TimeoutError } from "./provider-http";
import { capabilitiesOf, type Provider } from "./providers";
import { redact } from "./redact";
import { downloadRemote } from "./remote";
import { breakerFail, breakerOk, breakerOpen, describeStatus, type Attempt } from "./router";

export class ImageError extends Error {
  constructor(
    message: string,
    public attempts: Attempt[],
  ) {
    super(message);
    this.name = "ImageError";
  }
}

export type ImageRequest = {
  prompt: string;
  n?: number;
  size?: string;
  providerId?: string;
  autoFallback?: boolean;
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
  resolve?: (host: string) => Promise<string[]>;
};

function sniff(b: Buffer): "png" | "jpg" | "webp" | null {
  if (b[0] === 0x89 && b[1] === 0x50) return "png";
  if (b[0] === 0xff && b[1] === 0xd8) return "jpg";
  if (b.subarray(0, 4).toString("latin1") === "RIFF" && b.subarray(8, 12).toString("latin1") === "WEBP") return "webp";
  return null;
}

/**
 * Generates images with the first image-capable provider (OpenAI-style /images/generations), falling back
 * to the next one if allowed. A failed generation is NEVER retried on the same provider: it may already
 * have been billed. Results (base64 or URL) are validated as real images before they are stored.
 */
export async function generateImages(providers: Provider[], r: ImageRequest): Promise<{ assets: Asset[]; provider: Provider; attempts: Attempt[] }> {
  const attempts: Attempt[] = [];
  let candidates = providers.filter((p) => p.enabled && capabilitiesOf(p).image);
  if (r.providerId) {
    const chosen = candidates.find((p) => p.id === r.providerId);
    if (chosen) candidates = [chosen, ...candidates.filter((p) => p !== chosen)];
  }
  if (candidates.length === 0) throw new ImageError("No image provider is configured. Add a provider with an image model in Settings.", attempts);
  if (r.autoFallback === false) candidates = candidates.slice(0, 1);

  for (const p of candidates) {
    if (breakerOpen(p.id, Date.now())) {
      attempts.push({ providerId: p.id, reason: "temporarily skipped (circuit breaker open)" });
      continue;
    }
    try {
      const body = JSON.stringify({ model: p.imageModel, prompt: r.prompt, n: r.n ?? 1, ...(r.size && r.size !== "auto" ? { size: r.size } : {}) });
      const res = await providerFetch(p, "/images/generations", { method: "POST", body, timeoutMs: Math.max(p.timeoutMs, 120_000), signal: r.signal, fetchImpl: r.fetchImpl });
      if (!res.ok) {
        breakerFail(p.id, Date.now());
        const detail = redact((await res.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 140), [p.apiKey]);
        attempts.push({ providerId: p.id, reason: `${describeStatus(res.status)}${detail ? `: ${detail}` : ""}` });
        continue;
      }
      const data = ((await res.json().catch(() => ({}))) as { data?: { b64_json?: string; url?: string }[] }).data ?? [];
      const assets: Asset[] = [];
      let i = 0;
      for (const item of data.slice(0, 8)) {
        i++;
        const buf = item.b64_json ? Buffer.from(item.b64_json, "base64") : item.url ? (await downloadRemote(item.url, { maxBytes: maxGeneratedBytes(), signal: r.signal, resolve: r.resolve, fetchImpl: r.fetchImpl })).data : null;
        const ext = buf ? sniff(buf) : null;
        if (!buf || !ext) continue;
        assets.push(await saveAsset({ name: `image-${Date.now().toString(36)}-${i}.${ext}`, data: buf, origin: "generated" }));
      }
      if (assets.length === 0) {
        breakerFail(p.id, Date.now());
        attempts.push({ providerId: p.id, reason: "the provider returned no valid images" });
        continue;
      }
      breakerOk(p.id);
      return { assets, provider: p, attempts };
    } catch (e) {
      if (r.signal?.aborted) throw new ImageError("Request cancelled", attempts);
      breakerFail(p.id, Date.now());
      attempts.push({ providerId: p.id, reason: e instanceof TimeoutError ? "timed out (not retried: the image may still be billed)" : redact(e instanceof Error ? e.message : "request failed", [p.apiKey]).slice(0, 160) });
    }
  }
  throw new ImageError("All image providers failed", attempts);
}
