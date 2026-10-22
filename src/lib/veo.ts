import type { Provider } from "./providers-core";
import { redact } from "./redact";

/** Gemini Veo: POST :predictLongRunning, poll the returned operation, download the video URI (needs the API key). Pure; I/O is injected. */
export type VeoIO = {
  call: (path: string, body?: string) => Promise<Response>;
  download: (uri: string) => Promise<Uint8Array>;
  sleep: (ms: number) => Promise<void>;
  setProgress: (p: number, step: string) => void;
  aborted: () => boolean;
};

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

export function veoBody(prompt: string, aspect?: string): string {
  const ar = aspect === "9:16" || aspect === "16:9" ? aspect : "16:9";
  return JSON.stringify({ instances: [{ prompt }], parameters: { aspectRatio: ar } });
}

export function veoUri(op: Json): string | undefined {
  const s = op?.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri ?? op?.response?.generatedVideos?.[0]?.video?.uri ?? op?.response?.videos?.[0]?.uri;
  return typeof s === "string" ? s : undefined;
}

const errText = async (r: Response, p: Provider) => redact((await r.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 200), [p.apiKey]);

export async function runVeo(p: Provider, prompt: string, aspect: string | undefined, io: VeoIO, opts: { pollMs?: number; maxPolls?: number } = {}): Promise<Uint8Array> {
  const model = p.videoModel.replace(/^models\//, "");
  io.setProgress(3, "Submitting to Gemini (Veo)");
  const sub = await io.call(`/models/${model}:predictLongRunning`, veoBody(prompt, aspect));
  if (!sub.ok) throw new Error(`Veo rejected the request (HTTP ${sub.status}): ${await errText(sub, p)}`);
  const name = ((await sub.json().catch(() => ({}))) as Json).name;
  if (typeof name !== "string" || !/^[A-Za-z0-9_\-/.]{3,300}$/.test(name)) throw new Error("Veo returned no operation name");
  const max = opts.maxPolls ?? 60;
  let transient = 0;
  for (let i = 1; i <= max; i++) {
    await io.sleep(opts.pollMs ?? 10_000);
    if (io.aborted()) throw new Error("cancelled");
    let res: Response;
    try {
      res = await io.call(`/${name}`);
    } catch {
      if (++transient > 3) throw new Error("Lost contact with Gemini while waiting for the video");
      continue;
    }
    if (!res.ok) {
      if (res.status === 401 || res.status === 403 || res.status === 404) throw new Error(`Gemini refused the status check (HTTP ${res.status}): ${await errText(res, p)}`);
      if (++transient > 3) throw new Error(`Gemini keeps failing the status check (HTTP ${res.status})`);
      continue;
    }
    transient = 0;
    const op = (await res.json().catch(() => ({}))) as Json;
    if (op.error) throw new Error(`Veo failed: ${redact(String(op.error.message ?? JSON.stringify(op.error)).slice(0, 200), [p.apiKey])}`);
    if (op.done) {
      const uri = veoUri(op);
      if (!uri) {
        const why = op?.response?.generateVideoResponse?.raiMediaFilteredReasons?.[0];
        throw new Error(`Veo finished without a video${why ? `: ${redact(String(why).slice(0, 200), [p.apiKey])}` : " (the prompt may have been filtered)"}`);
      }
      io.setProgress(92, "Downloading result");
      return io.download(uri);
    }
    io.setProgress(5 + (85 * i) / max, "Gemini is rendering the video");
  }
  throw new Error("Veo did not finish in time. The job may still complete at the provider.");
}
