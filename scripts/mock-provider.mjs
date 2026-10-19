// Tiny OpenAI-style provider for the emulator test. Deliberately sends NO CORS headers:
// a plain WebView fetch would be blocked, so success proves the app's native HTTP path works.
import http from "node:http";
const KEY = "mock-key-12345";
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
http
  .createServer((req, res) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      const body = raw ? JSON.parse(raw) : {};
      console.log(req.method, req.url, req.headers["content-type"] || "-", raw.length);
      const json = (code, o) => (res.writeHead(code, { "content-type": "application/json" }), res.end(JSON.stringify(o)));
      if (req.headers.authorization !== `Bearer ${KEY}`) return json(401, { error: { message: "bad key" } });
      if (req.url === "/v1/models") return json(200, { data: [{ id: "m1" }, { id: "m2" }] });
      if (req.url === "/v1/images/generations") return json(200, { data: [{ b64_json: PNG.toString("base64") }] });
      if (req.url === "/v1/chat/completions") {
        if (!body.stream) return json(200, { choices: [{ message: { content: "ok" } }] });
        res.writeHead(200, { "content-type": "text/event-stream" });
        for (const w of ["Hello", " from", " mock"]) res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: w } }] })}\n\n`);
        return res.end("data: [DONE]\n\n");
      }
      json(404, { error: { message: "not found" } });
    });
  })
  .listen(8787, "0.0.0.0", () => console.log("mock provider on :8787"));
