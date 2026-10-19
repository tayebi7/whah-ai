import { providerFetch, TimeoutError } from "../lib/provider-http";
import { capabilitiesOf, type Provider } from "../lib/providers-core";
import { describeNetError } from "../lib/net-errors";
import { redact } from "../lib/redact";
import { breakerFail, breakerOk, breakerOpen, describeStatus, type Attempt } from "../lib/router";
import { saveAsset, fromBase64, sniffImage, type Asset } from "./assets";
import { netFetch, providerFetchImpl } from "./net";

export class ImageError extends Error {
  constructor(message: string, public attempts: Attempt[]) {
    super(message);
    this.name = "ImageError";
  }
}

export type ImageRequest = { prompt: string; n?: number; size?: string; providerId?: string; autoFallback?: boolean; signal?: AbortSignal };

/** Downloads a generated image/video from a URL the provider returned. */
export async function downloadBytes(url: string, maxBytes: number, signal?: AbortSignal): Promise<Uint8Array> {
  if (!/^https?:\/\//i.test(url)) throw new Error("unsupported result URL");
  const res = await netFetch(url, { signal }, { binary: true });
  if (!res.ok) throw new Error(`download failed (HTTP ${res.status})`);
  const buf = new Uint8Array(await res.arrayBuffer());
  if (buf.length > maxBytes) throw new Error("the result is too large");
  return buf;
}

/**
 * Picks the first provider that has an image model (OpenAI-style /images/generations) and falls back to the
 * next one if allowed. A failed generation is never retried on the same provider: it may already be billed.
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
      const res = await providerFetch(p, "/images/generations", { method: "POST", body, timeoutMs: Math.max(p.timeoutMs, 120_000), signal: r.signal, fetchImpl: providerFetchImpl });
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
        let buf: Uint8Array | null = null;
        try {
          buf = item.b64_json ? fromBase64(item.b64_json) : item.url ? await downloadBytes(item.url, 50 * 1024 * 1024, r.signal) : null;
        } catch {
          buf = null;
        }
        const ext = buf ? sniffImage(buf) : null;
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
      attempts.push({ providerId: p.id, reason: e instanceof TimeoutError ? "timed out (not retried: the image may still be billed)" : redact(describeNetError(e), [p.apiKey]).slice(0, 260) });
    }
  }
  throw new ImageError("All image providers failed", attempts);
}
