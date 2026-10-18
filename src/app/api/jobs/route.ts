import { fail } from "../../../lib/api-errors";
import { guard, json } from "../../../lib/http";
import { listJobs } from "../../../lib/jobs";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const g = guard(req, { bucket: "jobs", limit: 240 });
  if (g) return g;
  try {
    return json(200, { jobs: await listJobs() });
  } catch (e) {
    return fail(e);
  }
}
