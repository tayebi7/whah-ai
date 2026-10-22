import { safeStorage } from "./app";
import type { Connector, Skill } from "../lib/intent";

const read = <T,>(key: string): T[] => {
  try {
    const v = JSON.parse(safeStorage("local")?.getItem(key) ?? "[]");
    return Array.isArray(v) ? (v as T[]) : [];
  } catch {
    return [];
  }
};
const write = (key: string, v: unknown) => {
  try {
    safeStorage("local")?.setItem(key, JSON.stringify(v));
  } catch {
    /* storage unavailable: changes last for this session only */
  }
};

export const loadSkills = () => read<Skill>("waha-skills");
export const saveSkills = (s: Skill[]) => write("waha-skills", s);
export const loadConnectors = () => read<Connector>("waha-connectors");
export const saveConnectors = (c: Connector[]) => write("waha-connectors", c);

export const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);

export const SKILL_PRESETS: Omit<Skill, "id" | "enabled">[] = [
  { name: "Translator / مترجم", instruction: "When the user asks for a translation, translate faithfully, keep names and numbers, and reply with the translation first.", keywords: "ترجم, translate, traduis" },
  { name: "Teacher / معلم", instruction: "Explain step by step in simple language with one short example, then check understanding with one question.", keywords: "اشرح, explain, explique" },
  { name: "Code helper / مبرمج", instruction: "Answer with working, minimal code in a fenced block, then a two-line explanation.", keywords: "code, كود, برمجة, python, javascript" },
];
export const CONNECTOR_PRESETS: Omit<Connector, "id" | "enabled">[] = [
  { name: "Wikipedia (ar)", urlTemplate: "https://ar.wikipedia.org/w/api.php?action=query&list=search&srsearch={query}&srlimit=3&format=json&origin=*", headers: "", keywords: "ويكيبيديا, wikipedia" },
  { name: "Wikipedia (en)", urlTemplate: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={query}&srlimit=3&format=json&origin=*", headers: "", keywords: "wiki" },
];

const MAX = 6000;
export function plainText(body: string, contentType: string): string {
  let s = body;
  if (/json/i.test(contentType)) {
    try {
      s = JSON.stringify(JSON.parse(body));
    } catch {
      /* keep raw */
    }
  } else if (/html/i.test(contentType) || /^\s*<(!doctype|html)/i.test(body)) {
    s = body.replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  }
  return s.replace(/\s+/g, " ").trim().slice(0, MAX);
}

/** Fetches a URL for use as context. Returns null (never throws) when it cannot be read. */
export async function fetchContext(url: string, headersJson = "", signal?: AbortSignal): Promise<string | null> {
  try {
    let headers: Record<string, string> = {};
    if (headersJson.trim()) {
      const h = JSON.parse(headersJson);
      if (h && typeof h === "object") headers = Object.fromEntries(Object.entries(h).filter(([, v]) => typeof v === "string")) as Record<string, string>;
    }
    const res = await fetch(url, { headers, signal });
    if (!res.ok) return null;
    return plainText(await res.text(), res.headers.get("content-type") ?? "");
  } catch {
    return null;
  }
}
