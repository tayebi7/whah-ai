import { randomBytes } from "node:crypto";
import { allowLocal as allowLocalEnv } from "./config";
import { decryptSecret, encryptSecret } from "./crypto";
import { assertSafeUrl } from "./ssrf";
import { readJson, updateJson } from "./store";

export const PROTOCOLS = ["openai", "anthropic", "gemini"] as const;
export type Protocol = (typeof PROTOCOLS)[number];

/** How to talk to a provider's asynchronous video API. There is no standard, so every path/field is configurable. */
export type VideoApi = {
  submitPath: string;
  statusPath: string; // must contain {id}
  idField: string; // dot path in the submit response
  statusField: string; // dot path in the status response
  urlField: string; // dot path to the finished video URL
  doneValues: string[];
  failValues: string[];
  pollMs: number;
  maxPolls: number;
  extraBody?: Record<string, unknown>;
};

export type Provider = {
  id: string;
  name: string;
  protocol?: Protocol;
  baseUrl: string;
  apiKey: string; // decrypted; server-side only
  model: string; // chat model ("" = none)
  imageModel: string;
  videoModel: string;
  videoApi?: VideoApi;
  orgId?: string;
  headers?: Record<string, string>;
  priority: number;
  enabled: boolean;
  timeoutMs: number;
  maxRetries: number;
  supportsVision: boolean;
  /** Never send user files/images to this provider, not even as a fallback. */
  noAttachments: boolean;
  /** The stored key could not be decrypted (encryption key changed). */
  keyUnreadable?: boolean;
  source?: "env" | "stored";
};

export type Capabilities = { chat: boolean; vision: boolean; image: boolean; video: boolean };
export const capabilitiesOf = (p: Provider): Capabilities => ({
  chat: !!p.model,
  vision: !!p.model && p.supportsVision,
  image: !!p.imageModel && (p.protocol ?? "openai") === "openai",
  video: !!p.videoModel && !!p.videoApi,
});

export type PublicProvider = Omit<Provider, "apiKey" | "headers" | "videoApi"> & {
  videoApi?: Omit<VideoApi, "extraBody">;
  hasKey: boolean;
  keyHint: string;
  headerNames: string[];
  capabilities: Capabilities;
};

export function toPublic(p: Provider): PublicProvider {
  const { apiKey, headers, videoApi, ...rest } = p;
  const { extraBody: _x, ...api } = videoApi ?? ({} as VideoApi);
  return {
    ...rest,
    ...(videoApi ? { videoApi: api } : {}),
    hasKey: apiKey.length > 0,
    keyHint: apiKey ? (apiKey.length <= 8 ? "••••" : `••••${apiKey.slice(-4)}`) : "",
    headerNames: Object.keys(headers ?? {}),
    capabilities: capabilitiesOf(p),
  };
}

// ---------------------------------------------------------------- validation

export const DEFAULT_VIDEO_API: VideoApi = {
  submitPath: "/videos",
  statusPath: "/videos/{id}",
  idField: "id",
  statusField: "status",
  urlField: "video_url",
  doneValues: ["completed", "succeeded", "success", "done"],
  failValues: ["failed", "error", "cancelled", "canceled"],
  pollMs: 5000,
  maxPolls: 120,
};

const FORBIDDEN_HEADERS = new Set(["host", "content-length", "connection", "transfer-encoding", "authorization", "x-api-key"]);
const ID_RE = /^[a-z0-9-]{1,40}$/;
const FIELD_RE = /^[A-Za-z0-9_.-]{1,100}$/;
const isRec = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

export type ProviderInput = Partial<Omit<Provider, "keyUnreadable" | "source" | "videoApi">> & { clearKey?: boolean; videoApi?: Partial<VideoApi> };

