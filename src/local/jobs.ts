import type { Job } from "../lib/jobs";
import { redact } from "../lib/redact";
import { store } from "./db";

export type { Job };
export type JobContext = {
  setProgress: (percent: number, step: string) => void;
  warn: (message: string) => void;
  signal: AbortSignal;
};

const MAX_JOBS = 100;
const live = new Map<string, AbortController>();
const id = () => Array.from(crypto.getRandomValues(new Uint8Array(12)), (x) => x.toString(16).padStart(2, "0")).join("");

async function patch(jobId: string, change: Partial<Job> | ((j: Job) => Partial<Job>)) {
  await store().update<Job[]>("jobs", [], (list) => list.map((j) => (j.id === jobId ? { ...j, ...(typeof change === "function" ? change(j) : change), updatedAt: Date.now() } : j)));
}

/** Runs the work in the background of this page. Closing the app while a job runs marks it as failed on next start. */
export async function startJob(kind: string, title: string, work: (ctx: JobContext) => Promise<string[]>): Promise<Job> {
  const now = Date.now();
  const job: Job = { id: id(), kind, title: title.slice(0, 120), status: "running", progress: 0, step: "Starting", assetIds: [], warnings: [], createdAt: now, updatedAt: now };
  await store().update<Job[]>("jobs", [], (list) => [job, ...list].slice(0, MAX_JOBS));
  const ctrl = new AbortController();
  live.set(job.id, ctrl);
  let chain: Promise<unknown> = Promise.resolve();
  let finished = false;
  const queue = (c: Parameters<typeof patch>[1]) => void (chain = chain.then(() => patch(job.id, c)).catch(() => undefined));
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

const settle = (j: Job): Job => (j.status === "running" && !live.has(j.id) ? { ...j, status: "failed", step: "Failed", error: "The app was closed while this job was running" } : j);

export async function getJob(jobId: string) {
  const j = (await store().get<Job[]>("jobs", [])).find((x) => x.id === jobId);
  return j ? settle(j) : undefined;
}
export async function listJobs(limit = 50) {
  return (await store().get<Job[]>("jobs", [])).slice(0, limit).map(settle);
}
export function cancelJob(jobId: string) {
  const c = live.get(jobId);
  if (!c) return false;
  c.abort();
  return true;
}
