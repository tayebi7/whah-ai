import type { Provider } from "./providers-core";

/** Pure builders/parsers for the different image-generation dialects, shared by the server and the on-device app. */
export type ImageStyle = "openai" | "openrouter" | "gemini-native" | "imagen";
export type RawImage = { b64?: string; url?: string };

export function imageStyle(p: Pick<Provider, "protocol" | "baseUrl" | "imageModel">): ImageStyle {
  const protocol = p.protocol ?? "openai";
  if (protocol === "gemini") return /^(models\/)?imagen/i.test(p.imageModel) ? "imagen" : "gemini-native";
  if (/openrouter\.ai/i.test(p.baseUrl)) return "openrouter";
  return "openai";
}

const geminiModel = (m: string) => m.replace(/^models\//, "");

export function buildImageRequest(p: Provider, prompt: string, n = 1, size?: string): { path: string; body: string } {
  const style = imageStyle(p);
  const aspect = size && /^\d+x\d+$/.test(size) ? (() => { const [w, h] = size.split("x").map(Number); return w === h ? "1:1" : w > h ? "16:9" : "9:16"; })() : undefined;
  switch (style) {
    case "gemini-native":
      return {
        path: `/models/${geminiModel(p.imageModel)}:generateContent`,
        body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { responseModalities: ["TEXT", "IMAGE"] } }),
      };
    case "imagen":
      return {
        path: `/models/${geminiModel(p.imageModel)}:predict`,
        body: JSON.stringify({ instances: [{ prompt }], parameters: { sampleCount: Math.min(Math.max(n, 1), 4), ...(aspect ? { aspectRatio: aspect } : {}) } }),
      };
    case "openrouter":
      return {
        path: "/chat/completions",
        body: JSON.stringify({ model: p.imageModel, messages: [{ role: "user", content: prompt }], modalities: /(flux|sourceful|riverflow|seedream|recraft|ideogram|stable|sdxl)/i.test(p.imageModel) ? ["image"] : ["image", "text"] }),
      };
    default:
      return { path: "/images/generations", body: JSON.stringify({ model: p.imageModel, prompt, n, ...(size && size !== "auto" ? { size } : {}) }) };
  }
}

const fromDataUrl = (s: string): RawImage => {
  const m = /^data:[^;,]+;base64,(.+)$/s.exec(s);
  return m ? { b64: m[1] } : { url: s };
};

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

export function parseImageResponse(style: ImageStyle, json: unknown): RawImage[] {
  const j = (json ?? {}) as Json;
  const out: RawImage[] = [];
  if (style === "gemini-native") {
    for (const c of j.candidates ?? []) for (const part of c?.content?.parts ?? []) {
      const d = part?.inlineData ?? part?.inline_data;
      if (d?.data) out.push({ b64: d.data });
    }
  } else if (style === "imagen") {
    for (const pr of j.predictions ?? []) if (pr?.bytesBase64Encoded) out.push({ b64: pr.bytesBase64Encoded });
  } else if (style === "openrouter") {
    for (const ch of j.choices ?? []) {
      for (const im of ch?.message?.images ?? []) {
        const u = im?.image_url?.url ?? im?.url;
        if (typeof u === "string") out.push(fromDataUrl(u));
      }
      const content = ch?.message?.content;
      if (out.length === 0 && Array.isArray(content)) for (const part of content) { const u = part?.image_url?.url; if (typeof u === "string") out.push(fromDataUrl(u)); }
    }
  } else {
    for (const it of j.data ?? []) {
      if (it?.b64_json) out.push({ b64: it.b64_json });
      else if (typeof it?.url === "string") out.push({ url: it.url });
    }
  }
  return out;
}

/** Text the model answered with instead of an image (e.g. a safety refusal), to show a useful error. */
export function imageRefusalText(json: unknown): string {
  const j = (json ?? {}) as Json;
  const parts = j.candidates?.[0]?.content?.parts;
  const t = Array.isArray(parts) ? parts.map((x: Json) => x?.text).filter(Boolean).join(" ") : j.choices?.[0]?.message?.content;
  return typeof t === "string" ? t.replace(/\s+/g, " ").slice(0, 160) : "";
}
