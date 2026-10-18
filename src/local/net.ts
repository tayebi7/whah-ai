import { Capacitor, CapacitorHttp } from "@capacitor/core";

type NativeHttp = typeof CapacitorHttp;

/**
 * Network access from the phone to AI providers.
 * In the Android app the WebView's own fetch is blocked by CORS for most providers (for example NVIDIA),
 * so requests go through Capacitor's native HTTP client. In a normal browser the page's fetch is used.
 * Requests never depend on a server of ours: the phone talks to the provider directly.
 */
/** The page's own fetch, captured before the /api interceptor wraps it. */
export const baseFetch: typeof fetch = typeof globalThis.fetch === "function" ? globalThis.fetch.bind(globalThis) : ((() => Promise.reject(new Error("fetch is not available"))) as typeof fetch);
const nativeHttp = (): NativeHttp | undefined => (Capacitor.isNativePlatform() ? CapacitorHttp : undefined);
export const isNative = () => !!nativeHttp();

const abortError = () => new DOMException("The operation was aborted", "AbortError");

function race<T>(p: Promise<T>, signal?: AbortSignal | null): Promise<T> {
  if (!signal) return p;
  if (signal.aborted) return Promise.reject(abortError());
  return new Promise<T>((resolve, reject) => {
    const on = () => reject(abortError());
    signal.addEventListener("abort", on, { once: true });
    p.then(
      (v) => (signal.removeEventListener("abort", on), resolve(v)),
      (e) => (signal.removeEventListener("abort", on), reject(e)),
    );
  });
}

const toHeaders = (h: HeadersInit | undefined): Record<string, string> => {
  const out: Record<string, string> = {};
  if (!h) return out;
  if (h instanceof Headers) h.forEach((v, k) => (out[k] = v));
  else if (Array.isArray(h)) for (const [k, v] of h) out[k] = v;
  else Object.assign(out, h);
  return out;
};

const fromBase64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export type NetOptions = { binary?: boolean; timeoutMs?: number };

/** fetch() for provider calls. Pass { binary: true } when downloading an image or video. */
export async function netFetch(input: RequestInfo | URL, init: RequestInit = {}, o: NetOptions = {}): Promise<Response> {
  const native = nativeHttp();
  if (!native) return baseFetch(input, init);

  const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
  const method = (init.method ?? "GET").toUpperCase();
  const headers = toHeaders(init.headers);
  let data: unknown;
  if (typeof init.body === "string") {
    const ct = Object.entries(headers).find(([k]) => k.toLowerCase() === "content-type")?.[1] ?? "";
    try {
      data = /json/i.test(ct) ? JSON.parse(init.body) : init.body;
    } catch {
      data = init.body;
    }
  }
  const res = await race(
    native.request({ url, method, headers, ...(data !== undefined ? { data } : {}), responseType: o.binary ? "blob" : "text", connectTimeout: 30_000, readTimeout: o.timeoutMs ?? 120_000 }),
    init.signal,
  );
  const outHeaders = new Headers();
  for (const [k, v] of Object.entries(res.headers ?? {})) {
    try {
      outHeaders.set(k, v);
    } catch {
      /* ignore invalid header */
    }
  }
  const noBody = res.status === 204 || res.status === 205 || res.status === 304;
  let body: BodyInit | null = null;
  if (!noBody) {
    if (o.binary && typeof res.data === "string") body = fromBase64(res.data) as unknown as BodyInit;
    else body = typeof res.data === "string" ? res.data : res.data === undefined || res.data === null ? "" : JSON.stringify(res.data);
  }
  return new Response(body, { status: res.status >= 200 && res.status <= 599 ? res.status : 502, headers: outHeaders });
}

/** A fetch usable by the router / image / video code: provider calls use the native client when available. */
export const providerFetchImpl: typeof fetch = (input, init) => netFetch(input, init);