function validateVideoApi(v: unknown, errors: string[]): Partial<VideoApi> | undefined {
  if (!isRec(v)) {
    errors.push("videoApi: must be an object");
    return undefined;
  }
  const out: Partial<VideoApi> = {};
  const path = (k: "submitPath" | "statusPath") => {
    if (v[k] === undefined) return;
    const s = v[k];
    if (typeof s !== "string" || !s.startsWith("/") || s.startsWith("//") || s.includes("://") || s.includes("..") || s.length > 200 || /[\s\\]/.test(s)) {
      errors.push(`videoApi.${k}: must be a path on the provider such as "/videos" (no full URLs)`);
    } else out[k] = s;
  };
  path("submitPath");
  path("statusPath");
  if (out.statusPath && !out.statusPath.includes("{id}")) errors.push('videoApi.statusPath: must contain "{id}" where the job id goes');
  for (const k of ["idField", "statusField", "urlField"] as const) {
    if (v[k] === undefined) continue;
    if (typeof v[k] !== "string" || !FIELD_RE.test(v[k] as string)) errors.push(`videoApi.${k}: must be a field name or dot path`);
    else out[k] = v[k] as string;
  }
  for (const k of ["doneValues", "failValues"] as const) {
    if (v[k] === undefined) continue;
    const a = v[k];
    if (!Array.isArray(a) || a.length > 10 || a.some((x) => typeof x !== "string" || !x || x.length > 40)) errors.push(`videoApi.${k}: must be a list of up to 10 short strings`);
    else out[k] = (a as string[]).map((x) => x.toLowerCase());
  }
  const int = (k: "pollMs" | "maxPolls", min: number, max: number) => {
    if (v[k] === undefined) return;
    if (typeof v[k] !== "number" || !Number.isInteger(v[k]) || (v[k] as number) < min || (v[k] as number) > max) errors.push(`videoApi.${k}: must be a whole number between ${min} and ${max}`);
    else out[k] = v[k] as number;
  };
  int("pollMs", 500, 60_000);
  int("maxPolls", 1, 1000);
  if (v.extraBody !== undefined) {
    if (!isRec(v.extraBody) || JSON.stringify(v.extraBody).length > 4000) errors.push("videoApi.extraBody: must be a JSON object under 4000 characters");
    else out.extraBody = v.extraBody;
  }
  return out;
}

/**
 * Validates and normalizes provider input.
 * partial=false: a complete new provider (name, baseUrl and at least one model required).
 * partial=true: an edit; only the fields present are checked.
 */
export function validateProviderInput(input: unknown, opts: { allowLocal?: boolean; partial?: boolean } = {}): { value: ProviderInput; errors: string[] } {
  const errors: string[] = [];
  const value: ProviderInput = {};
  if (!isRec(input)) return { value, errors: ["provider must be a JSON object"] };
  const partial = opts.partial ?? false;
  const local = opts.allowLocal ?? allowLocalEnv();

  const str = (k: string, o: { max: number; min?: number; re?: RegExp; msg?: string; trim?: boolean }): string | undefined => {
    const v = input[k];
    if (v === undefined || v === null) return undefined;
    if (typeof v !== "string") {
      errors.push(`${k}: must be text`);
      return undefined;
    }
    const s = o.trim === false ? v : v.trim();
    if (s.length > o.max) errors.push(`${k}: must be at most ${o.max} characters`);
    else if (o.min !== undefined && s.length < o.min) errors.push(`${k}: is required`);
    else if (o.re && s !== "" && !o.re.test(s)) errors.push(`${k}: ${o.msg ?? "invalid format"}`);
    else return s;
    return undefined;
  };
  const int = (k: string, min: number, max: number): number | undefined => {
    const v = input[k];
    if (v === undefined || v === null) return undefined;
    if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
      errors.push(`${k}: must be a whole number between ${min} and ${max}`);
      return undefined;
    }
    return v;
  };
  const bool = (k: string): boolean | undefined => {
    const v = input[k];
    if (v === undefined || v === null) return undefined;
    if (typeof v !== "boolean") {
      errors.push(`${k}: must be true or false`);
      return undefined;
    }
    return v;
  };
  const set = <K extends keyof ProviderInput>(k: K, v: ProviderInput[K] | undefined) => {
    if (v !== undefined) value[k] = v;
  };

  set("id", str("id", { max: 40, re: ID_RE, msg: "use lowercase letters, digits and dashes" }));
  set("name", str("name", { max: 80, min: partial ? undefined : 1 }));
  if (!partial && input.name === undefined) errors.push("name: is required");
  const proto = str("protocol", { max: 20 });
  if (proto !== undefined) {
    if ((PROTOCOLS as readonly string[]).includes(proto)) value.protocol = proto as Protocol;
    else errors.push(`protocol: must be one of ${PROTOCOLS.join(", ")}`);
  }

  const baseUrl = str("baseUrl", { max: 300, min: partial ? undefined : 1 });
  if (!partial && input.baseUrl === undefined) errors.push("baseUrl: is required");
  if (baseUrl) {
    try {
      assertSafeUrl(baseUrl, local);
      value.baseUrl = baseUrl.replace(/\/+$/, "");
    } catch (e) {
      errors.push(`baseUrl: ${(e as Error).message}`);
    }
  }

  set("apiKey", str("apiKey", { max: 2000, re: /^\S+$/, msg: "must not contain spaces or line breaks", trim: false }));
  set("clearKey", bool("clearKey"));
  for (const k of ["model", "imageModel", "videoModel"] as const) set(k, str(k, { max: 200, re: /^[^\x00-\x1f]+$/, msg: "contains invalid characters" }));
  set("orgId", str("orgId", { max: 100, re: /^[A-Za-z0-9_.:-]+$/, msg: "contains invalid characters" }));
  set("priority", int("priority", 0, 100_000));
  set("enabled", bool("enabled"));
  set("timeoutMs", int("timeoutMs", 1000, 300_000));
  set("maxRetries", int("maxRetries", 0, 5));
  set("supportsVision", bool("supportsVision"));
  set("noAttachments", bool("noAttachments"));

  if (input.headers !== undefined && input.headers !== null) {
    if (!isRec(input.headers) || Object.keys(input.headers).length > 20) errors.push("headers: must be an object with at most 20 entries");
    else {
      const h: Record<string, string> = {};
      for (const [k, v] of Object.entries(input.headers)) {
        if (!/^[A-Za-z0-9-]{1,60}$/.test(k) || FORBIDDEN_HEADERS.has(k.toLowerCase())) errors.push(`headers: "${k}" is not allowed`);
        else if (typeof v !== "string" || v.length > 1000 || /[\r\n\0]/.test(v)) errors.push(`headers: invalid value for "${k}"`);
        else h[k] = v;
      }
      value.headers = h;
    }
  }

  if (input.videoApi !== undefined && input.videoApi !== null) value.videoApi = validateVideoApi(input.videoApi, errors);

  if (!partial) {
    if (!input.model && !input.imageModel && !input.videoModel) errors.push("model: set at least one of model (chat), imageModel or videoModel");
    if (input.videoModel && !input.videoApi) errors.push("videoApi: required when videoModel is set (use {} for the OpenAI-style defaults)");
  }
  return { value, errors };
}

