/**
 * On-device storage for the Android app: small JSON values (providers, file list, jobs) and file blobs.
 * IndexedDB in the WebView; an in-memory fallback is used when IndexedDB is missing (unit tests, private mode).
 */
export interface Store {
  get<T>(key: string, fallback: T): Promise<T>;
  set(key: string, value: unknown): Promise<void>;
  /** Read-modify-write, serialized so concurrent updates never lose data. */
  update<T>(key: string, fallback: T, fn: (cur: T) => T): Promise<T>;
  putBlob(id: string, data: Uint8Array): Promise<void>;
  getBlob(id: string): Promise<Uint8Array | undefined>;
  delBlob(id: string): Promise<void>;
}

class MemoryStore implements Store {
  private kv = new Map<string, string>();
  private blobs = new Map<string, Uint8Array>();
  private chain: Promise<unknown> = Promise.resolve();
  async get<T>(key: string, fallback: T): Promise<T> {
    const v = this.kv.get(key);
    return v === undefined ? fallback : (JSON.parse(v) as T);
  }
  async set(key: string, value: unknown) {
    this.kv.set(key, JSON.stringify(value));
  }
  update<T>(key: string, fallback: T, fn: (cur: T) => T): Promise<T> {
    const run = this.chain.then(async () => {
      const next = fn(await this.get<T>(key, fallback));
      await this.set(key, next);
      return next;
    });
    this.chain = run.catch(() => undefined);
    return run;
  }
  async putBlob(id: string, data: Uint8Array) {
    this.blobs.set(id, data);
  }
  async getBlob(id: string) {
    return this.blobs.get(id);
  }
  async delBlob(id: string) {
    this.blobs.delete(id);
  }
}

const req = <T>(r: IDBRequest<T>) => new Promise<T>((res, rej) => ((r.onsuccess = () => res(r.result)), (r.onerror = () => rej(r.error))));

class IdbStore implements Store {
  private db: Promise<IDBDatabase>;
  private chain: Promise<unknown> = Promise.resolve();
  constructor() {
    this.db = new Promise((res, rej) => {
      const o = indexedDB.open("waha-local", 1);
      o.onupgradeneeded = () => {
        o.result.createObjectStore("kv");
        o.result.createObjectStore("blobs");
      };
      o.onsuccess = () => res(o.result);
      o.onerror = () => rej(o.error);
    });
  }
  private async store(name: "kv" | "blobs", mode: IDBTransactionMode) {
    return (await this.db).transaction(name, mode).objectStore(name);
  }
  async get<T>(key: string, fallback: T): Promise<T> {
    const v = await req(await this.store("kv", "readonly").then((s) => s.get(key)));
    return v === undefined ? fallback : (v as T);
  }
  async set(key: string, value: unknown) {
    await req((await this.store("kv", "readwrite")).put(value, key));
  }
  update<T>(key: string, fallback: T, fn: (cur: T) => T): Promise<T> {
    const run = this.chain.then(async () => {
      const next = fn(await this.get<T>(key, fallback));
      await this.set(key, next);
      return next;
    });
    this.chain = run.catch(() => undefined);
    return run;
  }
  async putBlob(id: string, data: Uint8Array) {
    await req((await this.store("blobs", "readwrite")).put(data, id));
  }
  async getBlob(id: string) {
    const v = await req((await this.store("blobs", "readonly")).get(id));
    return v === undefined ? undefined : new Uint8Array(v as ArrayBuffer | Uint8Array);
  }
  async delBlob(id: string) {
    await req((await this.store("blobs", "readwrite")).delete(id));
  }
}

let current: Store | null = null;
export function store(): Store {
  if (!current) current = typeof indexedDB !== "undefined" ? new IdbStore() : new MemoryStore();
  return current;
}
/** Tests: start from an empty in-memory store. */
export function useMemoryStore(): Store {
  current = new MemoryStore();
  return current;
}
