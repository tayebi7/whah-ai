/** Remove known secrets and common key shapes from text before logging or returning it. */
export function redact(text: string, secrets: string[] = []): string {
  let out = text;
  for (const s of secrets) if (s && s.length >= 6) out = out.split(s).join("***");
  out = out.replace(/Bearer\s+[A-Za-z0-9._\-]+/g, "Bearer ***");
  out = out.replace(/\b(sk|nvapi|gsk|hf|key)[-_][A-Za-z0-9_\-]{8,}/g, "$1-***");
  return out;
}

export function maskKey(key: string): string {
  if (!key) return "";
  return key.length <= 8 ? "••••" : `••••${key.slice(-4)}`;
}
