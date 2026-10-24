import { fail } from "../../../../../lib/api-errors";
import { guard, isRecord, json, readJson } from "../../../../../lib/http";
import { testProvider } from "../../../../../lib/provider-test";
import { loadAllProviders } from "../../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Checks a provider. "connection" calls /models (free). With {"chat": true} it also sends a tiny chat
 * request (a few tokens, may be billed) to prove the model id works. Image and video models are NOT
 * test-called because that would cost real money.
 */
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(req, { bucket: "provider-test", limit: 20 });
  if (g) return g;
  const { id } = await params;
  const body = await readJson(req);
  const wantChat = body.ok && isRecord(body.value) && body.value.chat === true;
  try {
    const p = (await loadAllProviders()).providers.find((x) => x.id === id);
    if (!p) return json(404, { error: "Provider not found" });
    if (p.keyUnreadable) return json(200, { ok: false, steps: [{ name: "credentials", ok: false, detail: "The stored key cannot be decrypted (the encryption key changed). Re-enter the API key." }] });
    const steps = await testProvider(p, { chat: wantChat, signal: req.signal });
    return json(200, { ok: steps.every((s) => s.ok), steps });
  } catch (e) {
    return fail(e);
  }
}