// ---------------------------------------------------------------- environment providers

/** Providers declared in WAHA_PROVIDERS. Read-only in the UI. */
export function loadProviders(
  raw: string | undefined = process.env.WAHA_PROVIDERS,
  allowLocal: boolean = allowLocalEnv(),
): { providers: Provider[]; errors: string[] } {
  const errors: string[] = [];
  if (!raw || !raw.trim()) return { providers: [], errors: ["WAHA_PROVIDERS is not set"] };
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { providers: [], errors: ["WAHA_PROVIDERS is not valid JSON"] };
  }
  if (!Array.isArray(parsed)) return { providers: [], errors: ["WAHA_PROVIDERS must be a JSON array"] };

  const providers: Provider[] = [];
  const seen = new Set<string>();
  parsed.forEach((item, i) => {
    const label = isRec(item) && typeof item.id === "string" ? `provider "${item.id}"` : `provider #${i}`;
    const { value, errors: errs } = validateProviderInput(item, { allowLocal, partial: false });
    if (errs.length) return void errors.push(`${label}: ${errs.join("; ")}`);
    if (!value.id) return void errors.push(`${label}: id is required`);
    if (seen.has(value.id)) return void errors.push(`${label}: duplicate id "${value.id}"`);
    seen.add(value.id);
    providers.push({ ...build(value), source: "env" });
  });
  providers.sort((a, b) => a.priority - b.priority);
  return { providers, errors };
}

/** Fills defaults for a validated, complete provider input. */
function build(v: ProviderInput): Provider {
  const videoModel = v.videoModel ?? "";
  return {
    id: v.id as string,
    name: v.name as string,
    protocol: v.protocol ?? "openai",
    baseUrl: v.baseUrl as string,
    apiKey: v.apiKey ?? "",
    model: v.model ?? "",
    imageModel: v.imageModel ?? "",
    videoModel,
    ...(videoModel || v.videoApi ? { videoApi: { ...DEFAULT_VIDEO_API, ...(v.videoApi ?? {}) } } : {}),
    ...(v.orgId ? { orgId: v.orgId } : {}),
    ...(v.headers && Object.keys(v.headers).length ? { headers: v.headers } : {}),
    priority: v.priority ?? 100,
    enabled: v.enabled ?? true,
    timeoutMs: v.timeoutMs ?? 30_000,
    maxRetries: v.maxRetries ?? 2,
    supportsVision: v.supportsVision ?? false,
    noAttachments: v.noAttachments ?? false,
  };
}

// ---------------------------------------------------------------- encrypted store

type Stored = Omit<Provider, "apiKey" | "headers" | "keyUnreadable" | "source"> & { apiKeyEnc?: string; headersEnc?: string };

