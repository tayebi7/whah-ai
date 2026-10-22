"use client";

import { useEffect, useState } from "react";
import "../local/boot";
import Assistant from "../ui/Assistant";
import Books from "../ui/Books";
import Docs from "../ui/Docs";
import { Connectors, Skills } from "../ui/ExtrasPages";
import Settings from "../ui/Settings";
import Studio from "../ui/Studio";
import { AppProvider, safeStorage, useApp, type Tab } from "../ui/app";
import { ConvProvider, useConvs } from "../ui/convs";
import { dict, dirOf, type Lang } from "../ui/i18n";

const TABS: { key: Tab; icon: string }[] = [
  { key: "chat", icon: "✦" },
  { key: "studio", icon: "🎨" },
  { key: "docs", icon: "📁" },
  { key: "books", icon: "📖" },
  { key: "skills", icon: "🧩" },
  { key: "connectors", icon: "🔌" },
  { key: "settings", icon: "⚙️" },
];

function Shell({ tab, setTab, lang, setLang, dark, setDark }: { tab: Tab; setTab: (t: Tab) => void; lang: Lang; setLang: (l: Lang) => void; dark: boolean; setDark: (d: boolean) => void }) {
  const { t } = useApp();
  const { convs, active, open, remove, newChat } = useConvs();
  const [drawer, setDrawer] = useState(false);
  const pick = (k: Tab) => { setTab(k); setDrawer(false); };
  const history = convs.filter((c) => c.items.length > 0);
  return (
    <div className="shell">
      {drawer && <div className="scrim" onClick={() => setDrawer(false)} aria-hidden />}
      <aside className={`nav ${drawer ? "open" : ""}`} aria-label="Menu" data-testid="drawer">
        <div className="brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo-mark.svg" alt="" width={36} height={36} />
          <div>
            <strong>Waha AI</strong>
            <small>{t("tagline")}</small>
          </div>
        </div>
        <button className="btn primary newchat" onClick={() => { newChat(); pick("chat"); }}>＋ {t("newChat")}</button>
        <nav aria-label="Main">
          {TABS.map((x) => (
            <button key={x.key} className={`navbtn ${tab === x.key ? "on" : ""}`} aria-current={tab === x.key ? "page" : undefined} onClick={() => pick(x.key)} data-testid={`nav-${x.key}`}>
              <span aria-hidden>{x.icon}</span>
              <span>{t(`tab_${x.key}`)}</span>
            </button>
          ))}
        </nav>
        <div className="hist">
          <small className="muted">{t("a_history")}</small>
          {history.length === 0 && <small className="muted">{t("a_noHistory")}</small>}
          {history.slice(0, 20).map((c) => (
            <div key={c.id} className={`hist-row ${c.id === active.id && tab === "chat" ? "on" : ""}`}>
              <button onClick={() => { open(c.id); pick("chat"); }} dir="auto">{c.title || "…"}</button>
              <button className="x" aria-label={t("delete")} onClick={() => remove(c.id)}>✕</button>
            </div>
          ))}
        </div>
        <div className="row nav-tools">
          {(["ar", "en", "fr"] as Lang[]).map((l) => (
            <button key={l} className={`btn sm ${l === lang ? "active" : ""}`} onClick={() => setLang(l)} aria-pressed={l === lang}>
              {l.toUpperCase()}
            </button>
          ))}
          <button className="btn sm" onClick={() => setDark(!dark)} aria-label={t("theme")} title={t("theme")}>
            {dark ? "☀" : "☾"}
          </button>
        </div>
      </aside>
      <main className="main">
        {/* All tabs stay mounted so a running request or form is not lost when switching. */}
        <div hidden={tab !== "chat"} className="pane"><Assistant onMenu={() => setDrawer(true)} /></div>
        {(["studio", "docs", "books", "skills", "connectors", "settings"] as Tab[]).map((k) => (
          <div key={k} hidden={tab !== k} className="pane scroll">
            <div className="page-bar"><button className="icon-btn" aria-label={t("a_menu")} onClick={() => setDrawer(true)}>☰</button><strong>{t(`tab_${k}`)}</strong></div>
            {k === "studio" && <Studio />}
            {k === "docs" && <Docs active={tab === "docs"} />}
            {k === "books" && <Books />}
            {k === "skills" && <Skills />}
            {k === "connectors" && <Connectors />}
            {k === "settings" && <Settings />}
          </div>
        ))}
      </main>
    </div>
  );
}

export default function Home() {
  const [lang, setLang] = useState<Lang>("ar");
  const [dark, setDark] = useState(false);
  const [tab, setTab] = useState<Tab>("chat");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const l = safeStorage("local")?.getItem("waha-lang");
    if (l === "ar" || l === "en" || l === "fr") setLang(l);
    const d = safeStorage("local")?.getItem("waha-dark");
    setDark(d == null ? window.matchMedia("(prefers-color-scheme: dark)").matches : d === "1");
    setReady(true);
  }, []);

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = dirOf(lang);
    document.title = `Waha AI — ${dict[lang].tagline}`;
    if (ready) safeStorage("local")?.setItem("waha-lang", lang);
  }, [lang, ready]);

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    if (ready) safeStorage("local")?.setItem("waha-dark", dark ? "1" : "0");
  }, [dark, ready]);

  return (
    <AppProvider lang={lang} go={setTab}>
      <ConvProvider>
        <Shell tab={tab} setTab={setTab} lang={lang} setLang={setLang} dark={dark} setDark={setDark} />
      </ConvProvider>
    </AppProvider>
  );
}
