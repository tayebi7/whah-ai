import { fail } from "../../../lib/api-errors";
import { AssetError, listAssets, saveAsset } from "../../../lib/assets";
import { maxUploadBytes } from "../../../lib/config";
import { guard, json } from "../../../lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const g = guard(req, { bucket: "files", limit: 120 });
  if (g) return g;
  const u = new URL(req.url);
  const kind = u.searchParams.get("kind");
  try {
    return json(200, await listAssets({ limit: Number(u.searchParams.get("limit")) || 50, offset: Number(u.searchParams.get("offset")) || 0, kind: kind === "image" || kind === "document" || kind === "video" ? kind : undefined }));
  } catch (e) {
    return fail(e);
  }
}

/** multipart/form-data with one or more "file" fields. */
export async function POST(req: Request) {
  const g = guard(req, { bucket: "upload", limit: 40 });
  if (g) return g;
  const declared = Number(req.headers.get("content-length"));
  if (declared > maxUploadBytes() * 10 + 1024 * 1024) return json(413, { error: "Upload too large" });
  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return json(400, { error: "Expected multipart/form-data with a file field" });
  }
  const files = form.getAll("file").filter((f): f is File => typeof f !== "string");
  if (files.length === 0) return json(400, { error: 'No file received (field name must be "file")' });
  if (files.length > 10) return json(400, { error: "At most 10 files per upload" });

  const saved = [];
  const failed: { name: string; error: string }[] = [];
  for (const f of files) {
    try {
      saved.push(await saveAsset({ name: f.name, data: Buffer.from(await f.arrayBuffer()), origin: "upload" }));
    } catch (e) {
      if (e instanceof AssetError) failed.push({ name: f.name, error: e.message });
      else return fail(e);
    }
  }
  return json(saved.length ? 201 : 400, { assets: saved, failed });
}
