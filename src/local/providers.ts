import { buildProvider, DEFAULT_VIDEO_API, validateProviderInput as validateCore, type Provider, type ProviderInput } from "../lib/providers-core";
import { store } from "./db";

export { toPublic } from "../lib/providers-core";
export type { Provider, ProviderInput };

/** On the phone, the user's own device is the trust boundary: local (http, LAN) endpoints such as Ollama are allowed. */
export const validateProviderInput = (input: unknown, opts: { partial?: boolean } = {}) => validateCore(input, { ...opts, allowLocal: true });

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 28) || "provider";
const rand = () => Array.from(crypto.getRandomValues(new Uint8Array(2)), (x) => x.toString(16).padStart(2, "0")).join("");

export async function loadAllProviders(): Promise<{ providers: Provider[]; errors: string[] }> {
  const list = await store().get<Provider[]>("providers", []);
  const providers = list.map((p) => ({ ...p, protocol: p.protocol ?? "openai", source: "stored" as const })).sort((a, b) => a.priority - b.priority || a.name.localeCompare(b.name));
  return { providers, errors: [] };
}

export async function createProvider(value: ProviderInput): Promise<Provider> {
  let created: Provider | undefined;
  await store().update<Provider[]>("providers", [], (list) => {
    const id = value.id ?? `${slug(value.name ?? "")}-${rand()}`;
    if (list.some((p) => p.id === id)) throw new Error(`A provider with id "${id}" already exists`);
    created = buildProvider({ ...value, id });
    return [...list, created];
  });
  return { ...(created as Provider), source: "stored" };
}

export async function updateProvider(id: string, change: ProviderInput): Promise<Provider> {
  let updated: Provider | undefined;
  await store().update<Provider[]>("providers", [], (list) => {
    const i = list.findIndex((p) => p.id === id);
    if (i < 0) throw new Error("Provider not found");
    const cur = list[i];
    const { clearKey, id: _ignored, videoApi, apiKey, ...rest } = change;
    const merged: Provider = { ...cur, ...rest, id: cur.id };
    merged.apiKey = clearKey ? "" : apiKey ? apiKey : cur.apiKey;
    if (videoApi) merged.videoApi = { ...DEFAULT_VIDEO_API, ...(cur.videoApi ?? {}), ...videoApi };
    if (!merged.model && !merged.imageModel && !merged.videoModel) throw new Error("Set at least one of model (chat), imageModel or videoModel");
    if (merged.videoModel && !merged.videoApi) throw new Error("videoModel needs videoApi settings (send videoApi: {} for the OpenAI-style defaults)");
    updated = merged;
    const next = [...list];
    next[i] = merged;
    return next;
  });
  return { ...(updated as Provider), source: "stored" };
}

export async function deleteProvider(id: string): Promise<void> {
  await store().update<Provider[]>("providers", [], (list) => {
    if (!list.some((p) => p.id === id)) throw new Error("Provider not found");
    return list.filter((p) => p.id !== id);
  });
}

export async function reorderProviders(ids: string[]): Promise<void> {
  await store().update<Provider[]>("providers", [], (list) => {
    const next = list.map((p) => ({ ...p }));
    ids.forEach((id, i) => {
      const p = next.find((x) => x.id === id);
      if (p) p.priority = (i + 1) * 10;
    });
    return next;
  });
}
