import { fail } from "../../../../lib/api-errors";
import { guard, isRecord, json, readJson } from "../../../../lib/http";
import { generateImages, ImageError } from "../../../../lib/images";
import { loadAllProviders } from "../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 180;

export async function POST(req: Request) {
  const g = guard(req, { bucket: "image", limit: 12 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const b = body.value;
  if (!isRecord(b) || typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
  const n = b.n === undefined ? 1 : Number(b.n);
  if (!Number.isInteger(n) || n < 1 || n > 4) return json(400, { error: "n must be 1 to 4" });
  if (b.size !== undefined && !(typeof b.size === "string" && /^(auto|\d{3,4}x\d{3,4})$/.test(b.size))) return json(400, { error: 'size must be "auto" or like 1024x1024' });
  try {
    const { providers } = await loadAllProviders();
    const r = await generateImages(providers, {
      prompt: b.prompt.trim(),
      n,
      size: b.size as string | undefined,
      providerId: typeof b.providerId === "string" ? b.providerId : undefined,
      autoFallback: b.autoFallback !== false,
      signal: req.signal,
    });
    return json(200, { assets: r.assets, provider: { id: r.provider.id, name: r.provider.name, model: r.provider.imageModel }, attempts: r.attempts });
  } catch (e) {
    if (e instanceof ImageError) return json(e.attempts.length ? 502 : 400, { error: e.message, attempts: e.attempts });
    return fail(e);
  }
}
