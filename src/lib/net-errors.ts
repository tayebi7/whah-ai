/** Turns a low-level network failure (browser, Node or Android native HTTP) into one readable sentence plus the raw detail. */
export function describeNetError(e: unknown): string {
  const raw = (e instanceof Error ? `${e.name === "Error" ? "" : e.name + ": "}${e.message}` : typeof e === "string" ? e : "").replace(/\s+/g, " ").trim().slice(0, 220);
  const m = raw.toLowerCase();
  let hint = "";
  if (/unknownhost|unable to resolve host|enotfound|name or service not known|err_name_not_resolved|eai_again/.test(m)) hint = "the phone could not find this server (no internet, DNS blocked, or a typo in the URL)";
  else if (/ssl|certificate|handshake|cert_|trust anchor/.test(m)) hint = "the secure connection failed (check the phone's date and time, and any VPN or proxy)";
  else if (/timeout|timed out|etimedout/.test(m)) hint = "the server did not answer in time (slow or blocked network)";
  else if (/refused|econnrefused|connection reset|econnreset|unreachable|network is unreachable/.test(m)) hint = "the server refused or dropped the connection";
  else if (/cleartext/.test(m)) hint = "plain http is not allowed for this address";
  else if (/failed to fetch|networkerror|load failed|fetch failed/.test(m)) hint = "the request was blocked or there is no connection";
  return hint ? `${hint}${raw ? ` [${raw}]` : ""}` : raw || "unknown network error";
}
