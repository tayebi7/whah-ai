"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Asset } from "./api";
import { safeStorage } from "./app";
import { uid } from "./extras";

export type Item = {
  id: string;
  role: "user" | "ai";
  kind: "text" | "story" | "image" | "video" | "book" | "error";
  text?: string;
  files?: Asset[];
  assets?: Asset[];
  jobId?: string;
  jobTitle?: string;
  meta?: string;
  usedPrompt?: string;
  pending?: string;
  retry?: { text: string; kind: string };
};
export type Conv = { id: string; title: string; updatedAt: number; items: Item[] };

type Ctx = {
  convs: Conv[];
  active: Conv;
  update: (convId: string, fn: (items: Item[]) => Item[]) => void;
  newChat: () => void;
  open: (id: string) => void;
  remove: (id: string) => void;
};
const C = createContext<Ctx | null>(null);
export const useConvs = () => {
  const v = useContext(C);
  if (!v) throw new Error("useConvs outside provider");
  return v;
};

const KEY = "waha-convs";
const blank = (): Conv => ({ id: uid(), title: "", updatedAt: Date.now(), items: [] });

export function ConvProvider({ children }: { children: ReactNode }) {
  const [convs, setConvs] = useState<Conv[]>(() => [blank()]);
  const [activeId, setActiveId] = useState<string>(() => "");
  const loaded = useRef(false);

  useEffect(() => {
    let saved: Conv[] = [];
    try {
      const v = JSON.parse(safeStorage("local")?.getItem(KEY) ?? "[]");
      if (Array.isArray(v)) saved = v.filter((c) => c && typeof c.id === "string" && Array.isArray(c.items));
    } catch {
      saved = [];
    }
    const fresh = blank();
    setConvs([fresh, ...saved]);
    setActiveId(fresh.id);
    loaded.current = true;
  }, []);

  useEffect(() => {
    if (!loaded.current) return;
    const keep = convs
      .filter((c) => c.items.length > 0)
      .slice(0, 30)
      .map((c) => ({ ...c, items: c.items.map((i) => ({ ...i, pending: undefined })).slice(-80) }));
    try {
      safeStorage("local")?.setItem(KEY, JSON.stringify(keep));
    } catch {
      /* full or unavailable */
    }
  }, [convs]);

  const update = useCallback((convId: string, fn: (items: Item[]) => Item[]) => {
    setConvs((cs) =>
      cs.map((c) => {
        if (c.id !== convId) return c;
        const items = fn(c.items);
        const firstUser = items.find((i) => i.role === "user");
        return { ...c, items, updatedAt: Date.now(), title: c.title || (firstUser?.text ?? "").slice(0, 48) };
      }),
    );
  }, []);

  const newChat = useCallback(() => {
    const cur = convs.find((c) => c.id === activeId);
    if (cur && cur.items.length === 0) return;
    const b = blank();
    setConvs([b, ...convs.filter((c) => c.items.length > 0)]);
    setActiveId(b.id);
  }, [convs, activeId]);

  const remove = useCallback(
    (id: string) => {
      const rest = convs.filter((c) => c.id !== id && c.items.length > 0);
      if (id === activeId || !convs.some((c) => c.id === activeId)) {
        const b = blank();
        setConvs([b, ...rest]);
        setActiveId(b.id);
      } else setConvs([...convs.filter((c) => c.id === activeId && c.items.length === 0), ...rest]);
    },
    [convs, activeId],
  );

  const active = useMemo(() => convs.find((c) => c.id === activeId) ?? convs[0] ?? blank(), [convs, activeId]);
  const value = useMemo(() => ({ convs, active, update, newChat, open: setActiveId, remove }), [convs, active, update, newChat, remove]);
  return <C.Provider value={value}>{children}</C.Provider>;
}
