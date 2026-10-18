import type { Asset } from "../lib/assets";
import type { Job } from "../lib/jobs";

export type { Asset, Job };

export type Capabilities = { chat: boolean; vision: boolean; image: boolean; video: boolean };
export type VideoApiPublic = { submitPath: string; statusPath: string; idField: string; statusField: string; urlField: string; doneValues: string[]; failValues: string[]; pollMs: number; maxPolls: number };
export type PubProvider = {
  id: string;
  name: string;
  protocol?: "openai" | "anthropic" | "gemini";
  baseUrl: string;
  model: string;
  imageModel: string;
  videoModel: string;
  videoApi?: VideoApiPublic;
  orgId?: string;
  priority: number;
  enabled: boolean;
  timeoutMs: number;
  maxRetries: number;
  supportsVision: boolean;
  noAttachments: boolean;
  keyUnreadable?: boolean;
  source?: "env" | "stored";
  hasKey: boolean;
  keyHint: string;
  headerNames: string[];
  capabilities: Capabilities;
};

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public details: string[] = [],
    public attempts: { providerId: string; reason: string }[] = [],
  ) {
    super(message);
    this.name = "ApiError";
  }
}

/** One readable line for any error, including provider attempts and validation details. */
export function describeError(e: unknown): string {
  if (e instanceof ApiError) {
    const extra = [...e.details, ...e.attempts.map((a) => `${a.providerId}: ${a.reason}`)];
    // A bare "HTTP 400" tells the user nothing when the server already gave the real reason.
    if (/^HTTP \d{3}$/.test(e.message) && extra.length) return extra.join("; ");
    return extra.length ? `${e.message} (${extra.join("; ")})` : e.message;
  }
  return e instanceof Error ? e.message : String(e);
}

async function parse<T>(res: Response): Promise<T> {
  const text = await res.text();
  let data: Record<string, unknown> = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    /* non-JSON body */
  }
  if (!res.ok) {
    const failed = Array.isArray(data.failed) ? (data.failed as { name: string; error: string }[]).map((f) => `${f.name}: ${f.error}`) : [];
    throw new ApiError(
      typeof data.error === "string" ? data.error : `HTTP ${res.status}`,
      res.status,
      [...(Array.isArray(data.details) ? (data.details as string[]) : []), ...failed],
      Array.isArray(data.attempts) ? (data.attempts as { providerId: string; reason: string }[]) : [],
    );
  }
  return data as T;
}

export function createApi(getToken: () => string) {
  const auth = (): Record<string, string> => {
    const t = getToken();
    return t ? { "x-waha-token": t } : {};
  };
  const send = async <T>(method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> =>
    parse<T>(await fetch(path, { method, signal, headers: { ...auth(), ...(body !== undefined ? { "content-type": "application/json" } : {}) }, body: body !== undefined ? JSON.stringify(body) : undefined }));

  return {
    auth,
    get: <T>(path: string, signal?: AbortSignal) => send<T>("GET", path, undefined, signal),
    post: <T>(path: string, body?: unknown, signal?: AbortSignal) => send<T>("POST", path, body ?? {}, signal),
    put: <T>(path: string, body: unknown) => send<T>("PUT", path, body),
    del: <T>(path: string) => send<T>("DELETE", path),
    /** Uploads files; resolves with what was accepted and throws only if nothing was. */
    async upload(files: File[]): Promise<{ assets: Asset[]; failed: { name: string; error: string }[] }> {
      const fd = new FormData();
      for (const f of files) fd.append("file", f);
      try {
        return await parse(await fetch("/api/files", { method: "POST", headers: auth(), body: fd }));
      } catch (e) {
        throw e;
      }
    },
    async blob(id: string): Promise<Blob> {
      const res = await fetch(`/api/files/${id}`, { headers: auth() });
      if (!res.ok) throw new ApiError(`HTTP ${res.status}`, res.status);
      return res.blob();
    },
  };
}
export type Api = ReturnType<typeof createApi>;

export const fmtSize = (n: number) => (n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(1)} MB`);
