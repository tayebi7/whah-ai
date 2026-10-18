import { fail } from "../../../lib/api-errors";
import { guard, json, readJson } from "../../../lib/http";
import { PRESETS } from "../../../lib/presets";
import { createProvider, loadAllProviders, toPublic, validateProviderInput } from "../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Provider metadata only. API keys and header values are never sent to the browser. */
export async function GET(req: Request) {
  const g = guard(req, { bucket: "providers", limit: 120 });
  if (g) return g;
  try {
    const { providers, errors } = await loadAllProviders();
    return json(200, { providers: providers.map(toPublic), errors, presets: PRESETS });
  } catch (e) {
    return fail(e);
  }
}

export async function POST(req: Request) {
  const g = guard(req, { bucket: "settings", limit: 30 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const { value, errors } = validateProviderInput(body.value, { partial: false });
  if (errors.length) return json(400, { error: "Invalid provider", details: errors });
  try {
    return json(201, { provider: toPublic(await createProvider(value)) });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "";
    if (/already exists/.test(msg)) return json(409, { error: msg });
    if (/WAHA_ENCRYPTION_KEY/.test(msg)) return json(503, { error: msg });
    return fail(e);
  }
}