function seal(p: Provider): Stored {
  const { apiKey, headers, keyUnreadable: _k, source: _s, ...rest } = p;
  return {
    ...rest,
    ...(apiKey ? { apiKeyEnc: encryptSecret(apiKey) } : {}),
    ...(headers && Object.keys(headers).length ? { headersEnc: encryptSecret(JSON.stringify(headers)) } : {}),
  };
}

function open(s: Stored): Provider {
  const { apiKeyEnc, headersEnc, ...rest } = s;
  let apiKey = "";
  let headers: Record<string, string> | undefined;
  let keyUnreadable = false;
  try {
    if (apiKeyEnc) apiKey = decryptSecret(apiKeyEnc);
    if (headersEnc) headers = JSON.parse(decryptSecret(headersEnc));
  } catch {
    apiKey = "";
    headers = undefined;
    keyUnreadable = true;
  }
  return { ...rest, protocol: rest.protocol ?? "openai", apiKey, ...(headers ? { headers } : {}), ...(keyUnreadable ? { keyUnreadable } : {}), source: "stored" };
}

const readStored = () => readJson<Stored[]>("providers", []);

/** Stored providers plus WAHA_PROVIDERS; a stored provider wins when ids clash. Sorted by priority. */
export async function loadAllProviders(): Promise<{ providers: Provider[]; errors: string[] }> {
  const stored = (await readStored()).map(open);
  const env = loadProviders();
  const ids = new Set(stored.map((p) => p.id));
  const providers = [...stored, ...env.providers.filter((p) => !ids.has(p.id))];
  providers.sort((a, b) => a.priority - b.priority || a.name.localeCompare(b.name));
  return { providers, errors: process.env.WAHA_PROVIDERS ? env.errors : [] };
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 28) || "provider";

export async function createProvider(value: ProviderInput): Promise<Provider> {
  let created: Provider | undefined;
  const env = loadProviders().providers;
  await updateJson<Stored[]>("providers", [], (list) => {
    const taken = new Set([...list.map((p) => p.id), ...env.map((p) => p.id)]);
    const id = value.id ?? `${slug(value.name ?? "")}-${randomBytes(2).toString("hex")}`;
    if (taken.has(id)) throw new Error(`A provider with id "${id}" already exists`);
    created = build({ ...value, id });
    return [...list, seal(created)];
  });
  return { ...(created as Provider), source: "stored" };
}

export async function updateProvider(id: string, change: ProviderInput): Promise<Provider> {
  let updated: Provider | undefined;
  const isEnv = loadProviders().providers.some((p) => p.id === id);
  await updateJson<Stored[]>("providers", [], (list) => {
    const i = list.findIndex((p) => p.id === id);
    if (i < 0) throw new Error(isEnv ? `Provider "${id}" is read-only (defined in WAHA_PROVIDERS). Add a copy with a new id instead.` : "Provider not found");
    const cur = open(list[i]);
    const { clearKey, id: _ignored, videoApi, apiKey, ...rest } = change;
    const merged: Provider = { ...cur, ...rest, id: cur.id };
    merged.apiKey = clearKey ? "" : apiKey ? apiKey : cur.apiKey;
    if (clearKey || apiKey) delete merged.keyUnreadable;
    if (videoApi) merged.videoApi = { ...DEFAULT_VIDEO_API, ...(cur.videoApi ?? {}), ...videoApi };
    if (!merged.model && !merged.imageModel && !merged.videoModel) throw new Error("Set at least one of model (chat), imageModel or videoModel");
    if (merged.videoModel && !merged.videoApi) throw new Error("videoModel needs videoApi settings (send videoApi: {} for the OpenAI-style defaults)");
    updated = merged;
    const next = [...list];
    next[i] = seal(merged);
    return next;
  });
  return { ...(updated as Provider), source: "stored" };
}

export async function deleteProvider(id: string): Promise<void> {
  const isEnv = loadProviders().providers.some((p) => p.id === id);
  await updateJson<Stored[]>("providers", [], (list) => {
    if (!list.some((p) => p.id === id)) throw new Error(isEnv ? `Provider "${id}" is read-only (defined in WAHA_PROVIDERS)` : "Provider not found");
    return list.filter((p) => p.id !== id);
  });
}

/** Saves the given order as priorities 10, 20, 30... Environment providers keep their own priority. */
export async function reorderProviders(ids: string[]): Promise<void> {
  await updateJson<Stored[]>("providers", [], (list) => {
    const next = list.map((p) => ({ ...p }));
    ids.forEach((id, i) => {
      const p = next.find((x) => x.id === id);
      if (p) p.priority = (i + 1) * 10;
    });
    return next;
  });
}
