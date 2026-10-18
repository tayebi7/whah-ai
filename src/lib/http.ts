import { createHash, timingSafeEqual } from "node:crypto";

export function json(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers } });
}

export type AuthResult = { ok: true } | { ok: false; status: number; error: string };

const sha = (s: string) => createHash("sha256").update(s).digest();

/**
 * Shared-token guard for every /api route.
 * - WAHA_ACCESS_TOKEN set: header x-waha-token must match (constant-time comparison).
 * - not set: allowed only outside production (local development).
 * This is one shared secret for a private deployment, NOT multi-user authentication.
 */
export function authorize(req: Request): AuthResult {
  const token = process.env.WAHA_ACCESS_TOKEN;
  if (!token) {
    if (process.env.NODE_ENV === "production") return { ok: false, status: 503, error: "Server is not configured: set WAHA_ACCESS_TOKEN before exposing this app." };
    return { ok: true };
  }
  const given = req.headers.get("x-waha-token") ?? "";
  return timingSafeEqual(sha(given), sha(token)) ? { ok: true } : { ok: false, status: 401, error: "Unauthorized: missing or wrong access token" };
}

const buckets = new Map<string, number[]>();

/** In-memory sliding window, per server instance only. True when the caller is over the limit. */
export function rateLimited(key: string, limit: number, windowMs = 60_000, now = Date.now()): boolean {
  const recent = (buckets.get(key) ?? []).filter((t) => now - t < windowMs);
  recent.push(now);
  buckets.set(key, recent);
  if (buckets.size > 5000) for (const [k, v] of buckets) if (!v.some((t) => now - t < windowMs)) buckets.delete(k);
  return recent.length > limit;
}

export function resetRateLimits() {
  buckets.clear();
}

export const clientId = (req: Request) => req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "local";

/** Auth + per-client rate limit. Returns a Response to send, or null to continue. */
export function guard(req: Request, opts: { bucket: string; limit: number }): Response | null {
  const a = authorize(req);
  if (!a.ok) return json(a.status, { error: a.error });
  if (rateLimited(`${opts.bucket}:${clientId(req)}`, opts.limit)) return json(429, { error: "Too many requests. Please wait a minute." });
  return null;
}

export async function readJson(req: Request, maxChars = 1_000_000): Promise<{ ok: true; value: unknown } | { ok: false; res: Response }> {
  let text: string;
  try {
    text = await req.text();
  } catch {
    return { ok: false, res: json(400, { error: "Could not read the request body" }) };
  }
  if (text.length > maxChars) return { ok: false, res: json(413, { error: "Request body too large" }) };
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, res: json(400, { error: "Request body is not valid JSON" }) };
  }
}

export const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
