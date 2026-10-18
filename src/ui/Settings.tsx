"use client";

import { useState } from "react";
import { PRESETS } from "../lib/presets";
import { describeError, type PubProvider } from "./api";
import { useApp } from "./app";
import { ErrorBox, Field, Modal } from "./common";

type Form = {
  editingId: string | null;
  id: string;
  preset: string;
  name: string;
  protocol: "openai" | "anthropic" | "gemini";
  baseUrl: string;
  apiKey: string;
  clearKey: boolean;
  model: string;
  imageModel: string;
  videoModel: string;
  supportsVision: boolean;
  noAttachments: boolean;
  enabled: boolean;
  priority: string;
  timeoutMs: string;
  maxRetries: string;
  orgId: string;
  headers: string;
  v: { submitPath: string; statusPath: string; idField: string; statusField: string; urlField: string; doneValues: string; failValues: string; pollMs: string; maxPolls: string };
};

const emptyV = { submitPath: "", statusPath: "", idField: "", statusField: "", urlField: "", doneValues: "", failValues: "", pollMs: "", maxPolls: "" };
const blank = (): Form => ({
  editingId: null, id: "", preset: "custom", name: "", protocol: "openai", baseUrl: "", apiKey: "", clearKey: false, model: "", imageModel: "", videoModel: "",
  supportsVision: false, noAttachments: false, enabled: true, priority: "", timeoutMs: "", maxRetries: "", orgId: "", headers: "", v: { ...emptyV },
});

function fromProvider(p: PubProvider, copy: boolean): Form {
  const v = p.videoApi;
  return {
    editingId: copy ? null : p.id, id: copy ? "" : p.id, preset: "custom", name: copy ? `${p.name} (copy)` : p.name, protocol: p.protocol ?? "openai", baseUrl: p.baseUrl, apiKey: "", clearKey: false,
    model: p.model, imageModel: p.imageModel, videoModel: p.videoModel, supportsVision: p.supportsVision, noAttachments: p.noAttachments, enabled: p.enabled,
    priority: String(p.priority), timeoutMs: String(p.timeoutMs), maxRetries: String(p.maxRetries), orgId: p.orgId ?? "", headers: "",
    v: v ? { submitPath: v.submitPath, statusPath: v.statusPath, idField: v.idField, statusField: v.statusField, urlField: v.urlField, doneValues: v.doneValues.join(", "), failValues: v.failValues.join(", "), pollMs: String(v.pollMs), maxPolls: String(v.maxPolls) } : { ...emptyV },
  };
}

const list = (s: string) => s.split(",").map((x) => x.trim().toLowerCase()).filter(Boolean);

/** Builds the API payload; throws a readable Error for input the server could not interpret at all. */
function toPayload(f: Form): Record<string, unknown> {
  const body: Record<string, unknown> = {
    name: f.name.trim(), protocol: f.protocol, baseUrl: f.baseUrl.trim(), model: f.model.trim(), imageModel: f.imageModel.trim(), videoModel: f.videoModel.trim(),
    supportsVision: f.supportsVision, noAttachments: f.noAttachments, enabled: f.enabled, orgId: f.orgId.trim(),
  };
  if (!f.editingId && f.id.trim()) body.id = f.id.trim();
  for (const k of ["priority", "timeoutMs", "maxRetries"] as const) if (f[k].trim() !== "") body[k] = Number(f[k]);
  if (f.apiKey.trim()) body.apiKey = f.apiKey.trim();
  if (f.clearKey) body.clearKey = true;
  if (f.headers.trim()) {
    let h: unknown;
    try {
      h = JSON.parse(f.headers);
    } catch {
      throw new Error('Custom headers must be valid JSON, for example {"X-Org": "abc"}');
    }
    body.headers = h;
  }
  if (f.videoModel.trim()) {
    const v: Record<string, unknown> = {};
    for (const k of ["submitPath", "statusPath", "idField", "statusField", "urlField"] as const) if (f.v[k].trim()) v[k] = f.v[k].trim();
    if (f.v.doneValues.trim()) v.doneValues = list(f.v.doneValues);
    if (f.v.failValues.trim()) v.failValues = list(f.v.failValues);
    for (const k of ["pollMs", "maxPolls"] as const) if (f.v[k].trim()) v[k] = Number(f.v[k]);
    body.videoApi = v;
  }
  return body;
}

type TestResult = { ok: boolean; steps: { name: string; ok: boolean; detail: string }[] };

