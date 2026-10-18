import { fail } from "../../../lib/api-errors";
import { AssetError } from "../../../lib/assets";
import { buildMessages, type IncomingMessage } from "../../../lib/chat-input";
import { guard, isRecord, json, readJson } from "../../../lib/http";
import { loadAllProviders } from "../../../lib/providers";
import { redact } from "../../../lib/redact";
import { routeChat, RouterError } from "../../../lib/router";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

function parseMessages(v: unknown): IncomingMessage[] | string {
  if (!Array.isArray(v) || v.length < 1 || v.length > 200) return "messages must be a list of 1 to 200 items";
  const out: IncomingMessage[] = [];
  for (const m of v) {
    if (!isRecord(m) || !["system", "user", "assistant"].includes(m.role as string) || typeof m.content !== "string" || m.content.length > 200_000) return "each message needs a valid role and text content";
    const att = m.attachments;
    if (att !== undefined && (!Array.isArray(att) || att.length > 6 || att.some((a) => typeof a !== "string"))) return "attachments must be a list of file ids";
    out.push({ role: m.role as IncomingMessage["role"], content: m.content, attachments: att as string[] | undefined });
  }
  return out;
}

export async function POST(req: Request) {
  const g = guard(req, { bucket: "chat", limit: 30 });
  if (g) return g;
  const body = await readJson(req, 500_000);
  if (!body.ok) return body.res;
  if (!isRecord(body.value)) return json(400, { error: "Invalid request body" });
  const msgs = parseMessages(body.value.messages);
  if (typeof msgs === "string") return json(400, { error: msgs });
  const providerId = typeof body.value.providerId === "string" ? body.value.providerId : undefined;
  const autoFallback = body.value.autoFallback !== false;

  try {
    const { providers, errors } = await loadAllProviders();
    if (providers.length === 0) return json(503, { error: "No provider configured. Add one in Settings.", details: errors });

    let ordered = providers;
    if (providerId) {
      const chosen = providers.find((p) => p.id === providerId);
      if (!chosen) return json(400, { error: `Unknown provider "${providerId}"` });
      ordered = [chosen, ...providers.filter((p) => p.id !== chosen.id)];
    }

    const built = await buildMessages(msgs);
    const { response, provider, attempts } = await routeChat(ordered, built.messages, { autoFallback, signal: req.signal, requireVision: built.hasImages, hasAttachments: built.hasAttachments });
    return new Response(response.body, {
      status: 200,
      headers: {
        "content-type": "text/event-stream; charset=utf-8",
        "cache-control": "no-store",
        "x-waha-provider": encodeURIComponent(provider.name),
        "x-waha-model": encodeURIComponent(provider.model),
        "x-waha-fallback": encodeURIComponent(JSON.stringify(attempts)),
      },
    });
  } catch (e) {
    if (e instanceof RouterError) {
      const { providers } = await loadAllProviders().catch(() => ({ providers: [] }));
      return json(502, { error: redact(e.message, providers.map((p) => p.apiKey)), attempts: e.attempts });
    }
    if (e instanceof AssetError) return json(e.status, { error: e.message });
    return fail(e);
  }
}
