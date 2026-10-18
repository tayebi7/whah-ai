import { fail } from "../../../../../lib/api-errors";
import { guard, json } from "../../../../../lib/http";
import { providerFetch } from "../../../../../lib/provider-http";
import { loadAllProviders } from "../../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Lists model ids from the provider's /models endpoint (when it has one). */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(req, { bucket: "provider-test", limit: 20 });
  if (g) return g;
  const { id } = await params;
  try {
    const p = (await loadAllProviders()).providers.find((x) => x.id === id);
    if (!p) return json(404, { error: "Provider not found" });
    const res = await providerFetch(p, "/models", { timeoutMs: Math.min(p.timeoutMs, 20_000), signal: req.signal });
    if (!res.ok) return json(502, { error: `This provider did not list models (HTTP ${res.status}). Enter the model id manually.` });
    const data = (await res.json().catch(() => ({}))) as { data?: { id?: unknown }[]; models?: { name?: unknown; id?: unknown }[] };
    const raw = (data.data ?? data.models ?? []) as { id?: unknown; name?: unknown }[];
    const ids = raw.map((m) => (typeof m.id === "string" ? m.id : typeof m.name === "string" ? m.name.replace(/^models\//, "") : "")).filter(Boolean);
    return json(200, { models: [...new Set(ids)].sort().slice(0, 500) });
  } catch (e) {
    if (e instanceof Error && (e.name === "TimeoutError" || /fetch failed|cancelled/.test(e.message))) return json(502, { error: "Could not reach the provider. Enter the model id manually." });
    return fail(e);
  }
}
