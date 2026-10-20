import { providerFetch } from "./provider-http";
import type { Provider } from "./providers-core";

/** Model ids from the different shapes providers use for GET /models. */
export function parseModelList(data: unknown): string[] {
  const d = data as { data?: unknown; models?: unknown } | unknown[] | null;
  const raw = Array.isArray(d) ? d : Array.isArray(d?.data) ? d.data : Array.isArray(d?.models) ? d.models : [];
  const ids = (raw as unknown[])
    .map((m) => (typeof m === "string" ? m : typeof (m as { id?: unknown })?.id === "string" ? (m as { id: string }).id : typeof (m as { name?: unknown })?.name === "string" ? (m as { name: string }).name : ""))
    .map((s) => s.replace(/^models\//, ""))
    .filter(Boolean);
  return [...new Set(ids)].sort((a, b) => a.localeCompare(b)).slice(0, 1000);
}

export class ModelListError extends Error {}

/** Asks a provider (saved or not) which models it offers. Throws ModelListError with a readable reason. */
export async function fetchModelIds(p: Provider, o: { signal?: AbortSignal; fetchImpl?: typeof fetch; describe: (e: unknown) => string }): Promise<string[]> {
  let res: Response;
  try {
    res = await providerFetch(p, (p.protocol ?? "openai") === "gemini" ? "/models?pageSize=1000" : "/models", { timeoutMs: 25_000, signal: o.signal, fetchImpl: o.fetchImpl });
  } catch (e) {
    throw new ModelListError(`Could not reach the provider: ${o.describe(e)}`);
  }
  if (!res.ok) {
    let why = "";
    try {
      const t = (await res.text()).replace(/\s+/g, " ").slice(0, 160);
      const j = JSON.parse(t) as { error?: { message?: string } | string };
      why = typeof j.error === "string" ? j.error : (j.error?.message ?? "");
    } catch {
      /* body was not JSON */
    }
    const hint = res.status === 401 || res.status === 403 ? "check the API key" : res.status === 404 ? "this provider has no model list; type the model name yourself" : `HTTP ${res.status}`;
    throw new ModelListError(`The provider did not list models (${hint}${why ? `: ${why.replace(p.apiKey || "\u0000", "***")}` : ""})`);
  }
  const ids = parseModelList(await res.json().catch(() => ({})));
  if (ids.length === 0) throw new ModelListError("The provider returned an empty model list; type the model name yourself");
  return ids;
}
