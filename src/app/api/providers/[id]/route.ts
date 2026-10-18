import { fail } from "../../../../lib/api-errors";
import { guard, json, readJson } from "../../../../lib/http";
import { deleteProvider, toPublic, updateProvider, validateProviderInput } from "../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ id: string }> };
const status = (msg: string) => (/read-only/.test(msg) ? 409 : /not found/i.test(msg) ? 404 : /set at least|needs videoApi/.test(msg) ? 400 : /WAHA_ENCRYPTION_KEY/.test(msg) ? 503 : 0);

export async function PUT(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "settings", limit: 30 });
  if (g) return g;
  const { id } = await params;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const { value, errors } = validateProviderInput(body.value, { partial: true });
  if (errors.length) return json(400, { error: "Invalid provider", details: errors });
  try {
    return json(200, { provider: toPublic(await updateProvider(id, value)) });
  } catch (e) {
    const s = status(e instanceof Error ? e.message : "");
    return s ? json(s, { error: (e as Error).message }) : fail(e);
  }
}

export async function DELETE(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "settings", limit: 30 });
  if (g) return g;
  const { id } = await params;
  try {
    await deleteProvider(id);
    return json(200, { ok: true });
  } catch (e) {
    const s = status(e instanceof Error ? e.message : "");
    return s ? json(s, { error: (e as Error).message }) : fail(e);
  }
}
