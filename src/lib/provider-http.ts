import { cleanKey } from "./providers-core";
import type { Provider } from "./providers";

export class TimeoutError extends Error {
  constructor(message = "request timed out") {
    super(message);
    this.name = "TimeoutError";
  }
}

/** base + path, keeping a query string that belongs to the base (Azure's ?api-version=...) at the end. */
export function providerUrl(p: Pick<Provider, "baseUrl" | "protocol">, path: string): string {
  const q = p.baseUrl.indexOf("?");
  const base = q < 0 ? p.baseUrl : p.baseUrl.slice(0, q);
  let query = q < 0 ? "" : p.baseUrl.slice(q + 1);
  if (p.protocol === "azure" && !/(^|&)api-version=/.test(query)) query += `${query ? "&" : ""}api-version=2024-10-21`;
  const pq = path.indexOf("?");
  const joined = `${base}${pq < 0 ? path : path.slice(0, pq)}`;
  const all = [pq < 0 ? "" : path.slice(pq + 1), query].filter(Boolean).join("&");
  return all ? `${joined}?${all}` : joined;
}

/** Path that lists models for a protocol (null when the protocol has no list endpoint). */
export function modelsPath(p: Pick<Provider, "protocol">): string | null {
  switch (p.protocol ?? "openai") {
    case "gemini": return "/models?pageSize=1000";
    case "ollama": return "/api/tags";
    case "cohere": return "/v1/models?page_size=1000";
    case "azure": return null;
    default: return "/models";
  }
}

export type ProviderFetchOptions = { method?: string; body?: string | null; headers?: Record<string, string>; timeoutMs?: number; signal?: AbortSignal; fetchImpl?: typeof fetch };

/** Headers every provider call carries (auth differs per protocol). */
export function authHeaders(p: Provider): Record<string, string> {
  const protocol = p.protocol ?? "openai";
  const key = cleanKey(p.apiKey);
  const auth: Record<string, string> =
    protocol === "anthropic" ? { "x-api-key": key, "anthropic-version": "2023-06-01" } : protocol === "gemini" ? { "x-goog-api-key": key } : protocol === "azure" ? { "api-key": key } : key ? { authorization: `Bearer ${key}` } : {};
  return { ...auth, ...(p.orgId && protocol === "openai" ? { "OpenAI-Organization": p.orgId } : {}), ...(p.headers ?? {}) };
}

/**
 * One HTTP call to a provider. Never follows redirects (a compromised or malicious endpoint could
 * otherwise bounce the request, with the API key, to an internal address). Throws TimeoutError on
 * timeout and Error("cancelled") if aborted.
 */
export async function providerFetch(p: Provider, path: string, o: ProviderFetchOptions = {}): Promise<Response> {
  const ctrl = new AbortController();
  const onAbort = () => ctrl.abort();
  o.signal?.addEventListener("abort", onAbort, { once: true });
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    ctrl.abort();
  }, o.timeoutMs ?? p.timeoutMs);
  try {
    return await (o.fetchImpl ?? fetch)(providerUrl(p, path), {
      method: o.method ?? "GET",
      redirect: "error",
      headers: { ...(o.body ? { "content-type": "application/json" } : {}), ...authHeaders(p), ...(o.headers ?? {}) },
      body: o.body ?? undefined,
      signal: ctrl.signal,
    });
  } catch (e) {
    if (o.signal?.aborted) throw new Error("cancelled");
    if (timedOut) throw new TimeoutError();
    throw e;
  } finally {
    clearTimeout(timer);
    o.signal?.removeEventListener("abort", onAbort);
  }
}
