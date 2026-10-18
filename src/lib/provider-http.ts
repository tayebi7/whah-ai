import type { Provider } from "./providers";

export class TimeoutError extends Error {
  constructor(message = "request timed out") {
    super(message);
    this.name = "TimeoutError";
  }
}

export type ProviderFetchOptions = { method?: string; body?: string | null; headers?: Record<string, string>; timeoutMs?: number; signal?: AbortSignal; fetchImpl?: typeof fetch };

/** Headers every provider call carries (auth differs per protocol). */
export function authHeaders(p: Provider): Record<string, string> {
  const protocol = p.protocol ?? "openai";
  const auth: Record<string, string> =
    protocol === "anthropic" ? { "x-api-key": p.apiKey, "anthropic-version": "2023-06-01" } : protocol === "gemini" ? { "x-goog-api-key": p.apiKey } : p.apiKey ? { authorization: `Bearer ${p.apiKey}` } : {};
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
    return await (o.fetchImpl ?? fetch)(`${p.baseUrl}${path}`, {
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
