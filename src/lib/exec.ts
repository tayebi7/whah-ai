import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export class ToolMissingError extends Error {
  constructor(public tool: string) {
    super(`"${tool}" is not installed on the server, so this feature is unavailable`);
    this.name = "ToolMissingError";
  }
}

const found = new Map<string, boolean>();
/** True when an executable with this name is on PATH (result cached). */
export function hasTool(name: string): boolean {
  const cached = found.get(name);
  if (cached !== undefined) return cached;
  const exts = process.platform === "win32" ? (process.env.PATHEXT ?? ".EXE;.CMD").split(";") : [""];
  const ok = (process.env.PATH ?? "").split(path.delimiter).some((d) => d && exts.some((e) => fs.existsSync(path.join(d, name + e))));
  found.set(name, ok);
  return ok;
}

export type RunOptions = { timeoutMs?: number; cwd?: string; home?: string; maxOutput?: number; signal?: AbortSignal };

/**
 * Runs an external program WITHOUT a shell (arguments are never parsed by a shell), with a
 * timeout, an output cap, and a clean environment. Rejects with a short, readable message.
 */
export function run(cmd: string, args: string[], o: RunOptions = {}): Promise<{ stdout: Buffer; stderr: string }> {
  if (!hasTool(cmd)) return Promise.reject(new ToolMissingError(cmd));
  return new Promise((resolve, reject) => {
    const env = { PATH: process.env.PATH, LANG: "C.UTF-8", HOME: o.home ?? os.tmpdir(), TMPDIR: o.home ?? os.tmpdir() } as unknown as NodeJS.ProcessEnv;
    const child = spawn(cmd, args, { cwd: o.cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    const out: Buffer[] = [];
    let outLen = 0;
    let err = "";
    let timedOut = false;
    const cap = o.maxOutput ?? 200 * 1024 * 1024;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, o.timeoutMs ?? 60_000);
    const onAbort = () => child.kill("SIGKILL");
    o.signal?.addEventListener("abort", onAbort, { once: true });
    child.stdout.on("data", (d: Buffer) => {
      outLen += d.length;
      if (outLen > cap) child.kill("SIGKILL");
      else out.push(d);
    });
    child.stderr.on("data", (d: Buffer) => {
      if (err.length < 4000) err += d.toString("utf8");
    });
    child.on("error", (e) => {
      clearTimeout(timer);
      reject(new Error(`${cmd} failed to start: ${e.message}`));
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      o.signal?.removeEventListener("abort", onAbort);
      if (o.signal?.aborted) return reject(new Error("cancelled"));
      if (timedOut) return reject(new Error(`${cmd} timed out`));
      if (code !== 0) return reject(new Error(`${cmd} failed: ${err.trim().split("\n").slice(-3).join(" ").slice(0, 300) || `exit code ${code}`}`));
      resolve({ stdout: Buffer.concat(out), stderr: err });
    });
  });
}

/** Limits how many heavy tasks run at once (LibreOffice, OCR, ffmpeg...). */
export function semaphore(max: number) {
  let active = 0;
  const queue: (() => void)[] = [];
  return async function limit<T>(fn: () => Promise<T>): Promise<T> {
    if (active >= max) await new Promise<void>((r) => queue.push(r));
    active++;
    try {
      return await fn();
    } finally {
      active--;
      queue.shift()?.();
    }
  };
}

export async function withTempDir<T>(fn: (dir: string) => Promise<T>): Promise<T> {
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "waha-"));
  try {
    return await fn(dir);
  } finally {
    await fs.promises.rm(dir, { recursive: true, force: true });
  }
}
