import { fail } from "../../../../lib/api-errors";
import { guard, isRecord, json, readJson } from "../../../../lib/http";
import { reorderProviders } from "../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const g = guard(req, { bucket: "settings", limit: 30 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const ids = isRecord(body.value) ? body.value.ids : undefined;
  if (!Array.isArray(ids) || ids.length > 100 || ids.some((i) => typeof i !== "string")) return json(400, { error: "ids must be a list of provider ids" });
  try {
    await reorderProviders(ids as string[]);
    return json(200, { ok: true });
  } catch (e) {
    return fail(e);
  }
}
