/**
 * SSRF guard for provider URLs and server-side downloads.
 * assertSafeUrl checks the literal hostname only. Resolving DNS is done by remote.ts for
 * downloads; there is still a small window between the DNS check and the connection
 * (DNS rebinding). For internet-facing deployments also restrict egress at the network level.
 */
export function assertSafeUrl(raw: string, allowLocal = false): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error("Invalid URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("Only http(s) URLs are allowed");
  if (url.username || url.password) throw new Error("Credentials in URL are not allowed");
  if (!allowLocal && isPrivateHost(url.hostname)) throw new Error("Private or local addresses are blocked (set WAHA_ALLOW_LOCAL=true for local models)");
  if (!allowLocal && url.protocol !== "https:") throw new Error("HTTPS is required for non-local providers");
  return url;
}

function privateV4(a: number, b: number): boolean {
  return a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
}

export function isPrivateHost(hostnameRaw: string): boolean {
  const h = hostnameRaw.toLowerCase().replace(/^\[|\]$/g, "");
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local") || h.endsWith(".internal")) return true;
  if (h.includes(":")) {
    // IPv6 literal (hostnames never contain ":").
    if (h === "::1" || h === "::") return true;
    if (/^f[cd]/.test(h) || /^fe[89ab]/.test(h)) return true; // ULA fc00::/7, link-local fe80::/10
    const mapped = h.match(/^::ffff:(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
    if (mapped) return privateV4(Number(mapped[1]), Number(mapped[2]));
    const hex = h.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/); // the URL parser normalizes to hex pairs
    if (hex) {
      const hi = parseInt(hex[1], 16);
      return privateV4(hi >> 8, hi & 255);
    }
    return false;
  }
  const m = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  return m ? privateV4(Number(m[1]), Number(m[2])) : false;
}
