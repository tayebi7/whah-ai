import { authHeaders, providerUrl } from "./provider-http";
import type { Provider } from "./providers";

export type ChatPart = { type: "text"; text: string } | { type: "image_url"; image_url: { url: string } };
export type ChatMessage = { role: "system" | "user" | "assistant"; content: string | ChatPart[] };

export type BuiltRequest = { url: string; headers: Record<string, string>; body: string; streamed: boolean };

const parseDataUrl = (u: string) => {
  const m = u.match(/^data:([^;,]+);base64,(.+)$/s);
  return m ? { mime: m[1], data: m[2] } : null;
};
const textOf = (c: string | ChatPart[]) => (typeof c === "string" ? c : c.filter((p) => p.type === "text").map((p) => (p as { text: string }).text).join("\n"));

/**
 * Builds the HTTP request for one provider. OpenAI-style endpoints (OpenAI, OpenRouter, Groq, NIM,
 * Ollama, ...) honour `stream`. Anthropic and Gemini are always streamed and converted back to
 * OpenAI-style events by normalizeStream, so the rest of the app sees a single format.
 */
export function buildChatRequest(p: Provider, messages: ChatMessage[], stream: boolean): BuiltRequest {
  const protocol = p.protocol ?? "openai";
  const headers = { "content-type": "application/json", ...authHeaders(p) };

  if (protocol === "anthropic") {
    const system = messages.filter((m) => m.role === "system").map((m) => textOf(m.content)).join("\n\n");
    const conv = messages
      .filter((m) => m.role !== "system")
      .map((m) => ({
        role: m.role,
        content:
          typeof m.content === "string"
            ? m.content
            : m.content.map((part) => {
                if (part.type === "text") return { type: "text", text: part.text };
                const d = parseDataUrl(part.image_url.url);
                if (!d) throw new Error("Anthropic requires images as base64 data URLs");
                return { type: "image", source: { type: "base64", media_type: d.mime, data: d.data } };
              }),
      }));
    return { url: providerUrl(p, "/messages"), headers, streamed: true, body: JSON.stringify({ model: p.model, max_tokens: 4096, stream: true, ...(system ? { system } : {}), messages: conv }) };
  }

  if (protocol === "gemini") {
    const system = messages.filter((m) => m.role === "system").map((m) => textOf(m.content)).join("\n\n");
    const contents = messages
      .filter((m) => m.role !== "system")
      .map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts:
          typeof m.content === "string"
            ? [{ text: m.content }]
            : m.content.map((part) => {
                if (part.type === "text") return { text: part.text };
                const d = parseDataUrl(part.image_url.url);
                if (!d) throw new Error("Gemini requires images as base64 data URLs");
                return { inline_data: { mime_type: d.mime, data: d.data } };
              }),
      }));
    const model = p.model.replace(/^models\//, "");
    return {
      url: providerUrl(p, `/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`),
      headers,
      streamed: true,
      body: JSON.stringify({ contents, ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}) }),
    };
  }

  if (protocol === "ollama") {
    // Native Ollama API: images travel as bare base64 in an "images" list.
    const conv = messages.map((m) => {
      if (typeof m.content === "string") return { role: m.role, content: m.content };
      const images = m.content.filter((x) => x.type === "image_url").map((x) => parseDataUrl((x as { image_url: { url: string } }).image_url.url)?.data).filter(Boolean);
      return { role: m.role, content: textOf(m.content), ...(images.length ? { images } : {}) };
    });
    return { url: providerUrl(p, "/api/chat"), headers, streamed: true, body: JSON.stringify({ model: p.model, messages: conv, stream: true }) };
  }

  if (protocol === "cohere") {
    return { url: providerUrl(p, "/v2/chat"), headers, streamed: true, body: JSON.stringify({ model: p.model, messages, stream: true }) };
  }

  if (protocol === "azure") {
    // Azure OpenAI: the model is the deployment named in the URL; the api-version query is added by providerUrl.
    return { url: providerUrl(p, "/chat/completions"), headers, streamed: stream, body: JSON.stringify({ messages, stream }) };
  }

  return { url: providerUrl(p, "/chat/completions"), headers, streamed: stream, body: JSON.stringify({ model: p.model, messages, stream }) };
}

