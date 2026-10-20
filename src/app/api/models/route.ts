import { fail } from "../../../lib/api-errors";
import { guard, isRecord, json, readJson } from "../../../lib/http";
import { fetchModelIds, ModelListError } from "../../../lib/model-list";
import { describeNetError } from "../../../lib/net-errors";
import { loadAllProviders, validateProviderInput, type Provider } from "../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Lists the models of a provider that is not saved yet (URL + key typed in the form), or of a saved one when the key is left empty. */
export async function POST(req: Request) {
  const g = guard(req, { bucket: "provider-test", limit: 20 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  if (!isRecord(body.value)) return json(400, { error: "Invalid request body" });
  const b = body.value;
  const { value, errors } = validateProviderInput({ baseUrl: b.baseUrl, protocol: b.protocol, headers: b.headers, orgId: b.orgId, apiKey: b.apiKey || undefined }, { partial: true });
  if (errors.length || !value.baseUrl) return json(400, { error: "Invalid provider", details: errors.length ? errors : ["baseUrl: is required"] });
  try {
    let apiKey = value.apiKey ?? "";
    let headers = value.headers;
    if (!apiKey && typeof b.providerId === "string") {
      const saved = (await loadAllProviders()).providers.find((p) => p.id === b.providerId);
      if (saved) {
        apiKey = saved.apiKey;
        headers = { ...(saved.headers ?? {}), ...(headers ?? {}) };
      }
    }
    const p: Provider = { id: "preview", name: "preview", protocol: value.protocol ?? "openai", baseUrl: value.baseUrl, apiKey, model: "x", imageModel: "", videoModel: "", priority: 1, enabled: true, timeoutMs: 25_000, maxRetries: 0, supportsVision: false, noAttachments: false, ...(headers ? { headers } : {}), ...(value.orgId ? { orgId: value.orgId } : {}) };
    return json(200, { models: await fetchModelIds(p, { signal: req.signal, describe: describeNetError }) });
  } catch (e) {
    if (e instanceof ModelListError) return json(502, { error: e.message });
    return fail(e);
  }
}
