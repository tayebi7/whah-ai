import type { Api } from "./api";

export type ChatMsg = { role: "system" | "user" | "assistant"; content: string; attachments?: string[] };

/** Streams /api/chat (SSE) and returns the full text. `onDelta` gets the text so far. */
export async function streamChat(api: Api, messages: ChatMsg[], opts: { signal?: AbortSignal; onDelta?: (acc: string) => void; providerId?: string } = {}): Promise<{ text: string; meta: string }> {
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "content-type": "application/json", ...api.auth() },
    body: JSON.stringify({ messages, providerId: opts.providerId, autoFallback: true }),
    signal: opts.signal,
  });
  if (!res.ok || !res.body) {
    const data = await res.json().catch(() => ({}));
    const attempts = Array.isArray(data.attempts) ? ` — ${data.attempts.map((a: { providerId: string; reason: string }) => `${a.providerId}: ${a.reason}`).join("; ")}` : "";
    const details = Array.isArray(data.details) ? ` (${data.details.join("; ")})` : "";
    throw new Error(`${data.error ?? `HTTP ${res.status}`}${details}${attempts}`);
  }
  const name = decodeURIComponent(res.headers.get("x-waha-provider") ?? "");
  const model = decodeURIComponent(res.headers.get("x-waha-model") ?? "");
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  let acc = "";
  const eat = (line: string) => {
    const s = line.trim();
    if (!s.startsWith("data:")) return;
    const payload = s.slice(5).trim();
    if (!payload || payload === "[DONE]") return;
    let j: { error?: { message?: string }; choices?: { delta?: { content?: string } }[] };
    try {
      j = JSON.parse(payload);
    } catch {
      return;
    }
    if (j?.error) throw new Error(j.error.message ?? "stream error");
    const d = j?.choices?.[0]?.delta?.content;
    if (typeof d === "string") {
      acc += d;
      opts.onDelta?.(acc);
    }
  };
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop() ?? "";
    lines.forEach(eat);
  }
  eat(buf);
  return { text: acc, meta: [name, model].filter(Boolean).join(" · ") };
}

/** Rewrites a short prompt into a rich English prompt for an image/video model. Never throws: returns the original on any problem. */
export async function enhancePrompt(api: Api, kind: "image" | "video", prompt: string, signal?: AbortSignal): Promise<string> {
  if (prompt.length > 400) return prompt;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 12_000);
    signal?.addEventListener("abort", () => ctrl.abort(), { once: true });
    try {
      const r = await streamChat(
        api,
        [
          { role: "system", content: `You turn a user's idea into ONE detailed English prompt for an AI ${kind} generator: subject, setting, style, lighting, composition${kind === "video" ? ", camera movement" : ""}. Keep every element the user asked for. No text inside the picture. Reply with the prompt only, max 90 words, no quotes.` },
          { role: "user", content: prompt },
        ],
        { signal: ctrl.signal },
      );
      const t = r.text.trim().replace(/^["'`]+|["'`]+$/g, "");
      return t.length >= 10 && t.length <= 900 ? t : prompt;
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return prompt;
  }
}
