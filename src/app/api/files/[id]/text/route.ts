import { fail } from "../../../../../lib/api-errors";
import { assetPath, getAsset } from "../../../../../lib/assets";
import { extractText } from "../../../../../lib/extract";
import { guard, json } from "../../../../../lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(req, { bucket: "extract", limit: 20 });
  if (g) return g;
  const { id } = await params;
  try {
    const a = await getAsset(id);
    if (!a) return json(404, { error: "File not found" });
    try {
      return json(200, await extractText(a, await assetPath(id)));
    } catch (e) {
      return json(422, { error: e instanceof Error ? e.message : "Could not read this file" });
    }
  } catch (e) {
    return fail(e);
  }
}
