"use client";

import { useEffect, useState } from "react";
import type { Connector, Skill } from "../lib/intent";
import { useApp } from "./app";
import { CONNECTOR_PRESETS, SKILL_PRESETS, loadConnectors, loadSkills, saveConnectors, saveSkills, uid } from "./extras";
import { Field } from "./common";

export function Skills() {
  const { t } = useApp();
  const [items, setItems] = useState<Skill[]>([]);
  const [draft, setDraft] = useState({ name: "", instruction: "", keywords: "" });
  useEffect(() => setItems(loadSkills()), []);
  const commit = (n: Skill[]) => { setItems(n); saveSkills(n); };
  const add = (d: { name: string; instruction: string; keywords: string }) => {
    if (!d.name.trim() || !d.instruction.trim()) return;
    commit([...items, { id: uid(), name: d.name.trim().slice(0, 60), instruction: d.instruction.trim().slice(0, 1500), keywords: d.keywords.trim().slice(0, 300), enabled: true }]);
    setDraft({ name: "", instruction: "", keywords: "" });
  };
  return (
    <section className="page" data-testid="skills">
      <header className="page-head"><div><h2>{t("tab_skills")}</h2><p className="muted">{t("sk_help")}</p></div></header>
      <div className="card stack">
        <Field label={t("sk_name")}><input value={draft.name} maxLength={60} onChange={(e) => setDraft({ ...draft, name: e.target.value })} data-testid="sk-name" /></Field>
        <Field label={t("sk_instr")}><textarea rows={3} value={draft.instruction} maxLength={1500} onChange={(e) => setDraft({ ...draft, instruction: e.target.value })} data-testid="sk-instr" /></Field>
        <Field label={t("sk_kw")} hint={t("sk_kwHint")}><input value={draft.keywords} onChange={(e) => setDraft({ ...draft, keywords: e.target.value })} data-testid="sk-kw" /></Field>
        <div className="row"><button className="btn primary" disabled={!draft.name.trim() || !draft.instruction.trim()} onClick={() => add(draft)} data-testid="sk-add">{t("add")}</button></div>
        <div className="chips">{SKILL_PRESETS.map((p) => <button key={p.name} className="btn sm" onClick={() => add(p)}>＋ {p.name}</button>)}</div>
      </div>
      {items.length === 0 && <div className="card empty-card">{t("sk_empty")}</div>}
      {items.map((s) => (
        <div key={s.id} className={`card ${s.enabled ? "" : "off"}`}>
          <div className="row between"><strong>{s.name}</strong>
            <span className="row">
              <label className="check"><input type="checkbox" checked={s.enabled} onChange={(e) => commit(items.map((x) => (x.id === s.id ? { ...x, enabled: e.target.checked } : x)))} />{t("enabled")}</label>
              <button className="btn sm danger-outline" onClick={() => commit(items.filter((x) => x.id !== s.id))}>{t("delete")}</button>
            </span></div>
          <p className="small" dir="auto">{s.instruction}</p>
          <div className="muted small">{s.keywords ? `${t("sk_kw")}: ${s.keywords}` : t("sk_noKw")}</div>
        </div>
      ))}
    </section>
  );
}

export function Connectors() {
  const { t } = useApp();
  const [items, setItems] = useState<Connector[]>([]);
  const [draft, setDraft] = useState({ name: "", urlTemplate: "", headers: "", keywords: "" });
  const [err, setErr] = useState("");
  useEffect(() => setItems(loadConnectors()), []);
  const commit = (n: Connector[]) => { setItems(n); saveConnectors(n); };
  const add = (d: { name: string; urlTemplate: string; headers: string; keywords: string }) => {
    setErr("");
    if (!d.name.trim() || !/^https:\/\//i.test(d.urlTemplate.trim())) return setErr(t("cn_badUrl"));
    if (d.headers.trim()) {
      try { const h = JSON.parse(d.headers); if (!h || typeof h !== "object" || Array.isArray(h)) throw new Error(); } catch { return setErr(t("cn_badHeaders")); }
    }
    if (!d.keywords.trim()) return setErr(t("cn_needKw"));
    commit([...items, { id: uid(), name: d.name.trim().slice(0, 60), urlTemplate: d.urlTemplate.trim(), headers: d.headers.trim(), keywords: d.keywords.trim(), enabled: true }]);
    setDraft({ name: "", urlTemplate: "", headers: "", keywords: "" });
  };
  return (
    <section className="page" data-testid="connectors">
      <header className="page-head"><div><h2>{t("tab_connectors")}</h2><p className="muted">{t("cn_help")}</p></div></header>
      <div className="card stack">
        <Field label={t("sk_name")}><input value={draft.name} maxLength={60} onChange={(e) => setDraft({ ...draft, name: e.target.value })} data-testid="cn-name" /></Field>
        <Field label={t("cn_url")} hint={t("cn_urlHint")}><input value={draft.urlTemplate} dir="ltr" placeholder="https://api.example.com/search?q={query}" onChange={(e) => setDraft({ ...draft, urlTemplate: e.target.value })} data-testid="cn-url" /></Field>
        <Field label={t("cn_headers")} hint={t("cn_headersHint")}><input value={draft.headers} dir="ltr" placeholder='{"Authorization":"Bearer …"}' onChange={(e) => setDraft({ ...draft, headers: e.target.value })} /></Field>
        <Field label={t("sk_kw")} hint={t("cn_kwHint")}><input value={draft.keywords} onChange={(e) => setDraft({ ...draft, keywords: e.target.value })} data-testid="cn-kw" /></Field>
        {err && <div className="error" role="alert">{err}</div>}
        <div className="row"><button className="btn primary" onClick={() => add(draft)} data-testid="cn-add">{t("add")}</button></div>
        <div className="chips">{CONNECTOR_PRESETS.map((p) => <button key={p.name} className="btn sm" onClick={() => add(p)}>＋ {p.name}</button>)}</div>
        <small className="muted">{t("cn_note")}</small>
      </div>
      {items.length === 0 && <div className="card empty-card">{t("cn_empty")}</div>}
      {items.map((c) => (
        <div key={c.id} className={`card ${c.enabled ? "" : "off"}`}>
          <div className="row between"><strong>{c.name}</strong>
            <span className="row">
              <label className="check"><input type="checkbox" checked={c.enabled} onChange={(e) => commit(items.map((x) => (x.id === c.id ? { ...x, enabled: e.target.checked } : x)))} />{t("enabled")}</label>
              <button className="btn sm danger-outline" onClick={() => commit(items.filter((x) => x.id !== c.id))}>{t("delete")}</button>
            </span></div>
          <div className="kv" dir="ltr">{c.urlTemplate}</div>
          <div className="muted small">{t("sk_kw")}: {c.keywords}</div>
        </div>
      ))}
    </section>
  );
}
