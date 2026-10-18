"use client";

import { saveBlobAs } from "../local/save";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { describeError, fmtSize, type Asset, type Job } from "./api";
import { useApp } from "./app";

export function useBlobUrl(id: string | null, enabled = true) {
  const { api } = useApp();
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!id || !enabled) return;
    let alive = true;
    let made: string | null = null;
    setFailed(false);
    api
      .blob(id)
      .then((b) => {
        if (!alive) return;
        made = URL.createObjectURL(b);
        setUrl(made);
      })
      .catch(() => alive && setFailed(true));
    return () => {
      alive = false;
      if (made) URL.revokeObjectURL(made);
      setUrl(null);
    };
  }, [id, enabled, api]);
  return { url, failed };
}

export function useDownload() {
  const { api, toast, t } = useApp();
  return useCallback(
    async (a: Pick<Asset, "id" | "name">) => {
      try {
        await saveBlobAs(await api.blob(a.id), a.name);
      } catch (e) {
        toast(`${t("downloadFailed")}: ${describeError(e)}`, "error");
      }
    },
    [api, toast, t],
  );
}

const RTL_CHAR = /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/;
const STRONG_CHAR = /[A-Za-z\u00C0-\u024F\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/;

/**
 * A file name that reads correctly in right-to-left text: the extension is kept as one left-to-right unit
 * so "رحلة.docx" is not shown as "docx.رحلة". The direction is chosen from the first letter instead of
 * dir="auto", because browsers ignore <bdi> content when auto-detecting the direction of the parent.
 */
export function FileName({ name, className = "fname" }: { name: string; className?: string }) {
  const i = name.lastIndexOf(".");
  const hasExt = i > 0 && i < name.length - 1 && name.length - i <= 8;
  const first = name.match(STRONG_CHAR)?.[0];
  return (
    <span className={className} dir={first && RTL_CHAR.test(first) ? "rtl" : "ltr"} title={name}>
      <bdi>{hasExt ? name.slice(0, i) : name}</bdi>
      {hasExt && <bdi dir="ltr">{name.slice(i)}</bdi>}
    </span>
  );
}

const ICON: Record<string, string> = { pdf: "PDF", docx: "DOC", xlsx: "XLS", pptx: "PPT", odt: "ODT", epub: "EPUB", txt: "TXT", md: "MD", csv: "CSV", json: "JSON", html: "HTML" };

/** Preview + download for one stored file. Images and videos load through the authenticated API. */
export function AssetView({ asset, compact, actions }: { asset: Asset; compact?: boolean; actions?: ReactNode }) {
  const { t } = useApp();
  const download = useDownload();
  const media = asset.kind === "image" || asset.kind === "video";
  const { url, failed } = useBlobUrl(asset.id, media);
  return (
    <figure className={`asset ${compact ? "compact" : ""}`}>
      <div className="thumb">
        {asset.kind === "image" && url && <img src={url} alt={asset.name} loading="lazy" />}
        {asset.kind === "video" && url && <video src={url} controls preload="metadata" playsInline />}
        {media && !url && <span className="ph">{failed ? "!" : "…"}</span>}
        {!media && <span className="ph file">{ICON[asset.ext] ?? asset.ext.toUpperCase()}</span>}
      </div>
      <figcaption>
        <FileName name={asset.name} className="name" />
        <span className="sub">{fmtSize(asset.size)}</span>
        <span className="row wrap">
          <button className="btn sm" onClick={() => void download(asset)}>{t("download")}</button>
          {actions}
        </span>
      </figcaption>
    </figure>
  );
}

export function ErrorBox({ message, onRetry }: { message: string | null; onRetry?: () => void }) {
  const { t } = useApp();
  if (!message) return null;
  return (
    <div className="error" role="alert">
      <strong>{t("error")}:</strong> <span dir="auto">{message}</span>{" "}
      {onRetry && (
        <button className="btn sm" onClick={onRetry}>{t("retry")}</button>
      )}
    </div>
  );
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  const { t } = useApp();
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    ref.current?.focus();
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={`modal ${wide ? "wide" : ""}`} role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={ref}>
        <div className="modal-head">
          <h3>{title}</h3>
          <button className="btn sm" onClick={onClose} aria-label={t("close")}>✕</button>
        </div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}

export function Progress({ value, label }: { value: number; label?: string }) {
  return (
    <div className="progress" role="progressbar" aria-valuenow={Math.round(value)} aria-valuemin={0} aria-valuemax={100} aria-label={label}>
      <div style={{ inlineSize: `${Math.max(0, Math.min(100, value))}%` }} />
    </div>
  );
}

/** Polls a background job until it finishes. Keeps polling through brief network errors. */
export function useJob(id: string | null, onDone?: (j: Job) => void) {
  const { api } = useApp();
  const [job, setJob] = useState<Job | null>(null);
  const [lost, setLost] = useState(false);
  const done = useRef(onDone);
  done.current = onDone;
  useEffect(() => {
    if (!id) return;
    let alive = true;
    let timer: ReturnType<typeof setTimeout>;
    let misses = 0;
    const tick = async () => {
      try {
        const { job: j } = await api.get<{ job: Job }>(`/api/jobs/${id}`);
        if (!alive) return;
        misses = 0;
        setLost(false);
        setJob(j);
        if (j.status !== "running") return void done.current?.(j);
      } catch {
        if (!alive) return;
        if (++misses >= 5) setLost(true);
      }
      timer = setTimeout(tick, 1500);
    };
    void tick();
    return () => {
      alive = false;
      clearTimeout(timer);
    };
  }, [id, api]);
  return { job, lost };
}

/** Shows one job: progress, warnings, results (with previews/downloads) and cancel. */
export function JobCard({ id, title, onDone, actions }: { id: string; title?: string; onDone?: (j: Job) => void; actions?: (a: Asset) => ReactNode }) {
  const { api, t, toast } = useApp();
  const { job, lost } = useJob(id, onDone);
  const [assets, setAssets] = useState<Asset[]>([]);
  const resultKey = job?.status === "done" ? job.assetIds.join(",") : "";

  useEffect(() => {
    if (!resultKey) return;
    let alive = true;
    api
      .get<{ items: Asset[] }>("/api/files?limit=200")
      .then((d) => alive && setAssets(resultKey.split(",").map((i) => d.items.find((a) => a.id === i)).filter((a): a is Asset => !!a)))
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [resultKey, api]);

  const cancel = async () => {
    try {
      await api.del(`/api/jobs/${id}`);
    } catch (e) {
      toast(describeError(e), "error");
    }
  };

  if (!job) return <div className="card job"><span className="muted">{t("loading")}</span></div>;
  const label = job.status === "running" ? t("running") : job.status === "done" ? t("done") : job.status === "cancelled" ? t("cancelled") : t("failed");
  return (
    <div className={`card job ${job.status}`}>
      <div className="row between">
        <strong dir="auto">{title ?? job.title}</strong>
        <span className={`chip ${job.status}`}>{label}</span>
      </div>
      {job.status === "running" && (
        <>
          <Progress value={job.progress} label={job.step} />
          <div className="row between muted small">
            <span dir="auto">{job.step}</span>
            <span>{Math.round(job.progress)}%</span>
          </div>
          <button className="btn sm" onClick={() => void cancel()}>{t("cancel")}</button>
        </>
      )}
      {lost && job.status === "running" && <div className="muted small">{t("lostContact")}</div>}
      {job.error && <ErrorBox message={job.error} />}
      {job.warnings.length > 0 && (
        <ul className="warn">
          {job.warnings.map((w, i) => (
            <li key={i} dir="auto">{w}</li>
          ))}
        </ul>
      )}
      {job.status === "done" && assets.length > 0 && (
        <div className="grid">
          {assets.map((a) => (
            <AssetView key={a.id} asset={a} actions={actions?.(a)} />
          ))}
        </div>
      )}
    </div>
  );
}

export const ACCEPT = ".png,.jpg,.jpeg,.webp,.gif,.pdf,.docx,.xlsx,.pptx,.odt,.epub,.txt,.md,.csv,.json,.html,.mp4,.webm";

/** Upload button(s): files, and a camera/scan button that opens the phone camera. */
export function UploadButtons({ onUploaded, multiple = true, camera = true, images = false }: { onUploaded: (assets: Asset[]) => void; multiple?: boolean; camera?: boolean; images?: boolean }) {
  const { api, t, toast } = useApp();
  const [busy, setBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const camRef = useRef<HTMLInputElement>(null);

  const go = async (list: FileList | null) => {
    if (!list || list.length === 0) return;
    setBusy(true);
    try {
      const r = await api.upload([...list]);
      if (r.failed.length) toast(r.failed.map((f) => `${f.name}: ${f.error}`).join("\n"), "error");
      if (r.assets.length) onUploaded(r.assets);
    } catch (e) {
      toast(describeError(e), "error");
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
      if (camRef.current) camRef.current.value = "";
    }
  };

  return (
    <span className="row wrap">
      <input ref={fileRef} type="file" hidden multiple={multiple} accept={images ? "image/png,image/jpeg,image/webp,image/gif" : ACCEPT} onChange={(e) => void go(e.target.files)} />
      <button type="button" className="btn" disabled={busy} onClick={() => fileRef.current?.click()}>
        {busy ? t("uploading") : `📎 ${t("upload")}`}
      </button>
      {camera && (
        <>
          <input ref={camRef} type="file" hidden accept="image/*" capture="environment" onChange={(e) => void go(e.target.files)} />
          <button type="button" className="btn" disabled={busy} onClick={() => camRef.current?.click()} title={t("cameraHelp")}>
            📷 {t("camera")}
          </button>
        </>
      )}
    </span>
  );
}

/** Pick images from the library (and upload new ones). Selection order is kept. */
export function ImagePicker({ value, onChange, max, refreshKey = 0 }: { value: string[]; onChange: (ids: string[]) => void; max: number; refreshKey?: number }) {
  const { api, t, token } = useApp();
  const [items, setItems] = useState<Asset[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let alive = true;
    api
      .get<{ items: Asset[] }>("/api/files?kind=image&limit=60")
      .then((d) => alive && (setItems(d.items), setErr(null)))
      .catch((e) => alive && setErr(describeError(e)));
    return () => {
      alive = false;
    };
  }, [api, tick, refreshKey, token]);

  const toggle = (id: string) => {
    if (value.includes(id)) onChange(value.filter((v) => v !== id));
    else if (value.length < max) onChange([...value, id]);
  };

  return (
    <div className="picker">
      <div className="row between wrap">
        <span className="muted small">{t("selectedOf", { n: value.length, max })}</span>
        <UploadButtons
          images
          multiple
          onUploaded={(a) => {
            setTick((x) => x + 1);
            onChange([...value, ...a.filter((x) => x.kind === "image").map((x) => x.id)].slice(0, max));
          }}
        />
      </div>
      <ErrorBox message={err} />
      {items.length === 0 && !err && <p className="muted">{t("noImages")}</p>}
      <div className="pick-grid">
        {items.map((a) => (
          <PickTile key={a.id} asset={a} order={value.indexOf(a.id) + 1} onClick={() => toggle(a.id)} />
        ))}
      </div>
    </div>
  );
}

function PickTile({ asset, order, onClick }: { asset: Asset; order: number; onClick: () => void }) {
  const { url } = useBlobUrl(asset.id);
  return (
    <button type="button" className={`pick ${order ? "on" : ""}`} onClick={onClick} aria-pressed={order > 0} title={asset.name}>
      {url ? <img src={url} alt={asset.name} loading="lazy" /> : <span className="ph">…</span>}
      {order > 0 && <span className="badge">{order}</span>}
    </button>
  );
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small className="muted">{hint}</small>}
    </label>
  );
}
