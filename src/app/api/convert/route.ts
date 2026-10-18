import { fail } from "../../../lib/api-errors";
import { convertAsset, listConversions } from "../../../lib/convert";
import { guard, isRecord, json, readJson } from "../../../lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 200;

export async function GET(req: Request) {
  const g = guard(req, { bucket: "convert-list", limit: 120 });
  if (g) return g;
  return json(200, { conversions: listConversions() });
}

export async function POST(req: Request) {
  const g = guard(req, { bucket: "convert", limit: 15 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  if (!isRecord(body.value) || typeof body.value.assetId !== "string" || typeof body.value.to !== "string") return json(400, { error: "assetId and to are required" });
  try {
    return json(201, { asset: await convertAsset(body.value.assetId, body.value.to.toLowerCase()) });
  } catch (e) {
    if (e instanceof Error && e.name !== "AssetError" && /failed|timed out|no output|not safe|cannot write/.test(e.message)) return json(422, { error: `Conversion failed: ${e.message}` });
    return fail(e);
  }
}
