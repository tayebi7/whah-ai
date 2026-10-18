import { AssetError } from "./assets";
import { json } from "./http";
import { ToolMissingError } from "./exec";
import { redact } from "./redact";

/** Turns an unexpected error into a safe JSON response (no stack traces, no secrets). */
export function fail(e: unknown): Response {
  if (e instanceof AssetError) return json(e.status, { error: e.message });
  if (e instanceof ToolMissingError) return json(501, { error: e.message });
  const msg = e instanceof Error ? e.message : String(e);
  if (/corrupt|WAHA_ENCRYPTION_KEY/.test(msg)) return json(500, { error: redact(msg) });
  console.error("api error:", redact(msg));
  return json(500, { error: "Internal error" });
}
