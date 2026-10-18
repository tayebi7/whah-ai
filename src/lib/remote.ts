import dns from "node:dns/promises";
import { allowLocal as allowLocalEnv } from "./config";
import { assertSafeUrl, isPrivateHost } from "./ssrf";

export type RemoteOptions = {
  maxBytes: number;
  timeoutMs?: number;
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
  /** Injectable DNS lookup (tests). */
  resolve?: (host: string) => Promise<string[]>;
};

const defaultResolve = async (host: string) => (await dns.lookup(host, { all: true })).map((a) => a.address);

/**
 * Downloads a URL handed back by a provider (a generated image or video link).
 * Blocks private/local targets (literal hostnames AND the addresses the name resolves to),
 * never follows redirects, enforces a size cap while streaming, and a timeout.
 * Remaining gap: DNS could change between our check and the connection (rebinding); restrict
 * server egress at the network level for internet-facing deployments.
 */
export async function downloadRemote(rawUrl: string, o: RemoteOptions): Promise<{ data: Buffer; contentType: string }> {
  const local = allowLocalEnv();
  const url = assertSafeUrl(rawUrl, local);
  if (!local) {
    const host = url.hostname.replace(/^\[|\]$/g, "");
    const addrs = /^[\d.]+$/.test(host) || host.includes(":") ? [host] : await (o.resolve ?? defaultResolve)(host).catch(() => []);
    if (addrs.length === 0) throw new Error("Could not resolve the download address");
    if (addrs.some((a) => isPrivateHost(a))) throw new Error("The download address points to a private network and was blocked");
  }
  const ctrl = new AbortController();
  const onAbort = () => ctrl.abort();
  o.signal?.addEventListener("abort", onAbort, { once: true });
  const timer = setTimeout(() => ctrl.abort(), o.timeoutMs ?? 120_000);
  try {
    const res = await (o.fetchImpl ?? fetch)(url, { redirect: "manual", signal: ctrl.signal });
    if (res.status >= 300 && res.status < 400) throw new Error("The download link redirected, and redirects are not followed");
    if (!res.ok || !res.body) throw new Error(`Download failed (HTTP ${res.status})`);
    const declared = Number(res.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > o.maxBytes) throw new Error("The file is larger than the allowed limit");
    const chunks: Buffer[] = [];
    let total = 0;
    const reader = res.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > o.maxBytes) {
        await reader.cancel().catch(() => undefined);
        throw new Error("The file is larger than the allowed limit");
      }
      chunks.push(Buffer.from(value));
    }
    return { data: Buffer.concat(chunks), contentType: res.headers.get("content-type") ?? "application/octet-stream" };
  } catch (e) {
    if (o.signal?.aborted) throw new Error("cancelled");
    if (e instanceof Error && e.name === "AbortError") throw new Error("The download timed out");
    throw e;
  } finally {
    clearTimeout(timer);
    o.signal?.removeEventListener("abort", onAbort);
  }
}
