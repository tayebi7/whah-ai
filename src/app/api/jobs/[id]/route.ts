import { fail } from "../../../../lib/api-errors";
import { guard, json } from "../../../../lib/http";
import { cancelJob, getJob } from "../../../../lib/jobs";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "jobs", limit: 600 });
  if (g) return g;
  const { id } = await params;
  try {
    const j = await getJob(id);
    return j ? json(200, { job: j }) : json(404, { error: "Job not found" });
  } catch (e) {
    return fail(e);
  }
}

/** Cancels a running job. (For provider video jobs this stops waiting; the provider may still finish and bill.) */
export async function DELETE(req: Request, { params }: Ctx) {
  const g = guard(req, { bucket: "jobs", limit: 60 });
  if (g) return g;
  const { id } = await params;
  return cancelJob(id) ? json(200, { ok: true }) : json(404, { error: "No running job with this id" });
}
