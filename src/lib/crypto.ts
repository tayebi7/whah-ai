import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { dataDir } from "./config";

/**
 * AES-256-GCM encryption for stored secrets (API keys, custom header values).
 *
 * Key source, in order:
 *  1. WAHA_ENCRYPTION_KEY (32 bytes as 64 hex characters or base64). Recommended: keep it in
 *     your host's secret manager, separate from the data directory.
 *  2. A random key file <data>/.secret-key, created on first use (mode 0600). This protects
 *     against a leaked providers.json on its own, but NOT against someone who can read the
 *     whole data directory, because the key sits next to the ciphertext.
 */
const keyFile = () => path.join(dataDir(), ".secret-key");

function parseKey(raw: string): Buffer {
  const v = raw.trim();
  const key = /^[0-9a-fA-F]{64}$/.test(v) ? Buffer.from(v, "hex") : Buffer.from(v, "base64");
  if (key.length !== 32) throw new Error("WAHA_ENCRYPTION_KEY must be 32 bytes (64 hex characters or base64). Generate one with: openssl rand -hex 32");
  return key;
}

function fileKey(create: boolean): Buffer | null {
  const f = keyFile();
  try {
    return parseKey(fs.readFileSync(f, "utf8"));
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
  }
  if (!create) return null;
  fs.mkdirSync(path.dirname(f), { recursive: true });
  try {
    fs.writeFileSync(f, randomBytes(32).toString("hex"), { mode: 0o600, flag: "wx" });
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e; // another request created it first
  }
  return parseKey(fs.readFileSync(f, "utf8"));
}

function activeKey(): Buffer {
  const env = process.env.WAHA_ENCRYPTION_KEY;
  if (env && env.trim()) return parseKey(env);
  return fileKey(true) as Buffer;
}

/** Keys tried when decrypting (lets you move from the key file to an env key without data loss). */
function candidateKeys(): Buffer[] {
  const keys: Buffer[] = [];
  const env = process.env.WAHA_ENCRYPTION_KEY;
  if (env && env.trim()) keys.push(parseKey(env));
  try {
    const f = fileKey(false);
    if (f) keys.push(f);
  } catch {
    /* unreadable key file: decryption will report failure */
  }
  return keys;
}

/** Format: v1.<iv>.<tag>.<ciphertext> (base64url). */
export function encryptSecret(plain: string): string {
  const key = activeKey();
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", key, iv);
  const data = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return ["v1", iv.toString("base64url"), c.getAuthTag().toString("base64url"), data.toString("base64url")].join(".");
}

export function decryptSecret(payload: string): string {
  const [v, iv, tag, data] = payload.split(".");
  if (v !== "v1" || !iv || !tag || data === undefined) throw new Error("Unsupported encrypted payload");
  for (const key of candidateKeys()) {
    try {
      const d = createDecipheriv("aes-256-gcm", key, Buffer.from(iv, "base64url"));
      d.setAuthTag(Buffer.from(tag, "base64url"));
      return Buffer.concat([d.update(Buffer.from(data, "base64url")), d.final()]).toString("utf8");
    } catch {
      /* try the next key */
    }
  }
  throw new Error("Stored secret cannot be decrypted with the available key");
}
