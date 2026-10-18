import { type Asset, readAssetData, saveAsset } from "./assets";
import { maxGeneratedBytes } from "./config";
import { providerFetch, TimeoutError } from "./provider-http";
import type { Provider } from "./providers";
import { redact } from "./redact";
import { downloadRemote } from "./remote";

export function getPath(obj: unknown, pathStr: string): unknown {
  let cur: unknown = obj;
  for (const k of pathStr.split(".")) {
    if (cur === null || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[k];
  }
  return cur;
}

export type ProviderVideoInput = { prompt: string; imageAssetId?: string; seconds?: number; aspect?: string };
export type ProviderVideoContext = {
  setProgress: (p: number, step: string) => void;
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  resolve?: (host: string) => Promise<string[]>;
};

const isVideo = (b: Buffer) => b.subarray(4, 8).toString("latin1") === "ftyp" || (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3);

/**
 * Asynchronous video generation against a provider that exposes "submit a job, poll its status, download
 * the result". Field names and paths come from the provider's videoApi settings because there is no
 * standard for this. Submission is never retried automatically (it may be billed); polling tolerates brief
 * errors. Cancelling stops OUR polling only; the provider may still finish and bill the job.
 */
export async function generateProviderVideo(p: Provider, input: ProviderVideoInput, ctx: ProviderVideoContext): Promise<Asset> {
  const api = p.videoApi;
  if (!p.videoModel || !api) throw new Error("This provider has no video model/API configured");
  const sleep = ctx.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));

  const body: Record<string, unknown> = { ...(api.extraBody ?? {}), model: p.videoModel, prompt: input.prompt };
  if (input.seconds) body.duration = input.seconds;
  if (input.aspect) body.aspect_ratio = input.aspect;
  if (input.imageAssetId) {
    const { asset, data } = await readAssetData(input.imageAssetId);
    if (asset.kind !== "image" || data.length > 6 * 1024 * 1024) throw new Error("The reference image must be an image under 6 MB");
    body.image = `data:${asset.mime};base64,${data.toString("base64")}`;
  }

  ctx.setProgress(3, "Submitting to provider");
  let submit: Response;
  try {
    submit = await providerFetch(p, api.submitPath, { method: "POST", body: JSON.stringify(body), timeoutMs: p.timeoutMs, signal: ctx.signal, fetchImpl: ctx.fetchImpl });
  } catch (e) {
    if (e instanceof TimeoutError) throw new Error("The provider did not answer in time. The job may still have been created and billed; check the provider dashboard before trying again.");
    throw new Error(ctx.signal?.aborted ? "cancelled" : "Could not reach the video provider");
  }
  if (!submit.ok) {
    const t = redact((await submit.text().catch(() => "")).slice(0, 160), [p.apiKey]);
    throw new Error(`The video provider rejected the request (HTTP ${submit.status})${t ? `: ${t}` : ""}`);
  }
  const submitted = (await submit.json().catch(() => ({}))) as unknown;
  const id = getPath(submitted, api.idField);
  if ((typeof id !== "string" && typeof id !== "number") || !/^[A-Za-z0-9._:-]{1,200}$/.test(String(id))) {
    throw new Error(`The provider response had no usable job id at "${api.idField}" (check the videoApi settings)`);
  }

  let transient = 0;
  for (let i = 1; i <= api.maxPolls; i++) {
    await sleep(api.pollMs);
    if (ctx.signal?.aborted) throw new Error("cancelled");
    let res: Response;
    try {
      res = await providerFetch(p, api.statusPath.replace("{id}", encodeURIComponent(String(id))), { timeoutMs: Math.min(p.timeoutMs, 30_000), signal: ctx.signal, fetchImpl: ctx.fetchImpl });
    } catch {
      if (ctx.signal?.aborted) throw new Error("cancelled");
      if (++transient > 3) throw new Error("Lost contact with the video provider while waiting");
      continue;
    }
    if (res.status === 401 || res.status === 403 || res.status === 404) throw new Error(`The provider refused the status check (HTTP ${res.status})`);
    if (!res.ok) {
      await res.body?.cancel().catch(() => undefined);
      if (++transient > 3) throw new Error(`The provider keeps failing the status check (HTTP ${res.status})`);
      continue;
    }
    transient = 0;
    const st = (await res.json().catch(() => ({}))) as unknown;
    const status = String(getPath(st, api.statusField) ?? "").toLowerCase();
    if (api.failValues.includes(status)) {
      const why = getPath(st, "error.message") ?? getPath(st, "error");
      throw new Error(`The provider reported the job as "${status}"${typeof why === "string" ? `: ${redact(why, [p.apiKey]).slice(0, 160)}` : ""}`);
    }
    if (api.doneValues.includes(status)) {
      const url = getPath(st, api.urlField);
      if (typeof url !== "string") throw new Error(`The job finished but no video URL was found at "${api.urlField}"`);
      ctx.setProgress(92, "Downloading result");
      const { data } = await downloadRemote(url, { maxBytes: maxGeneratedBytes(), signal: ctx.signal, resolve: ctx.resolve, fetchImpl: ctx.fetchImpl });
      if (!isVideo(data)) throw new Error("The downloaded result is not a valid MP4/WebM video");
      return saveAsset({ name: `video-${Date.now().toString(36)}.${data[0] === 0x1a ? "webm" : "mp4"}`, data, origin: "generated" });
    }
    const reported = Number(getPath(st, "progress"));
    ctx.setProgress(Number.isFinite(reported) && reported >= 0 && reported <= 100 ? 5 + reported * 0.85 : 5 + (85 * i) / api.maxPolls, `Provider is rendering (${status || "waiting"})`);
  }
  throw new Error("The provider did not finish in time. The job may still complete at the provider; check its dashboard.");
}
