import { buildChatRequest, collectText, normalizeStream, type ChatMessage } from "./adapters";
import type { Provider } from "./providers";

export type { ChatMessage, ChatPart } from "./adapters";
export type Attempt = { providerId: string; reason: string };

export class RouterError extends Error {
  constructor(
    message: string,
    public attempts: Attempt[],
  ) {
    super(message);
    this.name = "RouterError";
  }
}

export type RouteOptions = {
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
  now?: () => number;
  signal?: AbortSignal;
  autoFallback?: boolean;
  stream?: boolean; // default true
  requireVision?: boolean; // request contains images
  hasAttachments?: boolean; // request contains user files (images or document text)
};

export type RouteResult = { response: Response; provider: Provider; attempts: Attempt[]; streamed: boolean };

const BREAKER_THRESHOLD = 3;
const BREAKER_OPEN_MS = 30_000;
const BACKOFF_BASE_MS = 500;
const BACKOFF_CAP_MS = 8_000;

const breakers = new Map<string, { fails: number; openUntil: number }>();
export const resetBreakers = () => breakers.clear();
export function breakerFail(id: string, now: number) {
  const b = breakers.get(id) ?? { fails: 0, openUntil: 0 };
  b.fails += 1;
  if (b.fails >= BREAKER_THRESHOLD) b.openUntil = now + BREAKER_OPEN_MS;
  breakers.set(id, b);
}
export const breakerOk = (id: string) => void breakers.delete(id);
export function breakerOpen(id: string, now: number) {
  const b = breakers.get(id);
  return !!b && b.openUntil > now;
}

export function backoffDelay(attempt: number, random: () => number = Math.random): number {
  const exp = Math.min(BACKOFF_CAP_MS, BACKOFF_BASE_MS * 2 ** attempt);
  return Math.floor(exp * (0.5 + random() * 0.5)); // jitter: 50%-100% of exp
}

export function describeStatus(status: number): string {
  if (status === 401 || status === 403) return `invalid credentials (HTTP ${status})`;
  if (status === 404) return `model or endpoint not found (HTTP ${status})`;
  if (status === 429) return "rate limited (HTTP 429)";
  if (status === 400 || status === 413 || status === 422) return `request rejected, possibly unsupported feature or context too long (HTTP ${status})`;
  if (status >= 500) return `provider error (HTTP ${status})`;
  return `unexpected response (HTTP ${status})`;
}

export const isRetryableStatus = (s: number) => s === 429 || s === 500 || s === 502 || s === 503 || s === 504;

/**
 * Sends a chat request. Tries providers in order (fallback only if enabled). Retries the SAME
 * provider only for 429/5xx responses and connection errors, never for auth/model errors, and never
 * after a timeout (the outcome is ambiguous and a paid request may already be running). Providers
 * that cannot handle the request (no vision, or configured to never receive attachments) are
 * skipped and reported, never silently sent the data. Redirects are refused. The returned Response
 * is only a provider's successful (2xx) response, already converted to OpenAI-style events.
 */
