import { promises as fs } from "node:fs";
import { fail } from "../../../../lib/api-errors";
import { assetPath, deleteAsset, getAsset } from "../../../../lib/assets";
import { guard, json } from "../../../../lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ id: string }> };

/** Always an attachment with nosniff and a sandbox policy, so a stored file can never run as a web page. */
export async function GET(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "files", limit: 240 });
  if (g) return g;
  const { id } = await params;
  try {
    const a = await getAsset(id);
    if (!a) return json(404, { error: "File not found" });
    let data: Buffer;
    try {
      data = await fs.readFile(await assetPath(id));
    } catch {
      return json(404, { error: "File not found" });
    }
    return new Response(new Uint8Array(data), {
      status: 200,
      headers: {
        "content-type": a.mime,
        "content-length": String(data.length),
        "content-disposition": `attachment; filename="download.${a.ext}"; filename*=UTF-8''${encodeURIComponent(a.name)}`,
        "x-content-type-options": "nosniff",
        "content-security-policy": "sandbox; default-src 'none'",
        "cache-control": "private, no-store",
      },
    });
  } catch (e) {
    return fail(e);
  }
}

export async function DELETE(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "files", limit: 120 });
  if (g) return g;
  const { id } = await params;
  try {
    return (await deleteAsset(id)) ? json(200, { ok: true }) : json(404, { error: "File not found" });
  } catch (e) {
    return fail(e);
  }
}
