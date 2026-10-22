/** Understands what a free-text prompt asks for (Arabic / English / French heuristics, no network). */
export type Intent = "image" | "video" | "story" | "book" | "chat";

const VERB = String.raw`(?:ارسم|ارسمي|اصنع|اصنعي|أنشئ|انشئ|أنشيء|انشيء|صمم|صمّم|ولد|ولّد|اعمل|اعملي|أعطني|اعطني|اريد|أريد|أبغى|ابغي|اكتب|اكتبي|حرك|حرّك|draw|paint|make|create|generate|design|produce|render|imagine|write|give me|i want|i need|dessine|crée|cree|génère|genere|fais|fabrique|réalise|realise|écris|ecris|donne-moi)`;
const has = (s: string, re: RegExp) => re.test(s);

const IMAGE_NOUN = /(?:صورة|صوره|صور|رسمة|رسم|لوحة|شعار|لوغو|logo|بوستر|ملصق|بطاقة|غلاف|خلفية|ايقونة|أيقونة|image|picture|photo|illustration|artwork|poster|wallpaper|drawing|portrait|icon|avatar|thumbnail|banner|sketch|dessin|affiche|illustration|fond d'écran|portrait)/i;
const VIDEO_NOUN = /(?:فيديو|فديو|مقطع|كليب|فيلم|انيميشن|أنيميشن|رسوم متحركة|video|vidéo|clip|film|movie|animation|animated|reel|short)/i;
const STORY_NOUN = /(?:قصة|قصه|حكاية|حكايه|خرافة|story|tale|fable|bedtime|histoire|conte|récit)/i;
const BOOK_NOUN = /(?:كتاب|رواية|روايه|دليل كامل|book|novel|ebook|e-book|livre|roman|guide complet)/i;

const QUESTION_START = /^\s*(?:كيف|كيفية|ما |ماذا|ما هو|ما هي|ماهو|ماهي|لماذا|لم |متى|أين|اين|من هو|من هي|هل |كم |اشرح|اشرحي|فسر|لخص|ترجم|what|why|how|when|where|who|which|is |are |can |does |do |explain|summari[sz]e|translate|comment|pourquoi|quand|où|qui |quel|est-ce|explique|résume|traduis)/i;
const DRAW_ONLY = /^\s*(?:ارسم|ارسمي|draw|paint|imagine|dessine|صمم|صمّم|design)\b/i;

export function detectIntent(raw: string): { intent: Intent; confidence: "high" | "low" } {
  const s = raw.trim().replace(/\s+/g, " ");
  if (!s) return { intent: "chat", confidence: "low" };
  const hasVerb = has(s, new RegExp(`(?:^|\\s)${VERB}(?=\\s|$)`, "i"));
  const q = has(s, QUESTION_START);
  // "how to draw a cat" / "كيف أرسم قطة": a question about the activity, not a request for it
  if (q && !has(s, /^\s*(?:أريد|اريد|i want|i need|give me|donne-moi)/i)) return { intent: "chat", confidence: "high" };

  const lead = (re: RegExp) => new RegExp(`^\\s*${re.source}`, "i").test(s);
  const cands: [number, Intent][] = [];
  const add = (re: RegExp, kind: Intent, leads: boolean) => {
    const m = re.exec(s);
    if (m && (hasVerb || leads)) cands.push([m.index, kind]);
  };
  add(BOOK_NOUN, "book", false);
  add(VIDEO_NOUN, "video", lead(/(?:video|فيديو|vidéo|clip|مقطع|animation)/));
  add(STORY_NOUN, "story", lead(/(?:قصة|قصه|حكاية|story|histoire|conte)/));
  add(IMAGE_NOUN, "image", lead(/(?:صورة|صوره|صور|رسم|شعار|لوغو|logo|image|picture|photo|poster|بوستر|illustration|dessin|affiche)/));
  if (cands.length) return { intent: cands.sort((x, y) => x[0] - y[0])[0][1], confidence: "high" };
  if (DRAW_ONLY.test(s)) return { intent: "image", confidence: "low" };
  return { intent: "chat", confidence: "low" };
}

/** Prompt cleanup for image/video: drop the "make me a picture of" wrapper but keep the subject. */
export function subjectOf(raw: string): string {
  const s = raw.trim().replace(/\s+/g, " ");
  const stripped = s
    .replace(new RegExp(`^(?:${VERB})\\s+(?:لي\\s+|me\\s+|moi\\s+)?(?:(?:a|an|the|une?|des|un)\\s+)?(?:${IMAGE_NOUN.source}|${VIDEO_NOUN.source})\\s*(?:لـ|ل|عن|of|about|de|d'|pour|for|:)?\\s*`, "i"), "")
    .trim();
  return stripped.length >= 3 ? stripped : s;
}

export type Skill = { id: string; name: string; instruction: string; keywords: string; enabled: boolean };
export type Connector = { id: string; name: string; urlTemplate: string; headers: string; keywords: string; enabled: boolean };

const kw = (s: string) => s.split(/[,،\n]/).map((x) => x.trim().toLowerCase()).filter(Boolean);

/** Skills whose keywords occur in the prompt (an enabled skill with no keywords applies to every chat). */
export function matchSkills(skills: Skill[], prompt: string, forced: string[] = []): Skill[] {
  const p = prompt.toLowerCase();
  return skills.filter((k) => k.enabled && (forced.includes(k.id) || (kw(k.keywords).length > 0 ? kw(k.keywords).some((w) => p.includes(w)) : false) || (kw(k.keywords).length === 0 && k.keywords === "*")));
}

export function matchConnectors(cs: Connector[], prompt: string, forced: string[] = []): Connector[] {
  const p = prompt.toLowerCase();
  return cs.filter((c) => c.enabled && (forced.includes(c.id) || kw(c.keywords).some((w) => p.includes(w))));
}

export function connectorUrl(c: Connector, query: string): string {
  return c.urlTemplate.replace(/\{query\}/g, encodeURIComponent(query));
}

export function urlsIn(prompt: string): string[] {
  return [...new Set(prompt.match(/https:\/\/[^\s<>"')،]+/g) ?? [])].slice(0, 2);
}
