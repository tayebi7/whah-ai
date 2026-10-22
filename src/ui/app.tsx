"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { createApi, type Api, type Asset, type PubProvider } from "./api";
import { dict, type Lang } from "./i18n";

export type Tab = "chat" | "studio" | "docs" | "books" | "skills" | "connectors" | "settings";

type Ctx = {
  lang: Lang;
  t: (key: string, vars?: Record<string, string | number>) => string;
  api: Api;
  token: string;
  setToken: (t: string) => void;
  providers: PubProvider[];
  providersLoaded: boolean;
  refreshProviders: () => Promise<void>;
  go: (tab: Tab) => void;
  /** Files the Documents tab wants the chat to start with. */
  chatSeed: Asset[];
  askAboutFiles: (assets: Asset[]) => void;
  consumeSeed: () => void;
  toast: (message: string, kind?: "ok" | "error") => void;
};

const AppCtx = createContext<Ctx | null>(null);
export const useApp = () => {
  const v = useContext(AppCtx);
  if (!v) throw new Error("useApp outside provider");
  return v;
};

export function safeStorage(kind: "local" | "session"): Storage | null {
  try {
    return kind === "local" ? window.localStorage : window.sessionStorage;
  } catch {
    return null;
  }
}

export function AppProvider({ lang, go, children }: { lang: Lang; go: (tab: Tab) => void; children: ReactNode }) {
  const [token, setTokenState] = useState("");
  const tokenRef = useRef("");
  const [providers, setProviders] = useState<PubProvider[]>([]);
  const [providersLoaded, setLoaded] = useState(false);
  const [chatSeed, setSeed] = useState<Asset[]>([]);
  const [toasts, setToasts] = useState<{ id: number; message: string; kind: "ok" | "error" }[]>([]);

  const setToken = useCallback((t: string) => {
    tokenRef.current = t;
    setTokenState(t);
    safeStorage("session")?.setItem("waha-token", t);
  }, []);

  useEffect(() => {
    const saved = safeStorage("session")?.getItem("waha-token") ?? "";
    tokenRef.current = saved;
    setTokenState(saved);
  }, []);

  const api = useMemo(() => createApi(() => tokenRef.current), []);

  const refreshProviders = useCallback(async () => {
    try {
      const d = await api.get<{ providers: PubProvider[] }>("/api/providers");
      setProviders(d.providers);
    } catch {
      setProviders([]);
    } finally {
      setLoaded(true);
    }
  }, [api]);

  useEffect(() => {
    void refreshProviders();
  }, [token, refreshProviders]);

  const t = useCallback(
    (key: string, vars?: Record<string, string | number>) => {
      let s = dict[lang][key] ?? dict.en[key] ?? key;
      if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v));
      return s;
    },
    [lang],
  );

  const toast = useCallback((message: string, kind: "ok" | "error" = "ok") => {
    const id = Date.now() + Math.random();
    setToasts((x) => [...x.slice(-3), { id, message, kind }]);
    setTimeout(() => setToasts((x) => x.filter((y) => y.id !== id)), kind === "error" ? 8000 : 3500);
  }, []);

  const value: Ctx = {
    lang,
    t,
    api,
    token,
    setToken,
    providers,
    providersLoaded,
    refreshProviders,
    go,
    chatSeed,
    askAboutFiles: (assets) => {
      setSeed(assets);
      go("chat");
    },
    consumeSeed: () => setSeed([]),
    toast,
  };

  return (
    <AppCtx.Provider value={value}>
      {children}
      <div className="toasts" aria-live="polite">
        {toasts.map((x) => (
          <div key={x.id} className={`toast ${x.kind}`} role={x.kind === "error" ? "alert" : "status"}>
            {x.message}
          </div>
        ))}
      </div>
    </AppCtx.Provider>
  );
}
