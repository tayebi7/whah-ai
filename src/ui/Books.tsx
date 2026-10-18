"use client";

import { useEffect, useState } from "react";
import { describeError, type Job } from "./api";
import { useApp } from "./app";
import { ErrorBox, Field, JobCard } from "./common";

const FORMATS = ["docx", "pdf", "epub", "md"] as const;
type Health = { features: { bookExport: boolean; bookPdf: boolean } };

export default function Books() {
  const { t, api, lang, providers, go, token } = useApp();
  const [brief, setBrief] = useState("");
  const [title, setTitle] = useState("");
  const [language, setLanguage] = useState<"ar" | "en" | "fr">(lang);
  const [kind, setKind] = useState<"story" | "book" | "guide">("story");
  const [audience, setAudience] = useState("");
  const [chapters, setChapters] = useState(3);
  const [words, setWords] = useState(300);
  const [illustrate, setIllustrate] = useState(false);
  const [cover, setCover] = useState(false);
  const [style, setStyle] = useState("");
  const [formats, setFormats] = useState<string[]>(["docx", "pdf"]);
  const [pageSize, setPageSize] = useState<"A4" | "A5" | "Letter">("A4");
  const [starting, setStarting] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [jobs, setJobs] = useState<{ id: string; title?: string }[]>([]);
  const [health, setHealth] = useState<Health | null>(null);

  const chatOk = providers.some((p) => p.enabled && p.capabilities.chat);
  const imageOk = providers.some((p) => p.enabled && p.capabilities.image);

  useEffect(() => {
    let alive = true;
    api.get<Health>("/api/health").then((h) => alive && setHealth(h)).catch(() => undefined);
    api
      .get<{ jobs: Job[] }>("/api/jobs")
      .then((d) => alive && setJobs(d.jobs.filter((j) => j.kind === "book").slice(0, 5).map((j) => ({ id: j.id }))))
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [api, token]);

  async function start() {
    setStarting(true);
    setErr(null);
    try {
      const { job } = await api.post<{ job: Job }>("/api/studio/book", {
        brief: brief.trim(), title: title.trim(), language, kind, audience: audience.trim(), chapters, wordsPerChapter: words, illustrate, cover, style: style.trim(), formats, pageSize,
      });
      setJobs((j) => [{ id: job.id, title: title.trim() || brief.trim().slice(0, 60) }, ...j]);
    } catch (e) {
      setErr(describeError(e));
    } finally {
      setStarting(false);
    }
  }

  const toggleFormat = (f: string) => setFormats((x) => (x.includes(f) ? x.filter((y) => y !== f) : [...x, f]));
  const needsImages = (illustrate || cover) && !imageOk;

  return (
    <section className="page">
      <header className="page-head">
        <div>
          <h2>{t("booksTitle")}</h2>
          <p className="muted">{t("booksHelp")}</p>
        </div>
      </header>

      <div className="card form-grid">
        {!chatOk && (
          <div className="span-all warn-line">
            {t("noChatProvider")} <button className="btn sm" onClick={() => go("settings")}>{t("openSettings")}</button>
          </div>
        )}
        <div className="span-all">
          <Field label={t("bookBrief")} hint={t("bookBriefHint")}>
            <textarea rows={4} dir="auto" maxLength={4000} value={brief} onChange={(e) => setBrief(e.target.value)} />
          </Field>
        </div>
        <Field label={t("bookTitle")}><input dir="auto" maxLength={120} value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t("optional")} /></Field>
        <Field label={t("bookLang")}>
          <select value={language} onChange={(e) => setLanguage(e.target.value as "ar" | "en" | "fr")}>
            <option value="ar">العربية</option>
            <option value="en">English</option>
            <option value="fr">Français</option>
          </select>
        </Field>
        <Field label={t("bookKind")}>
          <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
            <option value="story">{t("kind_story")}</option>
            <option value="book">{t("kind_book")}</option>
            <option value="guide">{t("kind_guide")}</option>
          </select>
        </Field>
        <Field label={t("audience")}><input dir="auto" maxLength={120} value={audience} onChange={(e) => setAudience(e.target.value)} placeholder={t("optional")} /></Field>
        <Field label={t("chapters")}><input type="number" min={1} max={20} value={chapters} onChange={(e) => setChapters(Number(e.target.value))} /></Field>
        <Field label={t("wordsPerChapter")}><input type="number" min={50} max={1500} step={50} value={words} onChange={(e) => setWords(Number(e.target.value))} /></Field>
        <Field label={t("pageSize")}>
          <select value={pageSize} onChange={(e) => setPageSize(e.target.value as typeof pageSize)}>
            <option value="A4">A4</option>
            <option value="A5">A5</option>
            <option value="Letter">Letter</option>
          </select>
        </Field>
        <Field label={t("artStyle")}><input dir="auto" maxLength={200} value={style} onChange={(e) => setStyle(e.target.value)} placeholder={t("artStylePh")} /></Field>
        <div className="span-all row wrap">
          <label className="check"><input type="checkbox" checked={illustrate} onChange={(e) => setIllustrate(e.target.checked)} />{t("illustrate")}</label>
          <label className="check"><input type="checkbox" checked={cover} onChange={(e) => setCover(e.target.checked)} />{t("makeCover")}</label>
        </div>
        {needsImages && <div className="span-all warn-line">{t("noImageForBook")}</div>}
        <div className="span-all">
          <strong>{t("exportFormats")}</strong>
          <div className="row wrap">
            {FORMATS.map((f) => (
              <label key={f} className="check">
                <input type="checkbox" checked={formats.includes(f)} onChange={() => toggleFormat(f)} disabled={(f === "pdf" && health && !health.features.bookPdf) || (health && !health.features.bookExport) || false} />
                .{f}
              </label>
            ))}
          </div>
          {health && !health.features.bookPdf && <small className="muted">{t("noPdfTool")}</small>}
        </div>
        <div className="span-all"><ErrorBox message={err} /></div>
        <div className="span-all row end">
          <button className="btn primary" disabled={starting || !brief.trim() || formats.length === 0} onClick={() => void start()}>
            {starting ? t("starting") : `📖 ${t("writeBook")}`}
          </button>
        </div>
      </div>

      <h3>{t("bookJobs")}</h3>
      {jobs.length === 0 && <p className="muted">{t("noJobs")}</p>}
      {jobs.map((j) => (
        <JobCard key={j.id} id={j.id} title={j.title} />
      ))}
    </section>
  );
}