export async function routeChat(providers: Provider[], messages: ChatMessage[], opts: RouteOptions = {}): Promise<RouteResult> {
  const doFetch = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const now = opts.now ?? Date.now;
  const attempts: Attempt[] = [];

  const candidates = opts.autoFallback === false ? providers.slice(0, 1) : providers;
  const usable: Provider[] = [];
  for (const p of candidates) {
    if (!p.enabled || !p.model) continue;
    if (opts.hasAttachments && p.noAttachments) {
      attempts.push({ providerId: p.id, reason: "skipped: configured to never receive user files" });
      continue;
    }
    if (opts.requireVision && !p.supportsVision) {
      attempts.push({ providerId: p.id, reason: "skipped: this provider does not accept images" });
      continue;
    }
    usable.push(p);
  }
  if (usable.length === 0) {
    const why = opts.requireVision ? "no enabled provider accepts images" : opts.hasAttachments ? "no enabled provider is allowed to receive files" : "no enabled provider has a chat model";
    throw new RouterError(`No provider can handle this request (${why}). Check Settings.`, attempts);
  }

  for (const provider of usable) {
    if (breakerOpen(provider.id, now())) {
      attempts.push({ providerId: provider.id, reason: "temporarily skipped (circuit breaker open)" });
      continue;
    }
    let req;
    try {
      req = buildChatRequest(provider, messages, opts.stream !== false);
    } catch (e) {
      attempts.push({ providerId: provider.id, reason: (e as Error).message });
      continue;
    }

    for (let n = 0; n <= provider.maxRetries; n++) {
      if (opts.signal?.aborted) throw new RouterError("Request cancelled", attempts);
      const ctrl = new AbortController();
      const onAbort = () => ctrl.abort();
      opts.signal?.addEventListener("abort", onAbort, { once: true });
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        ctrl.abort();
      }, provider.timeoutMs);

      let res: Response;
      try {
        res = await doFetch(req.url, { method: "POST", redirect: "error", headers: req.headers, body: req.body, signal: ctrl.signal });
      } catch {
        clearTimeout(timer);
        opts.signal?.removeEventListener("abort", onAbort);
        if (opts.signal?.aborted) throw new RouterError("Request cancelled", attempts);
        breakerFail(provider.id, now());
        if (timedOut) {
          attempts.push({ providerId: provider.id, reason: "timed out (not retried to avoid duplicate paid requests)" });
          break;
        }
        if (n < provider.maxRetries) {
          await sleep(backoffDelay(n, opts.random)); // connection error before any response: safe to retry
          continue;
        }
        attempts.push({ providerId: provider.id, reason: "connection failed" });
        break;
      }
      clearTimeout(timer);
      opts.signal?.removeEventListener("abort", onAbort);

      if (res.ok && res.body) {
        breakerOk(provider.id);
        const body = req.streamed ? normalizeStream(provider, res.body) : res.body;
        return { response: new Response(body, { status: 200, headers: res.headers }), provider, attempts, streamed: req.streamed };
      }

      const status = res.status;
      await res.body?.cancel().catch(() => undefined);
      breakerFail(provider.id, now());
      if (isRetryableStatus(status) && n < provider.maxRetries) {
        const retryAfter = Number(res.headers.get("retry-after"));
        await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? Math.min(retryAfter * 1000, BACKOFF_CAP_MS) : backoffDelay(n, opts.random));
        continue;
      }
      attempts.push({ providerId: provider.id, reason: describeStatus(status) });
      break;
    }
  }
  throw new RouterError("All providers failed", attempts);
}

/** Non-streaming convenience used by the studios (outlines, captions, chapters). */
export async function chatOnce(providers: Provider[], messages: ChatMessage[], opts: RouteOptions = {}): Promise<{ text: string; provider: Provider; attempts: Attempt[] }> {
  const r = await routeChat(providers, messages, { ...opts, stream: false });
  let text: unknown;
  try {
    if (r.streamed) text = await collectText(r.response.body as ReadableStream<Uint8Array>);
    else text = ((await r.response.json()) as { choices?: { message?: { content?: unknown } }[] })?.choices?.[0]?.message?.content;
  } catch {
    throw new RouterError("Provider returned an unreadable response", r.attempts);
  }
  if (typeof text !== "string" || !text.trim()) throw new RouterError("Provider returned an empty response", r.attempts);
  return { text, provider: r.provider, attempts: r.attempts };
}

/** Pulls the first JSON object/array out of a model reply (handles code fences and chatter). */
export function parseJsonLoose<T = unknown>(text: string): T {
  const cleaned = text.replace(/```(?:json)?/gi, "").trim();
  const starts = [cleaned.indexOf("{"), cleaned.indexOf("[")].filter((i) => i >= 0);
  if (!starts.length) throw new Error("The model did not return JSON");
  const start = Math.min(...starts);
  const close = cleaned[start] === "{" ? "}" : "]";
  const end = cleaned.lastIndexOf(close);
  if (end <= start) throw new Error("The model returned incomplete JSON");
  return JSON.parse(cleaned.slice(start, end + 1)) as T;
}
