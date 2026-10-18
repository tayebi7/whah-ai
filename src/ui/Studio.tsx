"use client";

import { useEffect, useState } from "react";
import { describeError, type Asset, type Job } from "./api";
import { useApp } from "./app";
import { AssetView, ErrorBox, Field, ImagePicker, JobCard } from "./common";

type Mode = "provider" | "slideshow" | "product";
type Aspect = "16:9" | "9:16" | "1:1";
type Health = { features: { slideshowVideo: boolean } };

const SIZES = ["1024x1024", "1536x1024", "1024x1536", "auto"];

function AspectSelect({ value, onChange }: { value: Aspect; onChange: (a: Aspect) => void }) {
  const { t } = useApp();
  return (
    <Field label={t("aspect")}>
      <select value={value} onChange={(e) => onChange(e.target.value as Aspect)}>
        <option value="16:9">16:9 — {t("landscape")}</option>
        <option value="9:16">9:16 — {t("portrait")}</option>
        <option value="1:1">1:1 — {t("square")}</option>
      </select>
    </Field>
  );
}

export default function Studio() {
  const { t, api, providers, go, toast, token } = useApp();
  const [tab, setTab] = useState<"image" | "video">("image");
  const imageProviders = providers.filter((p) => p.enabled && p.capabilities.image);
  const videoProviders = providers.filter((p) => p.enabled && p.capabilities.video);

  // ---- image
  const [prompt, setPrompt] = useState("");
  const [size, setSize] = useState("1024x1024");
  const [count, setCount] = useState(1);
  const [imgProvider, setImgProvider] = useState("");
  const [fallback, setFallback] = useState(true);
  const [making, setMaking] = useState(false);
  const [imgErr, setImgErr] = useState<string | null>(null);
  const [results, setResults] = useState<{ assets: Asset[]; provider: string; attempts: { providerId: string }[] } | null>(null);
  const [pickRefresh, setPickRefresh] = useState(0);

  // ---- video
  const [mode, setMode] = useState<Mode>("slideshow");
  const [vPrompt, setVPrompt] = useState("");
  const [seconds, setSeconds] = useState(5);
  const [aspect, setAspect] = useState<Aspect>("16:9");
  const [vProvider, setVProvider] = useState("");
  const [refImage, setRefImage] = useState<string[]>([]);
  const [slides, setSlides] = useState<string[]>([]);
  const [captions, setCaptions] = useState<Record<string, string>>({});
  const [perSlide, setPerSlide] = useState(3);
  const [kenBurns, setKenBurns] = useState(true);
  const [pName, setPName] = useState("");
  const [pDesc, setPDesc] = useState("");
  const [pLang, setPLang] = useState<"ar" | "en" | "fr">("ar");
  const [pPhotos, setPPhotos] = useState<string[]>([]);
  const [pGen, setPGen] = useState(0);
  const [starting, setStarting] = useState(false);
  const [vErr, setVErr] = useState<string | null>(null);
  const [jobs, setJobs] = useState<{ id: string; title?: string }[]>([]);
  const [ffmpeg, setFfmpeg] = useState(true);

  useEffect(() => {
    let alive = true;
    api.get<Health>("/api/health").then((h) => alive && setFfmpeg(h.features.slideshowVideo)).catch(() => undefined);
    api
      .get<{ jobs: Job[] }>("/api/jobs")
      .then((d) => alive && setJobs(d.jobs.filter((j) => j.kind === "video" || j.kind === "product-video").slice(0, 6).map((j) => ({ id: j.id }))))
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [api, token]);

  async function makeImages() {
    if (!prompt.trim()) return;
    setMaking(true);
    setImgErr(null);
    try {
      const r = await api.post<{ assets: Asset[]; provider: { name: string; model: string }; attempts: { providerId: string }[] }>("/api/studio/image", {
        prompt: prompt.trim(), n: count, size, providerId: imgProvider || undefined, autoFallback: fallback,
      });
      setResults({ assets: r.assets, provider: `${r.provider.name} · ${r.provider.model}`, attempts: r.attempts });
      setPickRefresh((x) => x + 1);
    } catch (e) {
      setImgErr(describeError(e));
    } finally {
      setMaking(false);
    }
  }

  function useInVideo(a: Asset) {
    setTab("video");
    setMode("slideshow");
    setSlides((s) => (s.includes(a.id) || s.length >= 12 ? s : [...s, a.id]));
    toast(t("addedToVideo"));
  }

  async function startVideo() {
    setStarting(true);
    setVErr(null);
    try {
      let body: Record<string, unknown>;
      let title: string;
      if (mode === "slideshow") {
        if (slides.length === 0) throw new Error(t("pickImagesFirst"));
        body = { mode, aspect, secondsPerSlide: perSlide, kenBurns, slides: slides.map((id) => ({ assetId: id, caption: captions[id]?.trim() || undefined })) };
        title = t("slideshowVideo");
      } else if (mode === "product") {
        if (!pName.trim()) throw new Error(t("productNameRequired"));
        body = { mode, productName: pName.trim(), description: pDesc.trim(), language: pLang, photoAssetIds: pPhotos, generateImages: pGen, aspect, secondsPerSlide: perSlide };
        title = pName.trim();
      } else {
        if (!vPrompt.trim()) throw new Error(t("promptRequired"));
        body = { mode, prompt: vPrompt.trim(), seconds, aspect, providerId: vProvider || undefined, imageAssetId: refImage[0] };
        title = vPrompt.trim().slice(0, 60);
      }
      const { job } = await api.post<{ job: Job }>("/api/studio/video", body);
      setJobs((j) => [{ id: job.id, title }, ...j]);
    } catch (e) {
      setVErr(describeError(e));
    } finally {
      setStarting(false);
    }
  }

  return (
    <section className="page">
      <header className="page-head">
        <div>
          <h2>{t("studioTitle")}</h2>
          <p className="muted">{t("studioHelp")}</p>
        </div>
      </header>
      <div className="seg" role="tablist">
        {(["image", "video"] as const).map((k) => (
          <button key={k} role="tab" aria-selected={tab === k} className={tab === k ? "on" : ""} onClick={() => setTab(k)}>
            {k === "image" ? `🖼 ${t("imageTab")}` : `🎬 ${t("videoTab")}`}
          </button>
        ))}
      </div>

      {tab === "image" && (
        <div className="stack">
          <div className="card form-grid">
            {imageProviders.length === 0 && (
              <div className="span-all warn-line">
                {t("noImageProvider")} <button className="btn sm" onClick={() => go("settings")}>{t("openSettings")}</button>
              </div>
            )}
            <div className="span-all">
              <Field label={t("prompt")}>
                <textarea rows={3} dir="auto" value={prompt} maxLength={4000} onChange={(e) => setPrompt(e.target.value)} placeholder={t("imagePromptPh")} />
              </Field>
            </div>
            <Field label={t("size")}>
              <select value={size} onChange={(e) => setSize(e.target.value)}>
                {SIZES.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("count")}>
              <select value={count} onChange={(e) => setCount(Number(e.target.value))}>
                {[1, 2, 3, 4].map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </Field>
            <Field label={t("provider")}>
              <select value={imgProvider} onChange={(e) => setImgProvider(e.target.value)}>
                <option value="">{t("auto")}</option>
                {imageProviders.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.imageModel}</option>)}
              </select>
            </Field>
            <label className="check"><input type="checkbox" checked={fallback} onChange={(e) => setFallback(e.target.checked)} />{t("fallback")}</label>
            <div className="span-all row end">
              <button className="btn primary" disabled={making || !prompt.trim()} onClick={() => void makeImages()}>{making ? t("generating") : `✨ ${t("generate")}`}</button>
            </div>
          </div>
          <ErrorBox message={imgErr} onRetry={() => void makeImages()} />
          {results && (
            <div className="card">
              <p className="muted small">{t("madeBy")}: {results.provider}{results.attempts.length ? ` — ${t("switched")} ${results.attempts.map((a) => a.providerId).join(", ")}` : ""}</p>
              <div className="grid">
                {results.assets.map((a) => (
                  <AssetView key={a.id} asset={a} actions={<button className="btn sm" onClick={() => useInVideo(a)}>🎬 {t("useInVideo")}</button>} />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {tab === "video" && (
        <div className="stack">
          <div className="seg small" role="tablist">
            {(["slideshow", "product", "provider"] as const).map((m) => (
              <button key={m} role="tab" aria-selected={mode === m} className={mode === m ? "on" : ""} onClick={() => setMode(m)}>
                {t(`mode_${m}`)}
              </button>
            ))}
          </div>
          <p className="muted small">{t(`modeHelp_${mode}`)}</p>
          {!ffmpeg && mode !== "provider" && <div className="warn-line">{t("noFfmpeg")}</div>}

          <div className="card form-grid">
            {mode === "provider" && (
              <>
                {videoProviders.length === 0 && (
                  <div className="span-all warn-line">
                    {t("noVideoProvider")} <button className="btn sm" onClick={() => go("settings")}>{t("openSettings")}</button>
                  </div>
                )}
                <div className="span-all">
                  <Field label={t("prompt")}>
                    <textarea rows={3} dir="auto" value={vPrompt} maxLength={4000} onChange={(e) => setVPrompt(e.target.value)} />
                  </Field>
                </div>
                <Field label={t("seconds")}>
                  <input type="number" min={1} max={60} value={seconds} onChange={(e) => setSeconds(Number(e.target.value))} />
                </Field>
                <AspectSelect value={aspect} onChange={setAspect} />
                <Field label={t("provider")}>
                  <select value={vProvider} onChange={(e) => setVProvider(e.target.value)}>
                    <option value="">{t("auto")}</option>
                    {videoProviders.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.videoModel}</option>)}
                  </select>
                </Field>
                <div className="span-all">
                  <strong>{t("refImage")}</strong>
                  <ImagePicker value={refImage} onChange={setRefImage} max={1} refreshKey={pickRefresh} />
                </div>
                <p className="muted small span-all">{t("providerVideoCost")}</p>
              </>
            )}

            {mode === "slideshow" && (
              <>
                <div className="span-all">
                  <strong>{t("slides")}</strong>
                  <ImagePicker value={slides} onChange={setSlides} max={12} refreshKey={pickRefresh} />
                </div>
                {slides.length > 0 && (
                  <div className="span-all stack">
                    <strong>{t("captions")}</strong>
                    {slides.map((id, i) => (
                      <label key={id} className="inline">
                        <span className="muted">{i + 1}</span>
                        <input dir="auto" maxLength={200} value={captions[id] ?? ""} onChange={(e) => setCaptions({ ...captions, [id]: e.target.value })} placeholder={t("captionPh")} />
                      </label>
                    ))}
                  </div>
                )}
                <AspectSelect value={aspect} onChange={setAspect} />
                <Field label={t("secondsPerSlide")}>
                  <input type="number" min={1} max={10} value={perSlide} onChange={(e) => setPerSlide(Number(e.target.value))} />
                </Field>
                <label className="check"><input type="checkbox" checked={kenBurns} onChange={(e) => setKenBurns(e.target.checked)} />{t("kenBurns")}</label>
              </>
            )}

            {mode === "product" && (
              <>
                <Field label={t("productName")}>
                  <input dir="auto" value={pName} maxLength={120} onChange={(e) => setPName(e.target.value)} />
                </Field>
                <Field label={t("captionLang")}>
                  <select value={pLang} onChange={(e) => setPLang(e.target.value as "ar" | "en" | "fr")}>
                    <option value="ar">العربية</option>
                    <option value="en">English</option>
                    <option value="fr">Français</option>
                  </select>
                </Field>
                <div className="span-all">
                  <Field label={t("productDesc")}>
                    <textarea rows={3} dir="auto" maxLength={2000} value={pDesc} onChange={(e) => setPDesc(e.target.value)} />
                  </Field>
                </div>
                <div className="span-all">
                  <strong>{t("productPhotos")}</strong>
                  <ImagePicker value={pPhotos} onChange={setPPhotos} max={10} refreshKey={pickRefresh} />
                </div>
                <Field label={t("genImages")} hint={t("genImagesHint")}>
                  <select value={pGen} onChange={(e) => setPGen(Number(e.target.value))}>
                    {[0, 1, 2, 3, 4].map((n) => <option key={n} value={n}>{n}</option>)}
                  </select>
                </Field>
                <AspectSelect value={aspect} onChange={setAspect} />
                <Field label={t("secondsPerSlide")}>
                  <input type="number" min={1} max={10} value={perSlide} onChange={(e) => setPerSlide(Number(e.target.value))} />
                </Field>
              </>
            )}

            <div className="span-all"><ErrorBox message={vErr} /></div>
            <div className="span-all row end">
              <button className="btn primary" disabled={starting || (mode !== "provider" && !ffmpeg)} onClick={() => void startVideo()}>
                {starting ? t("starting") : `🎬 ${t("makeVideo")}`}
              </button>
            </div>
          </div>

          <h3>{t("videoJobs")}</h3>
          {jobs.length === 0 && <p className="muted">{t("noJobs")}</p>}
          {jobs.map((j) => (
            <JobCard key={j.id} id={j.id} title={j.title} onDone={() => setPickRefresh((x) => x + 1)} />
          ))}
        </div>
      )}
    </section>
  );
}
