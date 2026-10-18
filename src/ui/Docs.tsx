"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { describeError, type Asset } from "./api";
import { useApp } from "./app";
import { AssetView, ErrorBox, Modal, UploadButtons } from "./common";

type Conv = { from: string; to: string; available: boolean; tool: string; note?: string };
type Health = { features: { ocr: boolean; documentConversion: boolean } };

export default function Docs() {
  const { t, api, lang, toast, askAboutFiles, token } = useApp();
  const [items, setItems] = useState<Asset[]>([]);
  const [total, setTotal] = useState(0);
  const [kind, setKind] = useState<"" | "image" | "document" | "video">("");
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [convs, setConvs] = useState<Conv[]>([]);
  const [health, setHealth] = useState<Health | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [preview, setPreview] = useState<{ asset: Asset; text: string; truncated?: boolean } | null>(null);
  const [limit, setLimit] = useState(48);
  const [drag, setDrag] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const d = await api.get<{ items: Asset[]; total: number }>(`/api/files?limit=${limit}${kind ? `&kind=${kind}` : ""}`);
      setItems(d.items);
      setTotal(d.total);
      setErr(null);
    } catch (e) {
      setErr(describeError(e));
    } finally {
      setLoading(false);
    }
  }, [api, kind, limit]);

  // Reload whenever the access token changes: the first load may have happened before it was entered.
  useEffect(() => {
    void load();
  }, [load, token]);

  useEffect(() => {
    api.get<{ conversions: Conv[] }>("/api/convert").then((d) => setConvs(d.conversions)).catch(() => undefined);
    api.get<Health>("/api/health").then(setHealth).catch(() => undefined);
  }, [api, token]);

  const targets = useMemo(() => {
    const m = new Map<string, Conv[]>();
    for (const c of convs) m.set(c.from, [...(m.get(c.from) ?? []), c]);
    return m;
  }, [convs]);

  async function convert(a: Asset, to: string) {
    setBusy(a.id);
    try {
      const r = await api.post<{ asset: Asset }>("/api/convert", { assetId: a.id, to });
      toast(t("converted", { name: r.asset.name }));
      await load();
    } catch (e) {
      toast(describeError(e), "error");
    } finally {
      setBusy(null);
    }
  }

  async function readText(a: Asset) {
    setBusy(a.id);
    try {
      const r = await api.get<{ text: string; truncated?: boolean }>(`/api/files/${a.id}/text`);
      setPreview({ asset: a, text: r.text, truncated: r.truncated });
    } catch (e) {
      toast(describeError(e), "error");
    } finally {
      setBusy(null);
    }
  }

  async function remove(a: Asset) {
    try {
      await api.del(`/api/files/${a.id}`);
      setItems((x) => x.filter((y) => y.id !== a.id));
      setTotal((n) => n - 1);
    } catch (e) {
      toast(describeError(e), "error");
    }
  }

  async function dropFiles(files: FileList) {
    try {
      const r = await api.upload([...files]);
      if (r.failed.length) toast(r.failed.map((f) => `${f.name}: ${f.error}`).join("\n"), "error");
      await load();
    } catch (e) {
      toast(describeError(e), "error");
    }
  }

  const when = (ts: number) => new Date(ts).toLocaleString(lang);

  return (
    <section className="page" onDragOver={(e) => { e.preventDefault(); setDrag(true); }} onDragLeave={() => setDrag(false)} onDrop={(e) => { e.preventDefault(); setDrag(false); if (e.dataTransfer.files.length) void dropFiles(e.dataTransfer.files); }}>
      <header className="page-head">
        <div>
          <h2>{t("docsTitle")}</h2>
          <p className="muted">{t("docsHelp")}</p>
        </div>
        <UploadButtons onUploaded={() => void load()} />
      </header>

      <div className={`dropzone ${drag ? "on" : ""}`}>{t("dropHere")}</div>

      <div className="row wrap between">
        <div className="seg small" role="tablist">
          {(["", "document", "image", "video"] as const).map((k) => (
            <button key={k || "all"} role="tab" aria-selected={kind === k} className={kind === k ? "on" : ""} onClick={() => setKind(k)}>
              {k === "" ? t("all") : t(`kind_${k}`)}
            </button>
          ))}
        </div>
        <span className="muted small">{t("filesCount", { n: total })}</span>
      </div>

      {health && !health.features.documentConversion && <div className="warn-line">{t("noConvertTools")}</div>}
      <ErrorBox message={err} onRetry={() => void load()} />
      {!loading && items.length === 0 && !err && <div className="card empty-card"><p>{t("noFiles")}</p></div>}

      <div className="grid wide">
        {items.map((a) => {
          const opts = targets.get(a.ext) ?? [];
          const canRead = a.kind !== "video" && (a.kind === "image" ? !!health?.features.ocr : true);
          return (
            <AssetView
              key={a.id}
              asset={a}
              actions={
                <>
                  {a.kind !== "video" && <button className="btn sm" onClick={() => askAboutFiles([a])}>💬 {t("askAbout")}</button>}
                  {canRead && <button className="btn sm" disabled={busy === a.id} onClick={() => void readText(a)}>{a.kind === "image" ? t("ocr") : t("readText")}</button>}
                  {opts.length > 0 && (
                    <select
                      className="sm"
                      aria-label={t("convertTo")}
                      value=""
                      disabled={busy === a.id}
                      onChange={(e) => e.target.value && void convert(a, e.target.value)}
                    >
                      <option value="">{busy === a.id ? t("converting") : `⇄ ${t("convertTo")}…`}</option>
                      {opts.map((c) => (
                        <option key={c.to} value={c.to} disabled={!c.available}>
                          .{c.to}{c.available ? "" : ` (${t("unavailable")})`}{c.note ? ` — ${c.note}` : ""}
                        </option>
                      ))}
                    </select>
                  )}
                  <button className="btn sm danger-outline" onClick={() => void remove(a)} aria-label={`${t("delete")} ${a.name}`}>🗑</button>
                </>
              }
            />
          );
        })}
      </div>
      {total > items.length && <button className="btn" onClick={() => setLimit((l) => l + 48)}>{t("loadMore")}</button>}
      <p className="muted small">{t("retentionNote")}</p>

      {preview && (
        <Modal title={preview.asset.name} onClose={() => setPreview(null)} wide>
          {preview.truncated && <div className="warn-line">{t("docTruncated")}</div>}
          <pre className="text-preview" dir="auto">{preview.text || t("noTextFound")}</pre>
          <div className="row end">
            <button className="btn" onClick={() => void navigator.clipboard?.writeText(preview.text).then(() => toast(t("copied")))}>{t("copy")}</button>
            <button className="btn primary" onClick={() => { askAboutFiles([preview.asset]); setPreview(null); }}>💬 {t("askAbout")}</button>
          </div>
        </Modal>
      )}
    </section>
  );
}
