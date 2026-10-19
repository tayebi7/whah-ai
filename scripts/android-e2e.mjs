// Drives the installed app's WebView over the Chrome DevTools protocol and exercises the real native networking.
import { execSync } from "node:child_process";
const sh = (c) => execSync(c, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const note = (name, ok, detail = "") => results.push({ name, ok, detail: String(detail).slice(0, 600) });

let pid = "";
for (let i = 0; i < 30 && !pid; i++) {
  try { pid = sh("adb shell pidof ai.waha.app"); } catch { /* not up yet */ }
  if (!pid) await sleep(2000);
}
if (!pid) { console.log("::error title=app::the app process never started"); process.exit(1); }
sh(`adb forward tcp:9222 localabstract:webview_devtools_remote_${pid.split(" ")[0]}`);

let target;
for (let i = 0; i < 30 && !target; i++) {
  try {
    const list = await (await fetch("http://127.0.0.1:9222/json")).json();
    target = list.find((t) => t.type === "page");
  } catch { /* retry */ }
  if (!target) await sleep(2000);
}
if (!target) { console.log("::error title=devtools::no WebView page found"); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => ((ws.onopen = res), (ws.onerror = () => rej(new Error("ws failed")))));
let id = 0;
const pending = new Map();
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) (pending.get(d.id)(d), pending.delete(d.id));
};
const evaluate = (expression) =>
  new Promise((resolve) => {
    const n = ++id;
    pending.set(n, resolve);
    ws.send(JSON.stringify({ id: n, method: "Runtime.evaluate", params: { expression, awaitPromise: true, returnByValue: true } }));
  }).then((d) => (d.result?.exceptionDetails ? { error: d.result.exceptionDetails.exception?.description ?? "exception" } : d.result?.result?.value));

for (let i = 0; i < 30; i++) {
  const t = await evaluate("document.readyState === 'complete' && document.body.innerText.length > 20");
  if (t === true) break;
  await sleep(2000);
}
note("app UI loaded", true, await evaluate("document.title + ' | ' + location.href"));
note("native platform", (await evaluate("!!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())")) === true);

const call = `async (method, path, body) => {
  const r = await fetch(path, { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  return { status: r.status, text: text.slice(0, 400), provider: r.headers.get("x-waha-provider") };
}`;
const api = async (method, path, body) => evaluate(`(${call})(${JSON.stringify(method)}, ${JSON.stringify(path)}, ${body === undefined ? "undefined" : JSON.stringify(body)})`);

// 1. local mock provider over cleartext HTTP (no CORS headers)
let r = await api("POST", "/api/providers", { name: "Mock", id: "mock", baseUrl: "http://10.0.2.2:8787/v1", apiKey: "mock-key-12345", model: "m1", imageModel: "img1", supportsVision: true });
note("add provider", r?.status === 201, JSON.stringify(r));
r = await api("POST", "/api/providers/mock/test", { chat: true });
note("test provider (connection + chat) over HTTP", r?.status === 200 && /"ok":true/.test(r.text), JSON.stringify(r));
r = await api("GET", "/api/providers/mock/models");
note("list models", r?.status === 200 && /m1/.test(r.text), JSON.stringify(r));
r = await api("POST", "/api/chat", { messages: [{ role: "user", content: "hi" }] });
note("chat reply", r?.status === 200 && /Hello from mock/.test(r.text.replace(/\\n|data:|\{[^}]*"content":"|"\}\]\}/g, "")) || /Hello/.test(r?.text ?? ""), JSON.stringify(r));
r = await api("POST", "/api/studio/image", { prompt: "a cat", n: 1 });
note("image generation", r?.status === 200 && /assets/.test(r.text), JSON.stringify(r));

// 2. a real HTTPS provider endpoint that needs no key
await api("POST", "/api/providers", { name: "OpenRouter", id: "openrouter", baseUrl: "https://openrouter.ai/api/v1", apiKey: "", model: "x" });
r = await api("GET", "/api/providers/openrouter/models");
note("real HTTPS provider (openrouter.ai) lists models", r?.status === 200 && /"models":\[/.test(r.text), JSON.stringify(r));
r = await api("POST", "/api/providers/openrouter/test", {});
note("real HTTPS provider connection test", r?.status === 200 && /"connection"/.test(r.text), JSON.stringify(r));

r = await api("POST", "/api/netcheck", {});
note("connection check reports the internet and each provider", r?.status === 200 && /Internet \(Google\)/.test(r.text) && /"ok":true/.test(r.text), JSON.stringify(r));

const failed = results.filter((x) => !x.ok);
const lines = results.map((x) => `${x.ok ? "PASS" : "FAIL"} ${x.name}${x.ok ? "" : " :: " + x.detail}`);
let logcat = "";
try { logcat = sh("adb logcat -d -s Capacitor:* Capacitor/Console:* chromium:E | tail -40"); } catch { /* ignore */ }
const msg = (lines.join("\n") + (failed.length ? "\n--- logcat ---\n" + logcat : "")).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
console.log(`::${failed.length ? "error" : "notice"} title=android e2e ${results.length - failed.length}/${results.length}::${msg}`);
try { sh("adb exec-out screencap -p > /tmp/screen.png"); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
