import { fail } from "../../../../lib/api-errors";
import { runBook, validateBook } from "../../../../lib/books";
import { hasTool } from "../../../../lib/exec";
import { guard, json, readJson } from "../../../../lib/http";
import { startJob } from "../../../../lib/jobs";
import { loadAllProviders } from "../../../../lib/providers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Starts a background book/story job (outline, chapters, illustrations, export). Poll /api/jobs/:id. */
export async function POST(req: Request) {
  const g = guard(req, { bucket: "book", limit: 8 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const v = validateBook(body.value);
  if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
  const input = v.value;
  try {
    if (!hasTool("pandoc")) return json(501, { error: '"pandoc" is not installed on the server, so books cannot be exported' });
    if (input.formats.includes("pdf") && !hasTool("soffice")) return json(501, { error: '"soffice" (LibreOffice) is not installed, so PDF export is unavailable' });
    const { providers } = await loadAllProviders();
    if (!providers.some((p) => p.enabled && p.model)) return json(400, { error: "No chat provider is configured. Add one in Settings." });
    return json(202, { job: await startJob("book", input.title || input.brief.slice(0, 60), (ctx) => runBook(input, providers, ctx)) });
  } catch (e) {
    return fail(e);
  }
}