export default function Settings() {
  const { t, api, providers, providersLoaded, refreshProviders, toast, token, setToken } = useApp();
  const [form, setForm] = useState<Form | null>(null);
  const [saving, setSaving] = useState(false);
  const [formErr, setFormErr] = useState<string | null>(null);
  const [models, setModels] = useState<string[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const [tests, setTests] = useState<Record<string, TestResult | "running">>({});
  const [confirmDel, setConfirmDel] = useState<PubProvider | null>(null);

  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => (f ? { ...f, [k]: v } : f));
  const stored = providers.filter((p) => p.source !== "env");

  function applyPreset(key: string) {
    const p = PRESETS.find((x) => x.key === key);
    setForm((f) => (f ? { ...f, preset: key, baseUrl: p?.baseUrl ?? f.baseUrl, protocol: p?.protocol ?? f.protocol, name: f.name || (p && p.key !== "custom" ? p.name : f.name) } : f));
  }

  async function save() {
    if (!form) return;
    setSaving(true);
    setFormErr(null);
    try {
      const body = toPayload(form);
      if (form.editingId) await api.put(`/api/providers/${form.editingId}`, body);
      else await api.post("/api/providers", body);
      await refreshProviders();
      toast(t("saved"));
      setForm(null);
    } catch (e) {
      setFormErr(describeError(e));
    } finally {
      setSaving(false);
    }
  }

  async function fetchModels() {
    if (!form?.editingId) return;
    setLoadingModels(true);
    setFormErr(null);
    try {
      const d = await api.get<{ models: string[] }>(`/api/providers/${form.editingId}/models`);
      setModels(d.models);
      toast(t("modelsFound", { n: d.models.length }));
    } catch (e) {
      setFormErr(describeError(e));
    } finally {
      setLoadingModels(false);
    }
  }

  async function runTest(id: string) {
    setTests((x) => ({ ...x, [id]: "running" }));
    try {
      const r = await api.post<TestResult>(`/api/providers/${id}/test`, { chat: true });
      setTests((x) => ({ ...x, [id]: r }));
    } catch (e) {
      setTests((x) => ({ ...x, [id]: { ok: false, steps: [{ name: "test", ok: false, detail: describeError(e) }] } }));
    }
  }

  async function toggle(p: PubProvider) {
    try {
      await api.put(`/api/providers/${p.id}`, { enabled: !p.enabled });
      await refreshProviders();
    } catch (e) {
      toast(describeError(e), "error");
    }
  }

  async function move(id: string, dir: -1 | 1) {
    const ids = stored.map((p) => p.id);
    const i = ids.indexOf(id);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    try {
      await api.post("/api/providers/reorder", { ids });
      await refreshProviders();
    } catch (e) {
      toast(describeError(e), "error");
    }
  }

  async function remove(p: PubProvider) {
    try {
      await api.del(`/api/providers/${p.id}`);
      await refreshProviders();
      toast(t("deleted"));
    } catch (e) {
      toast(describeError(e), "error");
    } finally {
      setConfirmDel(null);
    }
  }

  const caps = (p: PubProvider) =>
    [p.capabilities.chat && "chat", p.capabilities.vision && "vision", p.capabilities.image && "image", p.capabilities.video && "video"].filter(Boolean) as string[];

  return (
    <section className="page">
      <header className="page-head">
        <div>
          <h2>{t("providersTitle")}</h2>
          <p className="muted">{t("providersHelp")}</p>
        </div>
        <button className="btn primary" onClick={() => { setForm(blank()); setModels([]); setFormErr(null); }}>+ {t("addProvider")}</button>
      </header>

      <div className="card">
        <Field label={t("token")} hint={t("tokenHelp")}>
          <input type="password" value={token} onChange={(e) => setToken(e.target.value)} autoComplete="off" spellCheck={false} />
        </Field>
      </div>

      {providersLoaded && providers.length === 0 && <div className="card empty-card"><p>{t("noProviders")}</p></div>}

      <div className="stack">
        {providers.map((p, idx) => {
          const test = tests[p.id];
          const isStored = p.source !== "env";
          const si = stored.findIndex((x) => x.id === p.id);
          return (
            <article key={p.id} className={`card provider ${p.enabled ? "" : "off"}`}>
              <div className="row between wrap">
                <div>
                  <strong dir="auto">{p.name}</strong>{" "}
                  <span className="muted small">#{idx + 1} · {p.id}</span>
                  {!isStored && <span className="chip">{t("fromEnv")}</span>}
                </div>
                <div className="chips">
                  {caps(p).map((c) => (
                    <span key={c} className={`chip cap-${c}`}>{t(`cap_${c}`)}</span>
                  ))}
                </div>
              </div>
              <div className="kv" dir="ltr">
                <span>{p.baseUrl}</span>
                <span>{[p.model && `💬 ${p.model}`, p.imageModel && `🖼 ${p.imageModel}`, p.videoModel && `🎬 ${p.videoModel}`].filter(Boolean).join("  ")}</span>
                <span>{p.hasKey ? `🔑 ${p.keyHint}` : `🔓 ${t("noKey")}`}{p.keyUnreadable ? ` — ${t("keyUnreadable")}` : ""}</span>
              </div>
              <div className="row wrap">
                <button className="btn sm" onClick={() => void runTest(p.id)} disabled={test === "running"}>{test === "running" ? t("testing") : t("test")}</button>
                {isStored ? (
                  <>
                    <button className="btn sm" onClick={() => { setForm(fromProvider(p, false)); setModels([]); setFormErr(null); }}>{t("edit")}</button>
                    <button className="btn sm" onClick={() => void toggle(p)}>{p.enabled ? t("disable") : t("enable")}</button>
                    <button className="btn sm" aria-label={t("moveUp")} disabled={si <= 0} onClick={() => void move(p.id, -1)}>↑</button>
                    <button className="btn sm" aria-label={t("moveDown")} disabled={si < 0 || si >= stored.length - 1} onClick={() => void move(p.id, 1)}>↓</button>
                    <button className="btn sm danger-outline" onClick={() => setConfirmDel(p)}>{t("delete")}</button>
                  </>
                ) : (
                  <button className="btn sm" onClick={() => { setForm(fromProvider(p, true)); setModels([]); setFormErr(null); }}>{t("duplicate")}</button>
                )}
              </div>
              {test && test !== "running" && (
                <ul className={`test ${test.ok ? "ok" : "bad"}`}>
                  {test.steps.map((s, i) => (
                    <li key={i}>
                      <span>{s.ok ? "✓" : "✗"}</span> <strong>{s.name}</strong>: <span dir="auto">{s.detail}</span>
                    </li>
                  ))}
                </ul>
              )}
            </article>
          );
        })}
      </div>

      <p className="muted small">{t("testNote")}</p>

      {form && (
        <Modal title={form.editingId ? t("editProvider") : t("addProvider")} onClose={() => setForm(null)} wide>
          <form className="form-grid" onSubmit={(e) => { e.preventDefault(); void save(); }}>
            {!form.editingId && (
              <Field label={t("fPreset")}>
                <select value={form.preset} onChange={(e) => applyPreset(e.target.value)}>
                  {PRESETS.map((p) => (
                    <option key={p.key} value={p.key}>{p.name}</option>
                  ))}
                </select>
              </Field>
            )}
            <Field label={t("fName")}>
              <input required value={form.name} onChange={(e) => set("name", e.target.value)} dir="auto" maxLength={80} />
            </Field>
            {!form.editingId && (
              <Field label={t("fId")} hint={t("fIdHint")}>
                <input value={form.id} onChange={(e) => set("id", e.target.value.toLowerCase())} pattern="[a-z0-9\-]{1,40}" dir="ltr" />
              </Field>
            )}
            <Field label={t("fProtocol")}>
              <select value={form.protocol} onChange={(e) => set("protocol", e.target.value as Form["protocol"])}>
                <option value="openai">OpenAI-compatible</option>
                <option value="anthropic">Anthropic</option>
                <option value="gemini">Google Gemini</option>
              </select>
            </Field>
            <Field label={t("fBase")}>
              <input required value={form.baseUrl} onChange={(e) => set("baseUrl", e.target.value)} placeholder="https://api.example.com/v1" dir="ltr" inputMode="url" />
            </Field>
            <Field label={t("fKey")} hint={form.editingId ? t("fKeyKeep") : undefined}>
              <input type="password" value={form.apiKey} onChange={(e) => set("apiKey", e.target.value)} autoComplete="new-password" spellCheck={false} dir="ltr" />
            </Field>
            {form.editingId && (
              <label className="check">
                <input type="checkbox" checked={form.clearKey} onChange={(e) => set("clearKey", e.target.checked)} />
                {t("clearKey")}
              </label>
            )}

            <div className="span-all row between wrap">
              <strong>{t("fModels")}</strong>
              <button type="button" className="btn sm" disabled={!form.editingId || loadingModels} onClick={() => void fetchModels()} title={form.editingId ? "" : t("fetchAfterSave")}>
                {loadingModels ? t("loading") : t("fetchModels")}
              </button>
            </div>
            <datalist id="model-options">{models.map((m) => <option key={m} value={m} />)}</datalist>
            <Field label={`💬 ${t("fModel")}`}>
              <input list="model-options" value={form.model} onChange={(e) => set("model", e.target.value)} dir="ltr" placeholder="gpt-4o-mini" />
            </Field>
            <Field label={`🖼 ${t("fImageModel")}`}>
              <input list="model-options" value={form.imageModel} onChange={(e) => set("imageModel", e.target.value)} dir="ltr" placeholder="gpt-image-1" />
            </Field>
            <Field label={`🎬 ${t("fVideoModel")}`}>
              <input list="model-options" value={form.videoModel} onChange={(e) => set("videoModel", e.target.value)} dir="ltr" />
            </Field>
            <div className="span-all row wrap">
              <label className="check"><input type="checkbox" checked={form.supportsVision} onChange={(e) => set("supportsVision", e.target.checked)} />{t("fVision")}</label>
              <label className="check"><input type="checkbox" checked={form.noAttachments} onChange={(e) => set("noAttachments", e.target.checked)} />{t("fNoAttach")}</label>
              <label className="check"><input type="checkbox" checked={form.enabled} onChange={(e) => set("enabled", e.target.checked)} />{t("fEnabled")}</label>
            </div>

            {form.videoModel.trim() && (
              <fieldset className="span-all form-grid">
                <legend>{t("videoApiTitle")}</legend>
                <p className="muted small span-all">{t("videoApiHelp")}</p>
                <Field label={t("vSubmit")}><input dir="ltr" value={form.v.submitPath} onChange={(e) => set("v", { ...form.v, submitPath: e.target.value })} placeholder="/videos" /></Field>
                <Field label={t("vStatus")}><input dir="ltr" value={form.v.statusPath} onChange={(e) => set("v", { ...form.v, statusPath: e.target.value })} placeholder="/videos/{id}" /></Field>
                <Field label={t("vId")}><input dir="ltr" value={form.v.idField} onChange={(e) => set("v", { ...form.v, idField: e.target.value })} placeholder="id" /></Field>
                <Field label={t("vState")}><input dir="ltr" value={form.v.statusField} onChange={(e) => set("v", { ...form.v, statusField: e.target.value })} placeholder="status" /></Field>
                <Field label={t("vUrl")}><input dir="ltr" value={form.v.urlField} onChange={(e) => set("v", { ...form.v, urlField: e.target.value })} placeholder="video_url" /></Field>
                <Field label={t("vDone")}><input dir="ltr" value={form.v.doneValues} onChange={(e) => set("v", { ...form.v, doneValues: e.target.value })} placeholder="completed, succeeded" /></Field>
                <Field label={t("vFail")}><input dir="ltr" value={form.v.failValues} onChange={(e) => set("v", { ...form.v, failValues: e.target.value })} placeholder="failed, error" /></Field>
                <Field label={t("vPoll")}><input type="number" min={500} value={form.v.pollMs} onChange={(e) => set("v", { ...form.v, pollMs: e.target.value })} placeholder="5000" /></Field>
                <Field label={t("vMaxPolls")}><input type="number" min={1} value={form.v.maxPolls} onChange={(e) => set("v", { ...form.v, maxPolls: e.target.value })} placeholder="120" /></Field>
              </fieldset>
            )}

            <details className="span-all">
              <summary>{t("advanced")}</summary>
              <div className="form-grid">
                <Field label={t("fPriority")}><input type="number" min={0} value={form.priority} onChange={(e) => set("priority", e.target.value)} placeholder="100" /></Field>
                <Field label={t("fTimeout")}><input type="number" min={1000} value={form.timeoutMs} onChange={(e) => set("timeoutMs", e.target.value)} placeholder="30000" /></Field>
                <Field label={t("fRetries")}><input type="number" min={0} max={5} value={form.maxRetries} onChange={(e) => set("maxRetries", e.target.value)} placeholder="2" /></Field>
                <Field label={t("fOrg")}><input dir="ltr" value={form.orgId} onChange={(e) => set("orgId", e.target.value)} /></Field>
                <Field label={t("fHeaders")} hint={form.editingId ? t("fHeadersKeep") : undefined}>
                  <textarea dir="ltr" rows={3} value={form.headers} onChange={(e) => set("headers", e.target.value)} placeholder='{"X-Custom": "value"}' spellCheck={false} />
                </Field>
              </div>
            </details>

            <div className="span-all"><ErrorBox message={formErr} /></div>
            <div className="span-all row end">
              <button type="button" className="btn" onClick={() => setForm(null)}>{t("cancel")}</button>
              <button type="submit" className="btn primary" disabled={saving}>{saving ? t("saving") : t("save")}</button>
            </div>
          </form>
        </Modal>
      )}

      {confirmDel && (
        <Modal title={t("confirmDelete")} onClose={() => setConfirmDel(null)}>
          <p dir="auto">{t("confirmDeleteText", { name: confirmDel.name })}</p>
          <div className="row end">
            <button className="btn" onClick={() => setConfirmDel(null)}>{t("cancel")}</button>
            <button className="btn danger" onClick={() => void remove(confirmDel)}>{t("delete")}</button>
          </div>
        </Modal>
      )}
    </section>
  );
}

