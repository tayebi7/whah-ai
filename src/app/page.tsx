"use client";

import { useEffect, useState } from "react";
import "../local/boot";
import Books from "../ui/Books";
import Chat from "../ui/Chat";
import Docs from "../ui/Docs";
import Settings from "../ui/Settings";
import Studio from "../ui/Studio";
import { AppProvider, safeStorage, useApp, type Tab } from "../ui/app";
import { dict, dirOf, type Lang } from "../ui/i18n";

const TABS: { key: Tab; icon: string }[] = [
  { key: "chat", icon: "💬" },
  { key: "studio", icon: "🎨" },
  { key: "docs", icon: "📁" },
  { key: "books", icon: "📖" },
  { key: "settings", icon: "⚙️" },
];

function Shell({ tab, setTab, lang, setLang, dark, setDark }: { tab: Tab; setTab: (t: Tab) => void; lang: Lang; setLang: (l: Lang) => void; dark: boolean; setDark: (d: boolean) => void }) {
  const { t } = useApp();
  return (
    <div className="shell">
      <aside className="nav">
        <div className="brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo-mark.svg" alt="" width={40} height={40} />
          <div>
            <strong>Waha AI</strong>
            <small>{t("tagline")}</small>
          </div>
        </div>
        <nav aria-label="Main">
          {TABS.map((x) => (
            <button key={x.key} className={`navbtn ${tab === x.key ? "on" : ""}`} aria-current={tab === x.key ? "page" : undefined} onClick={() => setTab(x.key)}>
              <span aria-hidden>{x.icon}</span>
              <span>{t(`tab_${x.key}`)}</span>
            </button>
          ))}
        </nav>
        <div className="spacer" />
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
        {/* All tabs stay mounted so a running chat or form is not lost when switching. */}
        <div hidden={tab !== "chat"} className="pane"><Chat /></div>
        <div hidden={tab !== "studio"} className="pane scroll"><Studio /></div>
        <div hidden={tab !== "docs"} className="pane scroll"><Docs active={tab === "docs"} /></div>
        <div hidden={tab !== "books"} className="pane scroll"><Books /></div>
        <div hidden={tab !== "settings"} className="pane scroll"><Settings /></div>
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
    const tb = safeStorage("local")?.getItem("waha-tab");
    if (tb && TABS.some((x) => x.key === tb)) setTab(tb as Tab);
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

  useEffect(() => {
    if (ready) safeStorage("local")?.setItem("waha-tab", tab);
  }, [tab, ready]);

  return (
    <AppProvider lang={lang} go={setTab}>
      <Shell tab={tab} setTab={setTab} lang={lang} setLang={setLang} dark={dark} setDark={setDark} />
    </AppProvider>
  );
}
