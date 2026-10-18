import { fail } from "../../../../../lib/api-errors";
import { guard, isRecord, json, readJson } from "../../../../../lib/http";
import { providerFetch } from "../../../../../lib/provider-http";
import { loadAllProviders } from "../../../../../lib/providers";
import { describeStatus } from "../../../../../lib/router";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Step = { name: string; ok: boolean; detail: string };

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
    const steps: Step[] = [];
    const proto = p.protocol ?? "openai";

    try {
      const r = await providerFetch(p, "/models", { timeoutMs: Math.min(p.timeoutMs, 15_000), signal: req.signal });
      steps.push({ name: "connection", ok: r.ok, detail: r.ok ? "Reached the provider and the credentials were accepted" : r.status === 404 ? "Reachable (this provider has no /models endpoint, which is normal for some gateways)" : describeStatus(r.status) });
      if (!r.ok && r.status === 404) steps[0].ok = true;
      await r.body?.cancel().catch(() => undefined);
    } catch (e) {
      steps.push({ name: "connection", ok: false, detail: e instanceof Error && e.name === "TimeoutError" ? "Timed out" : "Could not connect (check the URL, network, and the local-model setting)" });
    }

    if (wantChat && p.model && steps[0].ok) {
      try {
        const path = proto === "anthropic" ? "/messages" : proto === "gemini" ? `/models/${encodeURIComponent(p.model.replace(/^models\//, ""))}:generateContent` : "/chat/completions";
        const payload =
          proto === "anthropic" ? { model: p.model, max_tokens: 5, messages: [{ role: "user", content: "Reply with: ok" }] } : proto === "gemini" ? { contents: [{ role: "user", parts: [{ text: "Reply with: ok" }] }] } : { model: p.model, messages: [{ role: "user", content: "Reply with: ok" }], max_tokens: 5 };
        const r = await providerFetch(p, path, { method: "POST", body: JSON.stringify(payload), timeoutMs: Math.min(p.timeoutMs, 30_000), signal: req.signal });
        steps.push({ name: "chat model", ok: r.ok, detail: r.ok ? `Model "${p.model}" answered` : describeStatus(r.status) });
        await r.body?.cancel().catch(() => undefined);
      } catch (e) {
        steps.push({ name: "chat model", ok: false, detail: e instanceof Error && e.name === "TimeoutError" ? "Timed out" : "Could not connect" });
      }
    }
    return json(200, { ok: steps.every((s) => s.ok), steps });
  } catch (e) {
    return fail(e);
  }
}
