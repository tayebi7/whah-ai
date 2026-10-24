import { buildChatRequest } from "./adapters";
import { describeNetError } from "./net-errors";
import { modelsPath, providerFetch } from "./provider-http";
import type { Provider } from "./providers-core";
import { redact } from "./redact";
import { describeStatus, errorDetail, keyFingerprint } from "./router";

export type TestStep = { name: string; ok: boolean; detail: string };

/**
 * Checks a provider: (1) can we reach it and are the credentials accepted (lists models, free), and optionally
 * (2) does the chat model answer, using the SAME request builder as real chats so a pass means chat will work.
 */
export async function testProvider(p: Provider, o: { chat: boolean; signal?: AbortSignal; fetchImpl?: typeof fetch }): Promise<TestStep[]> {
  const steps: TestStep[] = [];
  const mp = modelsPath(p);
  if (mp) {
    try {
      const r = await providerFetch(p, mp, { timeoutMs: Math.min(p.timeoutMs, 30_000), signal: o.signal, fetchImpl: o.fetchImpl });
      const bad = r.status === 401 || r.status === 403;
      steps.push({
        name: "connection",
        ok: r.ok || r.status === 404,
        detail: r.ok ? "Reached the provider and the credentials were accepted" : r.status === 404 ? "Reachable (this provider has no model list, which is normal for some gateways)" : `${describeStatus(r.status)}${bad ? ` [${keyFingerprint(p.apiKey)}]` : ""}`,
      });
      await r.body?.cancel().catch(() => undefined);
    } catch (e) {
      steps.push({ name: "connection", ok: false, detail: `Could not connect: ${redact(describeNetError(e), [p.apiKey])}` });
    }
  }
  if (o.chat && p.model && (steps.length === 0 || steps[0].ok)) {
    try {
      const req = buildChatRequest(p, [{ role: "user", content: "Reply with: ok" }], false);
      const r = await fetch0(o.fetchImpl)(req.url, { method: "POST", redirect: "error", headers: req.headers, body: req.body, signal: o.signal ? AbortSignal.any([o.signal, AbortSignal.timeout(Math.min(p.timeoutMs, 60_000))]) : AbortSignal.timeout(Math.min(p.timeoutMs, 60_000)) });
      const bad = r.status === 401 || r.status === 403;
      steps.push({ name: "chat model", ok: r.ok, detail: r.ok ? `Model "${p.model}" answered` : `${describeStatus(r.status)}${await errorDetail(r, [p.apiKey]).then((d) => (d ? `: ${d}` : ""))}${bad ? ` [${keyFingerprint(p.apiKey)}]` : ""}` });
      await r.body?.cancel().catch(() => undefined);
    } catch (e) {
      steps.push({ name: "chat model", ok: false, detail: `Could not connect: ${redact(describeNetError(e), [p.apiKey])}` });
    }
  }
  return steps;
}
const fetch0 = (f?: typeof fetch) => f ?? fetch;
