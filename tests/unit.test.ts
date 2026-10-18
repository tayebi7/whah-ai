import { beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { assertSafeUrl, isPrivateHost } from "../src/lib/ssrf";
import { redact, maskKey } from "../src/lib/redact";
import { backoffDelay, resetBreakers, routeChat, RouterError } from "../src/lib/router";
import type { Provider } from "../src/lib/providers";

const mk = (id: string, over: Partial<Provider> = {}): Provider => ({
  id, name: id.toUpperCase(), baseUrl: `https://${id}.example.com/v1`, apiKey: `key-${id}-secret`,
  model: "m", imageModel: "", videoModel: "", priority: 1, enabled: true, timeoutMs: 5000,
  maxRetries: 2, supportsVision: false, noAttachments: false, ...over,
});
const ok = () => new Response("data: {}\n\n", { status: 200 });
const status = (s: number) => new Response("err", { status: s });
const msgs = [{ role: "user" as const, content: "hi" }];
const sleep = async () => undefined;

describe("ssrf", () => {
  it("blocks private and local hosts", () => {
    for (const h of ["localhost", "a.local", "127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "::1", "fe80::1", "fd00::1"]) {
      assert.equal(isPrivateHost(h), true, h);
    }
  });
  it("does not block public hosts, including names starting with fc/fd", () => {
    for (const h of ["api.openai.com", "fcdn.example.com", "fdroid.org", "8.8.8.8", "172.32.0.1"]) assert.equal(isPrivateHost(h), false, h);
  });
  it("requires https, rejects credentials and bad URLs", () => {
    assert.throws(() => assertSafeUrl("http://api.example.com"));
    assert.throws(() => assertSafeUrl("https://u:p@api.example.com"));
    assert.throws(() => assertSafeUrl("ftp://x.com"));
    assert.throws(() => assertSafeUrl("not a url"));
    assert.doesNotThrow(() => assertSafeUrl("http://localhost:11434", true));
  });
});

describe("redact", () => {
  it("masks known secrets and key shapes", () => {
    assert.ok(!redact("auth Bearer abc.def-123 here").includes("abc.def"));
    assert.ok(!redact("x sk-1234567890abcdef y").includes("1234567890"));
    assert.ok(!redact("my secret-value-99", ["secret-value-99"]).includes("secret-value"));
    assert.equal(maskKey("abcdefghij"), "••••ghij");
    assert.equal(maskKey("abc"), "••••");
  });
});

describe("routeChat", () => {
  beforeEach(() => resetBreakers());

  it("uses the first provider when it succeeds", async () => {
    const r = await routeChat([mk("a"), mk("b")], msgs, { fetchImpl: async () => ok(), sleep });
    assert.equal(r.provider.id, "a");
    assert.deepEqual(r.attempts, []);
  });
  it("falls back after a 500 and records the attempt", async () => {
    const r = await routeChat([mk("a", { maxRetries: 0 }), mk("b")], msgs, {
      fetchImpl: async (u) => (String(u).includes("//a.") ? status(500) : ok()), sleep,
    });
    assert.equal(r.provider.id, "b");
    assert.equal(r.attempts[0].providerId, "a");
  });
  it("retries the same provider on 429", async () => {
    let n = 0;
    const r = await routeChat([mk("a")], msgs, { fetchImpl: async () => (++n < 3 ? status(429) : ok()), sleep });
    assert.equal(r.provider.id, "a");
    assert.equal(n, 3);
  });
  it("does not retry invalid credentials", async () => {
    let n = 0;
    await assert.rejects(routeChat([mk("a")], msgs, { fetchImpl: async () => (n++, status(401)), sleep }), RouterError);
    assert.equal(n, 1);
  });
  it("does not fall back when autoFallback is false", async () => {
    let n = 0;
    await assert.rejects(routeChat([mk("a", { maxRetries: 0 }), mk("b")], msgs, { autoFallback: false, fetchImpl: async () => (n++, status(500)), sleep }), RouterError);
    assert.equal(n, 1);
  });
  it("does not retry after a timeout", async () => {
    let n = 0;
    const fetchImpl = ((_u: unknown, init?: RequestInit) => new Promise((_r, rej) => {
      n++; init?.signal?.addEventListener("abort", () => rej(new Error("aborted")));
    })) as unknown as typeof fetch;
    const err: any = await routeChat([mk("a", { timeoutMs: 20 })], msgs, { fetchImpl, sleep }).catch((e) => e);
    assert.ok(err instanceof RouterError);
    assert.equal(n, 1);
    assert.match(err.attempts[0].reason, /timed out/);
  });
  it("opens the circuit breaker after repeated failures", async () => {
    const f = async () => status(500);
    for (let i = 0; i < 3; i++) await routeChat([mk("a", { maxRetries: 0 })], msgs, { fetchImpl: f, sleep }).catch(() => undefined);
    const err: any = await routeChat([mk("a", { maxRetries: 0 })], msgs, { fetchImpl: f, sleep }).catch((e) => e);
    assert.match(err.attempts[0].reason, /circuit breaker/);
  });
  it("never leaks the API key in attempts", async () => {
    const err: any = await routeChat([mk("a", { maxRetries: 0 })], msgs, { fetchImpl: async () => status(401), sleep }).catch((e) => e);
    assert.ok(!JSON.stringify(err.attempts).includes("secret"));
  });
  it("skips disabled providers, vision-less ones for images, and noAttachments ones for files", async () => {
    let r = await routeChat([mk("a", { enabled: false }), mk("b")], msgs, { fetchImpl: async () => ok(), sleep });
    assert.equal(r.provider.id, "b");
    r = await routeChat([mk("a"), mk("b", { supportsVision: true })], msgs, { requireVision: true, fetchImpl: async () => ok(), sleep });
    assert.equal(r.provider.id, "b");
    r = await routeChat([mk("a", { noAttachments: true }), mk("b")], msgs, { hasAttachments: true, fetchImpl: async () => ok(), sleep });
    assert.equal(r.provider.id, "b");
    await assert.rejects(routeChat([mk("a")], msgs, { requireVision: true, fetchImpl: async () => ok(), sleep }), RouterError);
  });
  it("backoff grows with jitter and is capped", () => {
    assert.equal(backoffDelay(0, () => 1), 500);
    assert.equal(backoffDelay(1, () => 1), 1000);
    assert.equal(backoffDelay(0, () => 0), 250);
    assert.equal(backoffDelay(20, () => 1), 8000);
  });
});
