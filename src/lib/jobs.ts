import { randomBytes } from "node:crypto";
import { readJson, updateJson } from "./store";
import { redact } from "./redact";

export type JobStatus = "running" | "done" | "failed" | "cancelled";
export type Job = {
  id: string;
  kind: string;
  title: string;
  status: JobStatus;
  progress: number;
  step: string;
  assetIds: string[];
  warnings: string[];
  error?: string;
  createdAt: number;
  updatedAt: number;
};

export type JobContext = {
  setProgress: (percent: number, step: string) => void;
  warn: (message: string) => void;
  signal: AbortSignal;
};

const MAX_JOBS = 200;
const live = new Map<string, AbortController>();

async function patch(id: string, change: Partial<Job> | ((j: Job) => Partial<Job>)) {
  await updateJson<Job[]>("jobs", [], (list) => list.map((j) => (j.id === id ? { ...j, ...(typeof change === "function" ? change(j) : change), updatedAt: Date.now() } : j)));
}

/**
 * Starts a background job and returns it immediately. The work function returns the ids of the files it
 * produced. Progress, warnings and the outcome are stored so the UI can poll. Jobs live in this server
 * process: a restart marks unfinished jobs as failed.
 */
export async function startJob(kind: string, title: string, work: (ctx: JobContext) => Promise<string[]>): Promise<Job> {
  const now = Date.now();
  const job: Job = { id: randomBytes(12).toString("hex"), kind, title: title.slice(0, 120), status: "running", progress: 0, step: "Starting", assetIds: [], warnings: [], createdAt: now, updatedAt: now };
  await updateJson<Job[]>("jobs", [], (list) => [job, ...list].slice(0, MAX_JOBS));
  const ctrl = new AbortController();
  live.set(job.id, ctrl);

  // Progress updates are serialized so a late update can never overwrite a final state.
  let chain: Promise<unknown> = Promise.resolve();
  let finished = false;
  const queue = (change: Parameters<typeof patch>[1]) => {
    chain = chain.then(() => patch(job.id, change)).catch(() => undefined);
  };
  const ctx: JobContext = {
    signal: ctrl.signal,
    setProgress: (p, step) => !finished && queue({ progress: Math.max(0, Math.min(99, Math.round(p))), step }),
    warn: (m) => !finished && queue((j) => ({ warnings: [...j.warnings, m.slice(0, 300)] })),
  };

  void (async () => {
    try {
      const assetIds = await work(ctx);
      finished = true;
      await chain;
      await patch(job.id, { status: "done", progress: 100, step: "Done", assetIds });
    } catch (e) {
      finished = true;
      await chain;
      const cancelled = ctrl.signal.aborted || (e instanceof Error && e.message === "cancelled");
      await patch(job.id, { status: cancelled ? "cancelled" : "failed", step: cancelled ? "Cancelled" : "Failed", error: cancelled ? "Cancelled" : redact(e instanceof Error ? e.message : String(e)).slice(0, 500) }).catch(() => undefined);
    } finally {
      live.delete(job.id);
    }
  })();
  return job;
}

/** Jobs recorded as running by a previous process can never finish; report them as failed. */
function settle(j: Job): Job {
  return j.status === "running" && !live.has(j.id) ? { ...j, status: "failed", step: "Failed", error: "The server restarted while this job was running" } : j;
}

export async function getJob(id: string): Promise<Job | undefined> {
  const j = (await readJson<Job[]>("jobs", [])).find((x) => x.id === id);
  return j ? settle(j) : undefined;
}

export async function listJobs(limit = 50): Promise<Job[]> {
  return (await readJson<Job[]>("jobs", [])).slice(0, limit).map(settle);
}

export function cancelJob(id: string): boolean {
  const c = live.get(id);
  if (!c) return false;
  c.abort();
  return true;
}
