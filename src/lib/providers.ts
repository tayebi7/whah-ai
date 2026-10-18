import { randomBytes } from "node:crypto";
import { allowLocal as allowLocalEnv } from "./config";
import { decryptSecret, encryptSecret } from "./crypto";
import { readJson, updateJson } from "./store";
import { DEFAULT_VIDEO_API, buildProvider as build, validateProviderInput as validateCore, type Provider, type ProviderInput } from "./providers-core";

export * from "./providers-core";
const isRec = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** Validates provider input; local (http / private) endpoints are allowed only when WAHA_ALLOW_LOCAL=true. */
export function validateProviderInput(input: unknown, opts: { allowLocal?: boolean; partial?: boolean } = {}) {
  return validateCore(input, { ...opts, allowLocal: opts.allowLocal ?? allowLocalEnv() });
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