const chunk = (text: string) => `data: ${JSON.stringify({ choices: [{ delta: { content: text } }] })}\n\n`;

/** Converts a provider's native stream to OpenAI-style SSE so the UI has a single format. */
export function normalizeStream(p: Provider, body: ReadableStream<Uint8Array>): ReadableStream<Uint8Array> {
  const protocol = p.protocol ?? "openai";
  if (protocol === "openai" || protocol === "azure") return body;
  const dec = new TextDecoder();
  const enc = new TextEncoder();
  let buf = "";

  const handle = (payload: string, out: (s: string) => void, fail: (e: Error) => void) => {
    let j: any;
    try {
      j = JSON.parse(payload);
    } catch {
      return;
    }
    if (protocol === "ollama") {
      if (j.error) return fail(new Error(typeof j.error === "string" ? j.error : (j.error.message ?? "provider stream error")));
      if (typeof j.message?.content === "string" && j.message.content) out(chunk(j.message.content));
    } else if (protocol === "cohere") {
      if (j.type === "content-delta" && typeof j.delta?.message?.content?.text === "string") out(chunk(j.delta.message.content.text));
      else if (j.type === "error" || j.error) fail(new Error(j.error?.message ?? j.message ?? "provider stream error"));
    } else if (protocol === "anthropic") {
      if (j.type === "content_block_delta" && j.delta?.type === "text_delta" && typeof j.delta.text === "string") out(chunk(j.delta.text));
      else if (j.type === "error") fail(new Error(j.error?.message ?? "provider stream error"));
    } else {
      if (j.error) return fail(new Error(j.error.message ?? "provider stream error"));
      const parts = j.candidates?.[0]?.content?.parts;
      if (Array.isArray(parts)) for (const part of parts) if (typeof part.text === "string") out(chunk(part.text));
    }
  };

  return body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(c, ctl) {
        buf += dec.decode(c, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? "";
        for (const l of lines) {
          const s = l.trim();
          if (s.startsWith("data:")) handle(s.slice(5).trim(), (t) => ctl.enqueue(enc.encode(t)), (e) => ctl.error(e));
          else if (protocol === "ollama" && s.startsWith("{")) handle(s, (t) => ctl.enqueue(enc.encode(t)), (e) => ctl.error(e));
        }
      },
      flush(ctl) {
        const s = buf.trim();
        if (s.startsWith("data:")) handle(s.slice(5).trim(), (t) => ctl.enqueue(enc.encode(t)), (e) => ctl.error(e));
        else if (protocol === "ollama" && s.startsWith("{")) handle(s, (t) => ctl.enqueue(enc.encode(t)), (e) => ctl.error(e));
        ctl.enqueue(enc.encode("data: [DONE]\n\n"));
      },
    }),
  );
}

/** Reads an OpenAI-style SSE stream to the end and returns the concatenated text. */
export async function collectText(stream: ReadableStream<Uint8Array>): Promise<string> {
  const reader = stream.getReader();
  const dec = new TextDecoder();
  let buf = "";
  let out = "";
  const eat = (line: string) => {
    const s = line.trim();
    if (!s.startsWith("data:")) return;
    const payload = s.slice(5).trim();
    if (!payload || payload === "[DONE]") return;
    try {
      const d = JSON.parse(payload)?.choices?.[0]?.delta?.content;
      if (typeof d === "string") out += d;
    } catch {
      /* ignore keep-alives */
    }
  };
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop() ?? "";
    lines.forEach(eat);
  }
  eat(buf);
  return out;
}
