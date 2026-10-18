import { promises as fs } from "node:fs";
import path from "node:path";
import { dataDir } from "./config";

/**
 * Tiny JSON-file store: one file per collection under the data directory.
 * - Writes are atomic (temp file + rename) so a crash never leaves half a file.
 * - Updates are serialized per collection inside this process.
 * - A corrupt file raises an error instead of being silently replaced by the fallback.
 * Limitation: no cross-process locking, so run ONE server instance per data directory.
 * For multi-instance deployments move these collections to a real database.
 */
const NAME_RE = /^[a-z0-9-]{1,40}$/;
const file = (name: string) => {
  if (!NAME_RE.test(name)) throw new Error(`Invalid collection name "${name}"`);
  return path.join(dataDir(), `${name}.json`);
};

export async function filesDir(): Promise<string> {
  const dir = path.join(dataDir(), "files");
  await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  return dir;
}

export async function readJson<T>(name: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await fs.readFile(file(name), "utf8")) as T;
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return fallback;
    if (e instanceof SyntaxError) throw new Error(`The "${name}" data file is corrupt. Restore it from a backup or remove it.`);
    throw e;
  }
}

const chains = new Map<string, Promise<unknown>>();

export function updateJson<T>(name: string, fallback: T, fn: (current: T) => T | Promise<T>): Promise<T> {
  const key = file(name);
  const run = async () => {
    const next = await fn(await readJson(name, fallback));
    await fs.mkdir(dataDir(), { recursive: true, mode: 0o700 });
    const tmp = `${key}.${process.pid}.${Date.now().toString(36)}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(next, null, 2), { mode: 0o600 });
    await fs.rename(tmp, key);
    return next;
  };
  const prev = chains.get(key) ?? Promise.resolve();
  const result = prev.then(run, run);
  chains.set(key, result.catch(() => undefined));
  return result;
}
