"use client";

import { saveBlobAs } from "../local/save";
import { useEffect, useRef, useState } from "react";
import { type Asset } from "./api";
import { useApp } from "./app";
import { ErrorBox, FileName, UploadButtons } from "./common";

type Msg = { role: "user" | "assistant"; content: string; meta?: string; files?: Asset[] };

async function readError(res: Response): Promise<string> {
  const data = await res.json().catch(() => ({}));
  const attempts = Array.isArray(data.attempts) ? ` — ${data.attempts.map((a: { providerId: string; reason: string }) => `${a.providerId}: ${a.reason}`).join("; ")}` : "";
  const details = Array.isArray(data.details) ? ` (${data.details.join("; ")})` : "";
  return `${data.error ?? `HTTP ${res.status}`}${details}${attempts}`;
}

export default function Chat() {
  const { t, api, providers, providersLoaded, go, chatSeed, consumeSeed } = useApp();
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [files, setFiles] = useState<Asset[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [providerId, setProviderId] = useState("");
  const [autoFallback, setAutoFallback] = useState(true);
  const abortRef = useRef<AbortController | null>(null);
  const endRef = useRef<HTMLDivElement>(null);

  const chatProviders = providers.filter((p) => p.enabled && p.capabilities.chat);
  const anyVision = chatProviders.some((p) => p.capabilities.vision);
  const hasImage = files.some((f) => f.kind === "image");

  useEffect(() => {
    if (chatSeed.length) {
      setFiles((f) => [...f, ...chatSeed.filter((s) => !f.some((x) => x.id === s.id))].slice(0, 6));
      consumeSeed();
    }
  }, [chatSeed, consumeSeed]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

  useEffect(() => () => abortRef.current?.abort(), []);

  async function send(history: Msg[]) {
    setBusy(true);
    setError(null);
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    setMessages([...history, { role: "assistant", content: "" }]);
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json", ...api.auth() },
        body: JSON.stringify({
          messages: history.map((m) => ({ role: m.role, content: m.content, ...(m.files?.length ? { attachments: m.files.map((f) => f.id) } : {}) })),
          providerId: providerId || undefined,
          autoFallback,
        }),
        signal: ctrl.signal,
      });
      if (!res.ok || !res.body) throw new Error(await readError(res));

      const name = decodeURIComponent(res.headers.get("x-waha-provider") ?? "");
      const model = decodeURIComponent(res.headers.get("x-waha-model") ?? "");
      let attempts: { providerId: string; reason?: string }[] = [];
      try {
        attempts = JSON.parse(decodeURIComponent(res.headers.get("x-waha-fallback") ?? "[]"));
      } catch {
        attempts = [];
      }
      const meta = `${t("answeredBy")}: ${name} · ${model}${attempts.length ? ` — ${t("switched")} ${attempts.map((a) => a.providerId).join(", ")}` : ""}`;

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      let acc = "";
      const eat = (line: string) => {
        const s = line.trim();
        if (!s.startsWith("data:")) return;
        const payload = s.slice(5).trim();
        if (!payload || payload === "[DONE]") return;
        try {
          const j = JSON.parse(payload);
          if (j?.error) throw new Error(j.error.message ?? "stream error");
          const delta = j?.choices?.[0]?.delta?.content;
          if (typeof delta === "string") {
            acc += delta;
            setMessages([...history, { role: "assistant", content: acc, meta }]);
          }
        } catch (e) {
          if (e instanceof Error && e.message !== "Unexpected end of JSON input" && !(e instanceof SyntaxError)) throw e;
        }
      };
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? "";
        lines.forEach(eat);
      }
      eat(buf);
      setMessages([...history, { role: "assistant", content: acc || "…", meta }]);
    } catch (e) {
      if ((e as Error).name !== "AbortError") setError((e as Error).message);
      setMessages((m) => (m.length && m[m.length - 1].role === "assistant" && !m[m.length - 1].content ? m.slice(0, -1) : m));
    } finally {
      setBusy(false);
      abortRef.current = null;
    }
  }

  function submit() {
    const text = input.trim();
    if ((!text && files.length === 0) || busy) return;
    const msg: Msg = { role: "user", content: text || t("describeFiles"), files: files.length ? files : undefined };
    setInput("");
    setFiles([]);
    void send([...messages.filter((m) => m.content), msg]);
  }

  function retry() {
    const hist = messages.filter((m) => m.content);
    if (hist.length && hist[hist.length - 1].role === "assistant") hist.pop();
    if (hist.length) void send(hist);
  }

  function exportChat() {
    const md = messages.map((m) => `**${m.role === "user" ? t("you") : "Waha AI"}:**\n\n${m.content}`).join("\n\n---\n\n");
    void saveBlobAs(new Blob([md], { type: "text/markdown;charset=utf-8" }), `waha-chat-${new Date().toISOString().slice(0, 10)}.md`);
  }

  return (
    <section className="chat-pane">
      <div className="toolbar">
        <label className="inline">
          <span>{t("provider")}</span>
          <select value={providerId} onChange={(e) => setProviderId(e.target.value)}>
            <option value="">{t("auto")}</option>
            {chatProviders.map((p) => (
              <option key={p.id} value={p.id}>{p.name} · {p.model}</option>
            ))}
          </select>
        </label>
        <label className="check">
          <input type="checkbox" checked={autoFallback} onChange={(e) => setAutoFallback(e.target.checked)} />
          {t("fallback")}
        </label>
        <span className="spacer" />
        <button className="btn sm" disabled={messages.length === 0} onClick={exportChat}>{t("exportChat")}</button>
        <button className="btn sm" onClick={() => { abortRef.current?.abort(); setMessages([]); setError(null); setFiles([]); }}>+ {t("newChat")}</button>
      </div>

      <div className="messages" aria-live="polite">
        {messages.length === 0 && (
          <div className="empty">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.svg" alt="" width={88} height={88} />
            {providersLoaded && chatProviders.length === 0 ? (
              <>
                <p>{t("noProviders")}</p>
                <button className="btn primary" onClick={() => go("settings")}>{t("openSettings")}</button>
              </>
            ) : (
              <p>{t("empty")}</p>
            )}
          </div>
        )}
        {messages.map((m, i) => (
          <div key={i} className={`msg ${m.role}`}>
            {m.files && m.files.length > 0 && (
              <div className="chips">
                {m.files.map((f) => (
                  <span key={f.id} className="chip">{f.kind === "image" ? "🖼" : "📄"} <FileName name={f.name} /></span>
                ))}
              </div>
            )}
            <div className="bubble" dir="auto">{m.content || (busy && i === messages.length - 1 ? "…" : "")}</div>
            {m.meta && <div className="meta">{m.meta}</div>}
            {m.role === "assistant" && m.content && (
              <button className="btn sm ghost" onClick={() => void navigator.clipboard?.writeText(m.content)}>{t("copy")}</button>
            )}
          </div>
        ))}
        <ErrorBox message={error} onRetry={retry} />
        <div ref={endRef} />
      </div>

      <form className="composer" onSubmit={(e) => { e.preventDefault(); submit(); }}>
        {files.length > 0 && (
          <div className="chips">
            {files.map((f) => (
              <span key={f.id} className="chip removable">
                {f.kind === "image" ? "🖼" : "📄"} <FileName name={f.name} />
                <button type="button" aria-label={t("remove")} onClick={() => setFiles(files.filter((x) => x.id !== f.id))}>✕</button>
              </span>
            ))}
          </div>
        )}
        {hasImage && !anyVision && <div className="warn-line">{t("visionWarn")}</div>}
        <div className="composer-row">
          <UploadButtons onUploaded={(a) => setFiles((f) => [...f, ...a].slice(0, 6))} />
          <textarea
            value={input}
            dir="auto"
            rows={2}
            placeholder={t("placeholder")}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                e.preventDefault();
                submit();
              }
            }}
          />
          {busy ? (
            <button type="button" className="btn danger" onClick={() => abortRef.current?.abort()}>{t("stop")}</button>
          ) : (
            <button type="submit" className="btn primary" disabled={!input.trim() && files.length === 0}>{t("send")}</button>
          )}
        </div>
      </form>
    </section>
  );
}
